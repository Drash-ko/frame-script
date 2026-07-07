import SwiftUI

struct FooterShortcutBar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme

    private var shortcuts: [(String, String)] {
        [
            ("⌘K", appState.localized("toolbar.commandPalette")),
            ("⌘⌥N", appState.localized("scene.add")),
            ("⌘1", appState.localized("mode.script")),
            ("⌘2", appState.localized("mode.bRoll")),
            ("⌘3", appState.localized("mode.editing")),
            ("⌘'", appState.localized("command.toggleFocus"))
        ]
    }

    var body: some View {
        HStack(spacing: 14) {
            ForEach(shortcuts, id: \.0) { key, label in
                HStack(spacing: 6) {
                    Text(key)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .frame(height: 19)
                        .background {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(theme.sidebar)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(theme.divider, lineWidth: 1)
                                )
                        }
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                }
            }

            Spacer()

            Button(appState.localized("shortcuts.title")) {
                appState.isShortcutsPresented = true
            }
            .font(.system(size: 12, weight: .medium))
            .buttonStyle(.cursorPlain)
            .foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(theme.background)
    }
}
