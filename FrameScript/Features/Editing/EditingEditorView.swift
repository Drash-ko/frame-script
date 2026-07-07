import SwiftUI

struct EditingEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Bindable var scene: Scene

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                EditorModeHeader(
                    title: scene.title,
                    subtitle: appState.localized("editing.linkedSubtitle")
                )

                if scene.scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmptyProductionState(message: appState.localized("editing.writeScriptFirst"))
                } else {
                    VStack(spacing: 16) {
                        ForEach(scene.textSegments.sortedByOrder) { segment in
                            EditingSegmentBlock(
                                segment: segment,
                                items: items(for: segment),
                                addEmptyAction: { addEmptyItem(linkedTo: segment.id) },
                                addPresetAction: { addItem(from: $0, linkedTo: segment.id) },
                                duplicateAction: duplicateItem,
                                deleteAction: deleteItem
                            )
                        }
                    }

                    let unlinked = unlinkedItems
                    if !unlinked.isEmpty {
                        ProductionUnlinkedBlock(title: appState.localized("production.unlinked")) {
                            ForEach(unlinked) { item in
                                EditingItemEditor(
                                    item: item,
                                    duplicateAction: { duplicateItem(item) },
                                    deleteAction: { deleteItem(item) }
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 52)
            .padding(.vertical, 42)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(theme.editorSurface)
        .onAppear {
            appState.rebuildProductionSegments(markUnsaved: false)
        }
        .onChange(of: scene.editingItems.count) { _, _ in appState.touchProject() }
    }

    private func items(for segment: TextSegment) -> [EditingItem] {
        scene.editingItems.filter { $0.linkedSegmentID == segment.id }
    }

    private var unlinkedItems: [EditingItem] {
        let validIDs = Set(scene.textSegments.map(\.id))
        return scene.editingItems.filter { item in
            guard let linkedID = item.linkedSegmentID else { return true }
            return !validIDs.contains(linkedID)
        }
    }

    private func addEmptyItem(linkedTo segmentID: UUID) {
        scene.editingItems.append(
            EditingItem(
                id: UUID(),
                linkedSegmentID: segmentID,
                templateType: "",
                cutStyle: "",
                transition: "",
                subtitleStyle: ""
            )
        )
        appState.touchProject()
    }

    private func addItem(from preset: EditingTemplatePreset, linkedTo segmentID: UUID) {
        scene.editingItems.append(
            EditingItem(
                id: UUID(),
                linkedSegmentID: segmentID,
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

private struct EditingSegmentBlock: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    let segment: TextSegment
    let items: [EditingItem]
    let addEmptyAction: () -> Void
    let addPresetAction: (EditingTemplatePreset) -> Void
    let duplicateAction: (EditingItem) -> Void
    let deleteAction: (EditingItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(appState.localized("production.scriptSegment"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
                Text(segment.sourceText)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if items.isEmpty {
                Text(appState.localized("editing.segmentEmpty"))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
            } else {
                VStack(spacing: 12) {
                    ForEach(items) { item in
                        EditingItemEditor(
                            item: item,
                            duplicateAction: { duplicateAction(item) },
                            deleteAction: { deleteAction(item) }
                        )
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    addEmptyAction()
                } label: {
                    Label(appState.localized("editing.addEmpty"), systemImage: "plus")
                }
                .buttonStyle(.cursorPlain)

                Menu(appState.localized("production.usePreset")) {
                    ForEach(EditingTemplatePreset.allCases) { preset in
                        Button(preset.title(appState: appState)) {
                            addPresetAction(preset)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .font(.system(size: 13, weight: .medium))
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.divider, lineWidth: 1)
                )
        }
    }
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
