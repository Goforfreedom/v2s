import Foundation
import WhisperKit

/// Owns the single shared WhisperKit pipeline and its lifecycle.
///
/// States are deliberately coarse: the SDK performs download and load as one
/// initializer step, so no byte-level progress API is used here — the UI
/// shows an indeterminate "downloading / loading" state instead of inventing
/// a percentage. On Intel Macs the manager never starts: WhisperKit targets
/// Apple Silicon, so those machines fall back to Apple recognition.
@MainActor
final class WhisperModelManager: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case ready
        case error(String)
    }

    enum Model: String, CaseIterable {
        case tiny
        case base
        case small

        /// Model name the SDK resolves (multilingual, not the .en variants,
        /// so auto-detection works and non-English speech is covered). The
        /// SDK maps these to the openai_whisper-{model} folders in
        /// argmaxinc/whisperkit-coreml; the folder prefix is not part of
        /// the model name.
        /// Raw values are exactly the SDK model names, so no switch needed.
        var variant: String { rawValue }

        var downloadSizeText: String {
            // Switched on the raw string, not on enum cases: the bare
            // `case tiny:` patterns below used to fail CI with
            // "enum case cannot be used as an instance member".
            switch rawValue {
            case "tiny": return "~80 MB"
            case "base": return "~150 MB"
            case "small": return "~500 MB"
            default: return ""
            }
        }
    }

    enum FallbackReason {
        case intelMac
        case modelNotReady
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var model: Model

    /// True when a session may use Whisper: Apple Silicon + loaded pipeline.
    var isReady: Bool {
        isAppleSilicon && pipeline != nil && state == .ready
    }

    var fallbackReason: FallbackReason {
        if isAppleSilicon == false {
            return .intelMac
        }
        if case .error(let message) = state {
            return .error(message)
        }
        return .modelNotReady
    }

    static var isAppleSilicon: Bool {
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0 else {
            return false
        }
        var machine = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 else {
            return false
        }
        return String(cString: machine) == "arm64"
    }

    var isAppleSilicon: Bool {
        Self.isAppleSilicon
    }

    private(set) var pipeline: WhisperKit?
    private let gate = WhisperTranscriptionGate()
    private var loadTask: Task<WhisperKit, Error>?
    private var loadGeneration = 0

    init(initialModel: Model) {
        self.model = initialModel
    }

    /// Starts a background load if needed; never blocks the caller.
    func prewarmInBackground() {
        Task { await ensureReady() }
    }

    /// Loads the model, downloading it first when it is not cached.
    /// Concurrent callers share the in-flight load instead of starting
    /// another one; this runs on MainActor up to the first suspension, so
    /// the check-then-create sequence cannot race.
    func ensureReady() async {
        guard isAppleSilicon else {
            return
        }
        guard isReady == false else {
            return
        }

        if let loadTask {
            let generation = loadGeneration
            do {
                let kit = try await loadTask.value
                guard generation == loadGeneration else {
                    return
                }
                pipeline = kit
                state = .ready
            } catch {
                guard generation == loadGeneration else {
                    return
                }
                pipeline = nil
                state = .error(error.localizedDescription)
            }
            if generation == loadGeneration {
                self.loadTask = nil
            }
            return
        }

        let model = self.model
        let generation = loadGeneration
        let task = Task<WhisperKit, Error> {
            // The initializer downloads the model when it is not cached and
            // loads it; only the variant is named here so the SDK defaults
            // for load/download apply.
            try await WhisperKit(WhisperKitConfig(model: model.variant))
        }
        loadTask = task
        state = .loading
        do {
            let kit = try await task.value
            guard generation == loadGeneration else {
                return
            }
            pipeline = kit
            state = .ready
        } catch {
            guard generation == loadGeneration else {
                return
            }
            pipeline = nil
            state = .error(error.localizedDescription)
        }
        if generation == loadGeneration {
            self.loadTask = nil
        }
    }

    /// Retries a failed load (or starts one when idle).
    func retry() {
        guard isAppleSilicon else {
            return
        }
        guard case .loading = state else {
            Task { await ensureReady() }
            return
        }
    }

    /// Switches models: drops the loaded pipeline, cancels any in-flight
    /// load (its result is ignored via the generation guard), and reloads
    /// the new model in the background.
    func setModel(_ newModel: Model) {
        guard newModel != model else {
            return
        }
        loadGeneration &+= 1
        loadTask?.cancel()
        loadTask = nil
        pipeline = nil
        model = newModel
        state = .idle
        prewarmInBackground()
    }

    /// A per-session engine bound to the shared pipeline, or nil when the
    /// caller must fall back to Apple recognition.
    func engine(language: String?) -> (any SpeechRecognitionEngine)? {
        guard isReady, let pipeline else {
            return nil
        }
        return WhisperSpeechRecognitionEngine(pipeline: pipeline, gate: gate, language: language)
    }

    /// Pure fallback decision, kept testable without the SDK (and without
    /// MainActor hops: it touches no instance state).
    nonisolated static func shouldUseWhisper(state: State, isAppleSilicon: Bool) -> Bool {
        isAppleSilicon && state == .ready
    }
}
