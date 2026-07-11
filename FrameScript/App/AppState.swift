import Foundation
import AppKit
import Observation
import SwiftUI

private struct GeneratedBRollSuggestion: Decodable {
    let source: String
    let description: String
    let notes: String
}

private struct GeneratedEditingSuggestion: Decodable {
    let description: String
    let notes: String
}

private enum GenerationError: LocalizedError {
    case invalidJSON
    case emptyDescription

    var errorDescription: String? {
        switch self {
        case .invalidJSON: "The provider did not return valid structured JSON."
        case .emptyDescription: "The provider returned an empty description."
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable, Codable, Hashable {
    case general
    case appearance
    case editor
    case templates
    case ai
    case export
    case advanced

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "switch.2"
        case .appearance: "paintpalette"
        case .editor: "text.alignleft"
        case .templates: "doc.on.doc"
        case .ai: "sparkles"
        case .export: "square.and.arrow.up"
        case .advanced: "wrench.and.screwdriver"
        }
    }

    @MainActor
    func title(appState: AppState) -> String {
        switch self {
        case .general: appState.localized("settings.general")
        case .appearance: appState.localized("settings.appearance")
        case .editor: appState.localized("settings.editor")
        case .templates: appState.localized("settings.templates")
        case .ai: appState.localized("settings.ai")
        case .export: appState.localized("settings.export")
        case .advanced: appState.localized("settings.advanced")
        }
    }
}

struct NewProjectRequest: Identifiable, Equatable {
    let id = UUID()
    var templateID: UUID?
    var locksTemplate: Bool
    var showsTemplateBrowser = false
}

@MainActor
@Observable
final class AppState {
    let projectStore: ProjectStore
    let editorState: EditorState
    let settingsStore: SettingsStore
    let aiState: AIState
    let windowState: WindowState
    let themeManager: ResolvedThemeManager
    let dependencies: AppDependencies

    var templates: [FrameTemplate]
    private let builtInTemplates: [FrameTemplate]
    private var autosaveTask: Task<Void, Never>?
    private var segmentRebuildTasks: [UUID: Task<Void, Never>] = [:]
    private var didApplyUITestLaunchArguments = false

    init(
        projectStore: ProjectStore = ProjectStore(),
        editorState: EditorState = EditorState(),
        settingsStore: SettingsStore = SettingsStore(),
        aiState: AIState = AIState(),
        windowState: WindowState = WindowState(),
        themeManager: ResolvedThemeManager = ResolvedThemeManager(),
        dependencies: AppDependencies = .live,
        templates: [FrameTemplate] = SampleData.templates
    ) {
        self.projectStore = projectStore
        self.editorState = editorState
        self.settingsStore = settingsStore
        self.aiState = aiState
        self.windowState = windowState
        self.themeManager = themeManager
        self.dependencies = dependencies
        self.builtInTemplates = templates.filter(\.builtIn)
        self.templates = Self.mergedTemplates(builtIns: templates.filter(\.builtIn), customTemplates: Self.loadCustomTemplates())
        self.windowState.isSidebarVisible = settingsStore.settings.windowPreferences.sidebarDefaultVisible
        self.projectStore.setSegmentSplitMode(settingsStore.settings.generalPreferences.defaultSplitMode)
    }

    func configure() {
        projectStore.configure(
            restoreLastProjectOnLaunch: settings.generalPreferences.restoreLastProjectOnLaunch && !settings.generalPreferences.showProjectBrowserOnLaunch,
            wordsPerMinute: settings.editorPreferences.wordsPerMinute
        )
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--framescript-ui-test-language-english") {
            settings.generalPreferences.language = .english
        } else if arguments.contains("--framescript-ui-test-language-russian") {
            settings.generalPreferences.language = .russian
        }
        if !didApplyUITestLaunchArguments,
           arguments.contains("--framescript-ui-test-open-demo") {
            didApplyUITestLaunchArguments = true
            openDemoProject()
        }
        projectStore.setSegmentSplitMode(settings.generalPreferences.defaultSplitMode)
        if editorState.selectedSceneID == nil {
            editorState.selectedSceneID = project.scenes.first?.id
        }
    }

    var project: FrameProject {
        projectStore.project
    }

    var settings: AppSettings {
        get { settingsStore.settings }
        set { settingsStore.settings = newValue }
    }

    var selectedMode: WorkspaceMode {
        get { editorState.selectedMode }
        set { editorState.selectedMode = newValue }
    }

    var selectedScene: Scene? {
        projectStore.selectedScene(id: editorState.selectedSceneID)
    }

    var hasOpenProject: Bool {
        projectStore.hasOpenProject
    }

    var recentProjectURLs: [URL] {
        projectStore.recentProjectURLs
    }

    var selectedSceneIndex: Int? {
        projectStore.selectedSceneIndex(id: editorState.selectedSceneID)
    }

    var totalDuration: TimeInterval {
        projectStore.totalDuration
    }

    var isSidebarVisible: Bool {
        get { windowState.isSidebarVisible }
        set { windowState.isSidebarVisible = newValue }
    }

    var isFocusModeEnabled: Bool {
        get { editorState.isFocusModeEnabled }
        set { editorState.isFocusModeEnabled = newValue }
    }

    var isCommandPalettePresented: Bool {
        get { windowState.isCommandPalettePresented }
        set { windowState.isCommandPalettePresented = newValue }
    }

    var isSettingsPresented: Bool {
        get { windowState.isSettingsPresented }
        set { windowState.isSettingsPresented = newValue }
    }

    var isShortcutsPresented: Bool {
        get { windowState.isShortcutsPresented }
        set { windowState.isShortcutsPresented = newValue }
    }

    var saveState: SaveState {
        projectStore.saveState
    }

    var currentLanguage: AppLanguage {
        settings.generalPreferences.language
    }

    func localized(_ key: String) -> String {
        L10n.tr(key, language: currentLanguage)
    }

    func selectMode(_ mode: WorkspaceMode) {
        editorState.selectedMode = mode
    }

    func selectProductionSegment(_ segmentID: UUID, mode: WorkspaceMode) {
        editorState.selectedProductionSegmentID = segmentID
        editorState.selectedMode = mode
    }

    @discardableResult
    func showProjectBrowser() -> Bool {
        guard closeProject() else { return false }
        editorState.selectedSceneID = nil
        return true
    }

    func newProject(template: FrameTemplate? = nil) {
        createNewProject(named: localized("project.untitled"), template: template)
    }

    func requestNewProject(
        template: FrameTemplate? = nil,
        locksTemplate: Bool = false,
        showsTemplateBrowser: Bool = false
    ) {
        let selectedTemplate = template ?? templates.first { $0.name == settings.generalPreferences.defaultNewProjectTemplate } ?? templates.first
        windowState.newProjectRequest = NewProjectRequest(
            templateID: selectedTemplate?.id,
            locksTemplate: locksTemplate,
            showsTemplateBrowser: showsTemplateBrowser
        )
    }

    func createNewProject(named name: String, template: FrameTemplate? = nil) {
        let selectedTemplate = template ?? templates.first { $0.name == settings.generalPreferences.defaultNewProjectTemplate } ?? templates.first
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? localized("project.untitled") : name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = SampleData.project(
            named: title,
            template: selectedTemplate,
            blankProjectStart: settings.generalPreferences.blankProjectStart,
            defaultSceneName: localized("templates.defaultScene"),
            exportPresetName: localized("export.editorHandoff"),
            sceneNameResolver: { [weak self] name in self?.localizedTemplateSceneName(name) ?? name }
        )
        projectStore.openProject(project, fileURL: nil, wordsPerMinute: settings.editorPreferences.wordsPerMinute, markUnsaved: true)
        projectStore.synchronizeTextSegments(splitMode: settings.generalPreferences.defaultSplitMode, wordsPerMinute: settings.editorPreferences.wordsPerMinute)
        editorState.selectedSceneID = project.scenes.sortedByOrder.first?.id
        editorState.selectedMode = .script
        editorState.isFocusModeEnabled = false
        windowState.newProjectRequest = nil
    }

    func openDemoProject() {
        let project = SampleData.demoProject(language: currentLanguage)
        projectStore.openProject(project, fileURL: nil, wordsPerMinute: settings.editorPreferences.wordsPerMinute, markUnsaved: true)
        projectStore.synchronizeTextSegments(splitMode: settings.generalPreferences.defaultSplitMode, wordsPerMinute: settings.editorPreferences.wordsPerMinute)
        editorState.selectedSceneID = project.scenes.sortedByOrder.first?.id
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.frameScript, .frameScriptLegacy]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = localized("dialog.openProject.message")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(at: url)
    }

    func openProject(at url: URL) {
        do {
            let project = try FrameScriptFileStore.read(from: url)
            projectStore.openProject(project, fileURL: url, wordsPerMinute: settings.editorPreferences.wordsPerMinute, markUnsaved: false)
            projectStore.synchronizeTextSegments(splitMode: settings.generalPreferences.defaultSplitMode, wordsPerMinute: settings.editorPreferences.wordsPerMinute, markUnsaved: false)
            editorState.selectedSceneID = project.scenes.sortedByOrder.first?.id
        } catch {
            presentError(localized("error.openProject"), details: error.localizedDescription)
        }
    }

    func importProject() {
        openProject()
    }

    @discardableResult
    func saveProject() -> Bool {
        guard hasOpenProject else { return false }
        do {
            try projectStore.saveCurrentProject(wordsPerMinute: settings.editorPreferences.wordsPerMinute)
            return true
        } catch ProjectStore.ProjectFileError.missingFileURL {
            return saveProjectAs()
        } catch {
            presentError(localized("error.saveProject"), details: error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func saveProjectAs() -> Bool {
        guard hasOpenProject else { return false }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.frameScript]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(project.title).fscr"
        panel.message = localized("dialog.saveProject.message")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try projectStore.saveCurrentProject(to: url, wordsPerMinute: settings.editorPreferences.wordsPerMinute)
            return true
        } catch {
            presentError(localized("error.saveProject"), details: error.localizedDescription)
            return false
        }
    }

    func exportProject() {
        guard hasOpenProject else { return }
        windowState.isExportPresented = true
    }

    func saveExport(format: ExportFormat, preferences: ExportPreferences, to url: URL) {
        guard hasOpenProject else { return }
        do {
            let rendered = dependencies.exportService.render(project: project, format: format, preferences: preferences, language: currentLanguage)
            try rendered.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            presentError(localized("error.exportProject"), details: error.localizedDescription)
        }
    }

    func copyExportToClipboard(format: ExportFormat, preferences: ExportPreferences) {
        guard hasOpenProject else { return }
        let rendered = dependencies.exportService.render(project: project, format: format, preferences: preferences, language: currentLanguage)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(rendered, forType: .string)
    }

    func duplicateProject() {
        guard hasOpenProject else { return }
        let copy = projectStore.duplicateProject(copySuffix: localized("templates.copySuffix"))
        editorState.selectedSceneID = copy.scenes.sortedByOrder.first?.id
    }

    @discardableResult
    func closeProject() -> Bool {
        guard hasOpenProject else { return true }
        guard confirmCloseProjectIfNeeded() else { return false }
        projectStore.closeProject()
        editorState.selectedSceneID = nil
        return true
    }

    func revealProjectInFinder() {
        guard let url = projectStore.currentFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func renameProject() {
        guard hasOpenProject,
              let newName = prompt(title: localized("project.rename"), message: localized("dialog.renameProject.message"), defaultValue: project.title),
              !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        project.title = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        touchProject()
    }

    func deleteProject() {
        guard hasOpenProject else { return }
        if settings.generalPreferences.confirmBeforeDeleting,
           !confirm(title: localized("dialog.deleteProject.title"), message: localized("dialog.deleteProject.message")) {
            return
        }
        projectStore.deleteCurrentProject()
        editorState.selectedSceneID = nil
    }

    func selectScene(_ sceneID: UUID) {
        editorState.selectedSceneID = sceneID
    }

    func touchProject() {
        projectStore.markProjectDirty()
        scheduleAutosaveIfNeeded()
    }

    func touchCurrentSceneText() {
        guard let scene = selectedScene else {
            touchProject()
            return
        }
        projectStore.setSegmentSplitMode(settings.generalPreferences.defaultSplitMode)
        projectStore.updateCurrentSceneMetrics(sceneID: scene.id, wordsPerMinute: settings.editorPreferences.wordsPerMinute)
        projectStore.markProjectDirty()
        scheduleSegmentRebuild(for: scene.id)
        scheduleAutosaveIfNeeded()
    }

    func rebuildProductionSegments(markUnsaved: Bool = true) {
        projectStore.synchronizeTextSegments(
            splitMode: settings.generalPreferences.defaultSplitMode,
            wordsPerMinute: settings.editorPreferences.wordsPerMinute,
            markUnsaved: markUnsaved
        )
        scheduleAutosaveIfNeeded()
    }

    func addBRollItem(sceneID: UUID, anchor: TextAnchor) {
        guard let scene = project.scenes.first(where: { $0.id == sceneID }) else { return }
        scene.bRollItems.append(BRollItem(textAnchor: anchor, linkedSegmentID: nil, templateType: "", sourceType: .custom, descriptionText: anchor.selectedText))
        editorState.selectedMode = .bRoll
        touchProject()
    }

    func addEditingItem(sceneID: UUID, anchor: TextAnchor) {
        guard let scene = project.scenes.first(where: { $0.id == sceneID }) else { return }
        scene.editingItems.append(EditingItem(textAnchor: anchor, linkedSegmentID: nil, templateType: "", cutStyle: anchor.selectedText, transition: "", subtitleStyle: ""))
        editorState.selectedMode = .editing
        touchProject()
    }

    func selectProductionItem(_ itemID: UUID, mode: WorkspaceMode) {
        editorState.selectedProductionItemID = itemID
        editorState.selectedProductionSegmentID = projectStore.segmentID(forProductionItem: itemID, mode: mode)
        editorState.selectedMode = mode
    }

    func addScene() {
        guard hasOpenProject else { return }
        let scene = projectStore.makeScene(order: project.scenes.count, title: localized("templates.defaultScene"))
        projectStore.addScene(scene, wordsPerMinute: settings.editorPreferences.wordsPerMinute)
        editorState.selectedSceneID = scene.id
        editorState.selectedMode = .script
        scheduleAutosaveIfNeeded()
    }

    func addScene(after sceneID: UUID) {
        guard hasOpenProject else { return }
        let ordered = project.scenes.sortedByOrder
        let targetIndex = ordered.firstIndex { $0.id == sceneID } ?? max(0, ordered.count - 1)
        let scene = projectStore.makeScene(order: targetIndex + 1, title: localized("templates.defaultScene"))
        projectStore.addScene(scene, afterSortedIndex: targetIndex, wordsPerMinute: settings.editorPreferences.wordsPerMinute)
        editorState.selectedSceneID = scene.id
        editorState.selectedMode = .script
        scheduleAutosaveIfNeeded()
    }

    func duplicateSelectedScene() {
        guard let scene = selectedScene else { return }
        let copy = projectStore.duplicate(scene, copySuffix: localized("templates.copySuffix"))
        projectStore.addScene(copy, wordsPerMinute: settings.editorPreferences.wordsPerMinute)
        editorState.selectedSceneID = copy.id
        scheduleAutosaveIfNeeded()
    }

    func deleteSelectedScene() {
        if settings.generalPreferences.confirmBeforeDeleting,
           !confirm(title: localized("dialog.deleteScene.title"), message: localized("dialog.deleteScene.message")) {
            return
        }
        guard let selectedSceneIndex else { return }
        projectStore.deleteScene(at: selectedSceneIndex, wordsPerMinute: settings.editorPreferences.wordsPerMinute)
        editorState.selectedSceneID = project.scenes[safe: min(selectedSceneIndex, project.scenes.count - 1)]?.id
        scheduleAutosaveIfNeeded()
    }

    func moveSelectedSceneUp() {
        moveSelectedScene(by: -1)
    }

    func moveSelectedSceneDown() {
        moveSelectedScene(by: 1)
    }

    private func moveSelectedScene(by delta: Int) {
        guard let selectedSceneIndex else { return }
        projectStore.moveScene(at: selectedSceneIndex, by: delta, wordsPerMinute: settings.editorPreferences.wordsPerMinute)
        scheduleAutosaveIfNeeded()
    }

    func renameSelectedScene() {
        guard let scene = selectedScene,
              let newName = prompt(title: localized("scene.rename"), message: localized("dialog.renameScene.message"), defaultValue: scene.title),
              !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        scene.title = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        touchProject()
    }

    func generateBRollForSelectedScene() {
        Task { await generateProductionSuggestion(kind: .bRollGeneration) }
    }

    func generateEditingNotesForSelectedScene() {
        Task { await generateProductionSuggestion(kind: .editingGeneration) }
    }

    private func generateProductionSuggestion(kind: AITask) async {
        guard settings.aiPreferences.provider != .disabled else {
            presentError(localized("ai.generationUnavailable.title"), details: localized("ai.generationConnect"))
            return
        }
        guard let scene = selectedScene else { return }
        rebuildProductionSegments(markUnsaved: false)
        let segments = scene.textSegments.sortedByOrder
        guard let segment = segments.first(where: { $0.id == editorState.selectedProductionSegmentID }) ?? segments.first else {
            presentError(localized("ai.generationFailed.title"), details: localized("ai.generationNoSegment"))
            return
        }

        let schema = kind == .bRollGeneration
            ? "Return only one JSON object with string fields: source, description, notes. Source must be one of: \(BRollSourceType.allCases.map(\.rawValue).joined(separator: ", "))."
            : "Return only one JSON object with string fields: description, notes."
        let context = settings.aiPreferences.privacyMode
            ? segment.sourceText
            : "Scene: \(scene.title)\nFull scene: \(scene.scriptText)\nTarget segment: \(segment.sourceText)"
        do {
            let response = try await OpenAICompatibleLLMProvider().complete(request: LLMRequest(
                task: kind,
                provider: settings.aiPreferences.provider,
                baseURL: settings.aiPreferences.baseURL,
                systemPrompt: "\(PromptBuilder().systemPrompt(for: kind)) \(schema) Do not use Markdown fences.",
                userPrompt: context,
                model: settings.aiPreferences.model,
                temperature: settings.aiPreferences.temperature,
                maxTokens: settings.aiPreferences.maxTokens
            ))
            let data = try Self.structuredJSONData(from: response.text)
            switch kind {
            case .bRollGeneration:
                let value = try JSONDecoder().decode(GeneratedBRollSuggestion.self, from: data)
                guard !value.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GenerationError.emptyDescription }
                let source = BRollSourceType.allCases.first { $0.rawValue.caseInsensitiveCompare(value.source) == .orderedSame } ?? .custom
                scene.bRollItems.append(BRollItem(textAnchor: projectStore.anchor(for: segment.id, in: scene), linkedSegmentID: segment.id, templateType: "", sourceType: source, descriptionText: value.description, notes: value.notes))
                selectedMode = .bRoll
            case .editingGeneration:
                let value = try JSONDecoder().decode(GeneratedEditingSuggestion.self, from: data)
                guard !value.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GenerationError.emptyDescription }
                scene.editingItems.append(EditingItem(textAnchor: projectStore.anchor(for: segment.id, in: scene), linkedSegmentID: segment.id, templateType: "", cutStyle: value.description, transition: "", subtitleStyle: "", notes: value.notes))
                selectedMode = .editing
            default: return
            }
            editorState.selectedProductionSegmentID = segment.id
            touchProject()
        } catch {
            presentError(localized("ai.generationFailed.title"), details: "\(localized("ai.generationFailed.message")) \(error.localizedDescription)")
        }
    }

    private static func structuredJSONData(from response: String) throws -> Data {
        guard let start = response.firstIndex(of: "{"), let end = response.lastIndex(of: "}"), start <= end,
              let data = String(response[start...end]).data(using: .utf8) else { throw GenerationError.invalidJSON }
        return data
    }

    func moveSelection(_ delta: Int) {
        guard let selectedSceneIndex else { return }
        let nextIndex = max(0, min(project.scenes.count - 1, selectedSceneIndex + delta))
        editorState.selectedSceneID = project.scenes[nextIndex].id
    }

    func analyzeSelectedScene() async {
        guard let scene = selectedScene else { return }
        aiState.isAnalyzing = true
        let comments = settings.aiPreferences.provider == .disabled
            ? disabledAIComments(for: scene)
            : await dependencies.analysisService.analyze(scene: scene, project: project, settings: settings.aiPreferences)
        scene.aiComments = comments
        touchProject()
        aiState.isAnalyzing = false
    }

    func analyzeFullScript() async {
        for scene in project.scenes.sortedByOrder {
            aiState.isAnalyzing = true
            let comments = settings.aiPreferences.provider == .disabled
                ? disabledAIComments(for: scene)
                : await dependencies.analysisService.analyze(scene: scene, project: project, settings: settings.aiPreferences)
            scene.aiComments = comments
        }
        touchProject()
        aiState.isAnalyzing = false
    }

    func clearRecentProjects() {
        projectStore.clearRecentProjects()
    }

    func openSettings(tab: SettingsTab = .general, highlightKey: String? = nil) {
        windowState.requestedSettingsTab = tab
        windowState.requestedSettingsHighlightKey = highlightKey
        windowState.settingsRequestID = UUID()
    }

    func resetSidebarWidth() {
        settings.windowPreferences.sidebarWidth = AppSettings.defaults.windowPreferences.sidebarWidth
    }

    func chooseDefaultExportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = localized("dialog.exportFolder.message")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.exportPreferences.defaultExportFolder = url.path
    }

    func clearDefaultExportFolder() {
        settings.exportPreferences.defaultExportFolder = ""
    }

    private func confirmCloseProjectIfNeeded() -> Bool {
        guard projectStore.needsCloseConfirmation else { return true }
        let alert = NSAlert()
        alert.messageText = localized("project.unsaved.title")
        alert.informativeText = projectStore.currentFileURL == nil
            ? localized("project.unsaved.untitled")
            : localized("project.unsaved.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: localized("project.unsaved.save"))
        alert.addButton(withTitle: localized("project.unsaved.discard"))
        alert.addButton(withTitle: localized("project.unsaved.cancel"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveProject()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func disabledAIComments(for scene: Scene) -> [AIComment] {
        [
            AIComment(
                sceneID: scene.id,
                segmentID: scene.textSegments.sortedByOrder.first?.id,
                type: localized("ai.disabled.type"),
                severity: .note,
                message: localized("ai.disabled.message"),
                suggestion: localized("ai.disabled.suggestion")
            )
        ]
    }

    private func scheduleAutosaveIfNeeded() {
        autosaveTask?.cancel()
        guard settings.generalPreferences.autosaveEnabled,
              projectStore.currentFileURL != nil,
              projectStore.hasUnsavedFileChanges else {
            return
        }
        let delay = UInt64(settings.generalPreferences.autosaveIntervalSeconds) * 1_000_000_000
        autosaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.performAutosave()
        }
    }

    private func scheduleSegmentRebuild(for sceneID: UUID) {
        segmentRebuildTasks[sceneID]?.cancel()
        segmentRebuildTasks[sceneID] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 320_000_000)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.projectStore.synchronizeTextSegments(
                forSceneID: sceneID,
                splitMode: self.settings.generalPreferences.defaultSplitMode,
                wordsPerMinute: self.settings.editorPreferences.wordsPerMinute,
                markUnsaved: false
            )
            self.segmentRebuildTasks[sceneID] = nil
        }
    }

    private func performAutosave() {
        guard settings.generalPreferences.autosaveEnabled,
              projectStore.currentFileURL != nil,
              projectStore.hasUnsavedFileChanges else {
            return
        }
        do {
            try projectStore.saveCurrentProject(wordsPerMinute: settings.editorPreferences.wordsPerMinute)
        } catch {
            presentError(localized("error.saveProject"), details: error.localizedDescription)
        }
    }

    private func presentError(_ title: String, details: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = details
        alert.alertStyle = .warning
        alert.addButton(withTitle: localized("dialog.ok"))
        alert.runModal()
    }

    private func confirm(title: String, message: String, confirmButtonTitle: String? = nil) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmButtonTitle ?? localized("dialog.delete"))
        alert.addButton(withTitle: localized("project.unsaved.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func prompt(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: localized("dialog.ok"))
        alert.addButton(withTitle: localized("project.unsaved.cancel"))
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.stringValue = defaultValue
        alert.accessoryView = textField
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return textField.stringValue
    }

    func scriptTemplates() -> [FrameTemplate] {
        templates.filter { $0.category == .script }
    }

    func displayName(_ template: FrameTemplate) -> String {
        guard template.builtIn else { return template.name }
        return localized("template.\(templateKey(for: template.name))")
    }

    func localizedTemplateSceneName(_ name: String) -> String {
        localized("template.scene.\(templateSceneKey(for: name))")
    }

    func createCustomTemplate() {
        let template = FrameTemplate(
            id: UUID(),
            category: .script,
            name: uniqueTemplateName(base: localized("templates.untitled")),
            builtIn: false,
            structureDefinition: [localized("templates.defaultScene")],
            customFields: []
        )
        templates.append(template)
        persistCustomTemplates()
    }

    func duplicateTemplate(_ template: FrameTemplate) {
        var copy = template
        copy.id = UUID()
        copy.builtIn = false
        copy.builtInSourceName = nil
        copy.name = uniqueTemplateName(base: "\(template.name) \(localized("templates.copySuffix"))")
        templates.append(copy)
        persistCustomTemplates()
    }

    @discardableResult
    func customizeBuiltInTemplate(_ template: FrameTemplate) -> FrameTemplate? {
        guard template.builtIn else { return template }
        var override = template
        override.builtIn = false
        override.builtInSourceName = template.name
        override.name = displayName(template)
        override.structureDefinition = template.structureDefinition.map(localizedTemplateSceneName)

        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return nil }
        templates[index] = override
        if settings.generalPreferences.defaultNewProjectTemplate == template.name {
            settings.generalPreferences.defaultNewProjectTemplate = override.name
        }
        persistCustomTemplates()
        return override
    }

    @discardableResult
    func restoreOriginalTemplate(_ template: FrameTemplate) -> FrameTemplate? {
        guard let sourceName = template.builtInSourceName,
              var original = builtInTemplates.first(where: { $0.name == sourceName }) else {
            return nil
        }
        guard confirm(
            title: localized("dialog.restoreTemplate.title"),
            message: localized("dialog.restoreTemplate.message"),
            confirmButtonTitle: localized("templates.restoreOriginal")
        ) else {
            return nil
        }

        guard let index = templates.firstIndex(where: { $0.id == template.id }) else { return nil }
        original.id = template.id
        templates[index] = original
        if settings.generalPreferences.defaultNewProjectTemplate == template.name {
            settings.generalPreferences.defaultNewProjectTemplate = original.name
        }
        persistCustomTemplates()
        return original
    }

    func updateTemplate(_ template: FrameTemplate) {
        guard !template.builtIn, let index = templates.firstIndex(where: { $0.id == template.id }) else { return }
        templates[index] = template
        persistCustomTemplates()
    }

    func deleteTemplate(_ template: FrameTemplate) {
        guard !template.builtIn else { return }
        guard confirm(
            title: localized("dialog.deleteTemplate.title"),
            message: localized("dialog.deleteTemplate.message")
        ) else {
            return
        }
        templates.removeAll { $0.id == template.id }
        if settings.generalPreferences.defaultNewProjectTemplate == template.name {
            settings.generalPreferences.defaultNewProjectTemplate = scriptTemplates().first?.name ?? "Blank"
        }
        persistCustomTemplates()
    }

    func resetSettingsWithConfirmation() {
        guard confirm(
            title: localized("dialog.resetSettings.title"),
            message: localized("dialog.resetSettings.message"),
            confirmButtonTitle: localized("settings.reset")
        ) else {
            return
        }
        settingsStore.reset()
    }

    func clearAPIKeysWithConfirmation() {
        guard confirm(
            title: localized("dialog.clearKeys.title"),
            message: localized("dialog.clearKeys.message"),
            confirmButtonTitle: localized("settings.clearKeys")
        ) else {
            return
        }
        for provider in AIProviderKind.allCases {
            KeychainStore.deleteAPIKey(account: provider.rawValue)
        }
    }

    private func templateKey(for name: String) -> String {
        switch name {
        case "Blank": "blank"
        case "Standard YouTube": "standardYouTube"
        case "Educational": "educational"
        case "Storytelling": "storytelling"
        case "Product Review": "productReview"
        case "Commentary / Essay": "commentaryEssay"
        case "Tutorial": "tutorial"
        default: name
        }
    }

    private func templateSceneKey(for name: String) -> String {
        switch name {
        case "Hook": "hook"
        case "Problem": "problem"
        case "Why this matters": "whyThisMatters"
        case "Explanation": "explanation"
        case "Example": "example"
        case "Takeaway": "takeaway"
        case "CTA": "cta"
        case "Context": "context"
        case "Core explanation": "coreExplanation"
        case "Summary": "summary"
        case "Setup": "setup"
        case "Conflict": "conflict"
        case "Turning point": "turningPoint"
        case "Resolution": "resolution"
        case "Lesson": "lesson"
        case "Product context": "productContext"
        case "What works": "whatWorks"
        case "What does not": "whatDoesNot"
        case "Verdict": "verdict"
        case "Thesis": "thesis"
        case "Argument": "argument"
        case "Counterpoint": "counterpoint"
        case "Implication": "implication"
        case "Closing": "closing"
        case "Goal": "goal"
        case "Requirements": "requirements"
        case "Step 1": "step1"
        case "Step 2": "step2"
        case "Common mistake": "commonMistake"
        case "Recap": "recap"
        default: name
        }
    }

    private func uniqueTemplateName(base: String) -> String {
        let names = Set(templates.map(\.name))
        guard names.contains(base) else { return base }
        var counter = 2
        while names.contains("\(base) \(counter)") {
            counter += 1
        }
        return "\(base) \(counter)"
    }

    private func persistCustomTemplates() {
        Self.saveCustomTemplates(templates.filter { !$0.builtIn })
    }

    private static func mergedTemplates(builtIns: [FrameTemplate], customTemplates: [FrameTemplate]) -> [FrameTemplate] {
        let customized = Dictionary(
            customTemplates.compactMap { template in
                template.builtInSourceName.map { ($0, template) }
            },
            uniquingKeysWith: { _, latest in latest }
        )
        let resolvedBuiltIns = builtIns.map { customized[$0.name] ?? $0 }
        let customOnly = customTemplates.filter { template in
            template.builtInSourceName == nil
                && !builtIns.contains { $0.name == template.name && $0.category == template.category }
        }
        return resolvedBuiltIns + customOnly
    }

    private static let customTemplatesKey = "FrameScript.customTemplates.v1"

    private static func loadCustomTemplates() -> [FrameTemplate] {
        guard let data = UserDefaults.standard.data(forKey: customTemplatesKey) else { return [] }
        return (try? JSONDecoder().decode([FrameTemplate].self, from: data)) ?? []
    }

    private static func saveCustomTemplates(_ templates: [FrameTemplate]) {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        UserDefaults.standard.set(data, forKey: customTemplatesKey)
    }
}

@MainActor
@Observable
final class ProjectStore {
    enum ProjectFileError: Error {
        case missingFileURL
    }

    private var isConfigured = false
    private(set) var project: FrameProject
    private(set) var hasOpenProject = false
    private(set) var currentFileURL: URL?
    private(set) var saveState: SaveState = .saved
    private(set) var hasUnsavedFileChanges = false
    private let recentProjectsKey = "FrameScript.recentProjectPaths"
    private(set) var recentProjectURLs: [URL] = []
    private var segmentSplitMode: SegmentType = AppSettings.defaults.generalPreferences.defaultSplitMode

    init(project: FrameProject = SampleData.defaultProject) {
        self.project = project
        recentProjectURLs = UserDefaults.standard.stringArray(forKey: recentProjectsKey)?.map(URL.init(fileURLWithPath:)) ?? []
        recalculateDurations(wordsPerMinute: AppSettings.defaults.editorPreferences.wordsPerMinute)
    }

    func setSegmentSplitMode(_ splitMode: SegmentType) {
        segmentSplitMode = splitMode
    }

    func configure(
        restoreLastProjectOnLaunch: Bool,
        wordsPerMinute: Int
    ) {
        if !isConfigured, restoreLastProjectOnLaunch {
            pruneMissingRecentProjectURLs()
            if let url = recentProjectURLs.first {
                do {
                    let restoredProject = try FrameScriptFileStore.read(from: url)
                    openProject(restoredProject, fileURL: url, wordsPerMinute: wordsPerMinute, markUnsaved: false)
                } catch {
                    recentProjectURLs.removeAll { $0.path == url.path }
                    UserDefaults.standard.set(recentProjectURLs.map(\.path), forKey: recentProjectsKey)
                }
            }
        }
        isConfigured = true
        recalculateDurations(wordsPerMinute: wordsPerMinute)
    }

    func openProject(_ project: FrameProject, fileURL: URL?, wordsPerMinute: Int, markUnsaved: Bool) {
        self.project = project
        currentFileURL = fileURL
        hasOpenProject = true
        if let fileURL {
            rememberRecentProject(fileURL)
        }
        recalculateDurations(wordsPerMinute: wordsPerMinute)
        hasUnsavedFileChanges = markUnsaved || fileURL == nil
        saveState = hasUnsavedFileChanges ? .edited : .saved
    }

    func closeProject() {
        hasOpenProject = false
        currentFileURL = nil
        hasUnsavedFileChanges = false
        saveState = .saved
    }

    var needsCloseConfirmation: Bool {
        hasOpenProject && (hasUnsavedFileChanges || currentFileURL == nil)
    }

    func saveCurrentProject(wordsPerMinute: Int) throws {
        guard let currentFileURL else { throw ProjectFileError.missingFileURL }
        try saveCurrentProject(to: currentFileURL, wordsPerMinute: wordsPerMinute)
    }

    func saveCurrentProject(to url: URL, wordsPerMinute: Int) throws {
        prepareForSave(wordsPerMinute: wordsPerMinute)
        try FrameScriptFileStore.write(project: project, to: url)
        currentFileURL = url
        rememberRecentProject(url)
        hasUnsavedFileChanges = false
        saveState = .saved
    }

    func duplicateProject(copySuffix: String) -> FrameProject {
        let copy = FrameProject(
            title: "\(project.title) \(copySuffix)",
            templateID: project.templateID,
            scenes: project.scenes.sortedByOrder.enumerated().map { index, scene in
                let sceneID = UUID()
                var oldToNewSegmentIDs: [UUID: UUID] = [:]
                let oldSegments = scene.textSegments.sortedByOrder
                let segments = oldSegments.enumerated().map { offset, segment in
                    let copy = TextSegment(
                        sceneID: sceneID,
                        order: offset,
                        sourceText: segment.sourceText,
                        segmentType: segment.segmentType,
                        timingEstimate: segment.timingEstimate
                    )
                    oldToNewSegmentIDs[segment.id] = copy.id
                    return copy
                }
                return Scene(
                    id: sceneID,
                    order: index,
                    sectionType: scene.sectionType,
                    title: scene.title,
                    scriptText: scene.scriptText,
                    notes: scene.notes,
                    estimatedDuration: scene.estimatedDuration,
                    textSegments: segments,
                    aiComments: scene.aiComments.map {
                        AIComment(
                            sceneID: sceneID,
                            segmentID: mappedSegmentID($0.segmentID, oldSegments: oldSegments, newSegments: segments, oldToNewSegmentIDs: oldToNewSegmentIDs),
                            type: $0.type,
                            severity: $0.severity,
                            message: $0.message,
                            suggestion: $0.suggestion,
                            status: $0.status
                        )
                    },
                    bRollItems: scene.bRollItems.map {
                        BRollItem(
                            textAnchor: $0.textAnchor,
                            linkedSegmentID: mappedSegmentID($0.linkedSegmentID, oldSegments: oldSegments, newSegments: segments, oldToNewSegmentIDs: oldToNewSegmentIDs),
                            templateType: $0.templateType,
                            sourceType: $0.sourceType,
                            descriptionText: $0.descriptionText,
                            mood: $0.mood,
                            framing: $0.framing,
                            motion: $0.motion,
                            duration: $0.duration,
                            notes: $0.notes,
                            status: $0.status
                        )
                    },
                    editingItems: scene.editingItems.map {
                        EditingItem(
                            textAnchor: $0.textAnchor,
                            linkedSegmentID: mappedSegmentID($0.linkedSegmentID, oldSegments: oldSegments, newSegments: segments, oldToNewSegmentIDs: oldToNewSegmentIDs),
                            templateType: $0.templateType,
                            cutStyle: $0.cutStyle,
                            transition: $0.transition,
                            subtitleStyle: $0.subtitleStyle,
                            emphasis: $0.emphasis,
                            zoom: $0.zoom,
                            sfx: $0.sfx,
                            musicCue: $0.musicCue,
                            graphics: $0.graphics,
                            notes: $0.notes
                        )
                    }
                )
            },
            settingsOverride: project.settingsOverride,
            exportPresets: project.exportPresets
        )
        project = copy
        currentFileURL = nil
        hasOpenProject = true
        hasUnsavedFileChanges = true
        saveState = .edited
        return copy
    }

    func deleteCurrentProject() {
        project = SampleData.defaultProject
        currentFileURL = nil
        hasOpenProject = false
        hasUnsavedFileChanges = false
        saveState = .saved
    }

    var totalDuration: TimeInterval {
        project.scenes.reduce(0) { $0 + $1.estimatedDuration }
    }

    func selectedScene(id: UUID?) -> Scene? {
        guard let id else { return project.scenes.sortedByOrder.first }
        return project.scenes.first(where: { $0.id == id }) ?? project.scenes.sortedByOrder.first
    }

    func selectedSceneIndex(id: UUID?) -> Int? {
        guard let id else { return nil }
        return project.scenes.sortedByOrder.firstIndex(where: { $0.id == id })
    }

    func makeScene(order: Int, title: String) -> Scene {
        let id = UUID()
        return Scene(
            id: id,
            order: order,
            sectionType: .custom,
            title: title,
            scriptText: "",
            textSegments: []
        )
    }

    func addScene(_ scene: Scene, wordsPerMinute: Int) {
        project.scenes.append(scene)
        normalizeSceneOrder()
        updateCurrentSceneMetrics(sceneID: scene.id, wordsPerMinute: wordsPerMinute)
        markProjectDirty()
    }

    func addScene(_ scene: Scene, afterSortedIndex index: Int, wordsPerMinute: Int) {
        for existing in project.scenes where existing.order > index {
            existing.order += 1
        }
        scene.order = index + 1
        project.scenes.append(scene)
        normalizeSceneOrder()
        updateCurrentSceneMetrics(sceneID: scene.id, wordsPerMinute: wordsPerMinute)
        markProjectDirty()
    }

    func duplicate(_ scene: Scene, copySuffix: String) -> Scene {
        let copyID = UUID()
        var oldToNewSegmentIDs: [UUID: UUID] = [:]
        let oldSegments = scene.textSegments.sortedByOrder
        let segments = oldSegments.enumerated().map { offset, segment in
            let copy = TextSegment(
                sceneID: copyID,
                order: offset,
                sourceText: segment.sourceText,
                segmentType: segment.segmentType,
                timingEstimate: segment.timingEstimate
            )
            oldToNewSegmentIDs[segment.id] = copy.id
            return copy
        }
        return Scene(
            id: copyID,
            order: project.scenes.count,
            sectionType: scene.sectionType,
            title: "\(scene.title) \(copySuffix)",
            scriptText: scene.scriptText,
            notes: scene.notes,
            estimatedDuration: scene.estimatedDuration,
            textSegments: segments,
            aiComments: scene.aiComments.map {
                AIComment(
                    sceneID: copyID,
                    segmentID: mappedSegmentID($0.segmentID, oldSegments: oldSegments, newSegments: segments, oldToNewSegmentIDs: oldToNewSegmentIDs),
                    type: $0.type,
                    severity: $0.severity,
                    message: $0.message,
                    suggestion: $0.suggestion,
                    status: $0.status
                )
            },
            bRollItems: scene.bRollItems.map {
                BRollItem(
                    textAnchor: $0.textAnchor,
                    linkedSegmentID: mappedSegmentID($0.linkedSegmentID, oldSegments: oldSegments, newSegments: segments, oldToNewSegmentIDs: oldToNewSegmentIDs),
                    templateType: $0.templateType,
                    sourceType: $0.sourceType,
                    descriptionText: $0.descriptionText,
                    mood: $0.mood,
                    framing: $0.framing,
                    motion: $0.motion,
                    duration: $0.duration,
                    notes: $0.notes,
                    status: $0.status
                )
            },
            editingItems: scene.editingItems.map {
                EditingItem(
                    textAnchor: $0.textAnchor,
                    linkedSegmentID: mappedSegmentID($0.linkedSegmentID, oldSegments: oldSegments, newSegments: segments, oldToNewSegmentIDs: oldToNewSegmentIDs),
                    templateType: $0.templateType,
                    cutStyle: $0.cutStyle,
                    transition: $0.transition,
                    subtitleStyle: $0.subtitleStyle,
                    emphasis: $0.emphasis,
                    zoom: $0.zoom,
                    sfx: $0.sfx,
                    musicCue: $0.musicCue,
                    graphics: $0.graphics,
                    notes: $0.notes
                )
            }
        )
    }

    private func mappedSegmentID(
        _ oldID: UUID?,
        oldSegments: [TextSegment],
        newSegments: [TextSegment],
        oldToNewSegmentIDs: [UUID: UUID]
    ) -> UUID? {
        guard let oldID else { return nil }
        if let newID = oldToNewSegmentIDs[oldID] {
            return newID
        }
        guard let oldOrder = oldSegments.first(where: { $0.id == oldID })?.order else {
            return nil
        }
        return newSegments.min { abs($0.order - oldOrder) < abs($1.order - oldOrder) }?.id
    }

    func deleteScene(at sortedIndex: Int, wordsPerMinute: Int) {
        guard project.scenes.count > 1 else { return }
        let ordered = project.scenes.sortedByOrder
        guard let scene = ordered[safe: sortedIndex],
              let storageIndex = project.scenes.firstIndex(where: { $0.id == scene.id }) else {
            return
        }
        project.scenes.remove(at: storageIndex)
        normalizeSceneOrder()
        markProjectDirty()
    }

    func moveScene(at sortedIndex: Int, by delta: Int, wordsPerMinute: Int) {
        let ordered = project.scenes.sortedByOrder
        let destination = max(0, min(ordered.count - 1, sortedIndex + delta))
        guard sortedIndex != destination,
              let sourceScene = ordered[safe: sortedIndex],
              let destinationScene = ordered[safe: destination] else {
            return
        }
        swap(&sourceScene.order, &destinationScene.order)
        normalizeSceneOrder()
        markProjectDirty()
    }

    func markProjectDirty() {
        project.updatedAt = Date()
        hasUnsavedFileChanges = true
        saveState = .edited
    }

    func updateCurrentSceneMetrics(sceneID: UUID, wordsPerMinute: Int) {
        guard let scene = project.scenes.first(where: { $0.id == sceneID }) else { return }
        scene.estimatedDuration = DurationEstimator.estimate(text: scene.scriptText, wordsPerMinute: wordsPerMinute)
    }

    private func prepareForSave(wordsPerMinute: Int) {
        synchronizeTextSegments(splitMode: segmentSplitMode, wordsPerMinute: wordsPerMinute, markUnsaved: false)
        recalculateDurations(wordsPerMinute: wordsPerMinute)
        project.updatedAt = Date()
        saveState = .autosaving
    }

    func synchronizeTextSegments(splitMode: SegmentType, wordsPerMinute: Int, markUnsaved: Bool = true) {
        segmentSplitMode = splitMode
        for scene in project.scenes {
            synchronizeTextSegments(for: scene, splitMode: splitMode, wordsPerMinute: wordsPerMinute)
        }
        recalculateDurations(wordsPerMinute: wordsPerMinute)
        project.updatedAt = Date()
        if markUnsaved {
            hasUnsavedFileChanges = true
            saveState = .edited
        }
    }

    func synchronizeTextSegments(forSceneID sceneID: UUID, splitMode: SegmentType, wordsPerMinute: Int, markUnsaved: Bool = true) {
        segmentSplitMode = splitMode
        guard let scene = project.scenes.first(where: { $0.id == sceneID }) else { return }
        synchronizeTextSegments(for: scene, splitMode: splitMode, wordsPerMinute: wordsPerMinute)
        scene.estimatedDuration = DurationEstimator.estimate(text: scene.scriptText, wordsPerMinute: wordsPerMinute)
        project.updatedAt = Date()
        if markUnsaved {
            hasUnsavedFileChanges = true
            saveState = .edited
        }
    }

    private func synchronizeTextSegments(for scene: Scene, splitMode: SegmentType, wordsPerMinute: Int) {
        let texts = TextSegmenter.segmentTexts(in: scene.scriptText, splitMode: splitMode)
        let oldSegments = scene.textSegments.sortedByOrder
        let oldSegmentsByID = Dictionary(uniqueKeysWithValues: oldSegments.map { ($0.id, $0) })
        var unusedOldSegments = oldSegments
        var oldToNewIDs: [UUID: UUID] = [:]
        var nextSegments: [TextSegment] = []

        for (index, text) in texts.enumerated() {
            let normalizedText = TextSegmenter.normalized(text)
            let exactIndex = unusedOldSegments.firstIndex {
                $0.segmentType == splitMode && TextSegmenter.normalized($0.sourceText) == normalizedText
            }
            let fallbackIndex = exactIndex ?? unusedOldSegments.firstIndex { $0.order == index }
            let segment = fallbackIndex.flatMap { unusedOldSegments.remove(at: $0) }
                ?? TextSegment(sceneID: scene.id, order: index, sourceText: text, segmentType: splitMode)

            let oldID = segment.id
            segment.sceneID = scene.id
            segment.order = index
            segment.sourceText = text
            segment.segmentType = splitMode
            segment.timingEstimate = DurationEstimator.estimate(text: text, wordsPerMinute: wordsPerMinute)
            oldToNewIDs[oldID] = segment.id
            nextSegments.append(segment)
        }

        let nearestSegmentID: (UUID) -> UUID? = { oldID in
            guard let oldOrder = oldSegmentsByID[oldID]?.order, !nextSegments.isEmpty else {
                return nextSegments.first?.id
            }
            return nextSegments.min { abs($0.order - oldOrder) < abs($1.order - oldOrder) }?.id
        }

        let validIDs = Set(nextSegments.map(\.id))
        for item in scene.bRollItems {
            if let repaired = TextAnchorRepair.repair(item.textAnchor, in: scene.scriptText) {
                item.textAnchor = repaired
            } else if item.textAnchor != nil {
                item.textAnchor = nil
            }
            guard let linkedID = item.linkedSegmentID, !validIDs.contains(linkedID) else { continue }
            item.linkedSegmentID = oldToNewIDs[linkedID] ?? nearestSegmentID(linkedID)
            if item.textAnchor == nil, let segmentID = item.linkedSegmentID, let segment = nextSegments.first(where: { $0.id == segmentID }) {
                item.textAnchor = TextAnchorRepair.anchor(for: segment, in: scene.scriptText)
            }
        }
        for item in scene.editingItems {
            if let repaired = TextAnchorRepair.repair(item.textAnchor, in: scene.scriptText) {
                item.textAnchor = repaired
            } else if item.textAnchor != nil {
                item.textAnchor = nil
            }
            guard let linkedID = item.linkedSegmentID, !validIDs.contains(linkedID) else { continue }
            item.linkedSegmentID = oldToNewIDs[linkedID] ?? nearestSegmentID(linkedID)
            if item.textAnchor == nil, let segmentID = item.linkedSegmentID, let segment = nextSegments.first(where: { $0.id == segmentID }) {
                item.textAnchor = TextAnchorRepair.anchor(for: segment, in: scene.scriptText)
            }
        }

        scene.textSegments = nextSegments
    }

    func anchor(for segmentID: UUID, in scene: Scene) -> TextAnchor? {
        guard let segment = scene.textSegments.first(where: { $0.id == segmentID }) else { return nil }
        return TextAnchorRepair.anchor(for: segment, in: scene.scriptText)
    }

    func segmentID(forProductionItem itemID: UUID, mode: WorkspaceMode) -> UUID? {
        for scene in project.scenes {
            switch mode {
            case .bRoll:
                if let item = scene.bRollItems.first(where: { $0.id == itemID }) {
                    return item.linkedSegmentID
                }
            case .editing:
                if let item = scene.editingItems.first(where: { $0.id == itemID }) {
                    return item.linkedSegmentID
                }
            case .script:
                continue
            }
        }
        return nil
    }

    private func recalculateDurations(wordsPerMinute: Int) {
        for scene in project.scenes {
            scene.estimatedDuration = DurationEstimator.estimate(
                text: scene.scriptText,
                wordsPerMinute: wordsPerMinute
            )
        }
    }

    private func normalizeSceneOrder() {
        for (index, scene) in project.scenes.sortedByOrder.enumerated() {
            scene.order = index
        }
    }

    private func rememberRecentProject(_ url: URL) {
        recentProjectURLs.removeAll { $0.path == url.path }
        recentProjectURLs.insert(url, at: 0)
        recentProjectURLs = Array(recentProjectURLs.prefix(8))
        UserDefaults.standard.set(recentProjectURLs.map(\.path), forKey: recentProjectsKey)
    }

    private func pruneMissingRecentProjectURLs() {
        recentProjectURLs = recentProjectURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        UserDefaults.standard.set(recentProjectURLs.map(\.path), forKey: recentProjectsKey)
    }

    func clearRecentProjects() {
        recentProjectURLs = []
        UserDefaults.standard.removeObject(forKey: recentProjectsKey)
    }
}

@Observable
final class EditorState {
    var selectedMode: WorkspaceMode = .script
    var selectedSceneID: UUID?
    var selectedProductionSegmentID: UUID?
    var selectedProductionItemID: UUID?
    var isFocusModeEnabled = false
}

enum TextAnchorRepair {
    private static let contextLength = 48

    static func anchor(for segment: TextSegment, in text: String) -> TextAnchor? {
        let full = text as NSString
        guard full.length > 0, !segment.sourceText.isEmpty else { return nil }
        var searchStart = 0
        let candidates = TextSegmenter.segmentTexts(in: text, splitMode: segment.segmentType)
        for candidate in candidates {
            let searchRange = NSRange(location: searchStart, length: max(0, full.length - searchStart))
            let found = full.range(of: candidate, options: [], range: searchRange)
            guard found.location != NSNotFound else { continue }
            if TextSegmenter.normalized(candidate) == TextSegmenter.normalized(segment.sourceText) {
                return anchor(in: text, range: found)
            }
            searchStart = NSMaxRange(found)
        }
        let fallback = full.range(of: segment.sourceText)
        return fallback.location == NSNotFound ? nil : anchor(in: text, range: fallback)
    }

    static func anchor(in text: String, range: NSRange) -> TextAnchor? {
        let full = text as NSString
        let bounded = clamp(range, toLength: full.length)
        guard bounded.length > 0, NSMaxRange(bounded) <= full.length else { return nil }
        let selected = full.substring(with: bounded)
        return TextAnchor(
            startUTF16: bounded.location,
            lengthUTF16: bounded.length,
            selectedText: selected,
            prefixContext: full.substring(with: NSRange(location: max(0, bounded.location - contextLength), length: bounded.location - max(0, bounded.location - contextLength))),
            suffixContext: full.substring(with: NSRange(location: NSMaxRange(bounded), length: min(contextLength, full.length - NSMaxRange(bounded))))
        )
    }

    static func repair(_ anchor: TextAnchor?, in text: String) -> TextAnchor? {
        guard let anchor else { return nil }
        let full = text as NSString
        guard anchor.lengthUTF16 >= 0, anchor.startUTF16 >= 0, !anchor.selectedText.isEmpty else { return nil }
        let stored = NSRange(location: anchor.startUTF16, length: anchor.lengthUTF16)
        if NSMaxRange(stored) <= full.length, full.substring(with: stored) == anchor.selectedText {
            return self.anchor(in: text, range: stored)
        }

        let searchRange = nearbySearchRange(previousOffset: anchor.startUTF16, textLength: full.length)
        let local = full.range(of: anchor.selectedText, options: [], range: searchRange)
        if local.location != NSNotFound, contextsMatch(anchor: anchor, text: full, range: local) {
            return self.anchor(in: text, range: local)
        }

        let global = nearestOccurrence(of: anchor.selectedText, in: full, near: anchor.startUTF16)
        guard global.location != NSNotFound, contextsMatch(anchor: anchor, text: full, range: global) else { return nil }
        return self.anchor(in: text, range: global)
    }

    private static func nearbySearchRange(previousOffset: Int, textLength: Int) -> NSRange {
        let radius = max(256, contextLength * 4)
        let start = max(0, previousOffset - radius)
        let end = min(textLength, previousOffset + radius)
        return NSRange(location: start, length: max(0, end - start))
    }

    private static func nearestOccurrence(of selectedText: String, in text: NSString, near offset: Int) -> NSRange {
        var best = NSRange(location: NSNotFound, length: 0)
        var bestDistance = Int.max
        var searchStart = 0
        while searchStart < text.length {
            let found = text.range(of: selectedText, options: [], range: NSRange(location: searchStart, length: text.length - searchStart))
            guard found.location != NSNotFound else { break }
            let distance = abs(found.location - offset)
            if distance < bestDistance {
                best = found
                bestDistance = distance
            }
            searchStart = max(NSMaxRange(found), found.location + 1)
        }
        return best
    }

    private static func contextsMatch(anchor: TextAnchor, text: NSString, range: NSRange) -> Bool {
        let beforeStart = max(0, range.location - contextLength)
        let before = text.substring(with: NSRange(location: beforeStart, length: range.location - beforeStart))
        let afterLength = min(contextLength, text.length - NSMaxRange(range))
        let after = text.substring(with: NSRange(location: NSMaxRange(range), length: afterLength))
        let prefixOK = anchor.prefixContext.isEmpty || before.hasSuffix(anchor.prefixContext) || anchor.prefixContext.hasSuffix(before)
        let suffixOK = anchor.suffixContext.isEmpty || after.hasPrefix(anchor.suffixContext) || anchor.suffixContext.hasPrefix(after)
        return prefixOK && suffixOK
    }

    private static func clamp(_ range: NSRange, toLength length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        let maxLength = max(0, length - location)
        return NSRange(location: location, length: min(max(0, range.length), maxLength))
    }
}

@Observable
final class SettingsStore {
    var settings: AppSettings {
        didSet { save() }
    }

    private let key = "FrameScript.settings.v1"

    init(settings: AppSettings? = nil) {
        self.settings = settings ?? Self.load() ?? .defaults
    }

    func reset() {
        settings = .defaults
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: "FrameScript.settings.v1") else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }
}

@Observable
final class AIState {
    var isAnalyzing = false
}

@Observable
final class WindowState {
    var isSidebarVisible = true
    var isCommandPalettePresented = false
    var isSettingsPresented = false
    var isShortcutsPresented = false
    var requestedSettingsTab: SettingsTab = .general
    var requestedSettingsHighlightKey: String?
    var settingsRequestID = UUID()
    var newProjectRequest: NewProjectRequest?
    var isExportPresented = false
    var pendingSettingsTab: SettingsTab?
    var pendingSettingsHighlightKey: String?
}

enum SaveState: String {
    case saved = "Saved"
    case edited = "Edited"
    case autosaving = "Saving..."
}

enum TextSegmenter {
    static func segmentTexts(in text: String, splitMode: SegmentType) -> [String] {
        switch splitMode {
        case .scene:
            let trimmed = trimmed(text)
            return trimmed.isEmpty ? [] : [trimmed]
        case .paragraph:
            return text
                .components(separatedBy: CharacterSet.newlines)
                .map(trimmed)
                .filter { !$0.isEmpty }
        case .sentence:
            return sentenceTexts(in: text)
        }
    }

    static func normalized(_ text: String) -> String {
        trimmed(text)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    private static func sentenceTexts(in text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        var previousWasTerminator = false
        let terminators = CharacterSet(charactersIn: ".!?…")
        let closers = CharacterSet(charactersIn: "\"'»”’)]}")

        for scalar in text.unicodeScalars {
            current.unicodeScalars.append(scalar)
            if terminators.contains(scalar) {
                previousWasTerminator = true
                continue
            }
            if previousWasTerminator, closers.contains(scalar) {
                continue
            }
            if previousWasTerminator, CharacterSet.whitespacesAndNewlines.contains(scalar) {
                appendTrimmed(current, to: &sentences)
                current = ""
                previousWasTerminator = false
                continue
            }
            previousWasTerminator = false
        }

        appendTrimmed(current, to: &sentences)
        return sentences
    }

    private static func appendTrimmed(_ text: String, to sentences: inout [String]) {
        let value = trimmed(text)
        if !value.isEmpty {
            sentences.append(value)
        }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Array where Element == Scene {
    var sortedByOrder: [Scene] {
        sorted { $0.order < $1.order }
    }
}

extension Array where Element == TextSegment {
    var sortedByOrder: [TextSegment] {
        sorted { $0.order < $1.order }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
