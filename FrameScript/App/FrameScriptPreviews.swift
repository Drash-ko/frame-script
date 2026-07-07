import SwiftData
import SwiftUI

enum FrameScriptPreviewSupport {
    @MainActor
    static var appState: AppState {
        AppState()
    }

    @MainActor
    static var modelContainer: ModelContainer {
        let schema = Schema([
            FrameProject.self,
            Scene.self,
            TextSegment.self,
            BRollItem.self,
            EditingItem.self,
            AIComment.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }
}

#Preview("FrameScript") {
    AppRootView()
        .environment(FrameScriptPreviewSupport.appState)
        .modelContainer(FrameScriptPreviewSupport.modelContainer)
        .frame(width: 1180, height: 760)
}
