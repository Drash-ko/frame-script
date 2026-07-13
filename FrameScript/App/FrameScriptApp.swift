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
                .keyboardShortcut(appState.settings.shortcut(for: .newProject).keyboardShortcut)
            Button(appState.localized("menu.newProjectFromTemplate")) {
                appState.requestNewProject(showsTemplateBrowser: true)
            }
            .keyboardShortcut(appState.settings.shortcut(for: .newProjectFromTemplate).keyboardShortcut)
            Menu(appState.localized("welcome.newFromTemplate")) {
                ForEach(appState.scriptTemplates()) { template in
                    Button(appState.displayName(template)) {
                        appState.requestNewProject(template: template, locksTemplate: true)
                    }
                }
            }
            Divider()
            Button(appState.localized("menu.open")) { appState.openProject() }
                .keyboardShortcut(appState.settings.shortcut(for: .openProject).keyboardShortcut)
            Menu(appState.localized("menu.openRecent")) {
                if appState.recentProjectEntries.isEmpty {
                    Text(appState.localized("menu.noRecentProjects"))
                } else {
                    ForEach(appState.recentProjectEntries) { entry in
                        Button(entry.displayName) {
                            appState.openRecentProject(entry)
                        }
                    }
                    Divider()
                    Menu(appState.localized("recent.manage")) {
                        ForEach(appState.recentProjectEntries) { entry in
                            Menu(entry.displayName) {
                                Button(appState.localized("recent.open")) {
                                    appState.openRecentProject(entry)
                                }
                                Button(appState.localized("project.reveal")) {
                                    appState.revealRecentProjectInFinder(entry)
                                }
                                .disabled(!appState.canRevealRecentProject(entry))
                                Divider()
                                Button(appState.localized("recent.remove")) {
                                    appState.removeRecentProject(entry)
                                }
                            }
                        }
                    }
                    Button(appState.localized("menu.clearMenu")) { appState.clearRecentProjects() }
                }
            }
        }

        CommandGroup(replacing: .saveItem) {
            Button(appState.localized("project.save")) { appState.saveProject() }
                .keyboardShortcut(appState.settings.shortcut(for: .save).keyboardShortcut)
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("project.saveAs")) { appState.saveProjectAs() }
                .keyboardShortcut(appState.settings.shortcut(for: .saveAs).keyboardShortcut)
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
                .keyboardShortcut(appState.settings.shortcut(for: .import).keyboardShortcut)
            Button(appState.localized("project.export")) { appState.exportProject() }
                .keyboardShortcut(appState.settings.shortcut(for: .export).keyboardShortcut)
                .disabled(!appState.hasOpenProject)
        }

        CommandGroup(replacing: .appSettings) {
            Button(appState.localized("command.openSettings")) {
                appState.openSettings(tab: .general)
                openSettings()
            }
            .keyboardShortcut(appState.settings.shortcut(for: .openSettings).keyboardShortcut)
        }

        CommandMenu(appState.localized("menu.view")) {
            Button(appState.localized("mode.script")) { appState.selectMode(.script) }
                .keyboardShortcut(appState.settings.shortcut(for: .scriptMode).keyboardShortcut)
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("mode.bRoll")) { appState.selectMode(.bRoll) }
                .keyboardShortcut(appState.settings.shortcut(for: .visualsMode).keyboardShortcut)
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("mode.editing")) { appState.selectMode(.editing) }
                .keyboardShortcut(appState.settings.shortcut(for: .editingMode).keyboardShortcut)
                .disabled(!appState.hasOpenProject)
            Divider()
            Button(appState.localized("command.toggleSidebar")) { appState.isSidebarVisible.toggle() }
                .keyboardShortcut(appState.settings.shortcut(for: .toggleContentsPanel).keyboardShortcut)
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("command.toggleAIReview")) {
                appState.settings.editorPreferences.showAIReviewPanel.toggle()
            }
            .keyboardShortcut(appState.settings.shortcut(for: .toggleAIReview).keyboardShortcut)
            .disabled(!appState.hasOpenProject)
            Button(appState.localized("command.toggleFocus")) { appState.isFocusModeEnabled.toggle() }
                .keyboardShortcut(appState.settings.shortcut(for: .toggleFocusMode).keyboardShortcut)
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("toolbar.commandPalette")) { appState.isCommandPalettePresented = true }
                .keyboardShortcut(appState.settings.shortcut(for: .commandPalette).keyboardShortcut)
            Button(appState.localized("command.showShortcuts")) { appState.isShortcutsPresented = true }
                .keyboardShortcut(appState.settings.shortcut(for: .showShortcuts).keyboardShortcut)
        }

        CommandMenu(appState.localized("menu.scene")) {
            Button(appState.localized("scene.add")) { appState.addScene() }
                .keyboardShortcut(appState.settings.shortcut(for: .addScene).keyboardShortcut)
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("scene.duplicate")) { appState.duplicateSelectedScene() }
                .keyboardShortcut(appState.settings.shortcut(for: .duplicateScene).keyboardShortcut)
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("scene.delete")) { appState.deleteSelectedScene() }
                .keyboardShortcut(appState.settings.shortcut(for: .deleteScene).keyboardShortcut)
                .disabled(!appState.hasOpenProject)
            Divider()
            Button(appState.localized("scene.moveUp")) { appState.moveSelectedSceneUp() }
                .keyboardShortcut(appState.settings.shortcut(for: .moveSceneUp).keyboardShortcut)
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("scene.moveDown")) { appState.moveSelectedSceneDown() }
                .keyboardShortcut(appState.settings.shortcut(for: .moveSceneDown).keyboardShortcut)
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("scene.rename")) { appState.renameSelectedScene() }
                .disabled(!appState.hasOpenProject)
        }

        CommandMenu(appState.localized("menu.tools")) {
            Button(appState.localized("ai.analyzeCurrentScene")) {
                appState.settings.editorPreferences.showAIReviewPanel = true
                Task { await appState.analyzeSelectedScene() }
            }
            .keyboardShortcut(appState.settings.shortcut(for: .analyzeCurrentScene).keyboardShortcut)
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
