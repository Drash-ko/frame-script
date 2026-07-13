import AppKit

enum ScriptEditorLayout {
    static let maximumTextColumnWidth: CGFloat = 900
    static let visualLineHeightMultiplier: CGFloat = 1.48
    static let textKitLineSpacing: CGFloat = visualLineHeightMultiplier * 4

    static func textColumnWidth(for availableWidth: CGFloat) -> CGFloat {
        min(maximumTextColumnWidth, max(0, availableWidth))
    }

    static func paragraphStyle() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = textKitLineSpacing
        return paragraph
    }
}
