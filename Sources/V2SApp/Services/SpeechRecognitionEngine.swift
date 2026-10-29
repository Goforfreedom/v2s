import Foundation

/// The recognizer a LiveTranscriptionSession feeds captured audio to.
///
/// Apple recognition stays inside the session (its two transcribers share the
/// session's draft/commit machinery); this protocol covers the WhisperKit
/// path and anything testable behind it. The session calls these methods on
/// its capture queue; callbacks may arrive on any queue, so the session hops
/// back to the capture queue before touching its own state.
protocol SpeechRecognitionEngine: AnyObject, Sendable {
    /// Whisper language code, or nil for true auto-detection.
    var language: String? { get }

    /// Mutable text for the segment still being spoken.
    var onDraft: (@Sendable (String) -> Void)? { get set }

    /// Final text for a finished segment, plus the Whisper language code
    /// reported for it. Empty text means "nothing recognizable": the session
    /// clears the draft and commits nothing.
    var onFinal: (@Sendable (String, String?) -> Void)? { get set }

    /// Feeds 16 kHz mono float samples for the current segment.
    func appendAudio(samples: [Float])

    /// Transcribes whatever the current segment accumulated and reports it
    /// through onFinal, then starts a fresh segment.
    func finalizeCurrentSegment()

    /// Drops any pending work. No callback fires after this returns.
    func stop()
}
