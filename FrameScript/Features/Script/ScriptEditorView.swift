import SwiftUI

struct ScriptEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Bindable var scene: Scene
    @FocusState private var editorFocused: Bool
    @State private var notesExpanded = false
    @State private var didApplyInitialNotesVisibility = false
    @State private var didManuallyToggleNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sceneHeader

            ZStack(alignment: .topLeading) {
                if scene.scriptText.isEmpty {
                    Text(appState.localized("script.placeholder"))
                        .font(.system(size: appState.settings.editorPreferences.fontSize))
                        .foregroundStyle(theme.secondaryText.opacity(0.58))
                        .padding(.top, 7)
                        .padding(.leading, 6)
                        .accessibilityHidden(true)
                }

                TextEditor(text: $scene.scriptText)
                    .font(.system(size: appState.settings.editorPreferences.fontSize))
                    .lineSpacing(appState.settings.editorPreferences.lineHeight * 4)
                    .scrollContentBackground(.hidden)
                    .disableAutocorrection(!appState.settings.editorPreferences.spellcheck)
                    .focused($editorFocused)
                    .accessibilityLabel(appState.localized("script.accessibilityLabel"))
                    .padding(0)
            }
            .frame(minHeight: appState.isFocusModeEnabled ? 430 : 390, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture {
                editorFocused = true
            }
            .textCursor()

            DisclosureGroup(isExpanded: Binding(
                get: { notesExpanded },
                set: {
                    notesExpanded = $0
                    didManuallyToggleNotes = true
                }
            )) {
                MultilineField(
                    placeholder: appState.localized("script.notesPlaceholder"),
                    text: $scene.notes,
                    minHeight: 82
                )
                .accessibilityLabel(appState.localized("script.notes"))
            }
            label: {
                Text(appState.localized("script.notes"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }
            .font(.system(size: 13))
            .tint(theme.secondaryText)
        }
        .frame(maxWidth: appState.settings.editorPreferences.editorWidth, alignment: .leading)
        .padding(.horizontal, appState.isFocusModeEnabled ? 80 : 48)
        .padding(.vertical, appState.isFocusModeEnabled ? 72 : 42)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.editorSurface)
        .onAppear {
            editorFocused = true
            applyInitialNotesVisibility()
        }
        .onChange(of: scene.scriptText) { _, _ in appState.touchProject() }
        .onChange(of: scene.title) { _, _ in appState.touchProject() }
        .onChange(of: scene.notes) { _, _ in appState.touchProject() }
        .onChange(of: appState.settings.editorPreferences.defaultNotesVisibility) { _, newValue in
            guard !didManuallyToggleNotes else { return }
            notesExpanded = !appState.isFocusModeEnabled && newValue == .expanded
        }
    }

    private var sceneHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(appState.localized("scene.title"), text: $scene.title)
                .textFieldStyle(.plain)
                .font(.system(size: appState.isFocusModeEnabled ? 34 : 30, weight: .semibold))
                .textCursor()

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    if appState.settings.editorPreferences.showSceneDuration {
                        Text(DurationEstimator.formatted(scene.estimatedDuration))
                        Text(appState.localized("script.estimated"))
                    }
                    if appState.settings.editorPreferences.showSceneDuration && appState.settings.editorPreferences.showWordCount {
                        Text("·")
                    }
                    if appState.settings.editorPreferences.showWordCount {
                        Text("\(wordCount) \(appState.localized("script.words"))")
                    }
                }

                if shouldShowSectionTag {
                    Label("\(appState.localized("script.templateSection")): \(appState.displayName(scene.sectionType))", systemImage: "tag")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryText)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(theme.secondaryText)
        }
    }

    private var wordCount: Int {
        scene.scriptText.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var shouldShowSectionTag: Bool {
        guard !appState.settings.windowPreferences.reducedChromeMode,
              scene.sectionType != .custom else {
            return false
        }
        return scene.title.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(appState.displayName(scene.sectionType)) != .orderedSame
    }

    private func applyInitialNotesVisibility() {
        guard !didApplyInitialNotesVisibility else { return }
        didApplyInitialNotesVisibility = true
        notesExpanded = !appState.isFocusModeEnabled
            && appState.settings.editorPreferences.defaultNotesVisibility == .expanded
    }
}
