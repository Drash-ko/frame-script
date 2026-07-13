import AppKit
import SwiftUI

struct KeyboardShortcutsSettings: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Binding var settings: AppSettings
    @State private var recording: ShortcutCommand?
    @State private var pendingBinding: ShortcutBinding?
    @State private var reassignPrompt: ShortcutReassignPrompt?
    @State private var lifecycle = ShortcutRecordingLifecycle()
    @State private var showResetConfirmation = false
    @State private var reservedShortcutWarning: ShortcutBinding?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(appState.localized("settings.keyboardShortcuts"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Button(appState.localized("shortcuts.resetAll")) {
                    lifecycle.stopForAlert()
                    showResetConfirmation = true
                }
                    .font(.system(size: 12))
                    .buttonStyle(.borderless)
                    .disabled(!ShortcutSettingsLayout.canResetAll(
                        customizedCommands: Set(settings.shortcutOverrides.keys), recording: recording
                    ))
                    .clickableCursor(enabled: ShortcutSettingsLayout.canResetAll(
                        customizedCommands: Set(settings.shortcutOverrides.keys), recording: recording
                    ))
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
        .alert(appState.localized("shortcuts.reserved.title"), isPresented: isReservedShortcutWarningPresented) {
            Button(appState.localized("dialog.ok")) { resumeRecordingAfterAlert() }
        } message: {
            if let reservedShortcutWarning {
                Text(String(format: appState.localized("shortcuts.reserved.message"), reservedShortcutWarning.display))
            }
        }
        .onDisappear { lifecycle.viewDidDisappear(); clearRecordingState() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            lifecycle.settingsWindowDidClose()
            clearRecordingState()
        }
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
                        // The local monitor is already running before this field is
                        // inserted. This view exists solely to take first responder
                        // asynchronously once AppKit has attached it to a window.
                        if isWaitingForKey {
                            ShortcutRecordingField()
                                .frame(width: 1, height: 1)
                                .accessibilityLabel(appState.localized("shortcuts.recording"))
                        }

                        if pendingBinding != nil {
                            ShortcutSettingsActionButton(appState.localized("shortcuts.save")) {
                                savePending(for: definition.command)
                            }
                        }
                        ShortcutSettingsActionButton(appState.localized("project.unsaved.cancel")) {
                            cancelRecording()
                        }
                    } else if state.showsEdit {
                        ShortcutSettingsActionButton(appState.localized("shortcuts.edit")) {
                            beginRecording(definition.command)
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
            ? ShortcutCapturePresentation.label(
                pendingBinding: pendingBinding,
                pressShortcut: appState.localized("shortcuts.pressShortcut")
            )
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
        guard ShortcutRegistry.isAssignable(pendingBinding) else {
            self.pendingBinding = nil
            reservedShortcutWarning = pendingBinding
            lifecycle.stopForAlert()
            return
        }
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
            lifecycle.stopForAlert()
            return
        }
        _ = settings.setShortcut(pendingBinding, for: command)
        lifecycle.save()
        clearRecordingState()
    }

    private func beginRecording(_ command: ShortcutCommand) {
        // Start suppression synchronously, before the row changes into its visible
        // recording state. First-responder assignment may follow on the next runloop.
        lifecycle.stopForAlert()
        recording = command
        pendingBinding = nil
        reassignPrompt = nil
        reservedShortcutWarning = nil
        startCapture(for: command)
    }

    private func startCapture(for command: ShortcutCommand) {
        let recordingState = $recording
        let pendingBindingState = $pendingBinding
        let reassignPromptState = $reassignPrompt
        let reservedWarningState = $reservedShortcutWarning
        let settingsState = $settings
        let lifecycle = lifecycle
        let session = ShortcutCaptureSession(
            onRecord: { [weak lifecycle] binding in
                // ShortcutCaptureSession has already removed its event monitor,
                // so an alert cannot have its keyboard interaction intercepted.
                guard let lifecycle else { return }
                lifecycle.candidateCaptured()
                guard recordingState.wrappedValue == command else { return }
                if ShortcutRecordingCoordinator.result(for: binding) == .reserved {
                    pendingBindingState.wrappedValue = nil
                    reservedWarningState.wrappedValue = binding
                    return
                }
                pendingBindingState.wrappedValue = binding
                if let conflictingCommand = ShortcutRegistry.conflict(
                    for: binding,
                    excluding: command,
                    overrides: settingsState.wrappedValue.shortcutOverrides
                ) {
                    reassignPromptState.wrappedValue = .init(
                        destination: command,
                        conflicting: conflictingCommand,
                        action: .assign(binding)
                    )
                }
            },
            onCancel: { [weak lifecycle] in
                lifecycle?.cancel()
                recordingState.wrappedValue = nil
                pendingBindingState.wrappedValue = nil
                reassignPromptState.wrappedValue = nil
            }
        )
        lifecycle.start(session)
    }

    private func reset(_ command: ShortcutCommand) {
        lifecycle.stopForAlert()
        if let conflictingCommand = settings.resetConflict(for: command) {
            reassignPrompt = .init(destination: command, conflicting: conflictingCommand, action: .reset)
        } else {
            _ = settings.resetShortcut(command)
        }
    }

    private func cancelRecording() {
        lifecycle.cancel()
        clearRecordingState()
    }

    private func clearRecordingState() {
        recording = nil
        pendingBinding = nil
        reassignPrompt = nil
        reservedShortcutWarning = nil
    }

    private var isWaitingForKey: Bool {
        recording != nil
            && reassignPrompt == nil
            && reservedShortcutWarning == nil
            && ShortcutCapturePresentation.showsRecordingField(
                pendingBinding: pendingBinding,
                isCaptureActive: lifecycle.isCaptureActive
            )
    }

    private func resumeRecordingAfterAlert() {
        reservedShortcutWarning = nil
        guard let recording, pendingBinding == nil, reassignPrompt == nil, !lifecycle.isCaptureActive else { return }
        startCapture(for: recording)
    }

    private var isReassignPromptPresented: Binding<Bool> {
        Binding(
            get: { reassignPrompt != nil },
            set: { if !$0 { cancelRecording() } }
        )
    }

    private var isReservedShortcutWarningPresented: Binding<Bool> {
        Binding(
            get: { reservedShortcutWarning != nil },
            set: { if !$0 { resumeRecordingAfterAlert() } }
        )
    }
}

enum ShortcutCapturePresentation {
    static func label(pendingBinding: ShortcutBinding?, pressShortcut: String) -> String {
        pendingBinding?.display ?? pressShortcut
    }

    static func showsRecordingField(pendingBinding: ShortcutBinding?, isCaptureActive: Bool) -> Bool {
        pendingBinding == nil && isCaptureActive
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
    let isLocked: Bool

    var showsEdit: Bool { !isRecording && !isLocked }
    var showsReset: Bool { isCustomized && !isLocked }
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
            isRecording: recording == definition.command,
            isLocked: recording != nil
        )
    }

    static func canResetAll(customizedCommands: Set<ShortcutCommand>, recording: ShortcutCommand?) -> Bool {
        !customizedCommands.isEmpty && recording == nil
    }
}

private struct ShortcutRecordingField: NSViewRepresentable {
    func makeNSView(context: Context) -> ShortcutCaptureView {
        ShortcutCaptureView()
    }
    func updateNSView(_ nsView: ShortcutCaptureView, context: Context) {
        nsView.requestFirstResponder()
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

/// Owns the recorder lifetime independently from the SwiftUI view state. Keeping
/// this seam small makes every exit path release the local event monitor before
/// the UI can present another control or native alert.
final class ShortcutRecordingLifecycle {
    private var session: ShortcutCaptureSession?

    var isCaptureActive: Bool { session?.isActive == true }

    func start(_ session: ShortcutCaptureSession) {
        stopForAlert()
        self.session = session
        session.start()
    }

    func candidateCaptured() {
        // The session has already stopped itself before invoking onRecord.
        session = nil
    }

    func save() {
        stopForAlert()
    }

    func cancel() {
        stopForAlert()
    }

    func viewDidDisappear() {
        stopForAlert()
    }

    func settingsWindowDidClose() {
        stopForAlert()
    }

    func stopForAlert() {
        session?.stop()
        session = nil
        ShortcutCaptureSession.stopActiveSession()
    }

    deinit { stopForAlert() }
}

enum ShortcutRecordingCoordinator {
    enum CandidateResult: Equatable {
        case accepted
        case reserved
    }

    static func result(for binding: ShortcutBinding) -> CandidateResult {
        ShortcutRegistry.isAssignable(binding) ? .accepted : .reserved
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
            // A valid candidate is terminal: it must not continue consuming
            // events while a Save/Cancel state or conflict alert is visible.
            stop()
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
    override var acceptsFirstResponder: Bool { true }

    func requestFirstResponder() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window else { return }
            window.makeFirstResponder(self)
        }
    }
}
