import SwiftUI

struct TopToolbar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var editorState = appState.editorState
        let reducedChrome = appState.settings.windowPreferences.reducedChromeMode

        HStack(spacing: reducedChrome ? 12 : 18) {
            Menu {
                Button(appState.localized("project.rename")) { appState.renameProject() }
                Button(appState.localized("project.save")) { appState.saveProject() }
                Button(appState.localized("project.saveAs")) { appState.saveProjectAs() }
                Button(appState.localized("project.reveal")) { appState.revealProjectInFinder() }
                    .disabled(appState.projectStore.currentFileURL == nil)
                Divider()
                Button(appState.localized("project.export")) { appState.exportProject() }
                Button(appState.localized("voiceover.title")) { appState.windowState.isVoiceoverPresented = true }
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

            ModeSwitcher(selection: $editorState.selectedMode)

            Spacer(minLength: 8)

            Text(DurationEstimator.formatted(appState.totalDuration))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(theme.secondaryText)
                .monospacedDigit()

            Button {
                appState.exportProject()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.cursorPlain)
            .foregroundStyle(theme.secondaryText)
            .help(appState.localized("project.export"))

            Button {
                appState.windowState.isVoiceoverPresented = true
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.cursorPlain)
            .foregroundStyle(theme.secondaryText)
            .help(appState.localized("voiceover.title"))

            Button {
                appState.isCommandPalettePresented = true
            } label: {
                Image(systemName: "command")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.cursorPlain)
            .foregroundStyle(theme.secondaryText)
            .help(appState.localized("toolbar.commandPalette"))

            Button {
                appState.openSettings(tab: .general)
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.cursorPlain)
            .foregroundStyle(theme.secondaryText)
            .help(appState.localized("toolbar.settings"))
        }
        .padding(.horizontal, reducedChrome ? 14 : 18)
        .frame(height: reducedChrome ? 50 : 58)
        .background(theme.background)
    }
}
