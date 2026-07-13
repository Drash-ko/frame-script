import Foundation
@testable import FrameScript
import XCTest

@MainActor
final class SettingsPreferencesTests: XCTestCase {
    func testLegacyLaunchBehaviorMigrationRestoresOnlyTheUnambiguousCombination() throws {
        for (showBrowser, restoreLastProject, expected) in [
            (false, true, LaunchBehavior.restoreLastProject),
            (true, true, .showProjectBrowser),
            (true, false, .showProjectBrowser),
            (false, false, .showProjectBrowser)
        ] {
            let preferences = try JSONDecoder().decode(
                GeneralPreferences.self,
                from: legacyGeneralPreferencesData(
                    showProjectBrowserOnLaunch: showBrowser,
                    restoreLastProjectOnLaunch: restoreLastProject
                )
            )
            XCTAssertEqual(preferences.launchBehavior, expected)
        }
    }

    func testRestoreLastProjectFallsBackToProjectBrowserWhenNoRecentProjectIsValid() {
        XCTAssertFalse(LaunchBehavior.restoreLastProject.shouldRestoreLastProject(hasOpenProject: false, hasRecentProject: false))
        XCTAssertFalse(LaunchBehavior.restoreLastProject.shouldRestoreLastProject(hasOpenProject: true, hasRecentProject: true))
        XCTAssertTrue(LaunchBehavior.restoreLastProject.shouldRestoreLastProject(hasOpenProject: false, hasRecentProject: true))
        XCTAssertFalse(LaunchBehavior.showProjectBrowser.shouldRestoreLastProject(hasOpenProject: false, hasRecentProject: true))
    }

    func testMissingInlineAutocompletePreferenceDefaultsToEnabled() throws {
        let data = Data("""
        {"provider":"Disabled","model":"gpt-4.1-mini","baseURL":"","temperature":0.4,"maxTokens":420,"privacyMode":true}
        """.utf8)

        XCTAssertTrue(try JSONDecoder().decode(AIPreferences.self, from: data).enableInlineAutocomplete)
    }

    func testDisabledInlineAutocompleteBlocksOnlyAutocompleteEligibility() async {
        let suiteName = "SettingsPreferencesTests-autocomplete-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configurationStore = AIProviderConfigurationStore(userDefaults: defaults)
        configurationStore.setHasStoredKey(true, for: .openAICompatible)
        var settings = AppSettings.defaults
        settings.aiPreferences.provider = .openAICompatible
        settings.aiPreferences.enableInlineAutocomplete = false
        let appState = AppState(
            recentProjectStore: RecentProjectStore(userDefaults: defaults),
            settingsStore: SettingsStore(settings: settings, userDefaults: defaults, key: "settings"),
            aiProviderConfigurationStore: configurationStore
        )

        XCTAssertEqual(appState.autocompleteConfigurationEligibility, .blockedPreferenceDisabled)
        let result = await appState.autocompleteScript(
            context: AutocompleteContext(prefix: "A sufficiently long script prefix.", suffix: "", sceneTitle: "Scene", language: .english)
        )
        XCTAssertEqual(result, .none)

        appState.settings.aiPreferences.enableInlineAutocomplete = true
        appState.inlineAutocompletePreferenceDidChange()
        XCTAssertEqual(appState.autocompleteConfigurationEligibility, .eligible)
    }

    func testNewAndResetSettingsEnableAIReviewAndInlineAutocomplete() {
        XCTAssertTrue(AppSettings.defaults.editorPreferences.showAIReviewPanel)
        XCTAssertTrue(AppSettings.defaults.aiPreferences.enableInlineAutocomplete)

        let suiteName = "SettingsPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(settings: .defaults, userDefaults: defaults, key: "settings")
        store.settings.editorPreferences.showAIReviewPanel = false
        store.settings.aiPreferences.enableInlineAutocomplete = false
        store.reset()

        XCTAssertTrue(store.settings.editorPreferences.showAIReviewPanel)
        XCTAssertTrue(store.settings.aiPreferences.enableInlineAutocomplete)
    }

    func testSavedAIReviewPreferenceIsPreservedAndFooterStateIsNotEncoded() throws {
        var settings = AppSettings.defaults
        settings.editorPreferences.showAIReviewPanel = false
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let editor = try XCTUnwrap(root["editorPreferences"] as? [String: Any])

        XCTAssertFalse(decoded.editorPreferences.showAIReviewPanel)
        XCTAssertNil(editor["showFooterShortcuts"])
    }

    private func legacyGeneralPreferencesData(
        showProjectBrowserOnLaunch: Bool,
        restoreLastProjectOnLaunch: Bool
    ) -> Data {
        Data("""
        {
          "showProjectBrowserOnLaunch": \(showProjectBrowserOnLaunch),
          "restoreLastProjectOnLaunch": \(restoreLastProjectOnLaunch),
          "language": "system",
          "autosaveEnabled": true,
          "autosaveIntervalSeconds": 10,
          "defaultNewProjectTemplate": "Blank",
          "blankProjectStart": "One empty scene",
          "defaultSplitMode": "paragraph",
          "confirmBeforeDeleting": true
        }
        """.utf8)
    }
}
