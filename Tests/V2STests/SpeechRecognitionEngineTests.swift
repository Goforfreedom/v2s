import XCTest
@testable import v2s

/// Stand-in for WhisperSpeechRecognitionEngine: records what the session
/// feeds it and fires the protocol callbacks on demand, so the contract the
/// session relies on is tested without the WhisperKit SDK.
private final class MockSpeechRecognitionEngine: SpeechRecognitionEngine, @unchecked Sendable {
    let language: String?
    var onDraft: (@Sendable (String) -> Void)?
    var onFinal: (@Sendable (String, String?) -> Void)?

    private(set) var appendedSampleCounts: [Int] = []
    private(set) var finalizeCallCount = 0
    private(set) var stopCallCount = 0
    private var stopped = false

    init(language: String?) {
        self.language = language
    }

    func appendAudio(samples: [Float]) {
        appendedSampleCounts.append(samples.count)
    }

    func finalizeCurrentSegment() {
        finalizeCallCount += 1
    }

    func stop() {
        stopped = true
        stopCallCount += 1
    }

    func emitDraft(_ text: String) {
        guard stopped == false else { return }
        onDraft?(text)
    }

    func emitFinal(_ text: String, detectedLanguage: String?) {
        guard stopped == false else { return }
        onFinal?(text, detectedLanguage)
    }
}

final class SpeechRecognitionEngineTests: XCTestCase {
    func testAutoDetectionPassesThroughAsNilLanguage() {
        let engine = MockSpeechRecognitionEngine(language: nil)
        XCTAssertNil(engine.language)
    }

    func testForcedLanguagePassesThrough() {
        let engine = MockSpeechRecognitionEngine(language: "zh")
        XCTAssertEqual(engine.language, "zh")
    }

    func testAppendAndFinalizeAreRecorded() {
        let engine = MockSpeechRecognitionEngine(language: "en")
        engine.appendAudio(samples: [Float](repeating: 0, count: 1600))
        engine.appendAudio(samples: [Float](repeating: 0, count: 800))
        engine.finalizeCurrentSegment()

        XCTAssertEqual(engine.appendedSampleCounts, [1600, 800])
        XCTAssertEqual(engine.finalizeCallCount, 1)
    }

    func testCallbacksFireUntilStop() {
        let engine = MockSpeechRecognitionEngine(language: nil)
        var drafts: [String] = []
        var finals: [(String, String?)] = []
        engine.onDraft = { drafts.append($0) }
        engine.onFinal = { finals.append(($0, $1)) }

        engine.emitDraft("hello")
        engine.emitFinal("hello world", detectedLanguage: "en")
        engine.stop()
        engine.emitDraft("after stop")
        engine.emitFinal("after stop", detectedLanguage: "en")

        XCTAssertEqual(drafts, ["hello"])
        XCTAssertEqual(finals.count, 1)
        XCTAssertEqual(finals[0].0, "hello world")
        XCTAssertEqual(finals[0].1, "en")
        XCTAssertEqual(engine.stopCallCount, 1)
    }

    func testFallbackDecisionNeedsReadyStateAndAppleSilicon() {
        XCTAssertTrue(
            WhisperModelManager.shouldUseWhisper(state: .ready, isAppleSilicon: true)
        )
        XCTAssertFalse(
            WhisperModelManager.shouldUseWhisper(state: .ready, isAppleSilicon: false)
        )
        XCTAssertFalse(
            WhisperModelManager.shouldUseWhisper(state: .loading, isAppleSilicon: true)
        )
        XCTAssertFalse(
            WhisperModelManager.shouldUseWhisper(state: .idle, isAppleSilicon: true)
        )
        XCTAssertFalse(
            WhisperModelManager.shouldUseWhisper(state: .error("boom"), isAppleSilicon: true)
        )
    }
}
