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

    private final class AutocompleteRequestRecorder {
        private(set) var requestCount = 0
        private var continuations: [CheckedContinuation<AutocompleteResult, Never>] = []

        func request(_ context: AutocompleteContext) async -> AutocompleteResult {
            requestCount += 1
            return await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }

        func respond(with result: AutocompleteResult) {
            precondition(!continuations.isEmpty)
            continuations.removeFirst().resume(returning: result)
        }
    }

    func testUserEditSynchronouslyUpdatesModel() {
        let box = TextBox("Old")
        let (coordinator, view) = makeCoordinator(box: box)
        view.textView.string = "Exact new text"

        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))

        XCTAssertEqual(box.value, "Exact new text")
    }

    func testConsecutiveEditorEditsCommitTextAndMetricsBeforeAutosave() throws {
        var writes = 0
        let (appState, scene, _) = makeAppState(fileURL: temporaryProjectURL()) { project, url in
            writes += 1
            try FrameScriptFileStore.write(project: project, to: url)
        }
        let (coordinator, view) = makeCoordinator(appState: appState, scene: scene)

        for text in ["one two", "one two three", "one two three four"] {
            view.textView.string = text
            coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
            XCTAssertEqual(scene.scriptText, text)
            XCTAssertEqual(scene.estimatedDuration, DurationEstimator.estimate(text: text, wordsPerMinute: 150))
        }

        XCTAssertEqual(scene.scriptText.split { $0.isWhitespace || $0.isNewline }.count, 4)
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(appState.saveState, .edited)
    }

    func testSceneAndTotalDurationObservationInvalidateFromEditorEdit() {
        let first = Scene(order: 0, sectionType: .custom, title: "One", scriptText: "one")
        let second = Scene(order: 1, sectionType: .custom, title: "Two", scriptText: "one two three")
        let project = FrameProject(title: "Project", scenes: [first, second])
        let (appState, _, _) = makeAppState(project: project, fileURL: nil)
        let (coordinator, view) = makeCoordinator(appState: appState, scene: first)
        nonisolated(unsafe) var invalidated = false
        withObservationTracking {
            _ = first.estimatedDuration
            _ = appState.totalDuration
        } onChange: {
            invalidated = true
        }

        view.textView.string = "one two three four five six"
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))

        let firstDuration = DurationEstimator.estimate(text: first.scriptText, wordsPerMinute: 150)
        let secondDuration = DurationEstimator.estimate(text: second.scriptText, wordsPerMinute: 150)
        XCTAssertEqual(first.estimatedDuration, firstDuration)
        XCTAssertEqual(appState.totalDuration, firstDuration + secondDuration)
        XCTAssertTrue(invalidated)
    }

    func testRepresentableDelegateEditUpdatesScriptAndDuration() throws {
        let (appState, scene, _) = makeAppState(fileURL: nil)
        let representable = makeRepresentable(
            text: Binding(get: { scene.scriptText }, set: { _ in }),
            onTextCommitted: { text in appState.commitScriptTextChange(sceneID: scene.id, text: text) }
        )
        let host = NSHostingView(rootView: representable)
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        host.layoutSubtreeIfNeeded()
        let container = try XCTUnwrap(firstSubview(of: MarkerTextContainerView.self, in: host))
        let textView = container.textView
        XCTAssertNotNil(textView.delegate as? LinkedScriptTextView.Coordinator)

        textView.string = "one two three four five six"
        textView.didChangeText()

        XCTAssertEqual(scene.scriptText, textView.string)
        XCTAssertEqual(scene.estimatedDuration, DurationEstimator.estimate(text: textView.string, wordsPerMinute: 150))
    }

    func testNativeTextEditKeepsAutocompleteThroughItsSelectionChangeAndCaretMovementCancels() async throws {
        let box = TextBox("This is enough editor context")
        let recorder = AutocompleteRequestRecorder()
        let parent = makeRepresentable(
            text: Binding(get: { box.value }, set: { box.value = $0 }),
            autocomplete: { context in await recorder.request(context) }
        )
        let coordinator = LinkedScriptTextView.Coordinator(parent: parent)
        let view = MarkerTextContainerView()
        coordinator.attach(to: view)
        view.textView.delegate = coordinator
        view.textView.string = box.value
        view.textView.setSelectedRange(NSRange(location: (box.value as NSString).length, length: 0))

        view.textView.insertText("!", replacementRange: view.textView.selectedRange())
        try await waitUntil { recorder.requestCount == 1 }
        recorder.respond(with: .suggestion("The next beat lands."))
        try await waitUntil { view.textView.ghostText == "The next beat lands." }

        XCTAssertEqual(recorder.requestCount, 1)
        XCTAssertEqual(view.textView.ghostText, "The next beat lands.")

        view.textView.insertText("?", replacementRange: view.textView.selectedRange())
        try await waitUntil { recorder.requestCount == 2 }
        view.textView.setSelectedRange(NSRange(location: 0, length: 0))
        recorder.respond(with: .suggestion("The next beat lands."))
        await Task.yield()

        XCTAssertEqual(recorder.requestCount, 2)
        XCTAssertTrue(view.textView.ghostText.isEmpty)
    }

    func testAutocompleteSurvivesRepeatedEditsAndPostEditSelectionNotificationsInOneEditor() async throws {
        let box = TextBox("This is enough editor context")
        let recorder = AutocompleteRequestRecorder()
        let parent = makeRepresentable(
            text: Binding(get: { box.value }, set: { box.value = $0 }),
            autocomplete: { context in await recorder.request(context) }
        )
        let coordinator = LinkedScriptTextView.Coordinator(parent: parent)
        let view = MarkerTextContainerView()
        coordinator.attach(to: view)
        view.textView.delegate = coordinator
        view.textView.string = box.value
        view.textView.setSelectedRange(NSRange(location: (box.value as NSString).length, length: 0))

        view.textView.keyDown(with: try keyEvent(keyCode: 0, characters: "a"))
        try await waitUntil { recorder.requestCount == 1 }
        recorder.respond(with: .suggestion("A beat follows."))
        try await waitUntil { view.textView.ghostText == "A beat follows." }

        view.textView.keyDown(with: try keyEvent(keyCode: 51, characters: "\u{7F}"))
        try await waitUntil { recorder.requestCount == 2 }
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view.textView))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view.textView))
        recorder.respond(with: .suggestion("Another beat follows."))
        try await waitUntil { view.textView.ghostText == "Another beat follows." }

        view.textView.keyDown(with: try keyEvent(keyCode: 0, characters: "a"))
        try await waitUntil { recorder.requestCount == 3 }
        recorder.respond(with: .suggestion("The scene continues."))
        try await waitUntil { view.textView.ghostText == "The scene continues." }

        view.textView.keyDown(with: try keyEvent(keyCode: 0, characters: "b"))
        try await waitUntil { recorder.requestCount == 4 }

        let length = (view.textView.string as NSString).length
        view.textView.keyDown(with: try keyEvent(keyCode: 123, characters: "\u{F702}"))
        try await waitUntil { view.textView.selectedRange().location == length - 1 }
        recorder.respond(with: .suggestion("This must not appear."))
        await Task.yield()
        XCTAssertTrue(view.textView.ghostText.isEmpty)

        view.textView.keyDown(with: try keyEvent(keyCode: 0, characters: "c"))
        try await waitUntil { recorder.requestCount == 5 }
        recorder.respond(with: .suggestion("Forward delete works."))
        try await waitUntil { view.textView.ghostText == "Forward delete works." }

        let textBeforeForwardDelete = view.textView.string
        view.textView.keyDown(with: try keyEvent(keyCode: 117, characters: "\u{F728}"))
        try await waitUntil { view.textView.string != textBeforeForwardDelete }
        try await waitUntil { recorder.requestCount == 6 }
    }

    func testUntitledEditorEditUpdatesMetricsWithoutSaveAs() {
        let (appState, scene, _) = makeAppState(fileURL: nil)
        let (coordinator, view) = makeCoordinator(appState: appState, scene: scene)

        view.textView.string = "untitled projects update right now"
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))

        XCTAssertEqual(scene.scriptText, "untitled projects update right now")
        XCTAssertEqual(scene.estimatedDuration, DurationEstimator.estimate(text: scene.scriptText, wordsPerMinute: 150))
        XCTAssertNil(appState.projectStore.currentFileURL)
        XCTAssertEqual(appState.saveState, .edited)
    }

    func testRapidEditorEditsCoalesceIntoOneAutosave() async throws {
        let fileURL = temporaryProjectURL()
        var writes = 0
        let (appState, scene, _) = makeAppState(fileURL: fileURL) { project, url in
            writes += 1
            try FrameScriptFileStore.write(project: project, to: url)
        }
        let (coordinator, view) = makeCoordinator(appState: appState, scene: scene)

        for text in ["first", "first second", "first second third"] {
            view.textView.string = text
            coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        }
        try await Task.sleep(for: .milliseconds(140))

        XCTAssertEqual(writes, 1)
        XCTAssertEqual(appState.saveState, .saved)
        XCTAssertEqual(try FrameScriptFileStore.read(from: fileURL).scenes.first?.scriptText, "first second third")
    }

    func testFailedAutosaveAfterEditorEditLeavesProjectDirty() async throws {
        enum WriteFailure: Error { case expected }
        let (appState, scene, _) = makeAppState(fileURL: temporaryProjectURL()) { _, _ in
            throw WriteFailure.expected
        }
        let (coordinator, view) = makeCoordinator(appState: appState, scene: scene)

        view.textView.string = "this write will fail"
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(appState.projectStore.hasUnsavedFileChanges)
        XCTAssertEqual(appState.saveState, .edited)
        XCTAssertEqual(appState.errorCenter.presentedError?.kind, .autosave)
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
        onTextCommitted: @escaping (String) -> Void = { _ in },
        autocomplete: @escaping (AutocompleteContext) async -> AutocompleteResult = { _ in .none },
        onTeardown: @escaping () -> Void = {}
    ) -> LinkedScriptTextView {
        LinkedScriptTextView(
            text: text,
            sceneID: UUID(),
            editorIdentity: UUID(),
            sceneTitle: "Scene",
            autocompleteProvider: .openAI,
            autocompleteConfigurationVersion: 0,
            autocompleteDelay: .zero,
            autocompleteFallbackLanguage: .english,
            autocompleteState: .constant(.idle),
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
            onTextCommitted: onTextCommitted,
            autocomplete: autocomplete,
            onTeardown: onTeardown,
            markerAction: { _, _ in },
            addMarkerAction: { _, _ in }
        )
    }

    private func makeAppState(
        project: FrameProject? = nil,
        fileURL: URL?,
        projectWriter: @escaping (FrameProject, URL) throws -> Void = FrameScriptFileStore.write
    ) -> (AppState, FrameScript.Scene, UserDefaults) {
        let scene = project?.scenes.first ?? Scene(order: 0, sectionType: .custom, title: "Scene", scriptText: "")
        let project = project ?? FrameProject(title: "Project", scenes: [scene])
        let store = ProjectStore(project: project, projectWriter: projectWriter)
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

    private func makeCoordinator(appState: AppState, scene: FrameScript.Scene) -> (LinkedScriptTextView.Coordinator, MarkerTextContainerView) {
        let parent = makeRepresentable(
            text: Binding(get: { scene.scriptText }, set: { _ in }),
            onTextCommitted: { text in appState.commitScriptTextChange(sceneID: scene.id, text: text) }
        )
        let coordinator = LinkedScriptTextView.Coordinator(parent: parent)
        let view = MarkerTextContainerView()
        coordinator.attach(to: view)
        coordinator.applyModelTextIfNeeded()
        return (coordinator, view)
    }

    private func temporaryProjectURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorPersistenceTests-\(UUID().uuidString).fscr")
    }

    private func firstSubview<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = firstSubview(of: type, in: subview) { return match }
        }
        return nil
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        timeout: Duration = .seconds(1)
    ) async throws {
        let clock = ContinuousClock()
        let start = clock.now
        while !condition() {
            guard clock.now - start < timeout else {
                XCTFail("Timed out waiting for editor delegate flow")
                return
            }
            await Task.yield()
        }
    }

    private func keyEvent(keyCode: UInt16, characters: String) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
