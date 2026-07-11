import SwiftUI

struct TopToolbar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 14) {
            Menu {
                Button(appState.localized("project.rename")) { appState.renameProject() }
                Button(appState.localized("project.save")) { appState.saveProject() }
                Button(appState.localized("project.saveAs")) { appState.saveProjectAs() }
                Button(appState.localized("project.reveal")) { appState.revealProjectInFinder() }
                    .disabled(appState.projectStore.currentFileURL == nil)
                Divider()
                Button(appState.localized("project.export")) { appState.exportProject() }
                Divider()
                Button(appState.localized("project.close")) { appState.closeProject() }
                Button(appState.localized("project.browser")) { appState.showProjectBrowser() }
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.project.title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        Text(appState.displayName(appState.saveState))
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.cursorPlain)
            .frame(width: 210, alignment: .leading)

            Spacer(minLength: 8)

            ModeSwitcher(selection: Binding(
                get: { appState.selectedMode },
                set: { appState.selectMode($0) }
            ))

            Spacer(minLength: 8)

            Text(DurationEstimator.formatted(appState.totalDuration))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .monospacedDigit()

            HStack(spacing: 5) {
                toolbarButton(
                    systemName: "square.and.arrow.up",
                    help: appState.localized("project.export"),
                    action: appState.exportProject
                )

                toolbarDivider

                Button {
                    appState.isFocusModeEnabled.toggle()
                } label: {
                    Image(systemName: appState.isFocusModeEnabled ? "viewfinder.circle.fill" : "viewfinder")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 30)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(appState.isFocusModeEnabled ? theme.accentSoft : Color.clear)
                        }
                }
                .buttonStyle(.cursorPlain)
                .foregroundStyle(appState.isFocusModeEnabled ? theme.accent.color : theme.secondaryText)
                .help(appState.localized("toolbar.focusMode"))

                toolbarDivider

                Button {
                    appState.isCommandPalettePresented = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .medium))
                        Text("⌘K")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.tertiaryText)
                            .padding(.horizontal, 4)
                            .frame(height: 17)
                            .background {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(theme.hover)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .stroke(theme.divider, lineWidth: 1)
                                    }
                            }
                    }
                    .frame(height: 30)
                }
                .buttonStyle(.cursorPlain)
                .foregroundStyle(theme.secondaryText)
                .help(appState.localized("toolbar.commandPalette"))

                toolbarDivider

                toolbarButton(systemName: "gearshape", help: appState.localized("toolbar.settings")) {
                    appState.openSettings(tab: .general)
                    openSettings()
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(theme.background)
    }

    private func toolbarButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.cursorPlain)
        .foregroundStyle(theme.secondaryText)
        .help(help)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(theme.divider)
            .frame(width: 1, height: 18)
            .padding(.horizontal, 2)
    }
}
