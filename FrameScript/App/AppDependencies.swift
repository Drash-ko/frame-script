import Foundation

@MainActor
struct AppDependencies {
    var rewriteService: any RewriteServicing
    var analysisService: any AnalysisServicing
    var exportService: any ExportServicing

    static let live = AppDependencies(
        rewriteService: RewriteService(provider: OpenAICompatibleLLMProvider()),
        analysisService: AnalysisService(provider: OpenAICompatibleLLMProvider()),
        exportService: ExportService()
    )
}
