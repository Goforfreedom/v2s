import Foundation
import WhisperKit

/// Segment-based WhisperKit recognition behind SpeechRecognitionEngine.
///
/// v2s captures its own audio (microphone + app audio) and cannot use
/// AudioStreamTranscriber's built-in mic capture, so this engine cuts
/// segments with the session's Silero VAD timing instead: samples accumulate
/// for the current segment, partial transcriptions of the growing segment
/// feed the draft layer, and a VAD silence / inactivity finalize transcribes
/// the whole segment for the commit layer. A partial already running keeps
/// running; a newer partial waits and follows (the same coalescing the draft
/// translator uses), so continuous speech never starves partials.
/// Transcriptions for all sessions funnel through one gate because a
/// WhisperKit instance is not safe to drive from two calls at once.
final class WhisperSpeechRecognitionEngine: SpeechRecognitionEngine, @unchecked Sendable {
    let language: String?
    var onDraft: (@Sendable (String) -> Void)?
    var onFinal: (@Sendable (String, String?) -> Void)?

    private let pipeline: WhisperKit
    private let gate: WhisperTranscriptionGate
    private let stateQueue = DispatchQueue(label: "com.franklioxygen.v2s.whisper-engine")
    private var samples: [Float] = []
    private var generation = 0
    private var partialTask: Task<Void, Never>?
    private var pendingPartial = false
    private var lastPartialSampleCount = 0
    private var lastEmittedDraftText = ""
    /// Draft cadence in samples (1.5 s of 16 kHz audio).
    private let partialIntervalSamples = 24_000
    /// Whisper's window: a segment never grows past 30 s.
    private let maxSegmentSamples = 480_000

    init(pipeline: WhisperKit, gate: WhisperTranscriptionGate, language: String?) {
        self.pipeline = pipeline
        self.gate = gate
        self.language = language
    }

    func appendAudio(samples newSamples: [Float]) {
        stateQueue.sync {
            samples.append(contentsOf: newSamples)
            if samples.count >= maxSegmentSamples {
                finalizeLocked()
                return
            }
            if samples.count - lastPartialSampleCount < partialIntervalSamples {
                return
            }
            if partialTask != nil {
                pendingPartial = true
                return
            }
            launchPartialLocked()
        }
    }

    func finalizeCurrentSegment() {
        stateQueue.sync {
            finalizeLocked()
        }
    }

    func stop() {
        stateQueue.sync {
            generation &+= 1
            partialTask?.cancel()
            partialTask = nil
            pendingPartial = false
            samples = []
            lastPartialSampleCount = 0
            lastEmittedDraftText = ""
        }
    }

    private func finalizeLocked() {
        generation &+= 1
        partialTask?.cancel()
        partialTask = nil
        pendingPartial = false
        let segmentSamples = samples
        samples = []
        lastPartialSampleCount = 0
        lastEmittedDraftText = ""
        guard segmentSamples.isEmpty == false else {
            return
        }
        let generationAtLaunch = generation
        Task {
            do {
                let result = try await transcribe(segmentSamples)
                guard generationAtLaunch == currentGeneration() else {
                    return
                }
                onFinal?(result.text, result.language)
            } catch is CancellationError {
                return
            } catch {
                // A failed segment must not wedge the session: report it as
                // an empty final so the draft clears and capture continues.
                guard generationAtLaunch == currentGeneration() else {
                    return
                }
                onFinal?("", nil)
            }
        }
    }

    private func launchPartialLocked() {
        let snapshot = samples
        let snapshotCount = snapshot.count
        let generationAtLaunch = generation
        let task = Task {
            do {
                let result = try await transcribe(snapshot)
                stateQueue.sync {
                    guard generationAtLaunch == generation else {
                        return
                    }
                    partialTask = nil
                    lastPartialSampleCount = snapshotCount
                    if result.text.isEmpty == false, result.text != lastEmittedDraftText {
                        lastEmittedDraftText = result.text
                        onDraft?(result.text)
                    }
                    if pendingPartial {
                        pendingPartial = false
                        launchPartialLocked()
                    }
                }
            } catch {
                // Cancellation is covered by the generation guard above (a
                // finalize/stop always bumps it). Any other failure just
                // skips this draft; newer audio still gets its own partial.
                stateQueue.sync {
                    guard generationAtLaunch == generation else {
                        return
                    }
                    partialTask = nil
                    lastPartialSampleCount = snapshotCount
                    if pendingPartial {
                        pendingPartial = false
                        launchPartialLocked()
                    }
                }
            }
        }
        partialTask = task
    }

    private func currentGeneration() -> Int {
        stateQueue.sync { generation }
    }

    private func transcribe(_ audio: [Float]) async throws -> (text: String, language: String?) {
        let options = DecodingOptions(language: language)
        let results: [TranscriptionResult] = try await gate.run {
            try await self.pipeline.transcribe(
                audioArray: audio,
                decodeOptions: options
            ) { _ in
                !Task.isCancelled
            }
        }
        let text = results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (text, results.first?.language)
    }
}
