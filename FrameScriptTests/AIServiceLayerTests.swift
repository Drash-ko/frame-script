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

    func testSystemFallbackResolvesMacOSLanguage() {
        let prompts = PromptBuilder()

        XCTAssertEqual(prompts.responseLanguage(for: "", fallback: .system, preferredLanguages: ["ru-RU"]), .russian)
        XCTAssertEqual(prompts.responseLanguage(for: "", fallback: .system, preferredLanguages: ["en-GB"]), .english)
    }

    func testAnalysisAcceptsOnlyCompleteStructuredResponseFields() async throws {
        let project = SampleData.demoProject(language: .english)
        let scene = try XCTUnwrap(project.scenes.first)
        var settings = AppSettings.defaults.aiPreferences
        settings.provider = .openAICompatible

        let service = AnalysisService(provider: StaticResponseProvider(text: #"{"title":"Hook","severity":"suggestion","message":"Make the opening more concrete.","suggestion":"Name the viewer's immediate benefit."}"#))
        let comments = try await service.analyze(scene: scene, project: project, settings: settings, interfaceLanguage: .english, apiKey: "secret")

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
            _ = try await service.analyze(scene: scene, project: project, settings: settings, interfaceLanguage: .english, apiKey: "secret")
            XCTFail("Expected malformed structured analysis")
        } catch let error as LLMProviderError {
            guard case .malformedResponse = error else { return XCTFail("Wrong error: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStructuredAnalysisDecodesPlainFencedWrappedAndExtraFields() throws {
        let object = #"{"title":"Hook","severity":"suggestion","message":"Make the opening concrete.","suggestion":"Name the immediate benefit.","ignored":true}"#
        let values = [
            object,
            "```json\n\(object)\n```",
            "{\"analysis\":\(object)}",
            "[\(object)]"
        ]

        for value in values {
            XCTAssertEqual(try AnalysisResponse.decode(from: value).title, "Hook")
        }
    }

    func testStructuredAnalysisRejectsIncompleteProse() {
        for value in ["This scene needs a stronger hook.", #"{"title":"Hook","severity":"note","message":"Incomplete"}"#] {
            XCTAssertThrowsError(try AnalysisResponse.decode(from: value))
        }
    }

    func testOneAnalysisReadsKeyOnceAndSecondAnalysisAddsNoRead() async throws {
        var reads = 0
        let session = ProviderCredentialSession(reader: { _ in reads += 1; return "secret" })
        let response = #"{"title":"Hook","severity":"suggestion","message":"Make the opening concrete.","suggestion":"Name the immediate benefit."}"#
        let provider = StaticResponseProvider(text: response)
        let dependencies = AppDependencies(
            rewriteService: RewriteService(provider: provider),
            analysisService: AnalysisService(provider: provider),
            exportService: ExportService(),
            llmProvider: provider,
            providerCredentials: session
        )
        let appState = AppState(dependencies: dependencies)
        appState.openDemoProject()
        appState.settings.aiPreferences.provider = .openRouter

        await appState.analyzeSelectedScene()
        XCTAssertEqual(reads, 1)
        await appState.analyzeSelectedScene()
        XCTAssertEqual(reads, 1)
    }
    func testConnectionTrimsKeyExactlyBeforeStorage() async throws {
        var stored = ""
        var tested = false
        try await AIConnectionTester.saveKeyAndTest(
            pendingAPIKey: "  secret-key\n",
            saveKey: { stored = $0 },
            acquireKey: { "stored-key" },
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
                acquireKey: { "stored-key" },
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

        try await provider.testConnection(request: request, apiKey: "secret")

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
                try await provider.testConnection(request: makeRequest(), apiKey: "secret")
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
            try await malformed.testConnection(request: makeRequest(), apiKey: "secret")
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
            try await provider.testConnection(request: makeRequest(), apiKey: "secret")
            XCTFail("Expected network failure")
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, .network(String(URLError.Code.notConnectedToInternet.rawValue)))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProviderCancellationPreservesCancellationInsteadOfMappingToNetworkError() async {
        let provider = makeProvider { _ in throw URLError(.cancelled) }

        do {
            _ = try await provider.complete(request: makeRequest(), apiKey: "secret")
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertNil(AppError.ai(LLMProviderError.network(String(URLError.Code.cancelled.rawValue))))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancelledAutocompleteReturnsNilWithoutAlert() async {
        let provider = CancelledAutocompleteProvider()
        let errorCenter = ErrorCenter()
        let appState = AppState(
            errorCenter: errorCenter,
            dependencies: AppDependencies(
                rewriteService: RewriteService(provider: provider),
                analysisService: AnalysisService(provider: provider),
                exportService: ExportService(),
                llmProvider: provider,
                providerCredentials: ProviderCredentialSession(reader: { _ in "secret" })
            )
        )
        appState.settings.aiPreferences.provider = .openAICompatible

        let result = await appState.autocompleteScript(context: "Draft")
        XCTAssertNil(result)
        XCTAssertNil(errorCenter.presentedError)
    }

    func testCredentialSessionReadsOnceThenReusesKey() throws {
        var reads = 0
        let session = ProviderCredentialSession(reader: { _ in reads += 1; return "secret" })

        XCTAssertEqual(try session.apiKey(for: .openRouter), "secret")
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(try session.apiKey(for: .openRouter), "secret")
        XCTAssertEqual(reads, 1)
    }

    func testCredentialSaveAndDeleteInvalidationRequiresNextRead() throws {
        var reads = 0
        let session = ProviderCredentialSession(reader: { _ in reads += 1; return "secret-\(reads)" })

        XCTAssertEqual(try session.apiKey(for: .groq), "secret-1")
        session.invalidate(for: .groq)
        XCTAssertEqual(try session.apiKey(for: .groq), "secret-2")
        session.invalidate(for: .groq)
        XCTAssertEqual(try session.apiKey(for: .groq), "secret-3")
    }

    func testSettingsNavigationDoesNotReadCredentials() {
        var reads = 0
        let session = ProviderCredentialSession(reader: { _ in reads += 1; return "secret" })
        let provider = StaticResponseProvider(text: "unused")
        let appState = AppState(dependencies: AppDependencies(
            rewriteService: RewriteService(provider: provider),
            analysisService: AnalysisService(provider: provider),
            exportService: ExportService(),
            llmProvider: provider,
            providerCredentials: session
        ))

        appState.openSettings()
        appState.openSettings(tab: .ai)
        XCTAssertEqual(reads, 0)
    }

    func testProviderUsesExplicitKeyWithoutCredentialLookup() async throws {
        var authorization = ""
        let provider = OpenAICompatibleLLMProvider(transport: { request in
            authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
            return self.response(status: 200, url: request.url!, body: #"{"choices":[{"message":{"content":"OK"},"finish_reason":"stop"}]}"#)
        })
        var request = makeRequest()
        request.provider = .openRouter
        request.baseURL = OpenAICompatibleLLMProvider.defaultBaseURL(for: .openRouter)

        _ = try await provider.complete(request: request, apiKey: "secret")
        XCTAssertEqual(authorization, "Bearer secret")
    }

    func testAnalysisRequestIncludesJSONSchemaResponseFormat() async throws {
        var body: [String: Any] = [:]
        let provider = OpenAICompatibleLLMProvider(transport: { request in
            body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any] ?? [:]
            return self.response(status: 200, url: request.url!, body: #"{"choices":[{"message":{"content":"{}"},"finish_reason":"stop"}]}"#)
        })
        var request = makeRequest()
        request.task = .analyze

        _ = try await provider.complete(request: request, apiKey: "secret")

        let format = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertNotNil(format["json_schema"])
    }

    func testAnalysisSucceedsOnFirstCompleteResponse() async throws {
        var requests: [URLRequest] = []
        let provider = makeProvider { request in
            requests.append(request)
            return self.response(status: 200, url: request.url!, body: self.chatResponse(
                content: #"{"title":"Hook","severity":"suggestion","message":"Make the opening concrete.","suggestion":"Name the immediate benefit."}"#,
                finishReason: "stop"
            ))
        }
        let (scene, project, settings) = try analysisInputs()

        let comments = try await AnalysisService(provider: provider).analyze(
            scene: scene, project: project, settings: settings, apiKey: "same-key"
        )

        XCTAssertEqual(comments.first?.type, "Hook")
        XCTAssertEqual(requests.count, 1)
        XCTAssertGreaterThanOrEqual(try maxTokens(in: XCTUnwrap(requests.first)), 1_024)
    }

    func testAnalysisRetriesOneTruncatedResponseThenSucceeds() async throws {
        var requests: [URLRequest] = []
        let provider = makeProvider { request in
            requests.append(request)
            let truncated = requests.count == 1
            return self.response(status: 200, url: request.url!, body: self.chatResponse(
                content: truncated
                    ? #"{"title":"Partial""#
                    : #"{"title":"Hook","severity":"suggestion","message":"Make the opening concrete.","suggestion":"Name the immediate benefit."}"#,
                finishReason: truncated ? "length" : "stop"
            ))
        }
        let (scene, project, settings) = try analysisInputs()

        let comments = try await AnalysisService(provider: provider).analyze(
            scene: scene, project: project, settings: settings, apiKey: "same-key"
        )

        XCTAssertEqual(comments.first?.type, "Hook")
        XCTAssertEqual(requests.count, 2)
        XCTAssertGreaterThanOrEqual(try maxTokens(in: requests[0]), 1_024)
        XCTAssertGreaterThanOrEqual(try maxTokens(in: requests[1]), 2_048)
        XCTAssertGreaterThan(try maxTokens(in: requests[1]), try maxTokens(in: requests[0]))
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer same-key", "Bearer same-key"])
    }

    func testAnalysisReturnsMalformedResponseAfterTwoTruncations() async throws {
        var requests: [URLRequest] = []
        let provider = makeProvider { request in
            requests.append(request)
            return self.response(status: 200, url: request.url!, body: self.chatResponse(
                content: #"{"title":"Partial""#,
                finishReason: "length"
            ))
        }
        let (scene, project, settings) = try analysisInputs()

        do {
            _ = try await AnalysisService(provider: provider).analyze(
                scene: scene, project: project, settings: settings, apiKey: "same-key"
            )
            XCTFail("Expected malformed response")
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, .malformedResponse(nil))
        }
        XCTAssertEqual(requests.count, 2)
    }

    func testStringAndTextPartArrayContentsDecode() async throws {
        let stringProvider = makeProvider { request in
            self.response(status: 200, url: request.url!, body: #"{"choices":[{"message":{"content":"Hello"},"finish_reason":"stop"}]}"#)
        }
        let partsProvider = makeProvider { request in
            self.response(status: 200, url: request.url!, body: #"{"choices":[{"message":{"content":[{"type":"text","text":"Hello "},{"type":"text","text":"world"}]},"finish_reason":"stop"}]}"#)
        }

        let stringResponse = try await stringProvider.complete(request: makeRequest(), apiKey: "secret")
        let partsResponse = try await partsProvider.complete(request: makeRequest(), apiKey: "secret")
        XCTAssertEqual(stringResponse.text, "Hello")
        XCTAssertEqual(partsResponse.text, "Hello world")
    }

    func testNullContentAtTokenLimitIsNotInvalidJSON() async {
        let provider = makeProvider { request in
            self.response(status: 200, url: request.url!, body: #"{"choices":[{"message":{"content":null},"finish_reason":"length"}]}"#)
        }
        do {
            _ = try await provider.complete(request: makeRequest(), apiKey: "secret")
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
        OpenAICompatibleLLMProvider(transport: transport)
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

    private func analysisInputs() throws -> (Scene, FrameProject, AIPreferences) {
        let project = SampleData.demoProject(language: .english)
        let scene = try XCTUnwrap(project.scenes.first)
        var settings = AppSettings.defaults.aiPreferences
        settings.provider = .googleAIStudio
        settings.maxTokens = 128
        return (scene, project, settings)
    }

    private func maxTokens(in request: URLRequest) throws -> Int {
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        return try XCTUnwrap(body?["max_tokens"] as? Int)
    }

    private func chatResponse(content: String, finishReason: String) -> String {
        let object: [String: Any] = [
            "choices": [["message": ["content": content], "finish_reason": finishReason]]
        ]
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
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

    func complete(request: LLMRequest, apiKey: String) async throws -> LLMResponse {
        LLMResponse(text: text)
    }
}

@MainActor
private struct CancelledAutocompleteProvider: LLMProviderProtocol {
    func complete(request: LLMRequest, apiKey: String) async throws -> LLMResponse {
        throw LLMProviderError.network(String(URLError.Code.cancelled.rawValue))
    }
}
