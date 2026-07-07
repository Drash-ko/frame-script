import Foundation

@MainActor
struct AppDependencies {
    var completionService: any CompletionServicing
    var rewriteService: any RewriteServicing
    var analysisService: any AnalysisServicing
    var voiceService: any VoiceServicing
    var exportService: any ExportServicing

    static let live = AppDependencies(
        completionService: CompletionService(provider: OpenAICompatibleLLMProvider()),
        rewriteService: RewriteService(provider: OpenAICompatibleLLMProvider()),
        analysisService: AnalysisService(provider: OpenAICompatibleLLMProvider()),
        voiceService: VoiceService(provider: SystemVoiceProvider()),
        exportService: ExportService()
    )
}
