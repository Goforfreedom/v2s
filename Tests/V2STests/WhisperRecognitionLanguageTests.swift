import XCTest
@testable import v2s

final class WhisperRecognitionLanguageTests: XCTestCase {
    func testAutoInputMapsToNilForTrueDetection() {
        XCTAssertNil(WhisperRecognitionLanguage.whisperCode(forAppLanguageID: "auto"))
    }

    func testKnownLanguagesMapToWhisperCodes() {
        XCTAssertEqual(WhisperRecognitionLanguage.whisperCode(forAppLanguageID: "en"), "en")
        XCTAssertEqual(WhisperRecognitionLanguage.whisperCode(forAppLanguageID: "zh-Hans"), "zh")
        XCTAssertEqual(WhisperRecognitionLanguage.whisperCode(forAppLanguageID: "zh-Hant"), "zh")
        XCTAssertEqual(WhisperRecognitionLanguage.whisperCode(forAppLanguageID: "yue"), "yue")
        XCTAssertEqual(WhisperRecognitionLanguage.whisperCode(forAppLanguageID: "ja"), "ja")
        // Whisper reports Norwegian as "no" while the app catalogs it as "nb".
        XCTAssertEqual(WhisperRecognitionLanguage.whisperCode(forAppLanguageID: "nb"), "no")
    }

    func testUnknownLanguageMapsToNilRatherThanAWrongLanguage() {
        XCTAssertNil(WhisperRecognitionLanguage.whisperCode(forAppLanguageID: "xx"))
        XCTAssertNil(WhisperRecognitionLanguage.whisperCode(forAppLanguageID: ""))
    }

    func testDetectedCodesMapBackToAppLanguageIDs() {
        XCTAssertEqual(WhisperRecognitionLanguage.appLanguageID(forWhisperCode: "en"), "en")
        XCTAssertEqual(WhisperRecognitionLanguage.appLanguageID(forWhisperCode: "zh"), "zh-Hans")
        XCTAssertEqual(WhisperRecognitionLanguage.appLanguageID(forWhisperCode: "no"), "nb")
        XCTAssertEqual(WhisperRecognitionLanguage.appLanguageID(forWhisperCode: "ja"), "ja")
        XCTAssertNil(WhisperRecognitionLanguage.appLanguageID(forWhisperCode: "xx"))
    }

    func testSupportedAppLanguageIDs() {
        XCTAssertTrue(WhisperRecognitionLanguage.isSupportedAppLanguageID("auto"))
        XCTAssertTrue(WhisperRecognitionLanguage.isSupportedAppLanguageID("en"))
        XCTAssertTrue(WhisperRecognitionLanguage.isSupportedAppLanguageID("zh-Hant"))
        XCTAssertFalse(WhisperRecognitionLanguage.isSupportedAppLanguageID("xx"))
        XCTAssertFalse(WhisperRecognitionLanguage.isSupportedAppLanguageID(""))
    }

    func testInputLanguageOptionsCoverTheSupportedCatalog() {
        let options = WhisperRecognitionLanguage.inputLanguageOptions
        XCTAssertEqual(
            options.map(\.id),
            WhisperRecognitionLanguage.supportedAppLanguageIDs
        )
        XCTAssertTrue(options.contains(where: { $0.id == "zh-Hans" }))
        XCTAssertTrue(options.contains(where: { $0.id == "yue" }))
    }
}
