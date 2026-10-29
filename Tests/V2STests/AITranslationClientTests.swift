import Foundation
import XCTest
@testable import v2s

final class AITranslationClientTests: XCTestCase {
    /// Intercepts every request so no test ever touches a real network.
    private final class MockURLProtocol: URLProtocol {
        static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool {
            true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let handler = Self.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.unknown))
                return
            }
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    override func setUp() {
        super.setUp()
        MockURLProtocol.handler = nil
    }

    private func makeClient(timeout: TimeInterval = 10) -> AITranslationClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return AITranslationClient(session: URLSession(configuration: configuration), timeout: timeout)
    }

    private func makeConfiguration(
        baseURL: String = "https://api.example.com/v1",
        model: String = "test-model",
        apiKey: String = "test-key"
    ) -> AITranslationClient.Configuration {
        AITranslationClient.Configuration(baseURL: baseURL, model: model, apiKey: apiKey)
    }

    private static func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.example.com/v1/chat/completions")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private static func chatCompletionJSON(content: String) -> Data {
        let escaped = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return Data("{\"choices\":[{\"message\":{\"content\":\"\(escaped)\"}}]}".utf8)
    }

    func testTranslateReturnsTrimmedContent() async throws {
        MockURLProtocol.handler = { _ in
            (Self.httpResponse(statusCode: 200), Self.chatCompletionJSON(content: "  你好世界  "))
        }
        let result = try await makeClient().translate(
            "Hello world",
            sourceLanguageName: "English",
            targetLanguageName: "Simplified Chinese",
            glossary: [:],
            configuration: makeConfiguration()
        )
        XCTAssertEqual(result, "你好世界")
    }

    func testTranslateSendsLanguagesGlossaryAndAuthHeader() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.handler = { request in
            capturedRequest = request
            return (Self.httpResponse(statusCode: 200), Self.chatCompletionJSON(content: "Bonjour"))
        }
        let result = try await makeClient().translate(
            "Hello AI",
            sourceLanguageName: "English",
            targetLanguageName: "French",
            glossary: ["AI": "intelligence artificielle"],
            configuration: makeConfiguration()
        )
        XCTAssertEqual(result, "Bonjour")
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.url?.path, "/v1/chat/completions")
        let body = try XCTUnwrap(request.httpBody)
        let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(bodyString.contains("English"))
        XCTAssertTrue(bodyString.contains("French"))
        XCTAssertTrue(bodyString.contains("intelligence artificielle"))
        XCTAssertTrue(bodyString.contains("test-model"))
    }

    func testTranslateOmitsGlossaryTermsAbsentFromText() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.handler = { request in
            capturedRequest = request
            return (Self.httpResponse(statusCode: 200), Self.chatCompletionJSON(content: "Bonjour"))
        }
        _ = try await makeClient().translate(
            "Hello",
            sourceLanguageName: "English",
            targetLanguageName: "French",
            glossary: ["AI": "intelligence artificielle"],
            configuration: makeConfiguration()
        )
        let request = try XCTUnwrap(capturedRequest)
        let body = try XCTUnwrap(request.httpBody)
        let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertFalse(bodyString.contains("intelligence artificielle"))
    }

    func testTranslateAutoDetectPromptOmitsSourceLanguage() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.handler = { request in
            capturedRequest = request
            return (Self.httpResponse(statusCode: 200), Self.chatCompletionJSON(content: "Bonjour"))
        }
        _ = try await makeClient().translate(
            "Hello",
            sourceLanguageName: nil,
            targetLanguageName: "French",
            glossary: [:],
            configuration: makeConfiguration()
        )
        let request = try XCTUnwrap(capturedRequest)
        let body = try XCTUnwrap(request.httpBody)
        let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(bodyString.contains("Detect the language"))
        XCTAssertTrue(bodyString.contains("French"))
        XCTAssertFalse(bodyString.contains("from English"))
    }

    func testTranslateMaps401ToUnauthorized() async throws {
        MockURLProtocol.handler = { _ in
            (Self.httpResponse(statusCode: 401), Data())
        }
        await XCTAssertThrowsError(
            try await makeClient().translate(
                "Hello",
                sourceLanguageName: "English",
                targetLanguageName: "French",
                glossary: [:],
                configuration: makeConfiguration()
            )
        ) { error in
            XCTAssertEqual(error as? AITranslationError, .unauthorized)
        }
    }

    func testTranslateMaps500ToHTTPStatus() async throws {
        MockURLProtocol.handler = { _ in
            (Self.httpResponse(statusCode: 500), Data())
        }
        await XCTAssertThrowsError(
            try await makeClient().translate(
                "Hello",
                sourceLanguageName: "English",
                targetLanguageName: "French",
                glossary: [:],
                configuration: makeConfiguration()
            )
        ) { error in
            XCTAssertEqual(error as? AITranslationError, .httpStatus(500))
        }
    }

    func testTranslateMapsMalformedJSONToInvalidResponse() async throws {
        MockURLProtocol.handler = { _ in
            (Self.httpResponse(statusCode: 200), Data("not json".utf8))
        }
        await XCTAssertThrowsError(
            try await makeClient().translate(
                "Hello",
                sourceLanguageName: "English",
                targetLanguageName: "French",
                glossary: [:],
                configuration: makeConfiguration()
            )
        ) { error in
            XCTAssertEqual(error as? AITranslationError, .invalidResponse)
        }
    }

    func testTranslateTimesOutWhenServerNeverResponds() async throws {
        MockURLProtocol.handler = { _ in
            // Blocks the protocol thread; the client's own timeout must win.
            Thread.sleep(forTimeInterval: 5)
            return (Self.httpResponse(statusCode: 200), Self.chatCompletionJSON(content: "Late"))
        }
        await XCTAssertThrowsError(
            try await makeClient(timeout: 0.2).translate(
                "Hello",
                sourceLanguageName: "English",
                targetLanguageName: "French",
                glossary: [:],
                configuration: makeConfiguration()
            )
        ) { error in
            XCTAssertEqual(error as? AITranslationError, .timeout)
        }
    }

    func testTranslateWithEmptyAPIKeyThrowsWithoutRequest() async throws {
        var requestMade = false
        MockURLProtocol.handler = { _ in
            requestMade = true
            return (Self.httpResponse(statusCode: 200), Self.chatCompletionJSON(content: "Hi"))
        }
        await XCTAssertThrowsError(
            try await makeClient().translate(
                "Hello",
                sourceLanguageName: "English",
                targetLanguageName: "French",
                glossary: [:],
                configuration: makeConfiguration(apiKey: "")
            )
        ) { error in
            XCTAssertEqual(error as? AITranslationError, .missingAPIKey)
        }
        XCTAssertFalse(requestMade)
    }

    func testTranslateWithInvalidBaseURLThrowsWithoutRequest() async throws {
        var requestMade = false
        MockURLProtocol.handler = { _ in
            requestMade = true
            return (Self.httpResponse(statusCode: 200), Self.chatCompletionJSON(content: "Hi"))
        }
        await XCTAssertThrowsError(
            try await makeClient().translate(
                "Hello",
                sourceLanguageName: "English",
                targetLanguageName: "French",
                glossary: [:],
                configuration: makeConfiguration(baseURL: "://bad")
            )
        ) { error in
            XCTAssertEqual(error as? AITranslationError, .invalidBaseURL)
        }
        XCTAssertFalse(requestMade)
    }

    func testTestConnectionSucceedsOnValidResponse() async throws {
        MockURLProtocol.handler = { _ in
            (Self.httpResponse(statusCode: 200), Self.chatCompletionJSON(content: "OK"))
        }
        try await makeClient().testConnection(configuration: makeConfiguration())
    }
}
