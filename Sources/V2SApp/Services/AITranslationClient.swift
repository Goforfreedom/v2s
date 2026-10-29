import Foundation

/// Errors from the OpenAI-compatible translation API client.
enum AITranslationError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case invalidBaseURL
    case unauthorized
    case httpStatus(Int)
    case timeout
    case invalidResponse
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing API key."
        case .invalidBaseURL:
            return "Invalid base URL."
        case .unauthorized:
            return "Authentication failed. Check the API key."
        case .httpStatus(let code):
            return "The API returned HTTP status \(code)."
        case .timeout:
            return "The translation request timed out."
        case .invalidResponse:
            return "The API returned an unexpected response."
        case .networkError(let detail):
            return "Network error: \(detail)"
        }
    }
}

/// Minimal client for OpenAI-compatible chat completions APIs, used as an
/// alternative translation engine. It is deliberately stateless: the caller
/// supplies the endpoint, model, and API key on every call, so no credential
/// is ever stored by this type. One source sentence maps to one request;
/// there is no streaming and no cross-sentence context in this version.
final class AITranslationClient: Sendable {
    struct Configuration: Sendable, Equatable {
        var baseURL: String
        var model: String
        var apiKey: String
    }

    private let session: URLSession
    private let timeout: TimeInterval

    init(session: URLSession = .shared, timeout: TimeInterval = 10) {
        self.session = session
        self.timeout = timeout
    }

    /// Translates one sentence. Returns the trimmed translation text, which
    /// may be empty when the model returns no content; the caller decides
    /// how to handle an empty result. A nil sourceLanguageName means
    /// "auto detect": the model identifies the source language from the text.
    func translate(
        _ text: String,
        sourceLanguageName: String?,
        targetLanguageName: String,
        glossary: [String: String],
        configuration: Configuration
    ) async throws -> String {
        let systemPrompt = Self.systemPrompt(
            sourceLanguageName: sourceLanguageName,
            targetLanguageName: targetLanguageName,
            glossary: glossary,
            text: text
        )
        let content = try await performChatCompletion(
            messages: [
                ChatCompletionRequest.Message(role: "system", content: systemPrompt),
                ChatCompletionRequest.Message(role: "user", content: text),
            ],
            configuration: configuration
        )
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sends a tiny request to verify that the endpoint is reachable and the
    /// API key is accepted. The reply content is ignored.
    func testConnection(configuration: Configuration) async throws {
        _ = try await performChatCompletion(
            messages: [
                ChatCompletionRequest.Message(role: "system", content: "Reply with OK."),
                ChatCompletionRequest.Message(role: "user", content: "Hi"),
            ],
            configuration: configuration
        )
    }

    private static func systemPrompt(
        sourceLanguageName: String?,
        targetLanguageName: String,
        glossary: [String: String],
        text: String
    ) -> String {
        var prompt: String
        if let sourceLanguageName, sourceLanguageName.isEmpty == false {
            prompt = "You are a translation engine. Translate the user's text from \(sourceLanguageName) to \(targetLanguageName). Output only the translation, without any explanation."
        } else {
            prompt = "You are a translation engine. Detect the language of the user's text and translate it into \(targetLanguageName). Output only the translation, without any explanation."
        }
        // Only terms that actually appear in this sentence can affect its
        // translation, so the rest are left out to keep the prompt — and the
        // time to first token — small when the glossary is large.
        let lowercasedText = text.lowercased()
        let terms = glossary
            .map { (source: $0.key.trimmingCharacters(in: .whitespacesAndNewlines), target: $0.value) }
            .filter { !$0.source.isEmpty && lowercasedText.contains($0.source.lowercased()) }
            .sorted { $0.source < $1.source }
        if terms.isEmpty == false {
            let list = terms.map { "\"\($0.source)\" -> \"\($0.target)\"" }.joined(separator: "; ")
            prompt += " Use these term translations: \(list)."
        }
        return prompt
    }

    private func performChatCompletion(
        messages: [ChatCompletionRequest.Message],
        configuration: Configuration
    ) async throws -> String {
        guard configuration.apiKey.isEmpty == false else {
            throw AITranslationError.missingAPIKey
        }
        let url = try Self.chatCompletionsURL(baseURL: configuration.baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout
        let body = ChatCompletionRequest(
            model: configuration.model,
            messages: messages,
            temperature: 0,
            stream: false
        )
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw AITranslationError.invalidResponse
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await dataWithTimeout(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AITranslationError {
            throw error
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw AITranslationError.timeout
        } catch {
            throw AITranslationError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AITranslationError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw AITranslationError.unauthorized
        default:
            throw AITranslationError.httpStatus(httpResponse.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content else {
                throw AITranslationError.invalidResponse
            }
            return content
        } catch let error as AITranslationError {
            throw error
        } catch {
            throw AITranslationError.invalidResponse
        }
    }

    /// Runs the request with a hard timeout enforced by the client itself, so
    /// a stalled connection cannot hang a live caption even when the
    /// underlying session does not time out on its own.
    private func dataWithTimeout(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask { try await self.session.data(for: request) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
                throw AITranslationError.timeout
            }
            guard let result = try await group.next() else {
                throw AITranslationError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    private static func chatCompletionsURL(baseURL: String) throws -> URL {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard trimmed.isEmpty == false else {
            throw AITranslationError.invalidBaseURL
        }
        if trimmed.hasSuffix("/chat/completions") {
            guard let url = URL(string: trimmed),
                  url.scheme == "http" || url.scheme == "https" else {
                throw AITranslationError.invalidBaseURL
            }
            return url
        }
        guard let url = URL(string: trimmed + "/chat/completions"),
              url.scheme == "http" || url.scheme == "https" else {
            throw AITranslationError.invalidBaseURL
        }
        return url
    }
}

private struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let stream: Bool
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}
