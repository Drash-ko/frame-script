import SwiftUI

struct EditingEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Bindable var scene: Scene
    @State private var isTemplatePickerPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                EditorModeHeader(
                    title: scene.title,
                    subtitle: appState.localized("editing.linkedSubtitle"),
                    sourceText: scene.scriptText
                )

                if scene.editingItems.isEmpty {
                    EmptyModeState(
                        title: appState.localized("editing.emptyTitle"),
                        message: appState.localized("editing.emptyMessage"),
                        actionTitle: appState.localized("editing.addItem"),
                        action: { isTemplatePickerPresented = true }
                    )
                } else {
                    VStack(spacing: 14) {
                        ForEach(scene.editingItems) { item in
                            EditingItemEditor(
                                item: item,
                                duplicateAction: { duplicateItem(item) },
                                deleteAction: { deleteItem(item) }
                            )
                        }
                    }

                    Button(appState.localized("editing.addItem")) {
                        isTemplatePickerPresented = true
                    }
                    .buttonStyle(.cursorPlain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 52)
            .padding(.vertical, 42)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(theme.editorSurface)
        .confirmationDialog(appState.localized("editing.templatePickerTitle"), isPresented: $isTemplatePickerPresented) {
            ForEach(EditingTemplatePreset.allCases) { preset in
                Button(preset.title(appState: appState)) {
                    addItem(from: preset)
                }
            }
            Button(appState.localized("project.unsaved.cancel"), role: .cancel) {}
        }
        .onChange(of: scene.editingItems.count) { _, _ in appState.touchProject() }
    }

    private func addItem(from preset: EditingTemplatePreset) {
        scene.editingItems.append(
            EditingItem(
                id: UUID(),
                linkedSegmentID: scene.textSegments.first?.id,
                templateType: preset.title(appState: appState),
                cutStyle: preset.cutStyle(appState: appState),
                transition: preset.transition(appState: appState),
                subtitleStyle: preset.subtitleStyle(appState: appState),
                emphasis: preset.emphasis(appState: appState),
                zoom: preset.zoom(appState: appState),
                sfx: preset.sfx(appState: appState),
                musicCue: preset.musicCue(appState: appState),
                graphics: preset.graphics(appState: appState),
                notes: preset.notes(appState: appState)
            )
        )
        appState.touchProject()
    }

    private func duplicateItem(_ item: EditingItem) {
        let copy = EditingItem(
            linkedSegmentID: item.linkedSegmentID,
            templateType: item.templateType,
            cutStyle: item.cutStyle,
            transition: item.transition,
            subtitleStyle: item.subtitleStyle,
            emphasis: item.emphasis,
            zoom: item.zoom,
            sfx: item.sfx,
            musicCue: item.musicCue,
            graphics: item.graphics,
            notes: item.notes
        )

        if let index = scene.editingItems.firstIndex(where: { $0.id == item.id }) {
            scene.editingItems.insert(copy, at: scene.editingItems.index(after: index))
        } else {
            scene.editingItems.append(copy)
        }
        appState.touchProject()
    }

    private func deleteItem(_ item: EditingItem) {
        scene.editingItems.removeAll { $0.id == item.id }
        appState.touchProject()
    }
}

private enum EditingTemplatePreset: String, CaseIterable, Identifiable {
    case minimal
    case educational
    case storytelling
    case fastSocial
    case documentary
    case custom

    var id: String { rawValue }

    @MainActor func title(appState: AppState) -> String { appState.localized("editing.template.\(rawValue)") }
    @MainActor func cutStyle(appState: AppState) -> String { appState.localized("editing.template.\(rawValue).cutStyle") }
    @MainActor func transition(appState: AppState) -> String { appState.localized("editing.template.\(rawValue).transition") }
    @MainActor func subtitleStyle(appState: AppState) -> String { appState.localized("editing.template.\(rawValue).subtitleStyle") }
    @MainActor func emphasis(appState: AppState) -> String { appState.localized("editing.template.\(rawValue).emphasis") }
    @MainActor func zoom(appState: AppState) -> String { appState.localized("editing.template.\(rawValue).zoom") }
    @MainActor func sfx(appState: AppState) -> String { appState.localized("editing.template.\(rawValue).sfx") }
    @MainActor func musicCue(appState: AppState) -> String { appState.localized("editing.template.\(rawValue).musicCue") }
    @MainActor func graphics(appState: AppState) -> String { appState.localized("editing.template.\(rawValue).graphics") }
    @MainActor func notes(appState: AppState) -> String { appState.localized("editing.template.\(rawValue).notes") }
}

private struct EditingItemEditor: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Bindable var item: EditingItem
    let duplicateAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(appState.localized("editing.item"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryText)

                Spacer()

                EditorIconButton(
                    systemName: "plus.square.on.square",
                    accessibilityLabel: appState.localized("editing.duplicateItem"),
                    action: duplicateAction
                )
                EditorIconButton(
                    systemName: "trash",
                    accessibilityLabel: appState.localized("editing.deleteItem"),
                    role: .destructive,
                    action: deleteAction
                )
            }

            HStack(spacing: 12) {
                TextField(appState.localized("templates.name"), text: $item.templateType)
                    .textFieldStyle(QuietTextFieldStyle())
                TextField(appState.localized("editing.cutStyle"), text: $item.cutStyle)
                    .textFieldStyle(QuietTextFieldStyle())
                TextField(appState.localized("editing.transition"), text: $item.transition)
                    .textFieldStyle(QuietTextFieldStyle())
            }

            HStack(spacing: 12) {
                QuietField(appState.localized("editing.subtitles")) {
                    TextField(appState.localized("editing.subtitlesPlaceholder"), text: $item.subtitleStyle)
                        .textFieldStyle(QuietTextFieldStyle())
                }
                QuietField(appState.localized("editing.emphasis")) {
                    TextField(appState.localized("editing.emphasisPlaceholder"), text: $item.emphasis)
                        .textFieldStyle(QuietTextFieldStyle())
                }
                QuietField(appState.localized("editing.zoom")) {
                    TextField(appState.localized("editing.zoomPlaceholder"), text: $item.zoom)
                        .textFieldStyle(QuietTextFieldStyle())
                }
            }

            HStack(spacing: 12) {
                QuietField(appState.localized("editing.sfx")) {
                    TextField(appState.localized("editing.sfxPlaceholder"), text: $item.sfx)
                        .textFieldStyle(QuietTextFieldStyle())
                }
                QuietField(appState.localized("editing.musicCue")) {
                    TextField(appState.localized("editing.musicCuePlaceholder"), text: $item.musicCue)
                        .textFieldStyle(QuietTextFieldStyle())
                }
            }

            QuietField(appState.localized("editing.graphics")) {
                MultilineField(placeholder: appState.localized("editing.graphicsPlaceholder"), text: $item.graphics, minHeight: 76)
            }

            QuietField(appState.localized("editing.notes")) {
                MultilineField(placeholder: appState.localized("editing.notesPlaceholder"), text: $item.notes, minHeight: 76)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.background.opacity(0.48))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.divider, lineWidth: 1)
                )
        }
        .onChange(of: item.templateType) { _, _ in appState.touchProject() }
        .onChange(of: item.cutStyle) { _, _ in appState.touchProject() }
        .onChange(of: item.transition) { _, _ in appState.touchProject() }
        .onChange(of: item.subtitleStyle) { _, _ in appState.touchProject() }
        .onChange(of: item.emphasis) { _, _ in appState.touchProject() }
        .onChange(of: item.zoom) { _, _ in appState.touchProject() }
        .onChange(of: item.sfx) { _, _ in appState.touchProject() }
        .onChange(of: item.musicCue) { _, _ in appState.touchProject() }
        .onChange(of: item.graphics) { _, _ in appState.touchProject() }
        .onChange(of: item.notes) { _, _ in appState.touchProject() }
    }
}
