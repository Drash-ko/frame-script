import SwiftUI

@main
struct FrameScriptApp: App {
    @State private var appState = AppState()
    @Environment(\.openSettings) private var openSettings

    var body: some SwiftUI.Scene {
        WindowGroup {
            ThemedSceneRoot {
                AppRootView()
            }
            .environment(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            appCommands
        }

        Settings {
            ThemedSceneRoot {
                SettingsRootView()
            }
                .environment(appState)
        }
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(appState.localized("menu.newProject")) { appState.requestNewProject() }
                .keyboardShortcut("n", modifiers: .command)
            Button(appState.localized("menu.newProjectFromTemplate")) {
                appState.requestNewProject(showsTemplateBrowser: true)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Menu(appState.localized("welcome.newFromTemplate")) {
                ForEach(appState.scriptTemplates()) { template in
                    Button(appState.displayName(template)) {
                        appState.requestNewProject(template: template, locksTemplate: true)
                    }
                }
            }
            Divider()
            Button(appState.localized("menu.open")) { appState.openProject() }
                .keyboardShortcut("o", modifiers: .command)
            Menu(appState.localized("menu.openRecent")) {
                if appState.recentProjectURLs.isEmpty {
                    Text(appState.localized("menu.noRecentProjects"))
                } else {
                    ForEach(appState.recentProjectURLs, id: \.path) { url in
                        Button(url.deletingPathExtension().lastPathComponent) {
                            appState.openProject(at: url)
                        }
                    }
                    Divider()
                    Button(appState.localized("menu.clearMenu")) { appState.clearRecentProjects() }
                }
            }
        }

        CommandGroup(replacing: .saveItem) {
            Button(appState.localized("project.save")) { appState.saveProject() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("project.saveAs")) { appState.saveProjectAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("menu.duplicateProject")) { appState.duplicateProject() }
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("project.rename")) { appState.renameProject() }
                .disabled(!appState.hasOpenProject)
            Divider()
            Button(appState.localized("project.close")) { appState.closeProject() }
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("menu.showProjectBrowser")) { appState.showProjectBrowser() }
                .disabled(!appState.hasOpenProject)
            Divider()
            Button(appState.localized("menu.deleteProject")) { appState.deleteProject() }
                .disabled(!appState.hasOpenProject)
        }

        CommandGroup(replacing: .importExport) {
            Button(appState.localized("menu.import")) { appState.importProject() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button(appState.localized("project.export")) { appState.exportProject() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!appState.hasOpenProject)
        }

        CommandGroup(replacing: .appSettings) {
            Button(appState.localized("command.openSettings")) {
                appState.openSettings(tab: .general)
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu(appState.localized("menu.view")) {
            Button(appState.localized("mode.script")) { appState.selectMode(.script) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("mode.bRoll")) { appState.selectMode(.bRoll) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("mode.editing")) { appState.selectMode(.editing) }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(!appState.hasOpenProject)
            Divider()
            Button(appState.localized("command.toggleSidebar")) { appState.isSidebarVisible.toggle() }
                .keyboardShortcut("\\", modifiers: .command)
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("command.toggleAIReview")) {
                appState.settings.editorPreferences.showAIReviewPanel.toggle()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!appState.hasOpenProject)
            Button(appState.localized("command.toggleFocus")) { appState.isFocusModeEnabled.toggle() }
                .keyboardShortcut("'", modifiers: .command)
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("toolbar.commandPalette")) { appState.isCommandPalettePresented = true }
                .keyboardShortcut("k", modifiers: .command)
            Button(appState.localized("command.showShortcuts")) { appState.isShortcutsPresented = true }
        }

        CommandMenu(appState.localized("menu.scene")) {
            Button(appState.localized("scene.add")) { appState.addScene() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("scene.duplicate")) { appState.duplicateSelectedScene() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("scene.delete")) { appState.deleteSelectedScene() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!appState.hasOpenProject)
            Divider()
            Button(appState.localized("scene.moveUp")) { appState.moveSelectedSceneUp() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("scene.moveDown")) { appState.moveSelectedSceneDown() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("scene.rename")) { appState.renameSelectedScene() }
                .disabled(!appState.hasOpenProject)
        }

        CommandMenu(appState.localized("menu.tools")) {
            Button(appState.localized("ai.analyzeCurrentScene")) {
                appState.settings.editorPreferences.showAIReviewPanel = true
                Task { await appState.analyzeSelectedScene() }
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(!appState.hasOpenProject)
            Button(appState.localized("menu.analyzeFullScript")) {
                appState.settings.editorPreferences.showAIReviewPanel = true
                Task { await appState.analyzeFullScript() }
            }
            .disabled(!appState.hasOpenProject)
            Button(appState.localized("menu.generateBRoll")) { appState.generateBRollForSelectedScene() }
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("menu.generateEditing")) { appState.generateEditingNotesForSelectedScene() }
                .disabled(!appState.hasOpenProject)
        }
    }
}

private struct ThemedSceneRoot<Content: View>: View {
    @Environment(AppState.self) private var appState
    @ViewBuilder var content: Content

    var body: some View {
        content
            .environment(\.frameTheme, appState.themeManager.frameTheme)
            .preferredColorScheme(appState.themeManager.preferredColorScheme)
            .onAppear(perform: updateTheme)
            .onChange(of: appState.settings.theme) { _, _ in updateTheme() }
            .onChange(of: appState.settings.accentColor) { _, _ in updateTheme() }
    }

    private func updateTheme() {
        appState.themeManager.update(
            selectedTheme: appState.settings.theme,
            accentColor: appState.settings.accentColor
        )
    }
}
