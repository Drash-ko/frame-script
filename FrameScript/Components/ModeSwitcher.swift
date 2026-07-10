import SwiftUI

struct ModeSwitcher: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Binding var selection: WorkspaceMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(WorkspaceMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    HStack(spacing: 5) {
                        Text(title(for: mode)).lineLimit(1).minimumScaleFactor(0.88)
                        Text(mode.shortcut)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.tertiaryText)
                            .padding(.horizontal, 4).frame(height: 16)
                            .background(RoundedRectangle(cornerRadius: 4).fill(theme.hover).overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.divider)))
                    }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selection == mode ? theme.primaryText : theme.secondaryText)
                        .frame(minWidth: 92, maxWidth: 112, minHeight: 28)
                        .background {
                            if selection == mode {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(theme.softAccent)
                            }
                        }
                }
                .buttonStyle(.cursorPlain)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.sidebar.opacity(0.82))
        }
    }

    private func title(for mode: WorkspaceMode) -> String {
        switch mode {
        case .script: appState.localized("mode.script")
        case .bRoll: appState.localized("mode.bRoll")
        case .editing: appState.localized("mode.editing")
        }
    }
}
