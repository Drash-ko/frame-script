import Foundation
@testable import FrameScript
import XCTest

@MainActor
final class AIServiceLayerTests: XCTestCase {
    func testPromptLanguageUsesDominantScriptLanguageAndInterfaceFallback() {
        let prompts = PromptBuilder()

        XCTAssertEqual(prompts.responseLanguage(for: "Это достаточно длинный русский текст для определения языка.", fallback: .english), .russian)
        XCTAssertEqual(prompts.responseLanguage(for: "", fallback: .russian), .russian)
        XCTAssertTrue(prompts.systemPrompt(for: .analyze, language: .russian).contains("Russian"))
        XCTAssertTrue(prompts.systemPrompt(for: .bRollGeneration, language: .english).contains("English"))
    }

    func testAnalysisAcceptsOnlyCompleteStructuredResponseFields() async throws {
        let project = SampleData.demoProject(language: .english)
        let scene = try XCTUnwrap(project.scenes.first)
        var settings = AppSettings.defaults.aiPreferences
        settings.provider = .openAICompatible

        let service = AnalysisService(provider: StaticResponseProvider(text: #"{"title":"Hook","severity":"suggestion","message":"Make the opening more concrete.","suggestion":"Name the viewer's immediate benefit."}"#))
        let comments = try await service.analyze(scene: scene, project: project, settings: settings, interfaceLanguage: .english)

        XCTAssertEqual(comments.first?.type, "Hook")
        XCTAssertEqual(comments.first?.message, "Make the opening more concrete.")
    }

    func testAnalysisRejectsRawOrIncompleteProviderText() async {
        let project = SampleData.demoProject(language: .english)
        guard let scene = project.scenes.first else { return XCTFail("Expected demo scene") }
        var settings = AppSettings.defaults.aiPreferences
        settings.provider = .openAICompatible
        let service = AnalysisService(provider: StaticResponseProvider(text: "**broken raw output"))

        do {
            _ = try await service.analyze(scene: scene, project: project, settings: settings, interfaceLanguage: .english)
            XCTFail("Expected malformed structured analysis")
        } catch let error as LLMProviderError {
            guard case .malformedResponse = error else { return XCTFail("Wrong error: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    func testConnectionTrimsKeyExactlyBeforeStorage() async throws {
        var stored = ""
        var tested = false
        try await AIConnectionTester.saveKeyAndTest(
            pendingAPIKey: "  secret-key\n",
            saveKey: { stored = $0 },
            request: makeRequest(),
            test: { _, key in
                XCTAssertEqual(key, "secret-key")
                tested = true
            }
        )
        XCTAssertEqual(stored, "secret-key")
        XCTAssertTrue(tested)
    }

    func testFailedKeyStorageStopsBeforeNetworkTest() async {
        enum Expected: Error { case storage }
        var tested = false
        do {
            try await AIConnectionTester.saveKeyAndTest(
                pendingAPIKey: "secret",
                saveKey: { _ in throw Expected.storage },
                request: makeRequest(),
                test: { _, _ in tested = true }
            )
            XCTFail("Expected storage failure")
        } catch Expected.storage {
            XCTAssertFalse(tested)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGoogleConnectionUsesOfficialEncodedModelEndpoint() async throws {
        var captured: URLRequest?
        let provider = makeProvider { request in
            captured = request
            return self.response(status: 200, url: request.url!, body: #"{"id":"models/gemini custom","object":"model","owned_by":"google"}"#)
        }
        var request = makeRequest()
        request.model = "gemini/custom model"

        try await provider.testConnection(request: request)

        XCTAssertEqual(captured?.httpMethod, "GET")
        XCTAssertEqual(captured?.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/openai/models/gemini%2Fcustom%20model")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    func testGoogleConnectionMaps401404429AndMalformedSuccessDifferently() async {
        for status in [401, 403, 404, 429] {
            let provider = makeProvider { request in
                self.response(status: status, url: request.url!, body: #"{"error":{"message":"failure","status":"STATUS","code":1}}"#)
            }
            do {
                try await provider.testConnection(request: makeRequest())
                XCTFail("Expected HTTP failure")
            } catch let error as LLMProviderError {
                XCTAssertEqual(error, .httpStatus(status, "STATUS · 1"))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        let malformed = makeProvider { request in
            self.response(status: 200, url: request.url!, body: #"{"unexpected":true}"#)
        }
        do {
            try await malformed.testConnection(request: makeRequest())
            XCTFail("Expected malformed response")
        } catch let error as LLMProviderError {
            guard case .malformedResponse = error else { return XCTFail("Wrong error: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGoogleConnectionMapsTransportFailureToNetworkError() async {
        let provider = makeProvider { _ in throw URLError(.notConnectedToInternet) }
        do {
            try await provider.testConnection(request: makeRequest())
            XCTFail("Expected network failure")
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, .network(String(URLError.Code.notConnectedToInternet.rawValue)))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEveryProviderConnectionReadsKeyExactlyOnce() async throws {
        for providerKind in [AIProviderKind.openAICompatible, .openRouter, .groq, .googleAIStudio] {
            var reads = 0
            let provider = OpenAICompatibleLLMProvider(
                transport: { request in
                    if providerKind == .googleAIStudio {
                        return self.response(status: 200, url: request.url!, body: #"{"id":"models/gemini"}"#)
                    }
                    return self.response(status: 200, url: request.url!, body: #"{"choices":[{"message":{"content":"OK"},"finish_reason":"stop"}]}"#)
                },
                apiKeyReader: { _ in reads += 1; return "secret" }
            )
            var request = makeRequest()
            request.provider = providerKind
            request.baseURL = OpenAICompatibleLLMProvider.defaultBaseURL(for: providerKind)
            request.model = AIProviderConfigurationStore.defaultModel(for: providerKind)

            try await provider.testConnection(request: request)

            XCTAssertEqual(reads, 1, "\(providerKind) should read Keychain once")
        }
    }

    func testSuppliedSavedKeySkipsKeychainRead() async throws {
        var reads = 0
        let provider = OpenAICompatibleLLMProvider(
            transport: { request in
                self.response(status: 200, url: request.url!, body: #"{"id":"models/gemini"}"#)
            },
            apiKeyReader: { _ in reads += 1; return "unexpected" }
        )

        try await provider.testConnection(request: makeRequest(), apiKey: "saved-in-memory")

        XCTAssertEqual(reads, 0)
    }

    func testGenerationReadsKeyExactlyOnce() async throws {
        var reads = 0
        let provider = OpenAICompatibleLLMProvider(
            transport: { request in
                self.response(status: 200, url: request.url!, body: #"{"choices":[{"message":{"content":"OK"},"finish_reason":"stop"}]}"#)
            },
            apiKeyReader: { _ in reads += 1; return "secret" }
        )
        var request = makeRequest()
        request.provider = .openRouter
        request.baseURL = OpenAICompatibleLLMProvider.defaultBaseURL(for: .openRouter)

        _ = try await provider.complete(request: request)

        XCTAssertEqual(reads, 1)
    }

    func testStringAndTextPartArrayContentsDecode() async throws {
        let stringProvider = makeProvider { request in
            self.response(status: 200, url: request.url!, body: #"{"choices":[{"message":{"content":"Hello"},"finish_reason":"stop"}]}"#)
        }
        let partsProvider = makeProvider { request in
            self.response(status: 200, url: request.url!, body: #"{"choices":[{"message":{"content":[{"type":"text","text":"Hello "},{"type":"text","text":"world"}]},"finish_reason":"stop"}]}"#)
        }

        let stringResponse = try await stringProvider.complete(request: makeRequest())
        let partsResponse = try await partsProvider.complete(request: makeRequest())
        XCTAssertEqual(stringResponse.text, "Hello")
        XCTAssertEqual(partsResponse.text, "Hello world")
    }

    func testNullContentAtTokenLimitIsNotInvalidJSON() async {
        let provider = makeProvider { request in
            self.response(status: 200, url: request.url!, body: #"{"choices":[{"message":{"content":null},"finish_reason":"length"}]}"#)
        }
        do {
            _ = try await provider.complete(request: makeRequest())
            XCTFail("Expected token limit diagnostic")
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, .malformedResponse("The provider reached its token limit before returning text."))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeProvider(
        transport: @escaping OpenAICompatibleLLMProvider.Transport
    ) -> OpenAICompatibleLLMProvider {
        OpenAICompatibleLLMProvider(transport: transport, apiKeyReader: { _ in "secret" })
    }

    private func makeRequest() -> LLMRequest {
        LLMRequest(
            task: .autocomplete,
            provider: .googleAIStudio,
            baseURL: OpenAICompatibleLLMProvider.defaultBaseURL(for: .googleAIStudio),
            systemPrompt: "System",
            userPrompt: "User",
            model: "gemini-3.5-flash",
            temperature: 0,
            maxTokens: 128
        )
    }

    private func response(status: Int, url: URL, body: String) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(body.utf8), response)
    }
}

@MainActor
private struct StaticResponseProvider: LLMProviderProtocol {
    let text: String

    func complete(request: LLMRequest) async throws -> LLMResponse {
        LLMResponse(text: text)
    }
}
