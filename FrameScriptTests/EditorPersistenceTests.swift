import AppKit
import Foundation
import SwiftUI
@testable import FrameScript
import XCTest

@MainActor
final class EditorPersistenceTests: XCTestCase {
    private final class TextBox {
        var value: String
        init(_ value: String) { self.value = value }
    }

    private final class TestActiveEditor: ActiveScriptEditor {
        let flushAction: () -> Void
        init(_ flushAction: @escaping () -> Void) { self.flushAction = flushAction }
        func commitMarkedTextAndFlush() -> Bool {
            flushAction()
            return true
        }
        var isActualFirstResponder: Bool { true }
    }

    func testUserEditSynchronouslyUpdatesModel() {
        let box = TextBox("Old")
        let (coordinator, view) = makeCoordinator(box: box)
        view.textView.string = "Exact new text"

        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))

        XCTAssertEqual(box.value, "Exact new text")
    }

    func testStaleRepresentableUpdateCannotReplaceLastUserText() {
        var emitted = ""
        let staleBinding = Binding<String>(get: { "Old model value" }, set: { emitted = $0 })
        let parent = makeRepresentable(text: staleBinding)
        let coordinator = LinkedScriptTextView.Coordinator(parent: parent)
        let view = MarkerTextContainerView()
        coordinator.attach(to: view)
        view.textView.string = "Newest editor value"
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))

        coordinator.applyModelTextIfNeeded()

        XCTAssertEqual(view.textView.string, "Newest editor value")
        XCTAssertEqual(emitted, "Newest editor value")
    }

    func testLegitimateExternalModelUpdateReachesTextView() {
        let box = TextBox("Old")
        let (coordinator, view) = makeCoordinator(box: box)
        view.textView.string = "User edit"
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        box.value = "AI rewrite"

        coordinator.applyModelTextIfNeeded()

        XCTAssertEqual(view.textView.string, "AI rewrite")
        XCTAssertEqual(box.value, "AI rewrite")
    }

    func testCaretSelectionAndScrollRestoreAndClamp() {
        let box = TextBox(String(repeating: "line of text\n", count: 80))
        var saved: ScriptEditorRestorationState?
        let parent = makeRepresentable(
            text: Binding(get: { box.value }, set: { box.value = $0 }),
            loadState: { saved },
            saveState: { saved = $0 }
        )
        let first = LinkedScriptTextView.Coordinator(parent: parent)
        let firstView = MarkerTextContainerView(frame: NSRect(x: 0, y: 0, width: 400, height: 140))
        first.attach(to: firstView)
        first.applyModelTextIfNeeded()
        firstView.textView.setSelectedRange(NSRange(location: 42, length: 12))
        firstView.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 120))
        first.captureRestorationState()

        let recreated = LinkedScriptTextView.Coordinator(parent: parent)
        let recreatedView = MarkerTextContainerView(frame: firstView.frame)
        recreated.attach(to: recreatedView)
        recreated.applyModelTextIfNeeded()
        recreated.restoreEditorStateIfAvailable()

        XCTAssertEqual(recreatedView.textView.selectedRange(), NSRange(location: 42, length: 12))
        XCTAssertEqual(recreatedView.scrollView.contentView.bounds.origin.y, 120, accuracy: 1)

        box.value = "short"
        recreated.applyModelTextIfNeeded()
        recreated.restoreEditorStateIfAvailable()
        XCTAssertLessThanOrEqual(NSMaxRange(recreatedView.textView.selectedRange()), 5)
    }

    func testRestorationStateIsIndependentPerSceneAndEditor() {
        let state = EditorState()
        let sceneA = UUID(), sceneB = UUID(), windowA = UUID(), windowB = UUID()
        let first = ScriptEditorRestorationState(selectedRange: NSRange(location: 3, length: 2), visibleOrigin: NSPoint(x: 0, y: 40))
        let second = ScriptEditorRestorationState(selectedRange: NSRange(location: 8, length: 1), visibleOrigin: NSPoint(x: 0, y: 90))
        state.setScriptEditorState(first, sceneID: sceneA, editorIdentity: windowA)
        state.setScriptEditorState(second, sceneID: sceneB, editorIdentity: windowB)

        XCTAssertEqual(state.scriptEditorState(sceneID: sceneA, editorIdentity: windowA), first)
        XCTAssertEqual(state.scriptEditorState(sceneID: sceneB, editorIdentity: windowB), second)
        XCTAssertNil(state.scriptEditorState(sceneID: sceneA, editorIdentity: windowB))
    }

    func testDismantleFlushesAndRunsImmediateTeardownBoundary() {
        let box = TextBox("Old")
        var toreDown = false
        let parent = makeRepresentable(
            text: Binding(get: { box.value }, set: { box.value = $0 }),
            onTeardown: { toreDown = true }
        )
        let coordinator = LinkedScriptTextView.Coordinator(parent: parent)
        let view = MarkerTextContainerView()
        coordinator.attach(to: view)
        view.textView.string = "Latest"

        LinkedScriptTextView.dismantleNSView(view, coordinator: coordinator)

        XCTAssertEqual(box.value, "Latest")
        XCTAssertTrue(toreDown)
    }

    func testEditorFlushCommitsCurrentTextBeforeDismantle() {
        let box = TextBox("Old")
        let (coordinator, view) = makeCoordinator(box: box)
        view.textView.string = "Text present only in NSTextView"

        coordinator.commitMarkedTextAndFlush()

        XCTAssertEqual(box.value, "Text present only in NSTextView")
    }

    func testModeSwitchesPreserveExactText() {
        for mode in [WorkspaceMode.bRoll, .editing] {
            let (appState, scene, _) = makeAppState(fileURL: nil)
            let exact = "Typed immediately before \(mode.rawValue)"
            let editor = TestActiveEditor {
                scene.scriptText = exact
                appState.commitScriptTextChange(sceneID: scene.id)
            }
            ActiveScriptEditorSession.shared.register(editor)
            defer { ActiveScriptEditorSession.shared.unregister(editor) }

            appState.selectMode(mode)

            XCTAssertEqual(scene.scriptText, exact)
            XCTAssertEqual(appState.selectedMode, mode)
            XCTAssertEqual(appState.saveState, .edited)
        }
    }

    func testSelectingAnotherScenePreservesPreviousText() {
        let first = Scene(order: 0, sectionType: .custom, title: "One", scriptText: "Old")
        let second = Scene(order: 1, sectionType: .custom, title: "Two", scriptText: "")
        let project = FrameProject(title: "Project", scenes: [first, second])
        let (appState, _, _) = makeAppState(project: project, fileURL: nil)
        appState.editorState.selectedSceneID = first.id
        let editor = TestActiveEditor {
            first.scriptText = "Preserved before scene switch"
            appState.commitScriptTextChange(sceneID: first.id)
        }
        ActiveScriptEditorSession.shared.register(editor)
        defer { ActiveScriptEditorSession.shared.unregister(editor) }

        appState.selectScene(second.id)

        XCTAssertEqual(first.scriptText, "Preserved before scene switch")
        XCTAssertEqual(appState.editorState.selectedSceneID, second.id)
    }

    func testResignActiveFlushesTextAndSegments() {
        let (appState, scene, _) = makeAppState(fileURL: nil)
        appState.configure()
        let editor = TestActiveEditor {
            scene.scriptText = "First sentence. Second sentence."
            appState.commitScriptTextChange(sceneID: scene.id)
        }
        ActiveScriptEditorSession.shared.register(editor)
        defer { ActiveScriptEditorSession.shared.unregister(editor) }

        NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: nil)

        XCTAssertEqual(scene.scriptText, "First sentence. Second sentence.")
        XCTAssertFalse(scene.textSegments.isEmpty)
    }

    func testResignActiveCapturesCaretAndScrollState() {
        let (appState, _, _) = makeAppState(fileURL: nil)
        appState.configure()
        var saved: ScriptEditorRestorationState?
        let parent = makeRepresentable(
            text: .constant(String(repeating: "line\n", count: 60)),
            loadState: { saved },
            saveState: { saved = $0 }
        )
        let coordinator = LinkedScriptTextView.Coordinator(parent: parent)
        let view = MarkerTextContainerView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        coordinator.attach(to: view)
        coordinator.applyModelTextIfNeeded()
        view.textView.setSelectedRange(NSRange(location: 24, length: 5))
        view.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 80))
        ActiveScriptEditorSession.shared.register(coordinator)
        defer { ActiveScriptEditorSession.shared.unregister(coordinator) }

        NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: nil)

        XCTAssertEqual(saved?.selectedRange, NSRange(location: 24, length: 5))
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved!.visibleOrigin.y, 80, accuracy: 1)
    }

    func testExistingFileAutosavesOnceAfterCoalescedWindow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Immediate.fscr")
        let (appState, scene, _) = makeAppState(fileURL: fileURL)
        try FrameScriptFileStore.write(project: appState.project, to: fileURL)

        scene.scriptText = "Persist after the coalesced window"
        let clock = ContinuousClock()
        let started = clock.now
        appState.commitScriptTextChange(sceneID: scene.id)
        while appState.saveState != .saved, clock.now - started < .milliseconds(180) {
            await Task.yield()
        }

        let saved = try FrameScriptFileStore.read(from: fileURL)
        XCTAssertEqual(saved.scenes.first?.scriptText, "Persist after the coalesced window")
        XCTAssertEqual(appState.saveState, .saved)
        XCTAssertGreaterThanOrEqual(clock.now - started, .milliseconds(50))
        XCTAssertLessThan(clock.now - started, .milliseconds(180))
    }

    func testUntitledProjectPreservesTextWithoutFileURL() {
        let (appState, scene, _) = makeAppState(fileURL: nil)
        let editor = TestActiveEditor {
            scene.scriptText = "Safe untitled text"
            appState.commitScriptTextChange(sceneID: scene.id)
        }
        ActiveScriptEditorSession.shared.register(editor)
        defer { ActiveScriptEditorSession.shared.unregister(editor) }

        appState.selectMode(.bRoll)

        XCTAssertNil(appState.projectStore.currentFileURL)
        XCTAssertEqual(scene.scriptText, "Safe untitled text")
        XCTAssertEqual(appState.saveState, .edited)
    }

    func testCommittedUntitledEditUpdatesMetricsWithoutSaving() {
        let (appState, scene, _) = makeAppState(fileURL: nil)
        scene.scriptText = "one two three four five"

        appState.commitScriptTextChange(sceneID: scene.id)

        XCTAssertEqual(scene.estimatedDuration, DurationEstimator.estimate(text: scene.scriptText, wordsPerMinute: 150))
        XCTAssertEqual(appState.saveState, .edited)
        XCTAssertNil(appState.projectStore.currentFileURL)
    }

    func testTextAndPlaceholderShareZeroHorizontalOrigin() {
        let view = MarkerTextContainerView()
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.textView.textContainerInset.width, 0)
        XCTAssertEqual(view.textView.textContainer?.lineFragmentPadding, 0)
        XCTAssertEqual(view.textView.placeholderOrigin.x, view.textView.textContainerOrigin.x)
        XCTAssertEqual(view.textView.placeholderOrigin.y, view.textView.textContainerOrigin.y)
    }

    private func makeCoordinator(box: TextBox) -> (LinkedScriptTextView.Coordinator, MarkerTextContainerView) {
        let parent = makeRepresentable(text: Binding(get: { box.value }, set: { box.value = $0 }))
        let coordinator = LinkedScriptTextView.Coordinator(parent: parent)
        let view = MarkerTextContainerView()
        coordinator.attach(to: view)
        coordinator.applyModelTextIfNeeded()
        return (coordinator, view)
    }

    private func makeRepresentable(
        text: Binding<String>,
        loadState: @escaping () -> ScriptEditorRestorationState? = { nil },
        saveState: @escaping (ScriptEditorRestorationState) -> Void = { _ in },
        onTeardown: @escaping () -> Void = {}
    ) -> LinkedScriptTextView {
        LinkedScriptTextView(
            text: text,
            sceneID: UUID(),
            editorIdentity: UUID(),
            loadRestorationState: loadState,
            saveRestorationState: saveState,
            markers: [],
            fontSize: 16,
            lineSpacing: 4,
            spellcheck: false,
            smartQuotes: false,
            placeholder: "Placeholder",
            textColor: .labelColor,
            placeholderColor: .secondaryLabelColor,
            backgroundColor: .textBackgroundColor,
            bRollColor: .systemBlue,
            editingColor: .systemGreen,
            addBRollLabel: "B-roll",
            addEditingLabel: "Editing",
            onTextCommitted: {},
            autocomplete: { _ in nil },
            onTeardown: onTeardown,
            markerAction: { _, _ in },
            addMarkerAction: { _, _ in }
        )
    }

    private func makeAppState(
        project: FrameProject? = nil,
        fileURL: URL?
    ) -> (AppState, FrameScript.Scene, UserDefaults) {
        let scene = project?.scenes.first ?? Scene(order: 0, sectionType: .custom, title: "Scene", scriptText: "")
        let project = project ?? FrameProject(title: "Project", scenes: [scene])
        let store = ProjectStore(project: project)
        store.openProject(project, fileURL: fileURL, wordsPerMinute: 150, markUnsaved: false)
        let suite = UserDefaults(suiteName: "EditorPersistenceTests-\(UUID().uuidString)")!
        var settings = AppSettings.defaults
        settings.generalPreferences.autosaveEnabled = true
        let appState = AppState(
            projectStore: store,
            recentProjectStore: RecentProjectStore(userDefaults: suite),
            editorState: EditorState(),
            settingsStore: SettingsStore(settings: settings, userDefaults: suite, key: "settings")
        )
        appState.editorState.selectedSceneID = scene.id
        appState.editorState.selectedMode = .script
        return (appState, scene, suite)
    }
}
