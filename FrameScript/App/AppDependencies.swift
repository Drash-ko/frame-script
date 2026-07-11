import Foundation

@MainActor
struct AppDependencies {
    var rewriteService: any RewriteServicing
    var analysisService: any AnalysisServicing
    var exportService: any ExportServicing
    var llmProvider: any LLMProviderProtocol
    var providerCredentials: ProviderCredentialSession

    static let live = AppDependencies(
        rewriteService: RewriteService(provider: OpenAICompatibleLLMProvider()),
        analysisService: AnalysisService(provider: OpenAICompatibleLLMProvider()),
        exportService: ExportService(),
        llmProvider: OpenAICompatibleLLMProvider(),
        providerCredentials: ProviderCredentialSession()
    )
}
