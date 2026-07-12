import AppKit
import Foundation
import SwiftUI
@testable import FrameScript
import XCTest

@MainActor
final class EditorPersistenceTests: XCTestCase {
    func testVisualsTerminologyUsesNaturalLocalizedValues() throws {
        let englishVisualsKeys = [
            "production.addBRollForSelection", "dialog.deleteScene.message", "settings.defaultSplit",
            "broll.linkedSubtitle", "broll.emptyTitle", "broll.addItem", "broll.addEmpty",
            "broll.segmentEmpty", "broll.writeScriptFirst", "settings.includeBRoll",
            "export.label.broll", "help.defaultSplit", "help.includeBRoll"
        ]
        for key in englishVisualsKeys {
            XCTAssertTrue(L10n.tr(key, language: .english).contains("Visual"), "Expected natural Visuals terminology for \(key)")
        }
        XCTAssertEqual(L10n.tr("broll.item", language: .english), "Visual")
        XCTAssertEqual(L10n.tr("broll.duplicateItem", language: .english), "Duplicate Visual")
        XCTAssertEqual(L10n.tr("broll.deleteItem", language: .english), "Delete Visual")

        let russianVisualsKeys = [
            "production.addBRollForSelection", "dialog.deleteScene.message", "settings.defaultSplit",
            "broll.linkedSubtitle", "broll.emptyTitle", "broll.emptyMessage", "broll.addItem",
            "broll.addEmpty", "broll.segmentEmpty", "broll.writeScriptFirst", "broll.item",
            "broll.duplicateItem", "broll.deleteItem", "settings.includeBRoll", "export.label.broll",
            "help.defaultSplit", "help.includeBRoll"
        ]
        for key in russianVisualsKeys {
            XCTAssertTrue(L10n.tr(key, language: .russian).localizedLowercase.contains("видеоряд"), "Expected natural видеоряд terminology for \(key)")
        }

        try assertNoVisibleBRoll(in: repositoryText("FrameScript/Core/Utilities/Localization.swift"), file: "Localization.swift")
    }

    func testAllExportFormatsUseVisualsHeadings() {
        let service = ExportService()
        let preferences = AppSettings.defaults.exportPreferences

        for (language, expectedHeading) in [(AppLanguage.english, "Visuals"), (.russian, "Видеоряд")] {
            let project = SampleData.demoProject(language: language)
            for format in ExportFormat.allCases {
                let output = service.render(project: project, format: format, preferences: preferences, language: language)
                XCTAssertTrue(output.contains(expectedHeading), "Expected \(expectedHeading) in \(format.rawValue) export")
                assertNoVisibleBRoll(in: output, file: "\(format.rawValue) export")
            }
        }
    }

    func testCurrentDocsDemoAndBannerContainNoVisibleBRoll() throws {
        for path in ["README.md", "RELEASE_NOTES.md", "docs/banner.svg", "FrameScript/Models/SampleData.swift"] {
            try assertNoVisibleBRoll(in: repositoryText(path), file: path)
        }

        let changelog = try repositoryText("CHANGELOG.md")
        let unreleased = try XCTUnwrap(changelog.components(separatedBy: "## [0.2.0]").first)
        try assertNoVisibleBRoll(in: unreleased, file: "CHANGELOG.md [Unreleased]")
    }

    func testFSCRCompatibilityKeepsBRollCodableNames() throws {
        XCTAssertEqual(WorkspaceMode.bRoll.rawValue, "B-Roll")
        XCTAssertEqual(BRollSourceType.stockFootage.rawValue, "Stock footage")

        let project = SampleData.demoProject(language: .english)
        let data = try FrameScriptFileStore.encoder.encode(FrameScriptFile(project: project))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"bRollItems\""))
        XCTAssertTrue(json.contains("\"descriptionText\""))

        let roundTripped = try FrameScriptFileStore.decoder.decode(FrameScriptFile.self, from: data).makeProject()
        XCTAssertEqual(roundTripped.scenes.first?.bRollItems.count, 1)

        var legacyFile = FrameScriptFile(project: project)
        legacyFile.fileVersion = 1
        let legacyData = try FrameScriptFileStore.encoder.encode(legacyFile)
        let legacyProject = try FrameScriptFileStore.decoder.decode(FrameScriptFile.self, from: legacyData).makeProject()
        XCTAssertEqual(legacyProject.scenes.first?.bRollItems.first?.descriptionText, project.scenes.first?.bRollItems.first?.descriptionText)
    }

    private func repositoryText(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func assertNoVisibleBRoll(in text: String, file: String, line: UInt = #line) {
        for term in ["B-roll", "B-Roll", "b-roll"] {
            XCTAssertFalse(text.contains(term), "Unexpected visible \(term) in \(file)", line: line)
        }
    }

    private final class TextBox {
        var value: String
        init(_ value: String) { self.value = value }
    }

    private final class TestActiveEditor: ActiveScriptEditor {
        let flushAction: () -> Void
        let sceneID = UUID()
        let editorIdentity = UUID()
        var owningWindow: NSWindow?
        var isActualFirstResponder = true
        private(set) var didCancelAutocomplete = false

        init(_ flushAction: @escaping () -> Void) { self.flushAction = flushAction }
        func commitMarkedTextAndFlush() -> Bool {
            flushAction()
            return true
        }
        func cancelAutocomplete(clearStatus: Bool) { didCancelAutocomplete = clearStatus }
    }

    @MainActor
    private final class AutocompleteRequestRecorder {
        private(set) var requestCount = 0
        private(set) var completedRequestCount = 0
        private(set) var providerRequestCount = 0
        private(set) var cooldownBlockedRequestCount = 0
        private(set) var contexts: [AutocompleteContext] = []
        var isCooldownActive = false
        private var continuations: [CheckedContinuation<AutocompleteResult, Never>] = []

        func request(_ context: AutocompleteContext) async -> AutocompleteResult {
            if isCooldownActive {
                cooldownBlockedRequestCount += 1
                return .temporarilyUnavailable(.rateLimited)
            }
            requestCount += 1
            providerRequestCount += 1
            contexts.append(context)
            let result = await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
            completedRequestCount += 1
            return result
        }

        func respond(with result: AutocompleteResult) {
            precondition(!continuations.isEmpty)
            continuations.removeFirst().resume(returning: result)
        }
    }

    @MainActor
    private final class RetryingAutocompleteProvider: LLMProviderProtocol {
        private(set) var calls = 0
        private(set) var completedCalls = 0
        private var retryContinuation: CheckedContinuation<LLMResponse, Never>?

        func complete(request: LLMRequest, apiKey: String) async throws -> LLMResponse {
            calls += 1
            if calls == 1 {
                completedCalls += 1
                return LLMResponse(text: "The next beat", finishReason: "length")
            }
            let response = await withCheckedContinuation { continuation in
                retryContinuation = continuation
            }
            completedCalls += 1
            return response
        }

        func respondToRetry(with response: LLMResponse) {
            let continuation = retryContinuation
            retryContinuation = nil
            continuation?.resume(returning: response)
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
            autocomplete: { @MainActor context in await recorder.request(context) }
        )
        let coordinator = LinkedScriptTextView.Coordinator(parent: parent)
        let view = MarkerTextContainerView()
        coordinator.attach(to: view)
        view.textView.delegate = coordinator
        view.textView.string = box.value
        view.textView.setSelectedRange(NSRange(location: (box.value as NSString).length, length: 0))

        view.textView.insertText("!", replacementRange: view.textView.selectedRange())
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 1 }, message: "first request")
        recorder.respond(with: .suggestion("The next beat lands."))
        try await waitUntil { view.textView.ghostText == "The next beat lands." }

        XCTAssertEqual(recorder.requestCount, 1)
        XCTAssertEqual(view.textView.ghostText, "The next beat lands.")

        view.textView.insertText("?", replacementRange: view.textView.selectedRange())
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil { recorder.requestCount == 2 }
        view.textView.setSelectedRange(NSRange(location: 0, length: 0))
        recorder.respond(with: .suggestion("The next beat lands."))
        await Task.yield()

        XCTAssertEqual(recorder.requestCount, 2)
        XCTAssertTrue(view.textView.ghostText.isEmpty)
    }

    func testAutocompleteAtAbsoluteDocumentEndSchedulesOneRequestAndShowsGhostText() async throws {
        let recorder = AutocompleteRequestRecorder()
        let (coordinator, view) = makeAutocompleteCoordinator(
            text: "This is enough editor context",
            recorder: recorder
        )
        view.textView.setSelectedRange(NSRange(location: (view.textView.string as NSString).length, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))

        try await waitUntil { recorder.requestCount == 1 }
        recorder.respond(with: .suggestion("The next beat lands."))
        try await waitUntil { view.textView.ghostText == "The next beat lands." }

        XCTAssertEqual(recorder.requestCount, 1)
    }

    func testAutocompleteInSentenceMiddleDoesNotSchedule() async {
        let recorder = AutocompleteRequestRecorder()
        let (coordinator, view) = makeAutocompleteCoordinator(
            text: "This is enough editor context",
            recorder: recorder
        )
        view.textView.setSelectedRange(NSRange(location: 8, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        await Task.yield()

        XCTAssertEqual(recorder.requestCount, 0)
        XCTAssertTrue(view.textView.ghostText.isEmpty)
    }

    func testAutocompleteBeforeExistingParagraphDoesNotSchedule() async {
        let recorder = AutocompleteRequestRecorder()
        let text = "This is enough first paragraph.\nA second paragraph already exists."
        let (coordinator, view) = makeAutocompleteCoordinator(text: text, recorder: recorder)
        let caret = (text as NSString).range(of: "\n").location
        view.textView.setSelectedRange(NSRange(location: caret, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        await Task.yield()

        XCTAssertEqual(recorder.requestCount, 0)
    }

    func testAutocompleteBeforeTrailingWhitespaceOrNewlineSchedules() async throws {
        let recorder = AutocompleteRequestRecorder()
        let text = "This is enough editor context \t\n"
        let (coordinator, view) = makeAutocompleteCoordinator(text: text, recorder: recorder)
        let caret = (text as NSString).length - 3
        view.textView.setSelectedRange(NSRange(location: caret, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 1 }, message: "trailing whitespace request")

        XCTAssertEqual(recorder.contexts[0].suffix, " \t\n")
    }

    func testAutocompleteBeforeZeroWidthSuffixDoesNotSchedule() async {
        let recorder = AutocompleteRequestRecorder()
        let text = "This is enough editor context\u{200B}"
        let (coordinator, view) = makeAutocompleteCoordinator(text: text, recorder: recorder)
        view.textView.setSelectedRange(NSRange(location: (text as NSString).length - 1, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        await Task.yield()

        XCTAssertEqual(recorder.requestCount, 0)
        XCTAssertTrue(view.textView.ghostText.isEmpty)
    }

    func testTabInsertsCompletionAtLogicalEndCaretAndPreservesTrailingWhitespace() async throws {
        let recorder = AutocompleteRequestRecorder()
        let text = "This is enough editor context   \n"
        let (coordinator, view) = makeAutocompleteCoordinator(text: text, recorder: recorder)
        let caret = (text as NSString).length - 4
        view.textView.setSelectedRange(NSRange(location: caret, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 1 }, message: "logical-end request")
        recorder.respond(with: .suggestion("The next beat lands."))
        try await waitUntil({ !view.textView.ghostText.isEmpty }, message: "logical-end ghost")

        view.textView.keyDown(with: try keyEvent(keyCode: 48, characters: "\t"))

        XCTAssertEqual(view.textView.string, "This is enough editor contextThe next beat lands.   \n")
    }

    func testMovingCaretFromDocumentEndCancelsAndClearsSuggestion() async throws {
        let recorder = AutocompleteRequestRecorder()
        let (coordinator, view) = makeAutocompleteCoordinator(
            text: "This is enough editor context",
            recorder: recorder
        )
        view.textView.setSelectedRange(NSRange(location: (view.textView.string as NSString).length, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil { recorder.requestCount == 1 }
        recorder.respond(with: .suggestion("A suggestion to clear."))
        try await waitUntil { !view.textView.ghostText.isEmpty }

        view.textView.setSelectedRange(NSRange(location: 0, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view.textView))

        XCTAssertTrue(view.textView.ghostText.isEmpty)
    }

    func testNoOpRightArrowAtLogicalEndPreservesVisibleSuggestion() async throws {
        let recorder = AutocompleteRequestRecorder()
        let (coordinator, view) = makeAutocompleteCoordinator(text: "This is enough editor context", recorder: recorder)
        view.textView.setSelectedRange(NSRange(location: (view.textView.string as NSString).length, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 1 }, message: "initial request")
        recorder.respond(with: .suggestion("A suggestion to preserve."))
        try await waitUntil({ !view.textView.ghostText.isEmpty }, message: "initial ghost")

        view.textView.keyDown(with: try keyEvent(keyCode: 124, characters: "\u{F703}"))

        XCTAssertEqual(view.textView.ghostText, "A suggestion to preserve.")
        XCTAssertEqual(recorder.requestCount, 1)
    }

    func testNoOpDownArrowAtLogicalEndDoesNotStartDuplicateRequest() async throws {
        let recorder = AutocompleteRequestRecorder()
        let (coordinator, view) = makeAutocompleteCoordinator(text: "This is enough editor context", recorder: recorder)
        view.textView.setSelectedRange(NSRange(location: (view.textView.string as NSString).length, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 1 }, message: "initial request")
        recorder.respond(with: .suggestion("A suggestion to preserve."))
        try await waitUntil({ !view.textView.ghostText.isEmpty }, message: "initial ghost")

        view.textView.keyDown(with: try keyEvent(keyCode: 125, characters: "\u{F701}"))
        await Task.yield()

        XCTAssertEqual(recorder.requestCount, 1)
        XCTAssertEqual(view.textView.ghostText, "A suggestion to preserve.")
    }

    func testCaretReturnSchedulesOneFreshRequestWithoutTextEdit() async throws {
        let recorder = AutocompleteRequestRecorder()
        let (coordinator, view) = makeAutocompleteCoordinator(text: "This is enough editor context", recorder: recorder)
        let end = (view.textView.string as NSString).length
        view.textView.setSelectedRange(NSRange(location: end, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 1 }, message: "first request")
        recorder.respond(with: .suggestion("First suggestion."))
        try await waitUntil({ !view.textView.ghostText.isEmpty }, message: "first ghost")

        view.textView.setSelectedRange(NSRange(location: end - 1, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view.textView))
        XCTAssertTrue(view.textView.ghostText.isEmpty)

        view.textView.setSelectedRange(NSRange(location: end, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view.textView))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 2 }, message: "caret return request")

        XCTAssertEqual(recorder.requestCount, 2)
    }

    func testLateResponseBeforeCaretMovementIsRejectedAfterCaretReturn() async throws {
        let recorder = AutocompleteRequestRecorder()
        let (coordinator, view) = makeAutocompleteCoordinator(text: "This is enough editor context", recorder: recorder)
        let end = (view.textView.string as NSString).length
        view.textView.setSelectedRange(NSRange(location: end, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 1 }, message: "first request")

        view.textView.setSelectedRange(NSRange(location: end - 1, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view.textView))
        view.textView.setSelectedRange(NSRange(location: end, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 2 }, message: "returned request")

        recorder.respond(with: .suggestion("Stale suggestion."))
        await Task.yield()
        XCTAssertTrue(view.textView.ghostText.isEmpty)
        recorder.respond(with: .suggestion("Fresh suggestion."))
        try await waitUntil({ view.textView.ghostText == "Fresh suggestion." }, message: "fresh ghost")
    }

    func testEscapeRequiresCaretDepartureBeforeCaretReturnRegenerates() async throws {
        let recorder = AutocompleteRequestRecorder()
        let (coordinator, view) = makeAutocompleteCoordinator(text: "This is enough editor context", recorder: recorder)
        let end = (view.textView.string as NSString).length
        view.textView.setSelectedRange(NSRange(location: end, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 1 }, message: "initial request")
        recorder.respond(with: .suggestion("Dismiss me."))
        try await waitUntil({ !view.textView.ghostText.isEmpty }, message: "initial ghost")

        view.textView.keyDown(with: try keyEvent(keyCode: 53, characters: "\u{1B}"))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view.textView))
        await Task.yield()
        XCTAssertEqual(recorder.requestCount, 1)

        view.textView.setSelectedRange(NSRange(location: end - 1, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view.textView))
        view.textView.setSelectedRange(NSRange(location: end, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 2 }, message: "post-Escape caret-return request")
    }

    func testLateEndOfDocumentResponseIsRejectedAfterCaretMovement() async throws {
        let recorder = AutocompleteRequestRecorder()
        let (coordinator, view) = makeAutocompleteCoordinator(
            text: "This is enough editor context",
            recorder: recorder
        )
        view.textView.setSelectedRange(NSRange(location: (view.textView.string as NSString).length, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil { recorder.requestCount == 1 }

        view.textView.setSelectedRange(NSRange(location: 5, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view.textView))
        recorder.respond(with: .suggestion("This must not appear."))
        try await waitUntil { recorder.completedRequestCount == 1 }

        XCTAssertTrue(view.textView.ghostText.isEmpty)
    }

    func testStaleSnapshotDuringAutocompleteRetryShowsNoGhostText() async throws {
        let provider = RetryingAutocompleteProvider()
        let dependencies = AppDependencies(
            rewriteService: RewriteService(provider: provider),
            analysisService: AnalysisService(provider: provider),
            exportService: ExportService(),
            llmProvider: provider,
            providerCredentials: ProviderCredentialSession(reader: { _ in "secret" })
        )
        let (appState, _, _) = makeAppState(
            fileURL: nil,
            dependencies: dependencies,
            hasAutocompleteStoredKey: true
        )
        appState.settings.aiPreferences.provider = .openAICompatible
        let text = "This is enough editor context"
        let box = TextBox(text)
        let parent = makeRepresentable(
            text: Binding(get: { box.value }, set: { box.value = $0 }),
            autocomplete: { @MainActor context in await appState.autocompleteScript(context: context) }
        )
        let coordinator = LinkedScriptTextView.Coordinator(parent: parent)
        let view = MarkerTextContainerView()
        coordinator.attach(to: view)
        view.textView.delegate = coordinator
        view.textView.string = text
        view.textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))

        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ provider.calls == 2 }, message: "retry request")

        view.textView.setSelectedRange(NSRange(location: 0, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view.textView))
        provider.respondToRetry(with: LLMResponse(text: "The next beat lands.", finishReason: "stop"))
        try await waitUntil({ provider.completedCalls == 2 }, message: "retry response")

        XCTAssertTrue(view.textView.ghostText.isEmpty)
    }

    func testGhostTextDoesNotLayOutOverExistingText() {
        let view = MarkerTextContainerView()
        view.textView.string = "Existing script text remains visible"
        view.textView.setSelectedRange(NSRange(location: 8, length: 0))
        view.textView.ghostText = "This must not cover the script."

        XCTAssertTrue(view.textView.ghostLineFragmentWidths().isEmpty)
    }

    func testAutocompleteRegeneratesForRepeatedEndOfDocumentContextsInOneEditor() async throws {
        let recorder = AutocompleteRequestRecorder()
        let (coordinator, view) = makeAutocompleteCoordinator(
            text: "This is enough editor context",
            recorder: recorder
        )
        view.textView.setSelectedRange(NSRange(location: (view.textView.string as NSString).length, length: 0))

        view.textView.insertText(" ", replacementRange: view.textView.selectedRange())
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 1 }, message: "first request")
        let firstGeneration = coordinator.autocompleteRequestGeneration
        let firstTextRevision = coordinator.textRevision
        recorder.respond(with: .suggestion("First suggestion."))
        try await waitUntil({ view.textView.ghostText == "First suggestion." }, message: "first ghost")

        view.textView.insertText("", replacementRange: NSRange(location: (view.textView.string as NSString).length - 1, length: 1))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 2 }, message: "deletion request")
        view.textView.insertText(" ", replacementRange: view.textView.selectedRange())
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 3 }, message: "regenerated identical-context request")
        XCTAssertEqual(recorder.contexts[0], recorder.contexts[2])
        XCTAssertGreaterThan(coordinator.autocompleteRequestGeneration, firstGeneration)
        XCTAssertGreaterThan(coordinator.textRevision, firstTextRevision)

        recorder.respond(with: .suggestion("Stale deletion response."))
        await Task.yield()
        XCTAssertTrue(view.textView.ghostText.isEmpty)
        recorder.respond(with: .suggestion("Second suggestion."))
        try await waitUntil({ view.textView.ghostText == "Second suggestion." }, message: "second ghost")

        view.textView.insertText("", replacementRange: NSRange(location: (view.textView.string as NSString).length - 1, length: 1))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 4 }, message: "second deletion request")
        view.textView.insertText(" ", replacementRange: view.textView.selectedRange())
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 5 }, message: "third identical-context request")
        recorder.respond(with: .suggestion("Stale second deletion response."))
        await Task.yield()
        recorder.respond(with: .suggestion("Third suggestion."))
        try await waitUntil({ view.textView.ghostText == "Third suggestion." }, message: "third ghost")

        view.textView.keyDown(with: try keyEvent(keyCode: 53, characters: "\u{1B}"))
        XCTAssertTrue(view.textView.ghostText.isEmpty)
        view.textView.insertText("!", replacementRange: view.textView.selectedRange())
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 6 }, message: "post-Escape request")
        recorder.respond(with: .suggestion("Escape suggestion."))
        try await waitUntil({ view.textView.ghostText == "Escape suggestion." }, message: "post-Escape ghost")

        coordinator.handleGhostAction(.replace)
        view.textView.insertText("?", replacementRange: view.textView.selectedRange())
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 7 }, message: "replacement request")
        recorder.respond(with: .suggestion("Replacement suggestion."))
        try await waitUntil({ view.textView.ghostText == "Replacement suggestion." }, message: "replacement ghost")

        coordinator.handleGhostAction(.replace)
        view.textView.insertText(".", replacementRange: view.textView.selectedRange())
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 8 }, message: "pre-undo request")
        view.textView.undoManager?.undo()
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 9 }, message: "undo request")
        view.textView.undoManager?.redo()
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 10 }, message: "redo request")
        XCTAssertEqual(view.textView.selectedRange().location, (view.textView.string as NSString).length)

        recorder.isCooldownActive = true
        let providerRequestCount = recorder.providerRequestCount
        view.textView.insertText(" ", replacementRange: view.textView.selectedRange())
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.cooldownBlockedRequestCount == 1 }, message: "cooldown block")
        recorder.respond(with: .suggestion("Stale undo response."))
        recorder.respond(with: .suggestion("Stale redo response."))
        recorder.respond(with: .suggestion("Stale cooldown response."))
        XCTAssertEqual(recorder.providerRequestCount, providerRequestCount)

        XCTAssertEqual(recorder.contexts[0], recorder.contexts[2])
    }

    func testMissingAutocompleteEligibilityStartsNoDebounceOrRequest() async {
        let text = "This is enough editor context"
        let recorder = AutocompleteRequestRecorder()
        let parent = makeRepresentable(
            text: .constant(text),
            autocompleteConfigurationIsEligible: false,
            autocomplete: { @MainActor context in await recorder.request(context) }
        )
        let coordinator = LinkedScriptTextView.Coordinator(parent: parent)
        let view = MarkerTextContainerView()
        coordinator.attach(to: view)
        view.textView.string = text
        view.textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))

        view.textView.insertText("!", replacementRange: view.textView.selectedRange())
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        await Task.yield()

        XCTAssertEqual(recorder.requestCount, 0)
        XCTAssertTrue(view.textView.ghostText.isEmpty)
    }

    func testAutocompleteEligibilityChangesWithoutRecreatingTheEditor() async throws {
        let text = "This is enough editor context"
        let recorder = AutocompleteRequestRecorder()
        let initial = makeRepresentable(
            text: .constant(text),
            autocompleteConfigurationVersion: 0,
            autocompleteConfigurationIsEligible: true,
            autocomplete: { @MainActor context in await recorder.request(context) }
        )
        let coordinator = LinkedScriptTextView.Coordinator(parent: initial)
        let view = MarkerTextContainerView()
        coordinator.attach(to: view)
        view.textView.string = text
        view.textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        view.textView.insertText("!", replacementRange: view.textView.selectedRange())
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 1 }, message: "initial eligible request")
        recorder.respond(with: .none)

        coordinator.parent = makeRepresentable(
            text: .constant(view.textView.string),
            autocompleteConfigurationVersion: 1,
            autocompleteConfigurationIsEligible: false,
            autocomplete: { @MainActor context in await recorder.request(context) }
        )
        coordinator.applyModelTextIfNeeded()
        view.textView.insertText("!", replacementRange: view.textView.selectedRange())
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        await Task.yield()
        XCTAssertEqual(recorder.requestCount, 1)

        coordinator.parent = makeRepresentable(
            text: .constant(view.textView.string),
            autocompleteConfigurationVersion: 2,
            autocompleteConfigurationIsEligible: true,
            autocomplete: { @MainActor context in await recorder.request(context) }
        )
        coordinator.applyModelTextIfNeeded()
        view.textView.insertText("!", replacementRange: view.textView.selectedRange())
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view.textView))
        try await waitUntil({ recorder.requestCount == 2 }, message: "restored eligible request")
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
        firstView.layoutSubtreeIfNeeded()
        let maximumOriginY = max(
            0,
            firstView.scrollView.documentView!.bounds.maxY - firstView.scrollView.contentView.bounds.height
        )
        let savedOriginY = min(120, maximumOriginY)
        firstView.textView.setSelectedRange(NSRange(location: 42, length: 12))
        firstView.scrollView.contentView.scroll(to: NSPoint(x: 120, y: savedOriginY))
        first.captureRestorationState()

        let recreated = LinkedScriptTextView.Coordinator(parent: parent)
        let recreatedView = MarkerTextContainerView(frame: firstView.frame)
        recreated.attach(to: recreatedView)
        recreated.applyModelTextIfNeeded()
        recreated.restoreEditorStateIfAvailable()

        XCTAssertEqual(recreatedView.textView.selectedRange(), NSRange(location: 42, length: 12))
        XCTAssertEqual(recreatedView.scrollView.contentView.bounds.origin.y, savedOriginY, accuracy: 1)
        XCTAssertGreaterThanOrEqual(recreatedView.scrollView.contentView.bounds.origin.x, 0)

        box.value = "short"
        recreated.applyModelTextIfNeeded()
        recreated.restoreEditorStateIfAvailable()
        XCTAssertLessThanOrEqual(NSMaxRange(recreatedView.textView.selectedRange()), 5)
        XCTAssertGreaterThanOrEqual(recreatedView.scrollView.contentView.bounds.origin.x, 0)
        XCTAssertGreaterThanOrEqual(recreatedView.scrollView.contentView.bounds.origin.y, 0)
        XCTAssertLessThanOrEqual(
            recreatedView.scrollView.contentView.bounds.maxX,
            recreatedView.scrollView.documentView!.bounds.maxX + 1
        )
        XCTAssertLessThanOrEqual(
            recreatedView.scrollView.contentView.bounds.maxY,
            recreatedView.scrollView.documentView!.bounds.maxY + 1
        )
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

    func testResignActiveFlushesAndCancelsTwoRegisteredEditors() {
        let (appState, scene, _) = makeAppState(fileURL: nil)
        appState.configure()
        var firstFlushes = 0
        var secondFlushes = 0
        let first = TestActiveEditor { firstFlushes += 1 }
        let second = TestActiveEditor { secondFlushes += 1 }
        ActiveScriptEditorSession.shared.register(first)
        ActiveScriptEditorSession.shared.register(second)
        defer {
            ActiveScriptEditorSession.shared.unregister(first)
            ActiveScriptEditorSession.shared.unregister(second)
        }

        XCTAssertTrue(ActiveScriptEditorSession.shared.flushAllForAppResignation())

        XCTAssertEqual(firstFlushes, 1)
        XCTAssertEqual(secondFlushes, 1)
        XCTAssertTrue(first.didCancelAutocomplete)
        XCTAssertTrue(second.didCancelAutocomplete)
        XCTAssertEqual(appState.selectedScene?.id, scene.id)
    }

    func testSessionFlushSelectsTheKeyWindowEditor() {
        let firstWindow = NSWindow()
        let secondWindow = NSWindow()
        var firstFlushes = 0
        var secondFlushes = 0
        let first = TestActiveEditor { firstFlushes += 1 }
        let second = TestActiveEditor { secondFlushes += 1 }
        first.isActualFirstResponder = false
        second.isActualFirstResponder = false
        first.owningWindow = firstWindow
        second.owningWindow = secondWindow
        ActiveScriptEditorSession.shared.register(first)
        ActiveScriptEditorSession.shared.register(second)
        defer {
            ActiveScriptEditorSession.shared.unregister(first)
            ActiveScriptEditorSession.shared.unregister(second)
        }

        XCTAssertTrue(ActiveScriptEditorSession.shared.flush(keyWindow: firstWindow))
        XCTAssertEqual(firstFlushes, 1)
        XCTAssertEqual(secondFlushes, 0)
    }

    func testSessionFlushWithNoKeyWindowDoesNotUseLastRegisteredEditor() {
        var flushes = 0
        let editor = TestActiveEditor { flushes += 1 }
        editor.isActualFirstResponder = false
        ActiveScriptEditorSession.shared.register(editor)
        defer { ActiveScriptEditorSession.shared.unregister(editor) }

        XCTAssertFalse(ActiveScriptEditorSession.shared.flush(keyWindow: nil))
        XCTAssertEqual(flushes, 0)
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
        view.layoutSubtreeIfNeeded()
        let expectedOrigin = NSPoint(
            x: 0,
            y: max(0, view.scrollView.documentView!.bounds.maxY - view.scrollView.contentView.bounds.height)
        )
        view.scrollView.contentView.scroll(to: expectedOrigin)
        ActiveScriptEditorSession.shared.register(coordinator)
        defer { ActiveScriptEditorSession.shared.unregister(coordinator) }

        NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: nil)

        XCTAssertEqual(saved?.selectedRange, NSRange(location: 24, length: 5))
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved!.visibleOrigin, expectedOrigin)
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

    private func makeAutocompleteCoordinator(
        text: String,
        recorder: AutocompleteRequestRecorder
    ) -> (LinkedScriptTextView.Coordinator, MarkerTextContainerView) {
        let box = TextBox(text)
        let parent = makeRepresentable(
            text: Binding(get: { box.value }, set: { box.value = $0 }),
            autocomplete: { @MainActor context in await recorder.request(context) }
        )
        let coordinator = LinkedScriptTextView.Coordinator(parent: parent)
        let view = MarkerTextContainerView()
        coordinator.attach(to: view)
        view.textView.delegate = coordinator
        view.textView.string = text
        return (coordinator, view)
    }

    private func makeRepresentable(
        text: Binding<String>,
        autocompleteConfigurationVersion: Int = 0,
        autocompleteConfigurationIsEligible: Bool = true,
        loadState: @escaping () -> ScriptEditorRestorationState? = { nil },
        saveState: @escaping (ScriptEditorRestorationState) -> Void = { _ in },
        onTextCommitted: @escaping (String) -> Void = { _ in },
        autocomplete: @escaping @MainActor (AutocompleteContext) async -> AutocompleteResult = { _ in .none },
        onTeardown: @escaping () -> Void = {}
    ) -> LinkedScriptTextView {
        LinkedScriptTextView(
            text: text,
            sceneID: UUID(),
            editorIdentity: UUID(),
            sceneTitle: "Scene",
            autocompleteProvider: .openAICompatible,
            autocompleteConfigurationVersion: autocompleteConfigurationVersion,
            autocompleteConfigurationIsEligible: autocompleteConfigurationIsEligible,
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
            addBRollLabel: "Add Visual",
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
        dependencies: AppDependencies = .live,
        hasAutocompleteStoredKey: Bool = false,
        projectWriter: @escaping (FrameProject, URL) throws -> Void = FrameScriptFileStore.write
    ) -> (AppState, FrameScript.Scene, UserDefaults) {
        let scene = project?.scenes.first ?? Scene(order: 0, sectionType: .custom, title: "Scene", scriptText: "")
        let project = project ?? FrameProject(title: "Project", scenes: [scene])
        let store = ProjectStore(project: project, projectWriter: projectWriter)
        store.openProject(project, fileURL: fileURL, wordsPerMinute: 150, markUnsaved: false)
        let suite = UserDefaults(suiteName: "EditorPersistenceTests-\(UUID().uuidString)")!
        let configurationStore = AIProviderConfigurationStore(userDefaults: suite)
        configurationStore.setHasStoredKey(hasAutocompleteStoredKey, for: .openAICompatible)
        var settings = AppSettings.defaults
        settings.generalPreferences.autosaveEnabled = true
        let appState = AppState(
            projectStore: store,
            recentProjectStore: RecentProjectStore(userDefaults: suite),
            editorState: EditorState(),
            settingsStore: SettingsStore(settings: settings, userDefaults: suite, key: "settings"),
            dependencies: dependencies,
            aiProviderConfigurationStore: configurationStore
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
        message: String = "editor delegate flow",
        timeout: Duration = .seconds(1)
    ) async throws {
        let clock = ContinuousClock()
        let start = clock.now
        while !condition() {
            guard clock.now - start < timeout else {
                XCTFail("Timed out waiting for \(message)")
                throw NSError(domain: "EditorPersistenceTests", code: 1)
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
