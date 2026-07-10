import SwiftUI

struct EditingEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Bindable var scene: Scene

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EditorModeHeader(title: scene.title, subtitle: appState.localized("editing.linkedSubtitle"))
                    if scene.scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && scene.editingItems.isEmpty {
                        EmptyProductionState(message: appState.localized("editing.writeScriptFirst"))
                    } else {
                        ForEach(scene.textSegments.sortedByOrder) { segment in segmentSection(segment).id(segment.id) }
                        if !unlinkedItems.isEmpty {
                            ProductionUnlinkedBlock(title: appState.localized("production.unlinked")) {
                                ForEach(unlinkedItems) { item in itemEditor(item) }
                            }
                        }
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 32).padding(.vertical, 32).frame(maxWidth: .infinity)
            }
            .onAppear { appState.rebuildProductionSegments(markUnsaved: false); scrollToSelection(proxy) }
            .onChange(of: appState.editorState.selectedProductionSegmentID) { _, _ in scrollToSelection(proxy) }
        }
        .background(theme.editorSurface)
        .onChange(of: scene.editingItems.count) { _, _ in appState.touchProject() }
    }

    private func segmentSection(_ segment: TextSegment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(segment.sourceText).font(.system(size: 13)).foregroundStyle(theme.secondaryText).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true).padding(.leading, 9)
                .overlay(alignment: .leading) { Capsule().fill(theme.editingMarker).frame(width: 3) }
            ForEach(items(for: segment)) { item in itemEditor(item) }
            HStack(spacing: 10) {
                Button { addEmptyItem(linkedTo: segment.id) } label: { Label(appState.localized("editing.addEmpty"), systemImage: "plus") }
                Menu(appState.localized("production.usePreset")) {
                    ForEach(EditingPreset.allCases) { preset in Button(preset.title(appState)) { addItem(from: preset, linkedTo: segment.id) } }
                }.menuStyle(.borderlessButton).fixedSize()
            }.font(.system(size: 12, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10).overlay(alignment: .bottom) { Divider() }
    }

    private func itemEditor(_ item: EditingItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(theme.editingMarker).frame(width: 7, height: 7)
                Text(appState.localized("editing.item")).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.secondaryText)
                Spacer(minLength: 8)
                linkMenu(item)
                EditorIconButton(systemName: "plus.square.on.square", accessibilityLabel: appState.localized("editing.duplicateItem")) { duplicateItem(item) }
                EditorIconButton(systemName: "trash", accessibilityLabel: appState.localized("editing.deleteItem"), role: .destructive) { deleteItem(item) }
            }
            QuietField(appState.localized("editing.description")) {
                MultilineField(placeholder: appState.localized("editing.descriptionPlaceholder"), text: Bindable(item).cutStyle, minHeight: 68)
            }
            QuietField(appState.localized("editing.notes")) {
                MultilineField(placeholder: appState.localized("editing.notesPlaceholder"), text: Bindable(item).notes, minHeight: 54)
            }
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 7).fill(theme.background.opacity(0.42)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.divider))
        .onChange(of: item.cutStyle) { _, _ in appState.touchProject() }.onChange(of: item.notes) { _, _ in appState.touchProject() }
    }

    private func linkMenu(_ item: EditingItem) -> some View {
        Menu {
            ForEach(Array(scene.textSegments.sortedByOrder.enumerated()), id: \.element.id) { index, segment in
                Button(segmentTitle(index, segment)) {
                    item.linkedSegmentID = segment.id
                    item.textAnchor = appState.projectStore.anchor(for: segment.id, in: scene)
                    appState.touchProject()
                }
            }
            Divider(); Button(appState.localized("production.unlinked")) {
                item.linkedSegmentID = nil
                item.textAnchor = nil
                appState.touchProject()
            }
        } label: { Label(linkLabel(item), systemImage: "link").font(.system(size: 12, weight: .medium)) }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private func items(for segment: TextSegment) -> [EditingItem] { scene.editingItems.filter { $0.linkedSegmentID == segment.id } }
    private var unlinkedItems: [EditingItem] {
        let ids = Set(scene.textSegments.map(\.id)); return scene.editingItems.filter { $0.linkedSegmentID.map { !ids.contains($0) } ?? true }
    }
    private func addEmptyItem(linkedTo id: UUID) { scene.editingItems.append(EditingItem(textAnchor: appState.projectStore.anchor(for: id, in: scene), linkedSegmentID: id, templateType: "", cutStyle: "", transition: "", subtitleStyle: "")); appState.touchProject() }
    private func addItem(from preset: EditingPreset, linkedTo id: UUID) { scene.editingItems.append(EditingItem(textAnchor: appState.projectStore.anchor(for: id, in: scene), linkedSegmentID: id, templateType: "", cutStyle: preset.description(appState), transition: "", subtitleStyle: "", notes: preset.notes(appState))); appState.touchProject() }
    private func duplicateItem(_ item: EditingItem) {
        let copy = EditingItem(textAnchor: item.textAnchor, linkedSegmentID: item.linkedSegmentID, templateType: "", cutStyle: item.cutStyle, transition: "", subtitleStyle: "", notes: item.notes)
        if let index = scene.editingItems.firstIndex(where: { $0.id == item.id }) { scene.editingItems.insert(copy, at: index + 1) } else { scene.editingItems.append(copy) }; appState.touchProject()
    }
    private func deleteItem(_ item: EditingItem) { scene.editingItems.removeAll { $0.id == item.id }; appState.touchProject() }
    private func linkLabel(_ item: EditingItem) -> String {
        guard let id = item.linkedSegmentID, let index = scene.textSegments.sortedByOrder.firstIndex(where: { $0.id == id }) else { return appState.localized("production.unlinked") }; return String(format: "%02d", index + 1)
    }
    private func segmentTitle(_ index: Int, _ segment: TextSegment) -> String { "\(String(format: "%02d", index + 1)) \(segment.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(42))" }
    private func scrollToSelection(_ proxy: ScrollViewProxy) { guard let id = appState.editorState.selectedProductionSegmentID else { return }; DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) } } }
}

private enum EditingPreset: String, CaseIterable, Identifiable {
    case minimal, educational, storytelling, fastSocial, documentary, custom
    var id: String { rawValue }
    @MainActor func title(_ app: AppState) -> String { app.localized("editing.template.\(rawValue)") }
    @MainActor func description(_ app: AppState) -> String { app.localized("editing.template.\(rawValue).cutStyle") }
    @MainActor func notes(_ app: AppState) -> String { app.localized("editing.template.\(rawValue).notes") }
}
