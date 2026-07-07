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
                    Text(title(for: mode))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selection == mode ? theme.primaryText : theme.secondaryText)
                        .frame(width: 86, height: 28)
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
