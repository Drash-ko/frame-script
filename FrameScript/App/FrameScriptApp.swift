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
                .configuredKeyboardShortcut(appState.shortcutBinding(for: .newProject))
            Button(appState.localized("menu.newProjectFromTemplate")) {
                appState.requestNewProject(showsTemplateBrowser: true)
            }
            .configuredKeyboardShortcut(appState.shortcutBinding(for: .newProjectFromTemplate))
            Menu(appState.localized("welcome.newFromTemplate")) {
                ForEach(appState.scriptTemplates()) { template in
                    Button(appState.displayName(template)) {
                        appState.requestNewProject(template: template, locksTemplate: true)
                    }
                }
            }
            Divider()
            Button(appState.localized("menu.open")) { appState.openProject() }
                .configuredKeyboardShortcut(appState.shortcutBinding(for: .openProject))
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
                .configuredKeyboardShortcut(appState.shortcutBinding(for: .save))
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("project.saveAs")) { appState.saveProjectAs() }
                .configuredKeyboardShortcut(appState.shortcutBinding(for: .saveAs))
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("menu.duplicateProject")) { appState.duplicateProject() }
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("project.rename")) { appState.renameProject() }
                .disabled(!appState.hasOpenProject)
            Divider()
            Button(appState.localized("project.browser")) { appState.returnToProjectList() }
                .disabled(!appState.hasOpenProject)
            Divider()
            Button(appState.localized("menu.deleteProject")) { appState.deleteProject() }
                .disabled(!appState.hasOpenProject)
        }

        CommandGroup(replacing: .importExport) {
            Button(appState.localized("menu.import")) { appState.importProject() }
                .configuredKeyboardShortcut(appState.shortcutBinding(for: .import))
            Button(appState.localized("project.export")) { appState.exportProject() }
                .configuredKeyboardShortcut(appState.shortcutBinding(for: .export))
                .disabled(!appState.hasOpenProject)
        }

        CommandGroup(replacing: .appSettings) {
            Button(appState.localized("command.openSettings")) {
                appState.openSettings(tab: .general)
                openSettings()
            }
            .configuredKeyboardShortcut(appState.shortcutBinding(for: .openSettings))
        }

        CommandMenu(appState.localized("menu.view")) {
            Button(appState.localized("mode.script")) { appState.selectMode(.script) }
                .configuredKeyboardShortcut(appState.shortcutBinding(for: .scriptMode))
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("mode.bRoll")) { appState.selectMode(.bRoll) }
                .configuredKeyboardShortcut(appState.shortcutBinding(for: .visualsMode))
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("mode.editing")) { appState.selectMode(.editing) }
                .configuredKeyboardShortcut(appState.shortcutBinding(for: .editingMode))
                .disabled(!appState.hasOpenProject)
            Divider()
            Button(appState.localized("command.toggleSidebar")) { appState.isSidebarVisible.toggle() }
                .configuredKeyboardShortcut(appState.shortcutBinding(for: .toggleContentsPanel))
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("command.toggleAIReview")) {
                appState.settings.editorPreferences.showAIReviewPanel.toggle()
            }
            .configuredKeyboardShortcut(appState.shortcutBinding(for: .toggleAIReview))
            .disabled(!appState.hasOpenProject)
            Button(appState.localized("command.toggleFocus")) { appState.isFocusModeEnabled.toggle() }
                .configuredKeyboardShortcut(appState.shortcutBinding(for: .toggleFocusMode))
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("toolbar.commandPalette")) { appState.isCommandPalettePresented = true }
                .configuredKeyboardShortcut(appState.shortcutBinding(for: .commandPalette))
            Button(appState.localized("command.showShortcuts")) { appState.isShortcutsPresented = true }
                .configuredKeyboardShortcut(appState.shortcutBinding(for: .showShortcuts))
        }

        CommandMenu(appState.localized("menu.scene")) {
            Button(appState.localized("scene.add")) { appState.addScene() }
                .configuredKeyboardShortcut(appState.shortcutBinding(for: .addScene))
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("scene.duplicate")) { appState.duplicateSelectedScene() }
                .configuredKeyboardShortcut(appState.shortcutBinding(for: .duplicateScene))
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("scene.delete")) { appState.deleteSelectedScene() }
                .configuredKeyboardShortcut(appState.shortcutBinding(for: .deleteScene))
                .disabled(!appState.hasOpenProject)
            Divider()
            Button(appState.localized("scene.moveUp")) { appState.moveSelectedSceneUp() }
                .configuredKeyboardShortcut(appState.shortcutBinding(for: .moveSceneUp))
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("scene.moveDown")) { appState.moveSelectedSceneDown() }
                .configuredKeyboardShortcut(appState.shortcutBinding(for: .moveSceneDown))
                .disabled(!appState.hasOpenProject)
            Button(appState.localized("scene.rename")) { appState.renameSelectedScene() }
                .disabled(!appState.hasOpenProject)
        }

        CommandMenu(appState.localized("menu.tools")) {
            Button(appState.localized("ai.analyzeCurrentScene")) {
                appState.settings.editorPreferences.showAIReviewPanel = true
                Task { await appState.analyzeSelectedScene() }
            }
            .configuredKeyboardShortcut(appState.shortcutBinding(for: .analyzeCurrentScene))
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

private extension View {
    @ViewBuilder
    func configuredKeyboardShortcut(_ binding: ShortcutBinding?) -> some View {
        if let binding {
            keyboardShortcut(binding.keyboardShortcut)
        } else {
            self
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
