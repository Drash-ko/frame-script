import AppKit
import SwiftUI

struct ScriptEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.frameTheme) private var theme
    @Bindable var scene: Scene
    let editorSessionID: UUID
    @State private var notesExpanded = false
    @State private var didApplyInitialNotesVisibility = false
    @State private var didManuallyToggleNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sceneHeader

            LinkedScriptTextView(
                text: $scene.scriptText,
                sceneID: scene.id,
                editorIdentity: editorSessionID,
                loadRestorationState: {
                    appState.editorState.scriptEditorState(sceneID: scene.id, editorIdentity: editorSessionID)
                },
                saveRestorationState: { state in
                    appState.editorState.setScriptEditorState(state, sceneID: scene.id, editorIdentity: editorSessionID)
                },
                markers: productionMarkers,
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
                addBRollLabel: appState.localized("production.addBRollForSelection"),
                addEditingLabel: appState.localized("production.addEditingForSelection"),
                onTextCommitted: { appState.commitScriptTextChange(sceneID: scene.id) },
                onTeardown: { appState.flushActiveEditorBoundary() },
                markerAction: appState.selectProductionItem,
                addMarkerAction: { mode, anchor in
                    switch mode {
                    case .bRoll:
                        appState.addBRollItem(sceneID: scene.id, anchor: anchor)
                    case .editing:
                        appState.addEditingItem(sceneID: scene.id, anchor: anchor)
                    case .script:
                        break
                    }
                }
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

    private var productionMarkers: [ProductionTextMarker] {
        var markers: [ProductionTextMarker] = []
        for item in scene.bRollItems {
            if let anchor = item.textAnchor {
                markers.append(ProductionTextMarker(itemID: item.id, mode: .bRoll, anchor: anchor))
            } else if let segmentID = item.linkedSegmentID,
                      let anchor = appState.projectStore.anchor(for: segmentID, in: scene) {
                markers.append(ProductionTextMarker(itemID: item.id, mode: .bRoll, anchor: anchor))
            }
        }
        for item in scene.editingItems {
            if let anchor = item.textAnchor {
                markers.append(ProductionTextMarker(itemID: item.id, mode: .editing, anchor: anchor))
            } else if let segmentID = item.linkedSegmentID,
                      let anchor = appState.projectStore.anchor(for: segmentID, in: scene) {
                markers.append(ProductionTextMarker(itemID: item.id, mode: .editing, anchor: anchor))
            }
        }
        return markers
    }

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

struct ProductionTextMarker: Hashable {
    var itemID: UUID
    var mode: WorkspaceMode
    var anchor: TextAnchor
}

struct LinkedScriptTextView: NSViewRepresentable {
    @Binding var text: String
    let sceneID: UUID
    let editorIdentity: UUID
    let loadRestorationState: () -> ScriptEditorRestorationState?
    let saveRestorationState: (ScriptEditorRestorationState) -> Void
    let markers: [ProductionTextMarker]
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
    let addBRollLabel: String
    let addEditingLabel: String
    let onTextCommitted: () -> Void
    let onTeardown: () -> Void
    let markerAction: (UUID, WorkspaceMode) -> Void
    let addMarkerAction: (WorkspaceMode, TextAnchor) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> MarkerTextContainerView {
        let view = MarkerTextContainerView()
        context.coordinator.attach(to: view)
        configureAppearance(view)
        context.coordinator.applyModelTextIfNeeded()
        ActiveScriptEditorSession.shared.register(context.coordinator)
        DispatchQueue.main.async {
            context.coordinator.restoreEditorStateIfAvailable()
            view.textView.window?.makeFirstResponder(view.textView)
        }
        return view
    }

    func updateNSView(_ view: MarkerTextContainerView, context: Context) {
        context.coordinator.parent = self
        configureAppearance(view)
        context.coordinator.applyModelTextIfNeeded()
    }

    static func dismantleNSView(_ view: MarkerTextContainerView, coordinator: Coordinator) {
        coordinator.commitMarkedTextAndFlush()
        ActiveScriptEditorSession.shared.unregister(coordinator)
        coordinator.parent.onTeardown()
        coordinator.detach(from: view)
    }

    private func configureAppearance(_ view: MarkerTextContainerView) {
        let font = NSFont.systemFont(ofSize: fontSize)
        let typographyChanged = view.cachedFontSize != fontSize || view.cachedLineSpacing != lineSpacing
        if view.textView.font != font { view.textView.font = font }
        view.textView.textColor = textColor
        view.textView.backgroundColor = backgroundColor
        view.scrollView.backgroundColor = backgroundColor
        view.textView.isContinuousSpellCheckingEnabled = spellcheck
        view.textView.isAutomaticQuoteSubstitutionEnabled = smartQuotes
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        view.textView.defaultParagraphStyle = paragraph
        view.textView.typingAttributes[.paragraphStyle] = paragraph
        if typographyChanged, let storage = view.textView.textStorage, storage.length > 0 {
            storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
        }
        view.cachedFontSize = fontSize
        view.cachedLineSpacing = lineSpacing
        view.textView.placeholder = placeholder
        view.textView.placeholderColor = placeholderColor
        view.markers = markers
        view.bRollColor = bRollColor
        view.editingColor = editingColor
        view.addBRollLabel = addBRollLabel
        view.addEditingLabel = addEditingLabel
        view.invalidateMarkerGeometry()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        enum ChangeOrigin {
            case user
            case externalModel
            case programmaticTextView
        }

        var parent: LinkedScriptTextView
        weak var view: MarkerTextContainerView?
        private(set) var changeOrigin: ChangeOrigin = .externalModel
        private(set) var lastUserEmittedValue: String?
        private var lastObservedModelValue: String
        private var pendingUserRevision: Int?
        private var userRevision = 0
        private var modelRevision = 0
        private var isApplyingProgrammaticUpdate = false
        private var pendingInitialRestorationState: ScriptEditorRestorationState?
        init(parent: LinkedScriptTextView) {
            self.parent = parent
            self.lastObservedModelValue = parent.text
        }

        func attach(to view: MarkerTextContainerView) {
            self.view = view
            view.coordinator = self
            pendingInitialRestorationState = parent.loadRestorationState()
        }

        func detach(from view: MarkerTextContainerView) {
            if self.view === view { self.view = nil }
            if view.coordinator === self { view.coordinator = nil }
        }

        @discardableResult
        func commitMarkedTextAndFlush() -> Bool {
            guard let textView = view?.textView else { return false }
            if textView.hasMarkedText() {
                textView.unmarkText()
            }
            let changed = emitCurrentText(from: textView, origin: .user)
            captureRestorationState()
            return changed
        }

        func captureRestorationState() {
            guard let view, pendingInitialRestorationState == nil else { return }
            parent.saveRestorationState(ScriptEditorRestorationState(
                selectedRange: view.textView.selectedRange(),
                visibleOrigin: view.scrollView.contentView.bounds.origin
            ))
        }

        func restoreEditorStateIfAvailable() {
            guard let view, let state = pendingInitialRestorationState ?? parent.loadRestorationState() else { return }
            let length = (view.textView.string as NSString).length
            view.textView.setSelectedRange(TextAnchorGeometry.clamp(state.selectedRange, toLength: length))
            view.layoutSubtreeIfNeeded()
            view.scrollView.contentView.scroll(to: state.visibleOrigin)
            view.scrollView.reflectScrolledClipView(view.scrollView.contentView)
            pendingInitialRestorationState = nil
        }

        func applyModelTextIfNeeded() {
            guard let view else { return }
            let textView = view.textView
            let modelText = parent.text
            guard textView.string != modelText else {
                lastObservedModelValue = modelText
                pendingUserRevision = nil
                return
            }

            let hasMarkedText = textView.hasMarkedText()
            let isUnacknowledgedUserRevision = pendingUserRevision != nil
                && lastUserEmittedValue == textView.string
                && modelText == lastObservedModelValue
            if hasMarkedText || isUnacknowledgedUserRevision {
                if isUnacknowledgedUserRevision { parent.text = textView.string }
                return
            }

            modelRevision += 1
            pendingUserRevision = nil
            lastObservedModelValue = modelText
            changeOrigin = .programmaticTextView
            isApplyingProgrammaticUpdate = true
            let selectedRange = textView.selectedRange()
            let visibleOrigin = view.scrollView.contentView.bounds.origin
            let undoManager = textView.undoManager
            undoManager?.disableUndoRegistration()
            textView.string = modelText
            undoManager?.enableUndoRegistration()
            textView.setSelectedRange(TextAnchorGeometry.clamp(selectedRange, toLength: (modelText as NSString).length))
            view.scrollView.contentView.scroll(to: visibleOrigin)
            isApplyingProgrammaticUpdate = false
            changeOrigin = .externalModel
            captureRestorationState()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isApplyingProgrammaticUpdate else { return }
            _ = emitCurrentText(from: textView, origin: .user)
            view?.invalidateMarkerGeometry()
            view?.needsDisplay = true
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if textView.hasMarkedText() { textView.unmarkText() }
            _ = emitCurrentText(from: textView, origin: .user)
            captureRestorationState()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            captureRestorationState()
        }

        @discardableResult
        private func emitCurrentText(from textView: NSTextView, origin: ChangeOrigin) -> Bool {
            let value = textView.string
            let changed = parent.text != value
            changeOrigin = origin
            lastUserEmittedValue = value
            if origin == .user {
                userRevision += 1
                pendingUserRevision = userRevision
            }
            parent.text = value
            if changed { parent.onTextCommitted() }
            return changed
        }

        func textView(_ textView: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            guard let view,
                  let range = view.selectionOrParagraphRange(at: charIndex),
                  let anchor = TextAnchorRepair.anchor(in: textView.string, range: range) else {
                return menu
            }
            menu.insertItem(NSMenuItem.separator(), at: 0)
            let editingItem = NSMenuItem(title: parent.addEditingLabel, action: #selector(addEditingForSelection(_:)), keyEquivalent: "")
            editingItem.target = self
            editingItem.representedObject = anchor
            menu.insertItem(editingItem, at: 0)
            let bRollItem = NSMenuItem(title: parent.addBRollLabel, action: #selector(addBRollForSelection(_:)), keyEquivalent: "")
            bRollItem.target = self
            bRollItem.representedObject = anchor
            menu.insertItem(bRollItem, at: 0)
            return menu
        }

        @MainActor @objc private func addBRollForSelection(_ sender: NSMenuItem) {
            guard let anchor = sender.representedObject as? TextAnchor else { return }
            parent.addMarkerAction(.bRoll, anchor)
        }

        @MainActor @objc private func addEditingForSelection(_ sender: NSMenuItem) {
            guard let anchor = sender.representedObject as? TextAnchor else { return }
            parent.addMarkerAction(.editing, anchor)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool { false }
    }
}

@MainActor
protocol ActiveScriptEditor: AnyObject {
    @discardableResult func commitMarkedTextAndFlush() -> Bool
    var isActualFirstResponder: Bool { get }
}

extension LinkedScriptTextView.Coordinator: ActiveScriptEditor {
    var isActualFirstResponder: Bool {
        guard let textView = view?.textView else { return false }
        return textView.window?.firstResponder === textView
    }
}

@MainActor
final class ActiveScriptEditorSession {
    static let shared = ActiveScriptEditorSession()
    private final class WeakEditor {
        weak var value: ActiveScriptEditor?
        init(_ value: ActiveScriptEditor) { self.value = value }
    }
    private var editors: [WeakEditor] = []

    private init() {}

    func register(_ editor: ActiveScriptEditor) {
        editors.removeAll { $0.value == nil || $0.value === editor }
        editors.append(WeakEditor(editor))
    }

    func unregister(_ editor: ActiveScriptEditor) {
        editors.removeAll { $0.value == nil || $0.value === editor }
    }

    @discardableResult
    func flush() -> Bool {
        editors.removeAll { $0.value == nil }
        guard let editor = editors.compactMap(\.value).first(where: \.isActualFirstResponder)
                ?? editors.compactMap(\.value).last else { return false }
        _ = editor.commitMarkedTextAndFlush()
        return true
    }
}

final class PlaceholderTextView: NSTextView {
    var placeholder = "" { didSet { needsDisplay = true } }
    var placeholderColor = NSColor.secondaryLabelColor { didSet { needsDisplay = true } }

    var placeholderOrigin: NSPoint {
        textContainerOrigin
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        (placeholder as NSString).draw(at: placeholderOrigin, withAttributes: [
            .font: font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: placeholderColor,
            .paragraphStyle: defaultParagraphStyle ?? NSParagraphStyle.default
        ])
    }
}

final class MarkerTextContainerView: NSView {
    let scrollView = NSScrollView()
    let textView = PlaceholderTextView()
    private let markerView = TextRangeMarkerView()
    weak var coordinator: LinkedScriptTextView.Coordinator?
    var markers: [ProductionTextMarker] = []
    var bRollColor = NSColor.systemBlue
    var editingColor = NSColor.systemGreen
    var addBRollLabel = ""
    var addEditingLabel = ""
    var cachedFontSize: Double?
    var cachedLineSpacing: Double?
    private var cachedDocumentMarkers: [DocumentMarkerRect] = []
    private var markerCacheSignature: MarkerCacheSignature?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 0, height: 7)
        textView.textContainer?.lineFragmentPadding = 0
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
        invalidateMarkerGeometry()
        markerView.needsDisplay = true
    }

    @objc private func scrolled() {
        markerView.needsDisplay = true
        coordinator?.captureRestorationState()
    }

    func invalidateMarkerGeometry() {
        markerCacheSignature = nil
        markerView.needsDisplay = true
    }

    fileprivate func markerRects() -> [ViewportMarkerRect] {
        rebuildMarkerGeometryIfNeeded()
        let visible = scrollView.contentView.bounds
        return cachedDocumentMarkers.compactMap { marker in
            var rect = marker.documentRect
            rect.origin.y -= visible.origin.y
            rect.origin.y = markerView.bounds.height - rect.maxY
            guard rect.intersects(markerView.bounds) else { return nil }
            return ViewportMarkerRect(itemID: marker.itemID, mode: marker.mode, rect: rect)
        }
    }

    func selectionOrParagraphRange(at charIndex: Int) -> NSRange? {
        let full = textView.string as NSString
        guard full.length > 0 else { return nil }
        let selected = textView.selectedRange()
        if selected.length > 0 {
            return TextAnchorGeometry.clamp(selected, toLength: full.length)
        }
        let safeIndex = min(max(0, charIndex), max(0, full.length - 1))
        let paragraph = full.paragraphRange(for: NSRange(location: safeIndex, length: 0))
        let trimmed = TextAnchorGeometry.trimmedRange(paragraph, in: full)
        return trimmed.length > 0 ? trimmed : nil
    }

    private func rebuildMarkerGeometryIfNeeded() {
        let signature = MarkerCacheSignature(
            textLength: (textView.string as NSString).length,
            containerWidth: textView.textContainer?.containerSize.width ?? 0,
            fontSize: cachedFontSize ?? 0,
            lineSpacing: cachedLineSpacing ?? 0,
            markers: markers
        )
        guard markerCacheSignature != signature else { return }
        markerCacheSignature = signature
        cachedDocumentMarkers = TextAnchorGeometry.documentMarkers(markers: markers, textView: textView)
    }
}

private struct MarkerCacheSignature: Equatable {
    var textLength: Int
    var containerWidth: CGFloat
    var fontSize: Double
    var lineSpacing: Double
    var markers: [ProductionTextMarker]
}

private struct DocumentMarkerRect {
    var itemID: UUID
    var mode: WorkspaceMode
    var documentRect: NSRect
}

private struct ViewportMarkerRect {
    var itemID: UUID
    var mode: WorkspaceMode
    var rect: NSRect
}

private enum TextAnchorGeometry {
    @MainActor
    static func documentMarkers(markers: [ProductionTextMarker], textView: NSTextView) -> [DocumentMarkerRect] {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return [] }
        layout.ensureLayout(for: container)
        let textLength = (textView.string as NSString).length
        return markers.flatMap { marker -> [DocumentMarkerRect] in
            let range = clamp(marker.anchor.nsRange, toLength: textLength)
            guard range.length > 0, NSMaxRange(range) <= textLength else { return [] }
            var actual = NSRange()
            let glyphRange = layout.glyphRange(forCharacterRange: range, actualCharacterRange: &actual)
            guard glyphRange.length > 0 else { return [] }
            let hasOtherModeAtSameRange = markers.contains { other in
                other.itemID != marker.itemID && other.mode != marker.mode && other.anchor.nsRange == marker.anchor.nsRange
            }
            let x: CGFloat = switch marker.mode {
            case .bRoll: hasOtherModeAtSameRange ? 2 : 5
            case .editing: hasOtherModeAtSameRange ? 8 : 5
            case .script: 5
            }
            var rects: [NSRect] = []
            layout.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineGlyphRange, _ in
                let intersection = NSIntersectionRange(glyphRange, lineGlyphRange)
                guard intersection.length > 0 else { return }
                let lineHeight = max(8, usedRect.height)
                let y = usedRect.minY + textView.textContainerInset.height
                rects.append(NSRect(x: x, y: y, width: 3, height: lineHeight))
            }
            return mergeAdjacent(rects).map { DocumentMarkerRect(itemID: marker.itemID, mode: marker.mode, documentRect: $0) }
        }
    }

    static func clamp(_ range: NSRange, toLength length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(max(0, range.length), max(0, length - location)))
    }

    static func trimmedRange(_ range: NSRange, in text: NSString) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)
        while start < end, isWhitespace(text, at: start) {
            start += 1
        }
        while end > start, isWhitespace(text, at: end - 1) {
            end -= 1
        }
        return NSRange(location: start, length: end - start)
    }

    private static func isWhitespace(_ text: NSString, at index: Int) -> Bool {
        text.rangeOfCharacter(from: .whitespacesAndNewlines, options: [], range: NSRange(location: index, length: 1)).location != NSNotFound
    }

    private static func mergeAdjacent(_ rects: [NSRect]) -> [NSRect] {
        let sorted = rects.sorted { $0.minY < $1.minY }
        return sorted.reduce(into: []) { result, rect in
            guard var last = result.popLast() else {
                result.append(rect)
                return
            }
            if abs(last.maxY - rect.minY) <= 1 {
                last = last.union(rect)
                result.append(last)
            } else {
                result.append(last)
                result.append(rect)
            }
        }
    }
}

private final class TextRangeMarkerView: NSView {
    weak var container: MarkerTextContainerView?
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let container else { return }
        for marker in container.markerRects() where marker.rect.intersects(bounds) {
            (marker.mode == .bRoll ? container.bRollColor : container.editingColor).setFill()
            NSBezierPath(roundedRect: marker.rect, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let container else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let marker = container.markerRects().reversed().first(where: { $0.rect.insetBy(dx: -2, dy: 0).contains(point) }) {
            container.coordinator?.parent.markerAction(marker.itemID, marker.mode)
        }
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
