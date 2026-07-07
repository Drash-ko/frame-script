import SwiftUI

struct BRollEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Bindable var scene: Scene
    @State private var isTemplatePickerPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                EditorModeHeader(
                    title: scene.title,
                    subtitle: appState.localized("broll.linkedSubtitle"),
                    sourceText: scene.scriptText
                )

                if scene.bRollItems.isEmpty {
                    EmptyModeState(
                        title: appState.localized("broll.emptyTitle"),
                        message: appState.localized("broll.emptyMessage"),
                        actionTitle: appState.localized("broll.addItem"),
                        action: { isTemplatePickerPresented = true }
                    )
                } else {
                    VStack(spacing: 14) {
                        ForEach(scene.bRollItems) { item in
                            BRollItemEditor(
                                item: item,
                                duplicateAction: { duplicateItem(item) },
                                deleteAction: { deleteItem(item) }
                            )
                        }
                    }

                    Button(appState.localized("broll.addItem")) {
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
        .confirmationDialog(appState.localized("broll.templatePickerTitle"), isPresented: $isTemplatePickerPresented) {
            ForEach(BRollTemplatePreset.allCases) { preset in
                Button(preset.title(appState: appState)) {
                    addItem(from: preset)
                }
            }
            Button(appState.localized("project.unsaved.cancel"), role: .cancel) {}
        }
        .onChange(of: scene.bRollItems.count) { _, _ in appState.touchProject() }
    }

    private func addItem(from preset: BRollTemplatePreset) {
        scene.bRollItems.append(
            BRollItem(
                id: UUID(),
                linkedSegmentID: scene.textSegments.first?.id,
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

private struct BRollItemEditor: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Bindable var item: BRollItem
    let duplicateAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(appState.localized("broll.item"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryText)

                Spacer()

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

            HStack(spacing: 12) {
                Picker(appState.localized("broll.source"), selection: $item.sourceType) {
                    ForEach(BRollSourceType.allCases) { source in
                        Text(appState.displayName(source)).tag(source)
                    }
                }
                .labelsHidden()
                .frame(width: 190)

                TextField(appState.localized("templates.name"), text: $item.templateType)
                    .textFieldStyle(QuietTextFieldStyle())

                Picker(appState.localized("broll.status"), selection: $item.status) {
                    ForEach(BRollStatus.allCases) { status in
                        Text(appState.displayName(status)).tag(status)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }

            QuietField(appState.localized("broll.description")) {
                MultilineField(placeholder: appState.localized("broll.descriptionPlaceholder"), text: $item.descriptionText)
            }

            HStack(spacing: 12) {
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

            QuietField(appState.localized("script.notes")) {
                MultilineField(placeholder: appState.localized("broll.notesPlaceholder"), text: $item.notes, minHeight: 70)
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
        .onChange(of: item.sourceType) { _, _ in appState.touchProject() }
        .onChange(of: item.status) { _, _ in appState.touchProject() }
        .onChange(of: item.descriptionText) { _, _ in appState.touchProject() }
        .onChange(of: item.mood) { _, _ in appState.touchProject() }
        .onChange(of: item.framing) { _, _ in appState.touchProject() }
        .onChange(of: item.motion) { _, _ in appState.touchProject() }
        .onChange(of: item.duration) { _, _ in appState.touchProject() }
        .onChange(of: item.notes) { _, _ in appState.touchProject() }
    }
}
