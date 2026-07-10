import AppKit
import SwiftUI

struct ScriptEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Bindable var scene: Scene
    @State private var notesExpanded = false
    @State private var didApplyInitialNotesVisibility = false
    @State private var didManuallyToggleNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sceneHeader

            LinkedScriptTextView(
                text: $scene.scriptText,
                segments: scene.textSegments.sortedByOrder,
                bRollSegmentIDs: Set(scene.bRollItems.compactMap(\.linkedSegmentID)),
                editingSegmentIDs: Set(scene.editingItems.compactMap(\.linkedSegmentID)),
                fontSize: appState.settings.editorPreferences.fontSize,
                lineSpacing: appState.settings.editorPreferences.lineHeight * 4,
                spellcheck: appState.settings.editorPreferences.spellcheck,
                smartQuotes: appState.settings.editorPreferences.smartQuotes,
                placeholder: appState.localized("script.placeholder"),
                textColor: NSColor(theme.primaryText),
                placeholderColor: NSColor(theme.secondaryText.opacity(0.58)),
                backgroundColor: NSColor(theme.editorSurface),
                bRollColor: NSColor(theme.bRollMarker),
                editingColor: NSColor(theme.editingMarker),
                markerAction: appState.selectProductionSegment
            )
            .frame(minHeight: appState.isFocusModeEnabled ? 430 : 390, maxHeight: .infinity)
            .accessibilityLabel(appState.localized("script.accessibilityLabel"))

            DisclosureGroup(isExpanded: Binding(
                get: { notesExpanded },
                set: {
                    notesExpanded = $0
                    didManuallyToggleNotes = true
                }
            )) {
                MultilineField(
                    placeholder: appState.localized("script.notesPlaceholder"),
                    text: $scene.notes,
                    minHeight: 82
                )
                .accessibilityLabel(appState.localized("script.notes"))
            } label: {
                Text(appState.localized("script.notes"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }
            .font(.system(size: 13))
            .tint(theme.secondaryText)
        }
        .frame(maxWidth: appState.settings.editorPreferences.editorWidth, alignment: .leading)
        .padding(.horizontal, appState.isFocusModeEnabled ? 80 : 48)
        .padding(.vertical, appState.isFocusModeEnabled ? 72 : 42)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.editorSurface)
        .onAppear { applyInitialNotesVisibility() }
        .onChange(of: scene.scriptText) { _, _ in appState.touchProject() }
        .onChange(of: scene.title) { _, _ in appState.touchProject() }
        .onChange(of: scene.notes) { _, _ in appState.touchProject() }
        .onChange(of: appState.settings.editorPreferences.defaultNotesVisibility) { _, newValue in
            guard !didManuallyToggleNotes else { return }
            notesExpanded = !appState.isFocusModeEnabled && newValue == .expanded
        }
    }

    private var sceneHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(appState.localized("scene.title"), text: $scene.title)
                .textFieldStyle(.plain)
                .font(.system(size: appState.isFocusModeEnabled ? 34 : 30, weight: .semibold))
                .textCursor()

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    if appState.settings.editorPreferences.showSceneDuration {
                        Text(DurationEstimator.formatted(scene.estimatedDuration))
                        Text(appState.localized("script.estimated"))
                    }
                    if appState.settings.editorPreferences.showSceneDuration && appState.settings.editorPreferences.showWordCount { Text("·") }
                    if appState.settings.editorPreferences.showWordCount { Text("\(wordCount) \(appState.localized("script.words"))") }
                }
                if shouldShowSectionTag {
                    Label("\(appState.localized("script.templateSection")): \(appState.displayName(scene.sectionType))", systemImage: "tag")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryText)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(theme.secondaryText)
        }
    }

    private var wordCount: Int { scene.scriptText.split { $0.isWhitespace || $0.isNewline }.count }

    private var shouldShowSectionTag: Bool {
        scene.sectionType != .custom && scene.title.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(appState.displayName(scene.sectionType)) != .orderedSame
    }

    private func applyInitialNotesVisibility() {
        guard !didApplyInitialNotesVisibility else { return }
        didApplyInitialNotesVisibility = true
        notesExpanded = !appState.isFocusModeEnabled && appState.settings.editorPreferences.defaultNotesVisibility == .expanded
    }
}

private struct LinkedScriptTextView: NSViewRepresentable {
    @Binding var text: String
    let segments: [TextSegment]
    let bRollSegmentIDs: Set<UUID>
    let editingSegmentIDs: Set<UUID>
    let fontSize: Double
    let lineSpacing: Double
    let spellcheck: Bool
    let smartQuotes: Bool
    let placeholder: String
    let textColor: NSColor
    let placeholderColor: NSColor
    let backgroundColor: NSColor
    let bRollColor: NSColor
    let editingColor: NSColor
    let markerAction: (UUID, WorkspaceMode) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> MarkerTextContainerView {
        let view = MarkerTextContainerView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        configure(view)
        DispatchQueue.main.async { view.textView.window?.makeFirstResponder(view.textView) }
        return view
    }

    func updateNSView(_ view: MarkerTextContainerView, context: Context) {
        context.coordinator.parent = self
        configure(view)
    }

    private func configure(_ view: MarkerTextContainerView) {
        if view.textView.string != text { view.textView.string = text }
        view.textView.font = .systemFont(ofSize: fontSize)
        view.textView.textColor = textColor
        view.textView.backgroundColor = backgroundColor
        view.scrollView.backgroundColor = backgroundColor
        view.textView.isContinuousSpellCheckingEnabled = spellcheck
        view.textView.isAutomaticQuoteSubstitutionEnabled = smartQuotes
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        view.textView.defaultParagraphStyle = paragraph
        view.textView.typingAttributes[.paragraphStyle] = paragraph
        if let storage = view.textView.textStorage, storage.length > 0 {
            storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
        }
        view.placeholder = placeholder
        view.placeholderColor = placeholderColor
        view.segments = segments
        view.bRollSegmentIDs = bRollSegmentIDs
        view.editingSegmentIDs = editingSegmentIDs
        view.bRollColor = bRollColor
        view.editingColor = editingColor
        view.needsLayout = true
        view.markerView.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LinkedScriptTextView
        weak var view: MarkerTextContainerView?
        init(parent: LinkedScriptTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            view?.markerView.needsDisplay = true
            view?.needsDisplay = true
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool { false }
    }
}

private final class MarkerTextContainerView: NSView {
    let scrollView = NSScrollView()
    let textView = NSTextView()
    let markerView = TextRangeMarkerView()
    weak var coordinator: LinkedScriptTextView.Coordinator?
    var placeholder = ""
    var placeholderColor = NSColor.secondaryLabelColor
    var segments: [TextSegment] = []
    var bRollSegmentIDs: Set<UUID> = []
    var editingSegmentIDs: Set<UUID> = []
    var bRollColor = NSColor.systemBlue
    var editingColor = NSColor.systemGreen

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 5, height: 7)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        markerView.container = self
        addSubview(scrollView)
        addSubview(markerView)
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        scrollView.contentView.postsBoundsChangedNotifications = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }

    override func layout() {
        super.layout()
        let markerWidth: CGFloat = 13
        scrollView.frame = NSRect(x: 0, y: 0, width: max(0, bounds.width - markerWidth), height: bounds.height)
        markerView.frame = NSRect(x: max(0, bounds.width - markerWidth), y: 0, width: markerWidth, height: bounds.height)
        textView.minSize = NSSize(width: scrollView.contentSize.width, height: 0)
        textView.maxSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        markerView.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard textView.string.isEmpty else { return }
        (placeholder as NSString).draw(at: NSPoint(x: 5, y: bounds.height - 7 - (textView.font?.ascender ?? 13)), withAttributes: [
            .font: textView.font ?? NSFont.systemFont(ofSize: 14), .foregroundColor: placeholderColor
        ])
    }

    @objc private func scrolled() { markerView.needsDisplay = true }

    func range(for segment: TextSegment) -> NSRange? {
        let full = textView.string as NSString
        var searchStart = 0
        for candidate in segments {
            let searchRange = NSRange(location: searchStart, length: full.length - searchStart)
            let found = full.range(of: candidate.sourceText, options: [], range: searchRange)
            guard found.location != NSNotFound else { continue }
            if candidate.id == segment.id { return found }
            searchStart = NSMaxRange(found)
        }
        return nil
    }

    func markerRects() -> [(UUID, WorkspaceMode, NSRect)] {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return [] }
        layout.ensureLayout(for: container)
        let visible = scrollView.contentView.bounds
        return segments.flatMap { segment -> [(UUID, WorkspaceMode, NSRect)] in
            guard let range = range(for: segment), range.length > 0 else { return [] }
            let glyphRange = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layout.boundingRect(forGlyphRange: glyphRange, in: container)
            rect.origin.x += textView.textContainerInset.width
            rect.origin.y += textView.textContainerInset.height
            rect.origin.y -= visible.origin.y
            rect.origin.y = markerView.bounds.height - rect.maxY
            let hasB = bRollSegmentIDs.contains(segment.id)
            let hasE = editingSegmentIDs.contains(segment.id)
            let height = max(8, rect.height)
            var result: [(UUID, WorkspaceMode, NSRect)] = []
            if hasB { result.append((segment.id, .bRoll, NSRect(x: hasE ? 2 : 5, y: rect.minY, width: 3, height: height))) }
            if hasE { result.append((segment.id, .editing, NSRect(x: hasB ? 8 : 5, y: rect.minY, width: 3, height: height))) }
            return result
        }
    }
}

private final class TextRangeMarkerView: NSView {
    weak var container: MarkerTextContainerView?
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let container else { return }
        for (_, mode, rect) in container.markerRects() where rect.intersects(bounds) {
            (mode == .bRoll ? container.bRollColor : container.editingColor).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let container else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let marker = container.markerRects().reversed().first(where: { $0.2.insetBy(dx: -2, dy: 0).contains(point) }) {
            container.coordinator?.parent.markerAction(marker.0, marker.1)
        }
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
