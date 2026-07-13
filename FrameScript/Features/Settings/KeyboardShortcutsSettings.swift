import AppKit
import SwiftUI

struct KeyboardShortcutsSettings: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Binding var settings: AppSettings
    @State private var recording: ShortcutCommand?
    @State private var pendingBinding: ShortcutBinding?
    @State private var conflict: ShortcutCommand?
    @State private var showResetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(appState.localized("settings.keyboardShortcuts"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Button(appState.localized("shortcuts.resetAll")) { showResetConfirmation = true }
                    .font(.system(size: 12))
                    .buttonStyle(.borderless)
                    .disabled(settings.shortcutOverrides.isEmpty)
                    .clickableCursor(enabled: !settings.shortcutOverrides.isEmpty)
            }
            ForEach(ShortcutSettingsLayout.categoryCards) { card in
                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.localized(card.category.localizationKey))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                    SettingsCard {
                        ForEach(card.definitions) { definition in
                            row(for: definition)
                        }
                    }
                }
            }
        }
        .alert(appState.localized("shortcuts.resetAll.title"), isPresented: $showResetConfirmation) {
            Button(appState.localized("dialog.ok"), role: .destructive) { settings.resetAllShortcuts() }
            Button(appState.localized("project.unsaved.cancel"), role: .cancel) { }
        } message: { Text(appState.localized("shortcuts.resetAll.message")) }
    }

    @ViewBuilder private func row(for definition: ShortcutDefinition) -> some View {
        let state = ShortcutSettingsLayout.rowState(
            for: definition,
            customizedCommands: Set(settings.shortcutOverrides.keys),
            recording: recording
        )

        SettingsRow(appState.localized(definition.localizationKey), isHighlighted: state.isRecording) {
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    shortcutKeycap(for: definition.command, isRecording: state.isRecording)
                    if state.isRecording {
                        ShortcutRecordingField { binding in
                            pendingBinding = binding
                            conflict = nil
                        } onCancel: {
                            cancelRecording()
                        }
                        .frame(width: 1, height: 1)
                        .accessibilityLabel(appState.localized("shortcuts.recording"))

                        if pendingBinding != nil {
                            ShortcutSettingsActionButton(appState.localized("shortcuts.save")) {
                                savePending(for: definition.command)
                            }
                        }
                        ShortcutSettingsActionButton(appState.localized("project.unsaved.cancel")) {
                            cancelRecording()
                        }
                    } else {
                        ShortcutSettingsActionButton(appState.localized("shortcuts.edit")) {
                            recording = definition.command
                            pendingBinding = nil
                            conflict = nil
                        }
                    }
                    if state.showsReset {
                        ShortcutSettingsActionButton(appState.localized("shortcuts.reset")) {
                            settings.resetShortcut(definition.command)
                        }
                    }
                }
                if state.isRecording, let conflict {
                    Text(String(format: appState.localized("shortcuts.conflict"), appState.localized(conflict.definition.localizationKey)))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.destructive)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private func shortcutKeycap(for command: ShortcutCommand, isRecording: Bool) -> some View {
        Text(isRecording ? appState.localized("shortcuts.pressShortcut") : settings.shortcut(for: command).display)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(theme.primaryText)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .frame(minHeight: 26)
            .background(theme.panelBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(theme.divider, lineWidth: 1)
            }
            .accessibilityLabel(isRecording ? appState.localized("shortcuts.pressShortcut") : settings.shortcut(for: command).display)
    }

    private func savePending(for command: ShortcutCommand) {
        guard let pendingBinding else { return }
        if let conflictingCommand = settings.setShortcut(pendingBinding, for: command) { conflict = conflictingCommand; return }
        cancelRecording()
    }

    private func cancelRecording() { recording = nil; pendingBinding = nil; conflict = nil }
}

private struct ShortcutSettingsActionButton: View {
    @Environment(\.frameTheme) private var theme
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.primaryText)
            .buttonStyle(.borderless)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
            .clickableCursor()
            .accessibilityLabel(title)
    }
}

struct ShortcutSettingsCategoryCard: Identifiable {
    let category: ShortcutCategory
    let definitions: [ShortcutDefinition]

    var id: ShortcutCategory { category }
}

struct ShortcutSettingsRowState {
    let isCustomized: Bool
    let isRecording: Bool

    var showsReset: Bool { isCustomized }
}

enum ShortcutSettingsLayout {
    static let categoryCards = ShortcutCategory.allCases.map { category in
        ShortcutSettingsCategoryCard(
            category: category,
            definitions: ShortcutRegistry.definitions
                .filter { $0.category == category }
                .sorted { $0.order < $1.order }
        )
    }

    static func rowState(
        for definition: ShortcutDefinition,
        customizedCommands: Set<ShortcutCommand>,
        recording: ShortcutCommand?
    ) -> ShortcutSettingsRowState {
        ShortcutSettingsRowState(
            isCustomized: customizedCommands.contains(definition.command),
            isRecording: recording == definition.command
        )
    }
}

/// A responder-backed field gives shortcut recording priority without a global event monitor.
private struct ShortcutRecordingField: NSViewRepresentable {
    let onRecord: (ShortcutBinding) -> Void
    let onCancel: () -> Void
    func makeNSView(context: Context) -> ShortcutCaptureView {
        let view = ShortcutCaptureView(); view.onRecord = onRecord; view.onCancel = onCancel
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }; return view
    }
    func updateNSView(_ nsView: ShortcutCaptureView, context: Context) {
        nsView.onRecord = onRecord; nsView.onCancel = onCancel
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }
}

private final class ShortcutCaptureView: NSView {
    var onRecord: ((ShortcutBinding) -> Void)?
    var onCancel: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?(); return }
        let modifiers = shortcutModifiers(from: event.modifierFlags)
        let binding: ShortcutBinding?
        switch event.keyCode {
        case 51: binding = .init(key: .delete, modifiers: modifiers)
        case 117: binding = .init(key: .forwardDelete, modifiers: modifiers)
        case 123: binding = .init(key: .leftArrow, modifiers: modifiers)
        case 124: binding = .init(key: .rightArrow, modifiers: modifiers)
        case 125: binding = .init(key: .downArrow, modifiers: modifiers)
        case 126: binding = .init(key: .upArrow, modifiers: modifiers)
        default: binding = event.charactersIgnoringModifiers.map { ShortcutBinding($0.lowercased(), modifiers: modifiers) }
        }
        guard let binding, binding.isValid else { return }
        onRecord?(binding)
    }
    private func shortcutModifiers(from flags: NSEvent.ModifierFlags) -> Set<ShortcutModifier> {
        var modifiers: Set<ShortcutModifier> = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }
}
