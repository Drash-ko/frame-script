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
        .onChange(of: scene.scriptText) { _, _ in appState.touchCurrentSceneText() }
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

private struct ProductionTextMarker: Hashable {
    var itemID: UUID
    var mode: WorkspaceMode
    var anchor: TextAnchor
}

private struct LinkedScriptTextView: NSViewRepresentable {
    @Binding var text: String
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
    let markerAction: (UUID, WorkspaceMode) -> Void
    let addMarkerAction: (WorkspaceMode, TextAnchor) -> Void

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
        if view.textView.string != text {
            let selectedRange = view.textView.selectedRange()
            let visibleOrigin = view.scrollView.contentView.bounds.origin
            view.textView.string = text
            view.textView.setSelectedRange(TextAnchorGeometry.clamp(selectedRange, toLength: (text as NSString).length))
            view.scrollView.contentView.scroll(to: visibleOrigin)
        }
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
        view.placeholder = placeholder
        view.placeholderColor = placeholderColor
        view.markers = markers
        view.bRollColor = bRollColor
        view.editingColor = editingColor
        view.addBRollLabel = addBRollLabel
        view.addEditingLabel = addEditingLabel
        view.invalidateMarkerGeometry()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LinkedScriptTextView
        weak var view: MarkerTextContainerView?
        init(parent: LinkedScriptTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            view?.invalidateMarkerGeometry()
            view?.needsDisplay = true
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

private final class MarkerTextContainerView: NSView {
    let scrollView = NSScrollView()
    let textView = NSTextView()
    let markerView = TextRangeMarkerView()
    weak var coordinator: LinkedScriptTextView.Coordinator?
    var placeholder = ""
    var placeholderColor = NSColor.secondaryLabelColor
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
        invalidateMarkerGeometry()
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

    func invalidateMarkerGeometry() {
        markerCacheSignature = nil
        markerView.needsDisplay = true
    }

    func markerRects() -> [ViewportMarkerRect] {
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
