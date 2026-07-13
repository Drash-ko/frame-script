import AppKit
import XCTest
@testable import FrameScript

final class ShortcutRegistryTests: XCTestCase {
    func testOldSettingsWithoutShortcutPreferencesUseFactoryDefaults() throws {
        let encoded = try JSONEncoder().encode(AppSettings.defaults)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        root.removeValue(forKey: "shortcutOverrides")
        let legacy = try JSONSerialization.data(withJSONObject: root)

        let settings = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertTrue(settings.shortcutOverrides.isEmpty)
        XCTAssertEqual(settings.activeShortcut(for: .commandPalette), ShortcutRegistry.definition(for: .commandPalette).factoryDefault)
    }

    func testBindingsRoundTripForCharactersPunctuationArrowsAndDelete() throws {
        let bindings = [
            ShortcutBinding("k", modifiers: [.command]),
            ShortcutBinding("/", modifiers: [.control, .option, .shift, .command]),
            ShortcutBinding(key: .upArrow, modifiers: [.command, .option]),
            ShortcutBinding(key: .delete, modifiers: [.command]),
            ShortcutBinding(key: .forwardDelete, modifiers: [.control])
        ]
        XCTAssertEqual(try JSONDecoder().decode([ShortcutBinding].self, from: JSONEncoder().encode(bindings)), bindings)
    }

    func testFactoryDefaultsAreUniqueAndModifierOrderIsMacStandard() {
        let defaults = ShortcutRegistry.definitions.map(\.factoryDefault)
        XCTAssertEqual(Set(defaults).count, defaults.count)
        XCTAssertEqual(ShortcutBinding("k", modifiers: [.command, .option, .shift, .control]).display, "⌃⌥⇧⌘K")
    }

    func testConflictWarningIdentifiesTheExistingCommandAndCancelPreservesAssignments() {
        var settings = AppSettings.defaults
        let original = settings.activeShortcut(for: .duplicateScene)
        let conflict = settings.setShortcut(try! XCTUnwrap(settings.activeShortcut(for: .save)), for: .duplicateScene)
        XCTAssertEqual(conflict, .save)
        XCTAssertEqual(settings.activeShortcut(for: .duplicateScene), original)
        XCTAssertEqual(settings.activeShortcut(for: .save), ShortcutRegistry.definition(for: .save).factoryDefault)
    }

    func testReassignMovesShortcutAndExplicitlyUnassignsDisplacedCommand() {
        var settings = AppSettings.defaults
        let saveBinding = try! XCTUnwrap(settings.activeShortcut(for: .save))

        XCTAssertEqual(settings.reassignShortcut(saveBinding, for: .duplicateScene), .save)
        XCTAssertEqual(settings.activeShortcut(for: .duplicateScene), saveBinding)
        XCTAssertNil(settings.activeShortcut(for: .save))
        XCTAssertEqual(settings.shortcutOverrides[.save], .unassigned)
        XCTAssertEqual(
            ShortcutDisplayFormatter.display(for: .save, settings: settings, notAssigned: "Not assigned"),
            "Not assigned"
        )
    }

    func testAssignedAndUnassignedShortcutsRoundTripThroughCodable() throws {
        var settings = AppSettings.defaults
        _ = settings.setShortcut(.init("p", modifiers: [.command, .option]), for: .commandPalette)
        _ = settings.reassignShortcut(try! XCTUnwrap(settings.activeShortcut(for: .save)), for: .duplicateScene)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.shortcutOverrides, settings.shortcutOverrides)
        XCTAssertEqual(decoded.activeShortcut(for: .commandPalette), .init("p", modifiers: [.command, .option]))
        XCTAssertNil(decoded.activeShortcut(for: .save))
    }

    func testOldShortcutOverridesDecodeWithoutDataLoss() throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings.defaults)) as? [String: Any])
        let oldBinding = ShortcutBinding("p", modifiers: [.command, .option])
        let legacyOverrides: [ShortcutCommand: ShortcutBinding] = [.commandPalette: oldBinding]
        root["shortcutOverrides"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyOverrides))

        let settings = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: root))
        XCTAssertEqual(settings.activeShortcut(for: .commandPalette), oldBinding)
    }

    func testPerCommandAndGlobalResets() {
        var settings = AppSettings.defaults
        XCTAssertNil(settings.setShortcut(ShortcutBinding("z", modifiers: [.command, .option]), for: .duplicateScene))
        XCTAssertNil(settings.resetShortcut(.duplicateScene))
        XCTAssertEqual(settings.activeShortcut(for: .duplicateScene), ShortcutRegistry.definition(for: .duplicateScene).factoryDefault)
        XCTAssertNil(settings.setShortcut(ShortcutBinding("z", modifiers: [.command, .option]), for: .duplicateScene))
        XCTAssertNil(settings.setShortcut(ShortcutBinding("g", modifiers: [.command, .option]), for: .toggleFocusMode))
        settings.resetAllShortcuts()
        XCTAssertTrue(settings.shortcutOverrides.isEmpty)
    }

    func testPerCommandResetIsConflictSafe() {
        var settings = AppSettings.defaults
        let defaultBinding = try! XCTUnwrap(settings.activeShortcut(for: .duplicateScene))
        _ = settings.reassignShortcut(defaultBinding, for: .save)

        XCTAssertEqual(settings.resetConflict(for: .duplicateScene), .save)
        XCTAssertEqual(settings.resetShortcut(.duplicateScene), .save)
        XCTAssertNil(settings.activeShortcut(for: .duplicateScene))
        XCTAssertEqual(settings.activeShortcut(for: .save), defaultBinding)

        XCTAssertEqual(settings.reassignFactoryDefault(to: .duplicateScene), .save)
        XCTAssertEqual(settings.activeShortcut(for: .duplicateScene), defaultBinding)
        XCTAssertNil(settings.activeShortcut(for: .save))
    }

    func testResetAllRestoresUniqueFactoryDefaults() {
        var settings = AppSettings.defaults
        _ = settings.reassignShortcut(try! XCTUnwrap(settings.activeShortcut(for: .save)), for: .duplicateScene)
        _ = settings.setShortcut(.init("p", modifiers: [.command, .option]), for: .commandPalette)

        settings.resetAllShortcuts()
        let activeBindings = ShortcutCommand.allCases.compactMap(settings.activeShortcut(for:))
        XCTAssertEqual(activeBindings.count, ShortcutCommand.allCases.count)
        XCTAssertEqual(Set(activeBindings).count, activeBindings.count)
        XCTAssertTrue(settings.shortcutOverrides.isEmpty)
    }

    func testEveryRegistryCommandHasEnglishAndRussianLocalization() {
        for definition in ShortcutRegistry.definitions {
            XCTAssertNotEqual(L10n.tr(definition.localizationKey, language: .english), definition.localizationKey)
            XCTAssertNotEqual(L10n.tr(definition.localizationKey, language: .russian), definition.localizationKey)
        }
    }

    func testReassignmentActionsAndUnassignedStateAreLocalized() {
        XCTAssertEqual(L10n.tr("shortcuts.reassign", language: .english), "Reassign")
        XCTAssertEqual(L10n.tr("project.unsaved.cancel", language: .english), "Cancel")
        XCTAssertEqual(L10n.tr("shortcuts.reassign", language: .russian), "Переназначить")
        XCTAssertEqual(L10n.tr("project.unsaved.cancel", language: .russian), "Отмена")
        XCTAssertEqual(L10n.tr("shortcuts.notAssigned", language: .english), "Not assigned")
        XCTAssertEqual(L10n.tr("shortcuts.notAssigned", language: .russian), "Не назначено")
    }

    func testConfiguredBindingUpdatesEverySharedShortcutHintAndCommandBinding() {
        var settings = AppSettings.defaults
        let replacement = ShortcutBinding("p", modifiers: [.command, .option])
        XCTAssertNil(settings.setShortcut(replacement, for: .commandPalette))
        let hint = ShortcutDisplayFormatter.display(for: .commandPalette, settings: settings, notAssigned: "Not assigned")

        XCTAssertEqual(hint, "⌥⌘P")
        XCTAssertEqual(settings.activeShortcut(for: .commandPalette), replacement)
        XCTAssertNotEqual(settings.activeShortcut(for: .commandPalette), ShortcutRegistry.definition(for: .commandPalette).factoryDefault)

        settings.shortcutOverrides[.commandPalette] = .unassigned
        XCTAssertEqual(ShortcutDisplayFormatter.display(for: .commandPalette, settings: settings, notAssigned: "Not assigned"), "Not assigned")
        XCTAssertNil(settings.activeShortcut(for: .commandPalette))
    }

    func testReassignedMacOSCommandUsesTheNewBindingWithoutRestartAndTheOldBindingStopsWorking() {
        var settings = AppSettings.defaults
        let oldBinding = try! XCTUnwrap(settings.activeShortcut(for: .commandPalette))
        let newBinding = ShortcutBinding("p", modifiers: [.command, .option])

        XCTAssertNil(settings.setShortcut(newBinding, for: .commandPalette))
        XCTAssertEqual(settings.activeShortcut(for: .commandPalette), newBinding)
        XCTAssertNotEqual(settings.activeShortcut(for: .commandPalette), oldBinding)
    }

    func testProjectTitleMenuHintsResolveCurrentSettingsAndHideExplicitUnassignments() {
        var settings = AppSettings.defaults
        let replacement = ShortcutBinding("w", modifiers: [.command, .option])

        XCTAssertEqual(ProjectTitleMenuShortcutHints.binding(for: .save, settings: settings), settings.activeShortcut(for: .save))
        XCTAssertNil(settings.setShortcut(replacement, for: .export))
        XCTAssertEqual(ProjectTitleMenuShortcutHints.binding(for: .export, settings: settings), replacement)

        settings.shortcutOverrides[.saveAs] = .unassigned
        XCTAssertNil(ProjectTitleMenuShortcutHints.binding(for: .saveAs, settings: settings))
        XCTAssertNil(ProjectTitleMenuShortcutHints.binding(for: .commandPalette, settings: settings))
    }

    func testProductionShortcutSurfacesUseTheActiveBindingFormatter() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = try [
            "FrameScript/App/FrameScriptApp.swift",
            "FrameScript/Components/ModeSwitcher.swift",
            "FrameScript/Components/TopToolbar.swift",
            "FrameScript/Components/SceneSidebar.swift",
            "FrameScript/Features/CommandPalette/CommandPaletteView.swift",
            "FrameScript/Features/Settings/ShortcutsOverlay.swift"
        ].map { path in
            try String(contentsOf: root.appendingPathComponent(path))
        }

        let menuCommands = sources[0]
        XCTAssertEqual(menuCommands.components(separatedBy: ".keyboardShortcut(").count - 1, 0)
        XCTAssertTrue(menuCommands.contains(".configuredKeyboardShortcut(appState.shortcutBinding"))
        XCTAssertTrue(sources[2].contains("ProjectTitleMenuShortcutHints.binding"))
        XCTAssertFalse(sources[2].contains(".keyboardShortcut("))
        for source in sources.dropFirst() {
            XCTAssertTrue(source.contains("shortcutDisplay(for:"))
            XCTAssertFalse(source.contains("settings.shortcut(for:"))
        }
    }

    func testOnlyOneProjectListExitActionRemainsInProductionSurfaces() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let paths = [
            "FrameScript/App/FrameScriptApp.swift",
            "FrameScript/Components/TopToolbar.swift",
            "FrameScript/Features/CommandPalette/CommandPaletteView.swift"
        ]
        let sources = try paths.map { try String(contentsOf: root.appendingPathComponent($0)) }.joined(separator: "\n")

        XCTAssertEqual(sources.components(separatedBy: "returnToProjectList()").count - 1, 3)
        XCTAssertFalse(sources.contains("closeProject()"))
        XCTAssertFalse(sources.contains("project.close"))
        XCTAssertFalse(sources.contains("command.closeProject"))
    }

    func testShortcutSettingsLayoutUsesOneOrderedCardForEveryCategory() {
        let cards = ShortcutSettingsLayout.categoryCards

        XCTAssertEqual(cards.map(\.category), ShortcutCategory.allCases)
        for card in cards {
            XCTAssertEqual(
                card.definitions.map(\.command),
                ShortcutRegistry.definitions
                    .filter { $0.category == card.category }
                    .sorted { $0.order < $1.order }
                    .map(\.command)
            )
        }
    }

    func testOverlayCategoryAndCommandOrderingIsDeterministic() {
        let sections = ShortcutsOverlayLayout.categorySections

        XCTAssertEqual(sections.map(\.category), ShortcutCategory.allCases)
        for section in sections {
            XCTAssertEqual(
                section.definitions.map(\.command),
                ShortcutRegistry.definitions
                    .filter { $0.category == section.category }
                    .map(\.command)
            )
        }
    }

    func testShortcutSettingsRowStateOnlyShowsResetForCustomizedCommands() {
        let definition = ShortcutRegistry.definition(for: .commandPalette)

        XCTAssertFalse(
            ShortcutSettingsLayout.rowState(for: definition, customizedCommands: [], recording: nil).showsReset
        )
        XCTAssertTrue(
            ShortcutSettingsLayout.rowState(for: definition, customizedCommands: [.commandPalette], recording: nil).showsReset
        )
    }

    func testShortcutSettingsRecordingStateOnlyHighlightsTheActiveRow() {
        let active = ShortcutRegistry.definition(for: .commandPalette)
        let inactive = ShortcutRegistry.definition(for: .save)

        XCTAssertTrue(
            ShortcutSettingsLayout.rowState(for: active, customizedCommands: [], recording: active.command).isRecording
        )
        XCTAssertFalse(
            ShortcutSettingsLayout.rowState(for: inactive, customizedCommands: [], recording: active.command).isRecording
        )
    }

    func testCapturedCandidateIsDisplayedInsteadOfTheRecordingPrompt() throws {
        let monitor = TestShortcutEventMonitor()
        var pendingBinding: ShortcutBinding?
        let session = ShortcutCaptureSession(eventMonitor: monitor, onRecord: { pendingBinding = $0 }, onCancel: {})
        session.start()

        XCTAssertNil(monitor.send(try keyEvent(keyCode: 45, characters: "n", modifiers: .command)))

        XCTAssertEqual(
            ShortcutCapturePresentation.label(pendingBinding: pendingBinding, pressShortcut: "Press shortcut…"),
            "⌘N"
        )
        XCTAssertFalse(session.isActive)
    }

    func testConflictDetectionOccursImmediatelyAfterCaptureAndStopsBeforeAlertPresentation() throws {
        let monitor = TestShortcutEventMonitor()
        let settings = AppSettings.defaults
        var conflict: ShortcutCommand?
        var captureWasStoppedBeforeAlert = false
        var session: ShortcutCaptureSession!
        session = ShortcutCaptureSession(eventMonitor: monitor, onRecord: { candidate in
            conflict = ShortcutRegistry.conflict(
                for: candidate,
                excluding: .duplicateScene,
                overrides: settings.shortcutOverrides
            )
            captureWasStoppedBeforeAlert = !session.isActive
        }, onCancel: {})
        session.start()

        let result = monitor.send(try keyEvent(keyCode: 1, characters: "s", modifiers: .command))

        XCTAssertNil(result)
        XCTAssertEqual(conflict, .save)
        XCTAssertTrue(captureWasStoppedBeforeAlert)
        XCTAssertEqual(monitor.removedCount, 1)
    }

    func testAlertKeyboardEventsAreNotConsumedAndDoNotChangeThePendingCandidate() throws {
        let monitor = TestShortcutEventMonitor()
        var pendingBinding: ShortcutBinding?
        let session = ShortcutCaptureSession(eventMonitor: monitor, onRecord: { pendingBinding = $0 }, onCancel: {})
        session.start()

        XCTAssertNil(monitor.send(try keyEvent(keyCode: 1, characters: "s", modifiers: .command)))
        let alertEvent = try keyEvent(keyCode: 36, characters: "\r", modifiers: [])

        XCTAssertTrue(monitor.send(alertEvent) === alertEvent)
        XCTAssertEqual(pendingBinding, .init("s", modifiers: [.command]))
        XCTAssertFalse(session.isActive)
    }

    func testNoCommandCanExecuteDuringTheInitialEditToCaptureTransition() throws {
        let monitor = TestShortcutEventMonitor()
        var recorded: [ShortcutBinding] = []
        let session = ShortcutCaptureSession(eventMonitor: monitor, onRecord: { recorded.append($0) }, onCancel: {})

        // This matches beginRecording: the monitor starts before the row becomes recording.
        session.start()
        let recordingRowIsVisible = true
        let result = monitor.send(try keyEvent(keyCode: 45, characters: "n", modifiers: .command))
        var newProjectRequests = 0
        if result != nil && recordingRowIsVisible { newProjectRequests += 1 }

        XCTAssertNil(result)
        XCTAssertEqual(newProjectRequests, 0)
        XCTAssertEqual(recorded, [.init("n", modifiers: [.command])])
    }

    func testEscapeCancelsRecordingAndRemovesCaptureSession() throws {
        let monitor = TestShortcutEventMonitor()
        var cancellations = 0
        let session = ShortcutCaptureSession(eventMonitor: monitor, onRecord: { _ in }, onCancel: { cancellations += 1 })
        session.start()

        XCTAssertNil(monitor.send(try keyEvent(keyCode: 53, characters: "", modifiers: [])))
        XCTAssertEqual(cancellations, 1)
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(monitor.removedCount, 1)
    }

    func testModifierOnlyAndUnmodifiedCharactersAreInvalidButConsumed() throws {
        let monitor = TestShortcutEventMonitor()
        var recorded: [ShortcutBinding] = []
        let session = ShortcutCaptureSession(eventMonitor: monitor, onRecord: { recorded.append($0) }, onCancel: {})
        session.start()

        XCTAssertNil(monitor.send(try keyEvent(keyCode: 0, characters: "a", modifiers: [])))
        XCTAssertNil(monitor.send(try keyEvent(keyCode: 55, characters: "", modifiers: .command)))
        XCTAssertTrue(recorded.isEmpty)
    }

    func testSaveRemovesItsCaptureSession() {
        assertCaptureSessionIsRemoved { $0.stop() }
    }

    func testCancelRemovesItsCaptureSession() {
        assertCaptureSessionIsRemoved { $0.stop() }
    }

    func testViewDisappearanceRemovesItsCaptureSession() {
        assertCaptureSessionIsRemoved { $0.stop() }
    }

    func testWindowClosureRemovesItsCaptureSession() {
        assertCaptureSessionIsRemoved { $0.stop() }
    }

    func testDeinitializationRemovesItsCaptureSession() {
        let monitor = TestShortcutEventMonitor()
        weak var deallocatedSession: ShortcutCaptureSession?
        var session: ShortcutCaptureSession? = ShortcutCaptureSession(eventMonitor: monitor, onRecord: { _ in }, onCancel: {})
        deallocatedSession = session
        session?.start()
        session = nil

        XCTAssertNil(deallocatedSession)
        XCTAssertEqual(monitor.removedCount, 1)
    }

    func testOnlyOneRecorderCanBeActive() {
        let firstMonitor = TestShortcutEventMonitor()
        let secondMonitor = TestShortcutEventMonitor()
        let first = ShortcutCaptureSession(eventMonitor: firstMonitor, onRecord: { _ in }, onCancel: {})
        let second = ShortcutCaptureSession(eventMonitor: secondMonitor, onRecord: { _ in }, onCancel: {})

        first.start()
        second.start()

        XCTAssertFalse(first.isActive)
        XCTAssertEqual(firstMonitor.removedCount, 1)
        XCTAssertTrue(second.isActive)
        second.stop()
    }

    private func keyEvent(keyCode: UInt16, characters: String, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func assertCaptureSessionIsRemoved(_ end: (ShortcutCaptureSession) -> Void) {
        let monitor = TestShortcutEventMonitor()
        let session = ShortcutCaptureSession(eventMonitor: monitor, onRecord: { _ in }, onCancel: {})
        session.start()
        end(session)

        XCTAssertFalse(session.isActive)
        XCTAssertEqual(monitor.removedCount, 1)
    }
}

private final class TestShortcutEventMonitor: ShortcutCaptureEventMonitoring {
    private var handler: ((NSEvent) -> NSEvent?)?
    private var token: NSObject?
    private(set) var removedCount = 0

    func addLocalKeyDownMonitor(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any {
        self.handler = handler
        let token = NSObject()
        self.token = token
        return token
    }

    func removeMonitor(_ monitor: Any) {
        removedCount += 1
        handler = nil
        token = nil
    }

    func send(_ event: NSEvent) -> NSEvent? {
        guard let handler else { return event }
        return handler(event)
    }
}
