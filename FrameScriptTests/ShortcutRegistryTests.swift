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
        XCTAssertEqual(settings.shortcut(for: .commandPalette), ShortcutRegistry.definition(for: .commandPalette).factoryDefault)
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
        let original = settings.shortcut(for: .duplicateScene)
        let conflict = settings.setShortcut(settings.shortcut(for: .save), for: .duplicateScene)
        XCTAssertEqual(conflict, .save)
        XCTAssertEqual(settings.shortcut(for: .duplicateScene), original)
        XCTAssertEqual(settings.activeShortcut(for: .save), ShortcutRegistry.definition(for: .save).factoryDefault)
    }

    func testReassignMovesShortcutAndExplicitlyUnassignsDisplacedCommand() {
        var settings = AppSettings.defaults
        let saveBinding = settings.shortcut(for: .save)

        XCTAssertEqual(settings.reassignShortcut(saveBinding, for: .duplicateScene), .save)
        XCTAssertEqual(settings.activeShortcut(for: .duplicateScene), saveBinding)
        XCTAssertNil(settings.activeShortcut(for: .save))
        XCTAssertEqual(settings.shortcutOverrides[.save], .unassigned)
        XCTAssertEqual(settings.shortcut(for: .save), ShortcutRegistry.definition(for: .save).factoryDefault)
    }

    func testAssignedAndUnassignedShortcutsRoundTripThroughCodable() throws {
        var settings = AppSettings.defaults
        _ = settings.setShortcut(.init("p", modifiers: [.command, .option]), for: .commandPalette)
        _ = settings.reassignShortcut(settings.shortcut(for: .save), for: .duplicateScene)

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
        XCTAssertEqual(settings.shortcut(for: .duplicateScene), ShortcutRegistry.definition(for: .duplicateScene).factoryDefault)
        XCTAssertNil(settings.setShortcut(ShortcutBinding("z", modifiers: [.command, .option]), for: .duplicateScene))
        XCTAssertNil(settings.setShortcut(ShortcutBinding("g", modifiers: [.command, .option]), for: .toggleFocusMode))
        settings.resetAllShortcuts()
        XCTAssertTrue(settings.shortcutOverrides.isEmpty)
    }

    func testPerCommandResetIsConflictSafe() {
        var settings = AppSettings.defaults
        let defaultBinding = settings.shortcut(for: .duplicateScene)
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
        _ = settings.reassignShortcut(settings.shortcut(for: .save), for: .duplicateScene)
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

    func testConfiguredBindingIsTheSingleSourceForKeycapsAndCommands() {
        var settings = AppSettings.defaults
        let replacement = ShortcutBinding("p", modifiers: [.command, .option])
        XCTAssertNil(settings.setShortcut(replacement, for: .commandPalette))
        XCTAssertEqual(settings.shortcut(for: .commandPalette).display, "⌥⌘P")
        XCTAssertNotEqual(settings.shortcut(for: .commandPalette), ShortcutRegistry.definition(for: .commandPalette).factoryDefault)
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

    func testRecordingCommandNConsumesEventBeforeNewProjectCommand() throws {
        let monitor = TestShortcutEventMonitor()
        var recorded: [ShortcutBinding] = []
        let session = ShortcutCaptureSession(eventMonitor: monitor, onRecord: { recorded.append($0) }, onCancel: {})
        session.start()

        let result = monitor.send(try keyEvent(keyCode: 45, characters: "n", modifiers: .command))
        var newProjectRequests = 0
        if result != nil { newProjectRequests += 1 }

        XCTAssertNil(result)
        XCTAssertEqual(newProjectRequests, 0)
        XCTAssertEqual(recorded, [.init("n", modifiers: [.command])])
    }

    func testRecordingCommandSConsumesEventBeforeSaveCommand() throws {
        let monitor = TestShortcutEventMonitor()
        let session = ShortcutCaptureSession(eventMonitor: monitor, onRecord: { _ in }, onCancel: {})
        session.start()

        let result = monitor.send(try keyEvent(keyCode: 1, characters: "s", modifiers: .command))
        var saveRequests = 0
        if result != nil { saveRequests += 1 }

        XCTAssertNil(result)
        XCTAssertEqual(saveRequests, 0)
    }

    func testRecordingExistingCustomizedShortcutDoesNotExecuteItsCommand() throws {
        let monitor = TestShortcutEventMonitor()
        var recorded: [ShortcutBinding] = []
        let session = ShortcutCaptureSession(eventMonitor: monitor, onRecord: { recorded.append($0) }, onCancel: {})
        session.start()

        let result = monitor.send(try keyEvent(keyCode: 35, characters: "p", modifiers: [.command, .option]))
        var paletteRequests = 0
        if result != nil { paletteRequests += 1 }

        XCTAssertNil(result)
        XCTAssertEqual(paletteRequests, 0)
        XCTAssertEqual(recorded, [.init("p", modifiers: [.command, .option])])
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

    func testCaptureSessionIsRemovedAfterSaveCancelDisappearanceAndWindowClosure() {
        for _ in 0..<4 {
            let monitor = TestShortcutEventMonitor()
            let session = ShortcutCaptureSession(eventMonitor: monitor, onRecord: { _ in }, onCancel: {})
            session.start()
            session.stop()
            XCTAssertFalse(session.isActive)
            XCTAssertEqual(monitor.removedCount, 1)
        }
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
