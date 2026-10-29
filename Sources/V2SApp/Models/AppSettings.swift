import Foundation

/// Which engine performs translation. `.apple` is the built-in on-device
/// Translation framework; `.ai` sends subtitle text (never audio) to a
/// user-configured OpenAI-compatible API.
enum TranslationEngine: String, Codable, CaseIterable, Sendable {
    case apple
    case ai
}

/// Presets for the AI translation endpoint. `.custom` leaves the base URL
/// and model entirely to the user.
enum AITranslationProvider: String, Codable, CaseIterable, Sendable {
    case openAI
    case deepSeek
    case custom

    var defaultBaseURL: String {
        switch self {
        case .openAI:
            return "https://api.openai.com/v1"
        case .deepSeek:
            return "https://api.deepseek.com/v1"
        case .custom:
            return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI:
            return "gpt-4o-mini"
        case .deepSeek:
            return "deepseek-chat"
        case .custom:
            return ""
        }
    }
}

struct AppSettings: Codable {
    var selectedSourceID: String?
    var selectedSourceIDs: [String]
    var sourceLanguageOverrides: [String: String]
    var sourceOutputLanguageOverrides: [String: String]
    var inputLanguageID: String
    /// Whisper recognition model raw value ("tiny", "base", "small").
    /// Old files without it decode to "base"; the retired
    /// recognitionLanguageID key is ignored by JSONDecoder when present.
    var recognitionModel: String
    var outputLanguageID: String
    var interfaceLanguageID: String?
    var overlayStyle: OverlayStyle
    var subtitleMode: SubtitleMode
    var subtitleDisplayMode: SubtitleDisplayMode
    var glossary: [String: String]
    var translationEngine: TranslationEngine
    var aiTranslationProvider: AITranslationProvider
    var aiTranslationBaseURL: String
    var aiTranslationModel: String
    var aiTranslationFallbackToApple: Bool

    static let `default` = AppSettings(
        selectedSourceID: nil,
        selectedSourceIDs: [],
        sourceLanguageOverrides: [:],
        sourceOutputLanguageOverrides: [:],
        inputLanguageID: "en",
        recognitionModel: "base",
        outputLanguageID: "zh-Hans",
        interfaceLanguageID: nil,
        overlayStyle: .default,
        subtitleMode: .balanced,
        subtitleDisplayMode: .both,
        glossary: [:],
        translationEngine: .apple,
        aiTranslationProvider: .openAI,
        aiTranslationBaseURL: "https://api.openai.com/v1",
        aiTranslationModel: "gpt-4o-mini",
        aiTranslationFallbackToApple: true
    )

    // Custom decoder so existing settings files load cleanly as new fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedSourceID = try? c.decodeIfPresent(String.self, forKey: .selectedSourceID)
        selectedSourceIDs = (try? c.decodeIfPresent([String].self, forKey: .selectedSourceIDs))
            ?? selectedSourceID.map { [$0] }
            ?? AppSettings.default.selectedSourceIDs
        sourceLanguageOverrides = (try? c.decodeIfPresent([String: String].self, forKey: .sourceLanguageOverrides))
            ?? AppSettings.default.sourceLanguageOverrides
        sourceOutputLanguageOverrides = (try? c.decodeIfPresent([String: String].self, forKey: .sourceOutputLanguageOverrides))
            ?? AppSettings.default.sourceOutputLanguageOverrides
        inputLanguageID = (try? c.decodeIfPresent(String.self, forKey: .inputLanguageID))
            ?? AppSettings.default.inputLanguageID
        recognitionModel = (try? c.decodeIfPresent(String.self, forKey: .recognitionModel))
            ?? AppSettings.default.recognitionModel
        outputLanguageID = (try? c.decodeIfPresent(String.self, forKey: .outputLanguageID))
            ?? AppSettings.default.outputLanguageID
        interfaceLanguageID = try? c.decodeIfPresent(String.self, forKey: .interfaceLanguageID)
        overlayStyle = (try? c.decodeIfPresent(OverlayStyle.self, forKey: .overlayStyle))
            ?? AppSettings.default.overlayStyle
        subtitleMode = (try? c.decodeIfPresent(SubtitleMode.self, forKey: .subtitleMode))
            ?? AppSettings.default.subtitleMode
        subtitleDisplayMode = (try? c.decodeIfPresent(SubtitleDisplayMode.self, forKey: .subtitleDisplayMode))
            ?? AppSettings.default.subtitleDisplayMode
        glossary = (try? c.decodeIfPresent([String: String].self, forKey: .glossary))
            ?? AppSettings.default.glossary
        translationEngine = (try? c.decodeIfPresent(TranslationEngine.self, forKey: .translationEngine))
            ?? AppSettings.default.translationEngine
        aiTranslationProvider = (try? c.decodeIfPresent(AITranslationProvider.self, forKey: .aiTranslationProvider))
            ?? AppSettings.default.aiTranslationProvider
        aiTranslationBaseURL = (try? c.decodeIfPresent(String.self, forKey: .aiTranslationBaseURL))
            ?? AppSettings.default.aiTranslationBaseURL
        aiTranslationModel = (try? c.decodeIfPresent(String.self, forKey: .aiTranslationModel))
            ?? AppSettings.default.aiTranslationModel
        aiTranslationFallbackToApple = (try? c.decodeIfPresent(Bool.self, forKey: .aiTranslationFallbackToApple))
            ?? AppSettings.default.aiTranslationFallbackToApple
    }

    init(
        selectedSourceID: String?,
        selectedSourceIDs: [String] = [],
        sourceLanguageOverrides: [String: String] = [:],
        sourceOutputLanguageOverrides: [String: String] = [:],
        inputLanguageID: String,
        recognitionModel: String = "base",
        outputLanguageID: String,
        interfaceLanguageID: String?,
        overlayStyle: OverlayStyle,
        subtitleMode: SubtitleMode,
        subtitleDisplayMode: SubtitleDisplayMode,
        glossary: [String: String],
        translationEngine: TranslationEngine = .apple,
        aiTranslationProvider: AITranslationProvider = .openAI,
        aiTranslationBaseURL: String = "https://api.openai.com/v1",
        aiTranslationModel: String = "gpt-4o-mini",
        aiTranslationFallbackToApple: Bool = true
    ) {
        self.selectedSourceID = selectedSourceID
        self.selectedSourceIDs = selectedSourceIDs
        self.sourceLanguageOverrides = sourceLanguageOverrides
        self.sourceOutputLanguageOverrides = sourceOutputLanguageOverrides
        self.inputLanguageID  = inputLanguageID
        self.recognitionModel = recognitionModel
        self.outputLanguageID = outputLanguageID
        self.interfaceLanguageID = interfaceLanguageID
        self.overlayStyle     = overlayStyle
        self.subtitleMode     = subtitleMode
        self.subtitleDisplayMode = subtitleDisplayMode
        self.glossary         = glossary
        self.translationEngine = translationEngine
        self.aiTranslationProvider = aiTranslationProvider
        self.aiTranslationBaseURL = aiTranslationBaseURL
        self.aiTranslationModel = aiTranslationModel
        self.aiTranslationFallbackToApple = aiTranslationFallbackToApple
    }
}
