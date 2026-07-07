import SwiftUI

struct ShortcutsOverlay: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme

    private var shortcuts: [(String, String)] {
        [
            ("⌘N", appState.localized("welcome.newProject")),
            ("⌘⇧N", appState.localized("welcome.newFromTemplate")),
            ("⌘O", appState.localized("welcome.openProject")),
            ("⌘S", appState.localized("project.save")),
            ("⌘⇧S", appState.localized("project.saveAs")),
            ("⌘E", appState.localized("project.export")),
            ("⌘⌥N", appState.localized("scene.add")),
            ("⌘D", appState.localized("scene.duplicate")),
            ("⌘⌫", appState.localized("scene.delete")),
            ("⌘⌥↑", appState.localized("scene.moveUp")),
            ("⌘⌥↓", appState.localized("scene.moveDown")),
            ("⌘1", appState.localized("mode.script")),
            ("⌘2", appState.localized("mode.bRoll")),
            ("⌘3", appState.localized("mode.editing")),
            ("⌘K", appState.localized("toolbar.commandPalette")),
            ("⌘\\", appState.localized("command.toggleSidebar")),
            ("⌘⇧R", appState.localized("command.toggleAIReview")),
            ("⌘'", appState.localized("command.toggleFocus")),
            ("⌘⇧A", appState.localized("ai.analyzeCurrentScene")),
            ("⌘,", appState.localized("toolbar.settings"))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appState.localized("shortcuts.title"))
                .font(.system(size: 24, weight: .semibold))

            LazyVGrid(columns: [GridItem(.fixed(90)), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                ForEach(shortcuts, id: \.0) { key, label in
                    Text(key)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(theme.background)
    }
}
