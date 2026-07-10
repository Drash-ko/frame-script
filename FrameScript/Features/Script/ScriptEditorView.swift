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

            HStack(alignment: .top, spacing: 18) {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if ProductionMarkerMiniMap.hasMarkers(in: scene) {
                    ProductionMarkerMiniMap(scene: scene)
                        .frame(width: 176)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
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
        guard scene.sectionType != .custom else {
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

private struct ProductionMarkerMiniMap: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    let scene: Scene

    static func hasMarkers(in scene: Scene) -> Bool {
        !scene.bRollItems.isEmpty || !scene.editingItems.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appState.localized("production.markers"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.tertiaryText)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(Array(scene.textSegments.sortedByOrder.enumerated()), id: \.element.id) { index, segment in
                        markerRow(index: index, segment: segment)
                    }

                    if scene.textSegments.isEmpty {
                        unlinkedMarkerRow
                    }
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.cardBackground.opacity(0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.divider, lineWidth: 1)
                }
        }
    }

    private func markerRow(index: Int, segment: TextSegment) -> some View {
        HStack(spacing: 6) {
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(theme.tertiaryText)
                .frame(width: 20, alignment: .leading)

            Text(segment.sourceText)
                .font(.system(size: 10))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 3) {
                if hasBRoll(segment) {
                    markerButton(color: theme.bRollMarker, mode: .bRoll, label: appState.localized("mode.bRoll"))
                }
                if hasEditing(segment) {
                    markerButton(color: theme.editingMarker, mode: .editing, label: appState.localized("mode.editing"))
                }
            }
            .frame(minWidth: 16, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .frame(height: 25)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(theme.hover.opacity((hasBRoll(segment) || hasEditing(segment)) ? 1 : 0.35))
        }
    }

    private var unlinkedMarkerRow: some View {
        HStack(spacing: 6) {
            Text(appState.localized("production.unlinked"))
                .font(.system(size: 10))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 2)
            if !scene.bRollItems.isEmpty {
                markerButton(color: theme.bRollMarker, mode: .bRoll, label: appState.localized("mode.bRoll"))
            }
            if !scene.editingItems.isEmpty {
                markerButton(color: theme.editingMarker, mode: .editing, label: appState.localized("mode.editing"))
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 25)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(theme.hover)
        }
    }

    private func markerButton(color: Color, mode: WorkspaceMode, label: String) -> some View {
        Button {
            appState.selectMode(mode)
        } label: {
            Capsule()
                .fill(color)
                .frame(width: 4, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.cursorPlain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func hasBRoll(_ segment: TextSegment) -> Bool {
        scene.bRollItems.contains { $0.linkedSegmentID == segment.id }
    }

    private func hasEditing(_ segment: TextSegment) -> Bool {
        scene.editingItems.contains { $0.linkedSegmentID == segment.id }
    }
}
