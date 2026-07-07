import Foundation

@MainActor
protocol LLMProviderProtocol {
    func complete(request: LLMRequest) async throws -> LLMResponse
}

@MainActor
protocol CompletionServicing {
    func suggestion(for scene: Scene, settings: AIPreferences) async -> String
}

@MainActor
protocol RewriteServicing {
    func rewrite(text: String, scene: Scene, settings: AIPreferences) async -> String
}

@MainActor
protocol AnalysisServicing {
    func analyze(scene: Scene, project: FrameProject, settings: AIPreferences) async -> [AIComment]
}

struct LLMRequest: Codable, Hashable {
    var task: AITask
    var provider: AIProviderKind
    var baseURL: String
    var systemPrompt: String
    var userPrompt: String
    var model: String
    var temperature: Double
    var maxTokens: Int
}

struct LLMResponse: Codable, Hashable {
    var text: String
}

enum AITask: String, Codable, Hashable {
    case autocomplete
    case rewrite
    case analyze
    case bRollGeneration
    case editingGeneration
}

@MainActor
struct MockLLMProvider: LLMProviderProtocol {
    func complete(request: LLMRequest) async throws -> LLMResponse {
        switch request.task {
        case .autocomplete:
            return LLMResponse(text: " with a clearer next beat.")
        case .rewrite:
            return LLMResponse(text: "Here is a cleaner, tighter version of the selected passage.")
        case .analyze:
            return LLMResponse(text: "The hook is clear. Consider adding a more concrete example before the explanation.")
        case .bRollGeneration:
            return LLMResponse(text: "Use a calm screen recording, a close-up insert, and one simple label animation.")
        case .editingGeneration:
            return LLMResponse(text: "Keep hard cuts, subtle punch-ins, and keyword-only captions.")
        }
    }
}

@MainActor
struct OpenAICompatibleLLMProvider: LLMProviderProtocol {
    func complete(request: LLMRequest) async throws -> LLMResponse {
        switch request.provider {
        case .disabled:
            return LLMResponse(text: "")
        case .openAICompatible, .openRouter:
            return try await completeChat(request: request)
        case .anthropicCompatible, .gemini:
            throw LLMProviderError.unsupportedProvider
        }
    }

    private func completeChat(request: LLMRequest) async throws -> LLMResponse {
        let account = request.provider.rawValue
        // The plaintext key exists only long enough to build the request header.
        // User projects and exports contain script data, not provider secrets.
        guard let apiKey = try KeychainStore.readAPIKey(account: account),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMProviderError.missingAPIKey
        }

        let base = request.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultBaseURL(for: request.provider)
            : request.baseURL
        guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else {
            throw LLMProviderError.invalidBaseURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(ChatCompletionRequest(
            model: request.model,
            messages: [
                ChatMessage(role: "system", content: request.systemPrompt),
                ChatMessage(role: "user", content: request.userPrompt)
            ],
            temperature: request.temperature,
            maxTokens: request.maxTokens
        ))

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw LLMProviderError.requestFailed
        }
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return LLMResponse(text: decoded.choices.first?.message.content ?? "")
    }

    private func defaultBaseURL(for provider: AIProviderKind) -> String {
        switch provider {
        case .openRouter:
            "https://openrouter.ai/api/v1"
        default:
            "https://api.openai.com/v1"
        }
    }
}

private enum LLMProviderError: Error {
    case missingAPIKey
    case invalidBaseURL
    case requestFailed
    case unsupportedProvider
}

private struct ChatCompletionRequest: Codable {
    var model: String
    var messages: [ChatMessage]
    var temperature: Double
    var maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct ChatMessage: Codable {
    var role: String
    var content: String
}

private struct ChatCompletionResponse: Codable {
    var choices: [ChatChoice]
}

private struct ChatChoice: Codable {
    var message: ChatMessage
}

struct PromptBuilder {
    func systemPrompt(for task: AITask) -> String {
        switch task {
        case .autocomplete:
            "Continue the YouTube script briefly. Stay natural, specific, and concise."
        case .rewrite:
            "Rewrite selected script text while preserving intent and voice."
        case .analyze:
            "Review the scene for clarity, retention, pacing, repetition, concrete examples, and weak phrasing."
        case .bRollGeneration:
            "Generate practical B-roll ideas that strengthen the meaning of the script."
        case .editingGeneration:
            "Generate restrained YouTube editing notes. Avoid timeline complexity."
        }
    }
}

@MainActor
struct CompletionService: CompletionServicing {
    var provider: any LLMProviderProtocol
    var promptBuilder = PromptBuilder()

    func suggestion(for scene: Scene, settings: AIPreferences) async -> String {
        guard settings.provider != .disabled, settings.inlineCompletionEnabled else { return "" }
        let request = LLMRequest(
            task: .autocomplete,
            provider: settings.provider,
            baseURL: settings.baseURL,
            systemPrompt: promptBuilder.systemPrompt(for: .autocomplete),
            userPrompt: scene.scriptText,
            model: settings.model,
            temperature: settings.temperature,
            maxTokens: autocompleteTokenLimit(for: settings.completionLength, fallback: settings.maxTokens)
        )
        return (try? await provider.complete(request: request).text) ?? ""
    }

    private func autocompleteTokenLimit(for length: CompletionLength, fallback: Int) -> Int {
        switch length {
        case .short:
            min(fallback, 80)
        case .medium:
            min(fallback, 180)
        case .long:
            min(fallback, 360)
        }
    }
}

@MainActor
struct RewriteService: RewriteServicing {
    var provider: any LLMProviderProtocol
    var promptBuilder = PromptBuilder()

    func rewrite(text: String, scene: Scene, settings: AIPreferences) async -> String {
        guard settings.provider != .disabled else { return text }
        let request = LLMRequest(
            task: .rewrite,
            provider: settings.provider,
            baseURL: settings.baseURL,
            systemPrompt: promptBuilder.systemPrompt(for: .rewrite),
            userPrompt: "Scene: \(scene.title)\n\n\(text)",
            model: settings.model,
            temperature: settings.temperature,
            maxTokens: settings.maxTokens
        )
        return (try? await provider.complete(request: request).text) ?? text
    }
}

@MainActor
struct AnalysisService: AnalysisServicing {
    var provider: any LLMProviderProtocol
    var promptBuilder = PromptBuilder()

    func analyze(scene: Scene, project: FrameProject, settings: AIPreferences) async -> [AIComment] {
        guard settings.provider != .disabled else {
            return [
                AIComment(
                    sceneID: scene.id,
                    segmentID: scene.textSegments.sortedByOrder.first?.id,
                    type: "AI setup",
                    severity: .note,
                    message: "Connect an AI provider to run deeper analysis.",
                    suggestion: "The service layer is provider-neutral; add an adapter without touching the UI."
                )
            ]
        }

        let request = LLMRequest(
            task: .analyze,
            provider: settings.provider,
            baseURL: settings.baseURL,
            systemPrompt: promptBuilder.systemPrompt(for: .analyze),
            userPrompt: userPrompt(scene: scene, project: project, privacyMode: settings.privacyMode),
            model: settings.model,
            temperature: settings.temperature,
            maxTokens: settings.maxTokens
        )
        let response = (try? await provider.complete(request: request).text) ?? "No analysis returned."
        return [
            AIComment(
                sceneID: scene.id,
                segmentID: scene.textSegments.sortedByOrder.first?.id,
                type: "Analysis",
                severity: .suggestion,
                message: response,
                suggestion: "Review this scene before recording."
            )
        ]
    }

    private func userPrompt(scene: Scene, project: FrameProject, privacyMode: Bool) -> String {
        if privacyMode {
            return "Scene: \(scene.title)\n\n\(scene.scriptText)"
        }
        let context = project.scenes.sortedByOrder.map { other in
            let marker = other.id == scene.id ? "CURRENT" : "CONTEXT"
            return "[\(marker)] \(other.title)\n\(other.scriptText)"
        }.joined(separator: "\n\n")
        return "Project: \(project.title)\n\n\(context)"
    }
}
