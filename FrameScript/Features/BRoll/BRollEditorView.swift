import SwiftUI

struct BRollEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Bindable var scene: Scene

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EditorModeHeader(title: scene.title, subtitle: appState.localized("broll.linkedSubtitle"))
                    if scene.scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && scene.bRollItems.isEmpty {
                        EmptyProductionState(message: appState.localized("broll.writeScriptFirst"))
                    } else {
                        ForEach(scene.textSegments.sortedByOrder) { segment in
                            segmentSection(segment).id(segment.id)
                        }
                        if !unlinkedItems.isEmpty {
                            ProductionUnlinkedBlock(title: appState.localized("production.unlinked")) {
                                ForEach(unlinkedItems) { item in itemEditor(item) }
                            }
                        }
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                appState.rebuildProductionSegments(markUnsaved: false)
                scrollToSelection(proxy)
            }
            .onChange(of: appState.editorState.selectedProductionSegmentID) { _, _ in scrollToSelection(proxy) }
        }
        .background(theme.editorSurface)
        .onChange(of: scene.bRollItems.count) { _, _ in appState.touchProject() }
    }

    private func segmentSection(_ segment: TextSegment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(segment.sourceText)
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 9)
                .overlay(alignment: .leading) { Capsule().fill(theme.bRollMarker).frame(width: 3) }

            ForEach(items(for: segment)) { item in itemEditor(item) }

            HStack(spacing: 10) {
                Button { addEmptyItem(linkedTo: segment.id) } label: {
                    Label(appState.localized("broll.addEmpty"), systemImage: "plus")
                }
                Menu(appState.localized("production.usePreset")) {
                    ForEach(BRollPreset.allCases) { preset in
                        Button(preset.title(appState)) { addItem(from: preset, linkedTo: segment.id) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .font(.system(size: 12, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func itemEditor(_ item: BRollItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(theme.bRollMarker).frame(width: 7, height: 7)
                Text(appState.localized("broll.item")).font(.system(size: 12, weight: .medium)).foregroundStyle(theme.secondaryText)
                Spacer(minLength: 8)
                linkMenu(item)
                EditorIconButton(systemName: "plus.square.on.square", accessibilityLabel: appState.localized("broll.duplicateItem")) { duplicateItem(item) }
                EditorIconButton(systemName: "trash", accessibilityLabel: appState.localized("broll.deleteItem"), role: .destructive) { deleteItem(item) }
            }
            QuietField(appState.localized("broll.source")) {
                Picker("", selection: Bindable(item).sourceType) {
                    ForEach(BRollSourceType.allCases) { Text(appState.displayName($0)).tag($0) }
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
            }
            QuietField(appState.localized("broll.description")) {
                MultilineField(placeholder: appState.localized("broll.descriptionPlaceholder"), text: Bindable(item).descriptionText, minHeight: 62)
            }
            QuietField(appState.localized("script.notes")) {
                MultilineField(placeholder: appState.localized("broll.notesPlaceholder"), text: Bindable(item).notes, minHeight: 54)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 7).fill(theme.background.opacity(0.42)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.divider))
        .onChange(of: item.sourceType) { _, _ in appState.touchProject() }
        .onChange(of: item.descriptionText) { _, _ in appState.touchProject() }
        .onChange(of: item.notes) { _, _ in appState.touchProject() }
    }

    private func linkMenu(_ item: BRollItem) -> some View {
        Menu {
            ForEach(Array(scene.textSegments.sortedByOrder.enumerated()), id: \.element.id) { index, segment in
                Button(segmentTitle(index, segment)) {
                    item.linkedSegmentID = segment.id
                    item.textAnchor = appState.projectStore.anchor(for: segment.id, in: scene)
                    appState.touchProject()
                }
            }
            Divider()
            Button(appState.localized("production.unlinked")) {
                item.linkedSegmentID = nil
                item.textAnchor = nil
                appState.touchProject()
            }
        } label: { Label(linkLabel(item), systemImage: "link").font(.system(size: 12, weight: .medium)) }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private func items(for segment: TextSegment) -> [BRollItem] { scene.bRollItems.filter { $0.linkedSegmentID == segment.id } }
    private var unlinkedItems: [BRollItem] {
        let ids = Set(scene.textSegments.map(\.id)); return scene.bRollItems.filter { $0.linkedSegmentID.map { !ids.contains($0) } ?? true }
    }
    private func addEmptyItem(linkedTo id: UUID) {
        scene.bRollItems.append(BRollItem(textAnchor: appState.projectStore.anchor(for: id, in: scene), linkedSegmentID: id, templateType: "", sourceType: .custom, descriptionText: "")); appState.touchProject()
    }
    private func addItem(from preset: BRollPreset, linkedTo id: UUID) {
        scene.bRollItems.append(BRollItem(textAnchor: appState.projectStore.anchor(for: id, in: scene), linkedSegmentID: id, templateType: "", sourceType: preset.source, descriptionText: preset.description(appState), notes: preset.notes(appState))); appState.touchProject()
    }
    private func duplicateItem(_ item: BRollItem) {
        let copy = BRollItem(textAnchor: item.textAnchor, linkedSegmentID: item.linkedSegmentID, templateType: "", sourceType: item.sourceType, descriptionText: item.descriptionText, notes: item.notes)
        if let index = scene.bRollItems.firstIndex(where: { $0.id == item.id }) { scene.bRollItems.insert(copy, at: index + 1) } else { scene.bRollItems.append(copy) }
        appState.touchProject()
    }
    private func deleteItem(_ item: BRollItem) { scene.bRollItems.removeAll { $0.id == item.id }; appState.touchProject() }
    private func linkLabel(_ item: BRollItem) -> String {
        guard let id = item.linkedSegmentID, let index = scene.textSegments.sortedByOrder.firstIndex(where: { $0.id == id }) else { return appState.localized("production.unlinked") }
        return String(format: "%02d", index + 1)
    }
    private func segmentTitle(_ index: Int, _ segment: TextSegment) -> String {
        let value = segment.sourceText.trimmingCharacters(in: .whitespacesAndNewlines); return "\(String(format: "%02d", index + 1)) \(value.prefix(42))"
    }
    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        guard let id = appState.editorState.selectedProductionSegmentID else { return }
        DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) } }
    }
}

private enum BRollPreset: String, CaseIterable, Identifiable {
    case stockFootage, screenRecording, talkingHead, textOnScreen, animation, infographic, custom
    var id: String { rawValue }
    var source: BRollSourceType {
        switch self { case .stockFootage: .stockFootage; case .screenRecording: .screenRecording; case .talkingHead: .talkingHead; case .textOnScreen: .textOnScreen; case .animation: .animation; case .infographic: .infographic; case .custom: .custom }
    }
    @MainActor func title(_ app: AppState) -> String { app.localized("broll.template.\(rawValue)") }
    @MainActor func description(_ app: AppState) -> String { app.localized("broll.template.\(rawValue).description") }
    @MainActor func notes(_ app: AppState) -> String { app.localized("broll.template.\(rawValue).notes") }
}
