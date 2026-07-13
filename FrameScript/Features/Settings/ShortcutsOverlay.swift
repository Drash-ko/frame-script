import SwiftUI

struct ShortcutsOverlay: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme

    private var shortcuts: [ShortcutDefinition] {
        ShortcutRegistry.definitions.sorted { $0.order < $1.order }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appState.localized("shortcuts.title"))
                .font(.system(size: 24, weight: .semibold))

            LazyVGrid(columns: [GridItem(.fixed(90)), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                ForEach(shortcuts) { shortcut in
                    Text(appState.settings.shortcut(for: shortcut.command).display)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                    Text(appState.localized(shortcut.localizationKey))
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(theme.background)
    }
}
