import AppKit
import SwiftUI

struct KeyboardShortcutsSettings: View {
    @Environment(AppState.self) private var appState
    @Binding var settings: AppSettings
    @State private var recording: ShortcutCommand?
    @State private var pendingBinding: ShortcutBinding?
    @State private var conflict: ShortcutCommand?
    @State private var showResetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(appState.localized("settings.keyboardShortcuts")).font(.system(size: 22, weight: .semibold))
                Spacer()
                Button(appState.localized("shortcuts.resetAll")) { showResetConfirmation = true }
                    .disabled(settings.shortcutOverrides.isEmpty)
            }
            ForEach(ShortcutCategory.allCases, id: \.self) { category in
                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.localized(category.localizationKey)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(ShortcutRegistry.definitions.filter { $0.category == category }.sorted { $0.order < $1.order }) { definition in row(for: definition) }
                }
            }
        }
        .alert(appState.localized("shortcuts.resetAll.title"), isPresented: $showResetConfirmation) {
            Button(appState.localized("dialog.ok"), role: .destructive) { settings.resetAllShortcuts() }
            Button(appState.localized("project.unsaved.cancel"), role: .cancel) { }
        } message: { Text(appState.localized("shortcuts.resetAll.message")) }
    }

    @ViewBuilder private func row(for definition: ShortcutDefinition) -> some View {
        let command = definition.command
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(appState.localized(definition.localizationKey)).frame(maxWidth: .infinity, alignment: .leading)
                Text(((recording == command ? pendingBinding : nil) ?? settings.shortcut(for: command)).display).font(.system(size: 12, weight: .semibold, design: .rounded)).padding(.horizontal, 7).padding(.vertical, 4).background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                if recording == command {
                    ShortcutRecordingField { binding in pendingBinding = binding; conflict = nil } onCancel: { cancelRecording() }
                        .frame(width: 1, height: 1).accessibilityLabel(appState.localized("shortcuts.recording"))
                    Button(appState.localized(pendingBinding == nil ? "shortcuts.recording" : "shortcuts.save")) { savePending(for: command) }.disabled(pendingBinding == nil)
                    Button(appState.localized("project.unsaved.cancel")) { cancelRecording() }
                } else {
                    Button(appState.localized("shortcuts.edit")) { recording = command; pendingBinding = nil; conflict = nil }
                }
                if settings.shortcutOverrides[command] != nil { Button(appState.localized("shortcuts.reset")) { settings.resetShortcut(command) } }
            }
            .padding(.horizontal, 12).frame(minHeight: 38).background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            if recording == command, pendingBinding == nil { Text(appState.localized("shortcuts.recordingHint")).font(.caption).foregroundStyle(.secondary) }
            if recording == command, let conflict { Text(String(format: appState.localized("shortcuts.conflict"), appState.localized(conflict.definition.localizationKey))).font(.caption).foregroundStyle(.red) }
        }
    }

    private func savePending(for command: ShortcutCommand) {
        guard let pendingBinding else { return }
        if let conflictingCommand = settings.setShortcut(pendingBinding, for: command) { conflict = conflictingCommand; return }
        cancelRecording()
    }

    private func cancelRecording() { recording = nil; pendingBinding = nil; conflict = nil }
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
