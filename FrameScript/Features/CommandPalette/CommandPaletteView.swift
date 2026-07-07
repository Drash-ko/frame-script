import SwiftUI

struct CommandPaletteView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.frameTheme) private var theme
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""

    private var commands: [PaletteCommand] {
        [
            PaletteCommand(title: appState.localized("command.switchScript"), detail: "⌘1") {
                appState.selectMode(.script)
            },
            PaletteCommand(title: appState.localized("command.switchBRoll"), detail: "⌘2") {
                appState.selectMode(.bRoll)
            },
            PaletteCommand(title: appState.localized("command.switchEditing"), detail: "⌘3") {
                appState.selectMode(.editing)
            },
            PaletteCommand(title: appState.localized("scene.add"), detail: "⌘⌥N", action: appState.addScene),
            PaletteCommand(title: appState.localized("scene.duplicate"), detail: "⌘D", action: appState.duplicateSelectedScene),
            PaletteCommand(title: appState.localized("scene.delete"), detail: "⌘⌫", action: appState.deleteSelectedScene),
            PaletteCommand(title: appState.localized("ai.analyzeCurrentScene"), detail: "⌘⇧A") {
                appState.settings.editorPreferences.showAIReviewPanel = true
                Task { await appState.analyzeSelectedScene() }
            },
            PaletteCommand(title: appState.localized("command.openSettings"), detail: "⌘,", action: {
                appState.openSettings(tab: .general)
                openSettings()
            }),
            PaletteCommand(title: appState.localized("command.toggleFocus"), detail: "⌘'") {
                appState.isFocusModeEnabled.toggle()
            },
            PaletteCommand(title: appState.localized("command.toggleSidebar"), detail: "⌘\\") {
                appState.isSidebarVisible.toggle()
            },
            PaletteCommand(title: appState.localized("command.toggleAIReview"), detail: "⌘⇧R") {
                appState.settings.editorPreferences.showAIReviewPanel.toggle()
            },
            PaletteCommand(title: appState.localized("command.closeProject"), detail: "") {
                appState.closeProject()
            },
            PaletteCommand(title: appState.localized("command.projectBrowser"), detail: "") {
                appState.showProjectBrowser()
            },
            PaletteCommand(title: appState.localized("command.showShortcuts"), detail: "?") {
                appState.isShortcutsPresented = true
            }
        ]
    }

    private var filtered: [PaletteCommand] {
        guard !query.isEmpty else { return commands }
        return commands.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(appState.localized("command.search"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .padding(.horizontal, 18)
                .frame(height: 58)
                .textCursor()

            Divider()
                .overlay(theme.divider)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { command in
                        Button {
                            command.action()
                            dismiss()
                        } label: {
                            HStack {
                                Text(command.title)
                                    .font(.system(size: 14))
                                Spacer()
                                Text(command.detail)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(theme.secondaryText)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                        }
                        .buttonStyle(.cursorPlain)
                    }

                    ForEach(appState.project.scenes.sortedByOrder.filter { query.isEmpty ? false : $0.title.localizedCaseInsensitiveContains(query) }) { scene in
                        Button {
                            appState.selectScene(scene.id)
                            dismiss()
                        } label: {
                            HStack {
                                Text(scene.title)
                                    .font(.system(size: 14))
                                Spacer()
                                Text(appState.localized("scene.kind"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.secondaryText)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                        }
                        .buttonStyle(.cursorPlain)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 560, height: 420)
        .background(theme.background)
    }
}

private struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let action: () -> Void
}
