import SwiftUI

struct BRollEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Bindable var scene: Scene

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                EditorModeHeader(
                    title: scene.title,
                    subtitle: appState.localized("broll.linkedSubtitle")
                )

                if scene.scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && scene.bRollItems.isEmpty {
                    EmptyProductionState(message: appState.localized("broll.writeScriptFirst"))
                } else {
                    if !scene.textSegments.isEmpty {
                        VStack(spacing: 16) {
                            ForEach(scene.textSegments.sortedByOrder) { segment in
                                BRollSegmentBlock(
                                    segment: segment,
                                    allSegments: scene.textSegments.sortedByOrder,
                                    items: items(for: segment),
                                    addEmptyAction: { addEmptyItem(linkedTo: segment.id) },
                                    addPresetAction: { addItem(from: $0, linkedTo: segment.id) },
                                    duplicateAction: duplicateItem,
                                    deleteAction: deleteItem
                                )
                            }
                        }
                    }

                    let unlinked = unlinkedItems
                    if !unlinked.isEmpty {
                        ProductionUnlinkedBlock(title: appState.localized("production.unlinked")) {
                            ForEach(unlinked) { item in
                                BRollItemEditor(
                                    item: item,
                                    segments: scene.textSegments.sortedByOrder,
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
        .onChange(of: scene.bRollItems.count) { _, _ in appState.touchProject() }
    }

    private func items(for segment: TextSegment) -> [BRollItem] {
        scene.bRollItems.filter { $0.linkedSegmentID == segment.id }
    }

    private var unlinkedItems: [BRollItem] {
        let validIDs = Set(scene.textSegments.map(\.id))
        return scene.bRollItems.filter { item in
            guard let linkedID = item.linkedSegmentID else { return true }
            return !validIDs.contains(linkedID)
        }
    }

    private func addEmptyItem(linkedTo segmentID: UUID) {
        scene.bRollItems.append(
            BRollItem(
                id: UUID(),
                linkedSegmentID: segmentID,
                templateType: "",
                sourceType: .custom,
                descriptionText: "",
                status: .idea
            )
        )
        appState.touchProject()
    }

    private func addItem(from preset: BRollTemplatePreset, linkedTo segmentID: UUID) {
        scene.bRollItems.append(
            BRollItem(
                id: UUID(),
                linkedSegmentID: segmentID,
                templateType: preset.title(appState: appState),
                sourceType: preset.sourceType,
                descriptionText: preset.description(appState: appState),
                mood: preset.mood(appState: appState),
                framing: preset.framing(appState: appState),
                motion: preset.motion(appState: appState),
                duration: preset.duration,
                notes: preset.notes(appState: appState),
                status: .idea
            )
        )
        appState.touchProject()
    }

    private func duplicateItem(_ item: BRollItem) {
        let copy = BRollItem(
            linkedSegmentID: item.linkedSegmentID,
            templateType: item.templateType,
            sourceType: item.sourceType,
            descriptionText: item.descriptionText,
            mood: item.mood,
            framing: item.framing,
            motion: item.motion,
            duration: item.duration,
            notes: item.notes,
            status: item.status
        )

        if let index = scene.bRollItems.firstIndex(where: { $0.id == item.id }) {
            scene.bRollItems.insert(copy, at: scene.bRollItems.index(after: index))
        } else {
            scene.bRollItems.append(copy)
        }
        appState.touchProject()
    }

    private func deleteItem(_ item: BRollItem) {
        scene.bRollItems.removeAll { $0.id == item.id }
        appState.touchProject()
    }
}

private enum BRollTemplatePreset: String, CaseIterable, Identifiable {
    case stockFootage
    case screenRecording
    case talkingHead
    case textOnScreen
    case animation
    case infographic
    case custom

    var id: String { rawValue }

    var sourceType: BRollSourceType {
        switch self {
        case .stockFootage: .stockFootage
        case .screenRecording: .screenRecording
        case .talkingHead: .talkingHead
        case .textOnScreen: .textOnScreen
        case .animation: .animation
        case .infographic: .infographic
        case .custom: .custom
        }
    }

    var duration: TimeInterval {
        switch self {
        case .talkingHead: 6
        case .textOnScreen, .animation, .infographic: 5
        default: 4
        }
    }

    @MainActor func title(appState: AppState) -> String { appState.localized("broll.template.\(rawValue)") }
    @MainActor func description(appState: AppState) -> String { appState.localized("broll.template.\(rawValue).description") }
    @MainActor func mood(appState: AppState) -> String { appState.localized("broll.template.\(rawValue).mood") }
    @MainActor func framing(appState: AppState) -> String { appState.localized("broll.template.\(rawValue).framing") }
    @MainActor func motion(appState: AppState) -> String { appState.localized("broll.template.\(rawValue).motion") }
    @MainActor func notes(appState: AppState) -> String { appState.localized("broll.template.\(rawValue).notes") }
}

private struct BRollSegmentBlock: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    let segment: TextSegment
    let allSegments: [TextSegment]
    let items: [BRollItem]
    let addEmptyAction: () -> Void
    let addPresetAction: (BRollTemplatePreset) -> Void
    let duplicateAction: (BRollItem) -> Void
    let deleteAction: (BRollItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(appState.localized("production.scriptSegment"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
                Text(segment.sourceText)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if items.isEmpty {
                Text(appState.localized("broll.segmentEmpty"))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
            } else {
                VStack(spacing: 12) {
                    ForEach(items) { item in
                        BRollItemEditor(
                            item: item,
                            segments: allSegments,
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
                    HStack(spacing: 6) {
                        Circle()
                            .fill(theme.bRollMarker)
                            .frame(width: 7, height: 7)
                        Image(systemName: "plus")
                        Text(appState.localized("broll.addEmpty"))
                    }
                }
                .buttonStyle(.cursorPlain)

                Menu(appState.localized("production.usePreset")) {
                    ForEach(BRollTemplatePreset.allCases) { preset in
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 136, alignment: .topLeading)
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

private struct BRollItemEditor: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Bindable var item: BRollItem
    let segments: [TextSegment]
    let duplicateAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(theme.bRollMarker)
                    .frame(width: 7, height: 7)

                Text(appState.localized("broll.item"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryText)

                Spacer()

                linkMenu

                EditorIconButton(
                    systemName: "plus.square.on.square",
                    accessibilityLabel: appState.localized("broll.duplicateItem"),
                    action: duplicateAction
                )
                EditorIconButton(
                    systemName: "trash",
                    accessibilityLabel: appState.localized("broll.deleteItem"),
                    role: .destructive,
                    action: deleteAction
                )
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 12) {
                    QuietField(appState.localized("broll.source")) {
                        Picker("", selection: $item.sourceType) {
                            ForEach(BRollSourceType.allCases) { source in
                                Text(appState.displayName(source)).tag(source)
                            }
                        }
                        .labelsHidden()
                    }
                    .frame(width: 180)

                    QuietField(appState.localized("templates.name")) {
                        TextField(appState.localized("templates.name"), text: $item.templateType)
                            .textFieldStyle(QuietTextFieldStyle())
                    }

                    QuietField(appState.localized("broll.status")) {
                        Picker("", selection: $item.status) {
                            ForEach(BRollStatus.allCases) { status in
                                Text(appState.displayName(status)).tag(status)
                            }
                        }
                        .labelsHidden()
                    }
                    .frame(width: 130)
                }

                VStack(alignment: .leading, spacing: 12) {
                    QuietField(appState.localized("broll.source")) {
                        Picker("", selection: $item.sourceType) {
                            ForEach(BRollSourceType.allCases) { source in
                                Text(appState.displayName(source)).tag(source)
                            }
                        }
                        .labelsHidden()
                    }
                    QuietField(appState.localized("templates.name")) {
                        TextField(appState.localized("templates.name"), text: $item.templateType)
                            .textFieldStyle(QuietTextFieldStyle())
                    }
                    QuietField(appState.localized("broll.status")) {
                        Picker("", selection: $item.status) {
                            ForEach(BRollStatus.allCases) { status in
                                Text(appState.displayName(status)).tag(status)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }

            QuietField(appState.localized("broll.description")) {
                MultilineField(placeholder: appState.localized("broll.descriptionPlaceholder"), text: $item.descriptionText)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    bRollDetailFields
                }
                VStack(alignment: .leading, spacing: 12) {
                    bRollDetailFields
                }
            }

            QuietField(appState.localized("script.notes")) {
                MultilineField(placeholder: appState.localized("broll.notesPlaceholder"), text: $item.notes, minHeight: 70)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 178, alignment: .topLeading)
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
        .onChange(of: item.sourceType) { _, _ in appState.touchProject() }
        .onChange(of: item.status) { _, _ in appState.touchProject() }
        .onChange(of: item.descriptionText) { _, _ in appState.touchProject() }
        .onChange(of: item.mood) { _, _ in appState.touchProject() }
        .onChange(of: item.framing) { _, _ in appState.touchProject() }
        .onChange(of: item.motion) { _, _ in appState.touchProject() }
        .onChange(of: item.duration) { _, _ in appState.touchProject() }
        .onChange(of: item.notes) { _, _ in appState.touchProject() }
    }

    @ViewBuilder
    private var bRollDetailFields: some View {
        QuietField(appState.localized("broll.mood")) {
            TextField(appState.localized("broll.moodPlaceholder"), text: $item.mood)
                .textFieldStyle(QuietTextFieldStyle())
        }
        QuietField(appState.localized("broll.framing")) {
            TextField(appState.localized("broll.framingPlaceholder"), text: $item.framing)
                .textFieldStyle(QuietTextFieldStyle())
        }
        QuietField(appState.localized("broll.motion")) {
            TextField(appState.localized("broll.motionPlaceholder"), text: $item.motion)
                .textFieldStyle(QuietTextFieldStyle())
        }
    }

    private var linkMenu: some View {
        Menu {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                Button(segmentMenuTitle(index: index, segment: segment)) {
                    item.linkedSegmentID = segment.id
                    appState.touchProject()
                }
            }
            Divider()
            Button(appState.localized("production.unlinked")) {
                item.linkedSegmentID = nil
                appState.touchProject()
            }
        } label: {
            Label(linkLabel, systemImage: "link")
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var linkLabel: String {
        guard let linkedID = item.linkedSegmentID,
              let index = segments.firstIndex(where: { $0.id == linkedID }) else {
            return appState.localized("production.unlinked")
        }
        return String(format: "%02d", index + 1)
    }

    private func segmentMenuTitle(index: Int, segment: TextSegment) -> String {
        let preview = segment.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = preview.count > 42 ? "\(preview.prefix(42))..." : preview
        return "\(String(format: "%02d", index + 1)) \(clipped)"
    }
}
