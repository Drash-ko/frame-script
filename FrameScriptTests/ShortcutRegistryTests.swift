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

    func testConflictIsRejectedWithoutChangingTheExistingBinding() {
        var settings = AppSettings.defaults
        let original = settings.shortcut(for: .duplicateScene)
        let conflict = settings.setShortcut(settings.shortcut(for: .save), for: .duplicateScene)
        XCTAssertEqual(conflict, .save)
        XCTAssertEqual(settings.shortcut(for: .duplicateScene), original)
    }

    func testPerCommandAndGlobalResets() {
        var settings = AppSettings.defaults
        XCTAssertNil(settings.setShortcut(ShortcutBinding("z", modifiers: [.command, .option]), for: .duplicateScene))
        settings.resetShortcut(.duplicateScene)
        XCTAssertEqual(settings.shortcut(for: .duplicateScene), ShortcutRegistry.definition(for: .duplicateScene).factoryDefault)
        XCTAssertNil(settings.setShortcut(ShortcutBinding("z", modifiers: [.command, .option]), for: .duplicateScene))
        XCTAssertNil(settings.setShortcut(ShortcutBinding("g", modifiers: [.command, .option]), for: .toggleFocusMode))
        settings.resetAllShortcuts()
        XCTAssertTrue(settings.shortcutOverrides.isEmpty)
    }

    func testEveryRegistryCommandHasEnglishAndRussianLocalization() {
        for definition in ShortcutRegistry.definitions {
            XCTAssertNotEqual(L10n.tr(definition.localizationKey, language: .english), definition.localizationKey)
            XCTAssertNotEqual(L10n.tr(definition.localizationKey, language: .russian), definition.localizationKey)
        }
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
}
