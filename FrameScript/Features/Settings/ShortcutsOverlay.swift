import SwiftUI

struct ShortcutsOverlay: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appState.localized("shortcuts.title"))
                .font(.system(size: 24, weight: .semibold))

            ForEach(ShortcutsOverlayLayout.categorySections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.localized(section.category.localizationKey))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)

                    LazyVGrid(columns: [GridItem(.fixed(90)), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        ForEach(section.definitions) { shortcut in
                            Text(appState.shortcutDisplay(for: shortcut.command))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.primaryText)
                            Text(appState.localized(shortcut.localizationKey))
                                .font(.system(size: 13))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(theme.background)
    }
}

struct ShortcutsOverlayCategorySection: Identifiable {
    let category: ShortcutCategory
    let definitions: [ShortcutDefinition]

    var id: ShortcutCategory { category }
}

enum ShortcutsOverlayLayout {
    /// Filtering the registry preserves its definition order. Categories are
    /// deliberately driven by allCases rather than a global order comparison.
    static let categorySections = ShortcutCategory.allCases.map { category in
        ShortcutsOverlayCategorySection(
            category: category,
            definitions: ShortcutRegistry.definitions.filter { $0.category == category }
        )
    }
}
