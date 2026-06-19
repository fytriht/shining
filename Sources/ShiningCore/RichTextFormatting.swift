import AppKit
import Foundation

public enum RichTextFormatting {
    public static var bodyAttributes: [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: bodyParagraphStyle
        ]
    }

    public static var timestampAttributes: [NSAttributedString.Key: Any] {
        [
            .font: timestampFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: timestampParagraphStyle,
            .baselineOffset: timestampBaselineOffset
        ]
    }

    public static var bodyFont: NSFont {
        NSFont.systemFont(ofSize: 14, weight: .regular)
    }

    public static var timestampFont: NSFont {
        NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .regular
        )
    }

    public static var timestampBaselineOffset: CGFloat {
        let defaultLineHeight = NSLayoutManager().defaultLineHeight(for: timestampFont)
        return max(0, (22 - defaultLineHeight) / 2)
    }

    public static var bodyParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 22
        style.maximumLineHeight = 22
        style.paragraphSpacing = 7
        return style.copy() as? NSParagraphStyle ?? style
    }

    public static var timestampParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.minimumLineHeight = 22
        style.maximumLineHeight = 22
        return style.copy() as? NSParagraphStyle ?? style
    }
}
