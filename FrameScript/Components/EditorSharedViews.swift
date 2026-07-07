import SwiftUI

struct EditorModeHeader: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    let title: String
    let subtitle: String
    let sourceText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 30, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
            }

            Text(sourceText.isEmpty ? appState.localized("editor.noScriptText") : sourceText)
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(5)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.background.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(theme.divider, lineWidth: 1)
                        )
                }
        }
    }
}

struct EmptyModeState: View {
    @Environment(\.frameTheme) private var theme
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 17, weight: .medium))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
                .buttonStyle(.cursorPlain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.background.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.divider, lineWidth: 1)
                )
        }
    }
}

struct EditorIconButton: View {
    @Environment(\.frameTheme) private var theme
    let systemName: String
    let accessibilityLabel: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.cursorPlain)
        .foregroundStyle(role == .destructive ? theme.destructive : theme.secondaryText)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
    }
}
