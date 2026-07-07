import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct AppRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FrameProject.updatedAt, order: .reverse) private var projects: [FrameProject]

    var body: some View {
        @Bindable var windowState = appState.windowState
        Group {
            if appState.hasOpenProject {
                AppShellView()
            } else {
                WelcomeView()
            }
        }
            .task {
                appState.configure(modelContext: modelContext, existingProjects: projects)
            }
            .sheet(item: $windowState.newProjectRequest) { request in
                NewProjectSheet(request: request)
                    .environment(appState)
                    .environment(\.frameTheme, appState.themeManager.frameTheme)
            }
            .sheet(isPresented: $windowState.isExportPresented) {
                ExportSheetView()
                    .environment(appState)
                    .environment(\.frameTheme, appState.themeManager.frameTheme)
            }
            .sheet(isPresented: $windowState.isVoiceoverPresented) {
                VoiceoverSheetView()
                    .environment(appState)
                    .environment(\.frameTheme, appState.themeManager.frameTheme)
            }
    }
}

struct AppShellView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme

    var body: some View {
        @Bindable var windowState = appState.windowState
        @Bindable var settingsStore = appState.settingsStore
        let sidebarWidth = settingsStore.settings.windowPreferences.sidebarWidth
        let reducedChrome = settingsStore.settings.windowPreferences.reducedChromeMode
        let hidesSidebarForFocus = appState.isFocusModeEnabled
            && appState.settings.windowPreferences.focusModeBehavior == .hidePanels

        VStack(spacing: 0) {
            TopToolbar()

            HSplitView {
                if appState.isSidebarVisible && !hidesSidebarForFocus {
                    SceneSidebar()
                        .frame(
                            minWidth: 180,
                            idealWidth: sidebarWidth,
                            maxWidth: 420
                        )
                        .background(SidebarWidthReader(width: $settingsStore.settings.windowPreferences.sidebarWidth))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                HStack(spacing: 0) {
                    editorContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if appState.settings.editorPreferences.showAIReviewPanel && !appState.isFocusModeEnabled {
                        Divider()
                            .overlay(theme.divider)

                        AIReviewPanel()
                            .frame(width: 292)
                    }
                }
                .frame(minWidth: 640, maxWidth: .infinity, maxHeight: .infinity)
            }

            if appState.settings.editorPreferences.showFooterShortcuts && !reducedChrome && !appState.isFocusModeEnabled {
                Divider()
                    .overlay(theme.divider)
                FooterShortcutBar()
            }
        }
        .background(theme.background)
        .foregroundStyle(theme.primaryText)
        .frame(minWidth: 980, minHeight: 680)
        .sheet(isPresented: $windowState.isCommandPalettePresented) {
            CommandPaletteView()
                .environment(appState)
                .environment(\.frameTheme, theme)
        }
        .sheet(isPresented: $windowState.isShortcutsPresented) {
            ShortcutsOverlay()
                .environment(appState)
                .environment(\.frameTheme, theme)
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        if let scene = appState.selectedScene {
            switch appState.selectedMode {
            case .script:
                ScriptEditorView(scene: scene)
            case .bRoll:
                BRollEditorView(scene: scene)
            case .editing:
                EditingEditorView(scene: scene)
            }
        } else {
            EmptyProjectView()
        }
    }
}

private struct SidebarWidthReader: View {
    @Binding var width: Double

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { persist(proxy.size.width) }
                .onChange(of: proxy.size.width) { _, newValue in
                    persist(newValue)
                }
        }
    }

    private func persist(_ value: Double) {
        let clamped = min(420, max(180, value))
        if abs(width - clamped) > 0.5 {
            width = clamped
        }
    }
}

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @State private var isTemplatePickerPresented = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(appState.localized("app.name"))
                        .font(.system(size: 34, weight: .semibold))
                    Text(appState.localized("welcome.subtitle"))
                        .font(.system(size: 14))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    WelcomeAction(title: appState.localized("welcome.newBlankProject"), systemImage: "plus", action: {
                        appState.requestNewProject(template: appState.scriptTemplates().first { $0.isBlank }, locksTemplate: true)
                    })
                    WelcomeAction(title: appState.localized("welcome.newFromTemplate"), systemImage: "doc.badge.plus", action: {
                        isTemplatePickerPresented = true
                    })
                    WelcomeAction(title: appState.localized("welcome.openProject"), systemImage: "folder", action: appState.openProject)
                    WelcomeAction(title: appState.localized("welcome.openDemo"), systemImage: "play.rectangle", action: appState.openDemoProject)
                }
                .frame(width: 260)

                Spacer()
            }
            .padding(52)
            .frame(width: 420, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(theme.sidebarBackground)

            VStack(alignment: .leading, spacing: 18) {
                Text(appState.localized("welcome.recent"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                if appState.recentProjectURLs.isEmpty {
                    Text(appState.localized("welcome.noRecent"))
                        .font(.system(size: 14))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: 420, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(appState.recentProjectURLs, id: \.path) { url in
                                Button {
                                    appState.openProject(at: url)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "doc.text")
                                            .foregroundStyle(theme.accent.color)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(url.deletingPathExtension().lastPathComponent)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(theme.primaryText)
                                            Text(url.path)
                                                .font(.system(size: 12))
                                                .foregroundStyle(theme.secondaryText)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.cursorPlain)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(theme.hover)
                                )
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(52)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.appBackground)
        }
        .foregroundStyle(theme.primaryText)
        .frame(minWidth: 820, minHeight: 560)
        .sheet(isPresented: $isTemplatePickerPresented) {
            TemplatePickerView()
                .environment(appState)
                .environment(\.frameTheme, theme)
        }
    }
}

private struct WelcomeAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
        .clickableCursor()
    }
}

private struct TemplatePickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTemplateID: UUID?
    @State private var projectName = ""
    @FocusState private var isNameFocused: Bool

    private var templates: [FrameTemplate] {
        appState.scriptTemplates()
    }

    private var selectedTemplate: FrameTemplate? {
        templates.first { $0.id == selectedTemplateID } ?? templates.first
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(appState.localized("templates.newFromTemplate"))
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.bottom, 8)

                ForEach(templates) { template in
                    Button {
                        selectedTemplateID = template.id
                    } label: {
                        HStack {
                            Text(appState.displayName(template))
                                .font(.system(size: 13, weight: selectedTemplate?.id == template.id ? .semibold : .regular))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .foregroundStyle(selectedTemplate?.id == template.id ? theme.primaryText : theme.secondaryText)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(selectedTemplate?.id == template.id ? theme.accentSoft.opacity(0.62) : Color.clear)
                        }
                    }
                    .buttonStyle(.cursorPlain)
                }

                Spacer()

                Button(appState.localized("templates.manage")) {
                    appState.openSettings(tab: .templates)
                    dismiss()
                    openSettings()
                }
                .buttonStyle(.cursorPlain)
            }
            .padding(18)
            .frame(width: 240, alignment: .topLeading)
            .background(theme.panelBackground)

            Divider()
                .overlay(theme.divider)

            VStack(alignment: .leading, spacing: 16) {
                if let selectedTemplate {
                    Text(appState.displayName(selectedTemplate))
                        .font(.system(size: 24, weight: .semibold))

                    QuietField(appState.localized("newProject.name")) {
                        TextField(appState.localized("project.untitled"), text: $projectName)
                            .textFieldStyle(QuietTextFieldStyle())
                            .focused($isNameFocused)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(appState.localized("templates.structure"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.secondaryText)

                        if selectedTemplate.structureDefinition.isEmpty {
                            Text(appState.localized("templates.blankStructure"))
                                .font(.system(size: 14))
                                .foregroundStyle(theme.secondaryText)
                        } else {
                            ForEach(Array(selectedTemplate.structureDefinition.enumerated()), id: \.offset) { index, sceneName in
                                HStack(spacing: 10) {
                                    Text(String(format: "%02d", index + 1))
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(theme.tertiaryText)
                                        .frame(width: 28, alignment: .leading)
                                    Text(selectedTemplate.builtIn ? appState.localizedTemplateSceneName(sceneName) : sceneName)
                                        .font(.system(size: 14))
                                        .foregroundStyle(theme.primaryText)
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    }

                    Spacer()

                    HStack {
                        Button(appState.localized("project.unsaved.cancel")) {
                            dismiss()
                        }
                        .clickableCursor()

                        Spacer()

                        Button(appState.localized("templates.createProject")) {
                            appState.createNewProject(named: resolvedProjectName, template: selectedTemplate)
                            dismiss()
                        }
                        .keyboardShortcut(.defaultAction)
                        .clickableCursor()
                    }
                }
            }
            .padding(24)
            .frame(width: 420, height: 420, alignment: .topLeading)
            .background(theme.windowBackground)
        }
        .foregroundStyle(theme.primaryText)
        .frame(width: 660, height: 420)
        .onAppear {
            selectedTemplateID = selectedTemplateID ?? templates.first?.id
            projectName = projectName.isEmpty ? appState.localized("project.untitled") : projectName
            isNameFocused = true
        }
    }

    private var resolvedProjectName: String {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appState.localized("project.untitled") : trimmed
    }
}

private struct NewProjectSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let request: NewProjectRequest
    @State private var projectName = ""
    @State private var selectedTemplateID: UUID?
    @FocusState private var isNameFocused: Bool

    private var templates: [FrameTemplate] {
        appState.scriptTemplates()
    }

    private var selectedTemplate: FrameTemplate? {
        templates.first { $0.id == selectedTemplateID } ?? templates.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(appState.localized("newProject.title"))
                .font(.system(size: 20, weight: .semibold))

            QuietField(appState.localized("newProject.name")) {
                TextField(appState.localized("project.untitled"), text: $projectName)
                    .textFieldStyle(QuietTextFieldStyle())
                    .focused($isNameFocused)
            }

            QuietField(appState.localized("newProject.template")) {
                Picker("", selection: $selectedTemplateID) {
                    ForEach(templates) { template in
                        Text(appState.displayName(template)).tag(Optional(template.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(request.locksTemplate)
            }

            if let selectedTemplate {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.localized("templates.structure"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.secondaryText)

                    if selectedTemplate.structureDefinition.isEmpty {
                        Text(appState.localized("templates.blankStructure"))
                            .font(.system(size: 13))
                            .foregroundStyle(theme.secondaryText)
                    } else {
                        ForEach(Array(selectedTemplate.structureDefinition.prefix(6).enumerated()), id: \.offset) { index, sceneName in
                            Text("\(index + 1). \(selectedTemplate.builtIn ? appState.localizedTemplateSceneName(sceneName) : sceneName)")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.primaryText)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(theme.divider, lineWidth: 1)
                        )
                }
            }

            HStack {
                Button(appState.localized("project.unsaved.cancel")) {
                    appState.windowState.newProjectRequest = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .clickableCursor()

                Spacer()

                Button(appState.localized("newProject.create")) {
                    appState.createNewProject(named: resolvedProjectName, template: selectedTemplate)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .clickableCursor()
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(theme.windowBackground)
        .foregroundStyle(theme.primaryText)
        .onAppear {
            selectedTemplateID = request.templateID ?? templates.first?.id
            projectName = appState.localized("project.untitled")
            isNameFocused = true
        }
    }

    private var resolvedProjectName: String {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appState.localized("project.untitled") : trimmed
    }
}

private struct ExportSheetView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var preferences: ExportPreferences
    @State private var format: ExportFormat

    init() {
        let defaults = AppSettings.defaults.exportPreferences
        _preferences = State(initialValue: defaults)
        _format = State(initialValue: defaults.defaultFormat)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appState.localized("export.title"))
                .font(.system(size: 20, weight: .semibold))

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(appState.localized("settings.defaultFormat"), selection: $format) {
                        ForEach(ExportFormat.allCases) { option in
                            Text(appState.displayName(option)).tag(option)
                        }
                    }
                    .frame(width: 260)

                    Toggle(appState.localized("settings.timestamps"), isOn: $preferences.includeTimestamps)
                    Toggle(appState.localized("settings.sectionNames"), isOn: $preferences.includeSectionNames)
                    Toggle(appState.localized("settings.includeBRoll"), isOn: $preferences.includeBRoll)
                    Toggle(appState.localized("settings.includeEditing"), isOn: $preferences.includeEditingNotes)
                    Toggle(appState.localized("settings.includeAI"), isOn: $preferences.includeAINotes)
                    Toggle(appState.localized("settings.teleprompter"), isOn: $preferences.teleprompterFormatting)
                }
                .toggleStyle(.checkbox)

                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.localized("export.preview"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.secondaryText)

                    ScrollView {
                        Text(previewText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.primaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(12)
                    }
                    .frame(width: 430, height: 300)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(theme.editorSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(theme.divider, lineWidth: 1)
                            )
                    }
                }
            }

            HStack {
                Button(appState.localized("project.unsaved.cancel")) {
                    appState.windowState.isExportPresented = false
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .clickableCursor()

                Spacer()

                Button(appState.localized("export.copy")) {
                    appState.copyExportToClipboard(format: format, preferences: effectivePreferences)
                }
                .clickableCursor()

                Button(appState.localized("export.saveFile")) {
                    saveFile()
                }
                .keyboardShortcut(.defaultAction)
                .clickableCursor()
            }
        }
        .padding(24)
        .frame(width: 760)
        .background(theme.windowBackground)
        .foregroundStyle(theme.primaryText)
        .onAppear {
            preferences = appState.settings.exportPreferences
            format = appState.settings.exportPreferences.defaultFormat
        }
    }

    private var effectivePreferences: ExportPreferences {
        var copy = preferences
        copy.defaultFormat = format
        return copy
    }

    private var previewText: String {
        appState.dependencies.exportService.render(project: appState.project, format: format, preferences: effectivePreferences, language: appState.currentLanguage)
    }

    private func saveFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(appState.project.title).\(format.fileExtension)"
        panel.message = appState.localized("dialog.exportProject.message")
        if !preferences.defaultExportFolder.isEmpty {
            let folder = URL(fileURLWithPath: preferences.defaultExportFolder)
            if FileManager.default.fileExists(atPath: folder.path) {
                panel.directoryURL = folder
            }
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.saveExport(format: format, preferences: effectivePreferences, to: url)
        appState.windowState.isExportPresented = false
        dismiss()
    }
}

private struct VoiceoverSheetView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private var hasCurrentSceneText: Bool {
        !(appState.selectedScene?.scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private var hasFullScriptText: Bool {
        !appState.project.scenes.map(\.scriptText).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appState.localized("voiceover.title"))
                .font(.system(size: 20, weight: .semibold))

            Text(appState.localized("voiceover.message"))
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Button(appState.localized("voiceover.playCurrentScene")) {
                    appState.playVoicePreview()
                }
                .disabled(!hasCurrentSceneText || appState.voiceState.isSpeaking)
                .clickableCursor(enabled: hasCurrentSceneText && !appState.voiceState.isSpeaking)

                Button(appState.localized("voiceover.playFullScript")) {
                    appState.playFullScriptVoicePreview()
                }
                .disabled(!hasFullScriptText || appState.voiceState.isSpeaking)
                .clickableCursor(enabled: hasFullScriptText && !appState.voiceState.isSpeaking)

                Button(appState.localized("voiceover.stop")) {
                    appState.stopVoicePreview()
                }
                .disabled(!appState.voiceState.isSpeaking)
                .clickableCursor(enabled: appState.voiceState.isSpeaking)
            }

            Divider()
                .overlay(theme.divider)

            VStack(alignment: .leading, spacing: 8) {
                Text(appState.localized("voiceover.exportAudio"))
                    .font(.system(size: 13, weight: .medium))
                Text(appState.localized("voiceover.exportUnavailable"))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(appState.localized("dialog.ok")) {
                    appState.windowState.isVoiceoverPresented = false
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .clickableCursor()
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(theme.windowBackground)
        .foregroundStyle(theme.primaryText)
    }
}

private struct EmptyProjectView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            Text(appState.localized("scene.emptyTitle"))
                .font(.system(size: 24, weight: .medium))
            Text(appState.localized("scene.emptyMessage"))
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryText)
            Button(appState.localized("scene.add")) {
                appState.addScene()
            }
            .buttonStyle(.cursorPlain)
            .keyboardShortcut(.defaultAction)
            .clickableCursor()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
