import AppKit
import SwiftUI

struct KeyboardShortcutsSettings: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Binding var settings: AppSettings
    @State private var recording: ShortcutCommand?
    @State private var pendingBinding: ShortcutBinding?
    @State private var reassignPrompt: ShortcutReassignPrompt?
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
        .alert(appState.localized("shortcuts.reassign.title"), isPresented: isReassignPromptPresented) {
            Button(appState.localized("shortcuts.reassign")) {
                if let prompt = reassignPrompt {
                    switch prompt.action {
                    case let .assign(binding):
                        _ = settings.reassignShortcut(binding, for: prompt.destination)
                    case .reset:
                        _ = settings.reassignFactoryDefault(to: prompt.destination)
                    }
                }
                cancelRecording()
            }
            Button(appState.localized("project.unsaved.cancel"), role: .cancel) {
                // Keep both bindings unchanged and end the capture session.
                cancelRecording()
            }
        } message: {
            if let prompt = reassignPrompt {
                Text(String(
                    format: appState.localized("shortcuts.reassign.message"),
                    appState.localized(prompt.conflicting.definition.localizationKey),
                    appState.localized(prompt.destination.definition.localizationKey)
                ))
            }
        }
        .onDisappear { cancelRecording() }
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
                            ShortcutCaptureSession.stopActiveSession()
                            recording = definition.command
                            pendingBinding = nil
                        }
                    }
                    if state.showsReset {
                        ShortcutSettingsActionButton(appState.localized("shortcuts.reset")) {
                            reset(definition.command)
                        }
                    }
                }
            }
        }
    }

    private func shortcutKeycap(for command: ShortcutCommand, isRecording: Bool) -> some View {
        let label = isRecording
            ? appState.localized("shortcuts.pressShortcut")
            : settings.activeShortcut(for: command)?.display ?? appState.localized("shortcuts.notAssigned")
        return Text(label)
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
            .accessibilityLabel(label)
    }

    private func savePending(for command: ShortcutCommand) {
        guard let pendingBinding else { return }
        if let conflictingCommand = ShortcutRegistry.conflict(
            for: pendingBinding,
            excluding: command,
            overrides: settings.shortcutOverrides
        ) {
            reassignPrompt = .init(
                destination: command,
                conflicting: conflictingCommand,
                action: .assign(pendingBinding)
            )
            return
        }
        _ = settings.setShortcut(pendingBinding, for: command)
        cancelRecording()
    }

    private func reset(_ command: ShortcutCommand) {
        if let conflictingCommand = settings.resetConflict(for: command) {
            reassignPrompt = .init(destination: command, conflicting: conflictingCommand, action: .reset)
        } else {
            _ = settings.resetShortcut(command)
        }
    }

    private func cancelRecording() {
        ShortcutCaptureSession.stopActiveSession()
        recording = nil
        pendingBinding = nil
        reassignPrompt = nil
    }

    private var isReassignPromptPresented: Binding<Bool> {
        Binding(
            get: { reassignPrompt != nil },
            set: { if !$0 { cancelRecording() } }
        )
    }
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

private struct ShortcutRecordingField: NSViewRepresentable {
    let onRecord: (ShortcutBinding) -> Void
    let onCancel: () -> Void
    func makeNSView(context: Context) -> ShortcutCaptureView {
        let view = ShortcutCaptureView()
        view.onRecord = onRecord
        view.onCancel = onCancel
        DispatchQueue.main.async { view.beginCapture() }
        return view
    }
    func updateNSView(_ nsView: ShortcutCaptureView, context: Context) {
        nsView.onRecord = onRecord
        nsView.onCancel = onCancel
        DispatchQueue.main.async { nsView.beginCapture() }
    }
    static func dismantleNSView(_ nsView: ShortcutCaptureView, coordinator: ()) {
        nsView.endCapture()
    }
}

private struct ShortcutReassignPrompt: Identifiable {
    enum Action {
        case assign(ShortcutBinding)
        case reset
    }

    let destination: ShortcutCommand
    let conflicting: ShortcutCommand
    let action: Action

    var id: String { "\(destination.rawValue)-\(conflicting.rawValue)" }
}

protocol ShortcutCaptureEventMonitoring: AnyObject {
    func addLocalKeyDownMonitor(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any
    func removeMonitor(_ monitor: Any)
}

private final class AppKitShortcutCaptureEventMonitor: ShortcutCaptureEventMonitoring, @unchecked Sendable {
    static let shared = AppKitShortcutCaptureEventMonitor()

    func addLocalKeyDownMonitor(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler) as Any
    }

    func removeMonitor(_ monitor: Any) {
        NSEvent.removeMonitor(monitor)
    }
}

/// A scoped, injectable local monitor that consumes events before SwiftUI
/// commands see them. The coordinator guarantees there is only one recorder.
final class ShortcutCaptureSession: @unchecked Sendable {
    private nonisolated(unsafe) static weak var activeSession: ShortcutCaptureSession?

    private let eventMonitor: ShortcutCaptureEventMonitoring
    private let onRecord: (ShortcutBinding) -> Void
    private let onCancel: () -> Void
    private var monitorToken: Any?

    private(set) var isActive = false

    init(
        eventMonitor: ShortcutCaptureEventMonitoring = AppKitShortcutCaptureEventMonitor.shared,
        onRecord: @escaping (ShortcutBinding) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.eventMonitor = eventMonitor
        self.onRecord = onRecord
        self.onCancel = onCancel
    }

    deinit { stop() }

    func start() {
        if Self.activeSession !== self { Self.activeSession?.stop() }
        guard !isActive else { return }
        Self.activeSession = self
        isActive = true
        monitorToken = eventMonitor.addLocalKeyDownMonitor { [weak self] event in
            self?.consume(event)
        }
    }

    func stop() {
        if let monitorToken {
            eventMonitor.removeMonitor(monitorToken)
            self.monitorToken = nil
        }
        isActive = false
        if Self.activeSession === self { Self.activeSession = nil }
    }

    static func stopActiveSession() {
        activeSession?.stop()
    }

    /// Returning `nil` consumes the event in the local application event loop.
    @discardableResult
    func consume(_ event: NSEvent) -> NSEvent? {
        guard isActive else { return event }
        if event.keyCode == 53 {
            stop()
            onCancel()
            return nil
        }
        if let binding = ShortcutCaptureParser.binding(from: event) {
            onRecord(binding)
        }
        return nil
    }
}

enum ShortcutCaptureParser {
    static func binding(from event: NSEvent) -> ShortcutBinding? {
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
        guard let binding, binding.isValid else { return nil }
        return binding
    }

    private static func shortcutModifiers(from flags: NSEvent.ModifierFlags) -> Set<ShortcutModifier> {
        var modifiers: Set<ShortcutModifier> = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }
}

private final class ShortcutCaptureView: NSView {
    var onRecord: ((ShortcutBinding) -> Void)?
    var onCancel: (() -> Void)?
    private var captureSession: ShortcutCaptureSession?

    override var acceptsFirstResponder: Bool { true }

    deinit { captureSession?.stop() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { endCapture() }
    }

    func beginCapture() {
        guard captureSession == nil else { return }
        let session = ShortcutCaptureSession(
            onRecord: { [weak self] binding in self?.onRecord?(binding) },
            onCancel: { [weak self] in self?.onCancel?() }
        )
        captureSession = session
        session.start()
        window?.makeFirstResponder(self)
    }

    func endCapture() {
        captureSession?.stop()
        captureSession = nil
    }

    override func keyDown(with event: NSEvent) {
        _ = captureSession?.consume(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard captureSession?.isActive == true else { return super.performKeyEquivalent(with: event) }
        _ = captureSession?.consume(event)
        return true
    }
}
