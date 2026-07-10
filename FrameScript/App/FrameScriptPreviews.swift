import SwiftUI

enum FrameScriptPreviewSupport {
    @MainActor
    static var appState: AppState {
        AppState()
    }
}

#Preview("FrameScript") {
    AppRootView()
        .environment(FrameScriptPreviewSupport.appState)
        .frame(width: 1180, height: 760)
}
