import Foundation

/// Maps the app's input-language IDs to Whisper language codes.
///
/// Whisper runs one multilingual model, so the recognizer itself can detect
/// the spoken language: an "auto" input passes nil through to WhisperKit
/// instead of needing a concrete recognizer locale (the old
/// recognitionLanguageID workaround, which tracked the last concrete pick).
/// IDs outside the table also map to nil, so a stale settings value degrades
/// to detection rather than to a wrong language.
enum WhisperRecognitionLanguage {
    /// Whisper code for an app language ID, or nil for true auto-detection.
    /// Both "auto" and unknown IDs yield nil.
    static func whisperCode(forAppLanguageID identifier: String) -> String? {
        whisperCodesByAppLanguageID[identifier]
    }

    /// App language ID for a Whisper code reported by a transcription result.
    /// Chinese collapses to Simplified (Whisper reports a single "zh" code),
    /// and Norwegian reports as "no" while the app catalogs it as "nb".
    static func appLanguageID(forWhisperCode code: String) -> String? {
        if let mapped = appLanguageIDsByWhisperCode[code] {
            return mapped
        }
        return whisperCodesByAppLanguageID[code] != nil ? code : nil
    }

    static func isSupportedAppLanguageID(_ identifier: String) -> Bool {
        identifier == TranslationCoordinator.automaticSourceLanguageID
            || whisperCodesByAppLanguageID[identifier] != nil
    }

    /// Picker options for the Whisper-supported catalog. Display names come
    /// from the app catalog so they localize like the other pickers; callers
    /// prepend the "auto" entry.
    static var inputLanguageOptions: [LanguageOption] {
        supportedAppLanguageIDs.map { id in
            LanguageOption(id: id, displayName: LanguageCatalog.displayName(for: id))
        }
    }

    /// App language IDs the multilingual Whisper models cover, in catalog order.
    static let supportedAppLanguageIDs: [String] = [
        "en", "zh-Hans", "zh-Hant", "yue", "es", "de", "ja", "fr", "it", "ko",
        "pt", "ar", "ca", "cs", "da", "fi", "el", "he", "hi", "hr", "hu", "id",
        "ms", "nb", "nl", "pl", "ro", "ru", "sk", "sv", "th", "tr", "uk", "vi",
    ]

    private static let whisperCodesByAppLanguageID: [String: String] = [
        "en": "en", "zh-Hans": "zh", "zh-Hant": "zh", "yue": "yue",
        "es": "es", "de": "de", "ja": "ja", "fr": "fr", "it": "it", "ko": "ko",
        "pt": "pt", "ar": "ar", "ca": "ca", "cs": "cs", "da": "da", "fi": "fi",
        "el": "el", "he": "he", "hi": "hi", "hr": "hr", "hu": "hu", "id": "id",
        "ms": "ms", "nb": "no", "nl": "nl", "pl": "pl", "ro": "ro", "ru": "ru",
        "sk": "sk", "sv": "sv", "th": "th", "tr": "tr", "uk": "uk", "vi": "vi",
    ]

    private static let appLanguageIDsByWhisperCode: [String: String] = [
        "zh": "zh-Hans",
        "no": "nb",
    ]
}
