import AppKit
import Foundation

public enum RichTextPasteSanitizer {
    public static var defaultTextAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor
        ]
    }

    public static func sanitizedPlainText(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: defaultTextAttributes)
    }

    public static func sanitizedImportedRichText(
        data: Data,
        documentType: NSAttributedString.DocumentType,
        preservesAttachments: Bool = true
    ) -> NSAttributedString? {
        guard let attributedString = try? NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        ) else {
            return nil
        }

        return sanitizedAttributedString(
            attributedString,
            normalizesLists: true,
            preservesAttachments: preservesAttachments
        )
    }

    public static func sanitizedAttributedString(
        _ attributedString: NSAttributedString,
        normalizesLists: Bool = false,
        preservesAttachments: Bool = true
    ) -> NSAttributedString {
        guard attributedString.length > 0 else {
            return NSAttributedString()
        }

        guard normalizesLists else {
            let result = NSMutableAttributedString()
            appendSanitizedContent(
                from: attributedString,
                range: NSRange(location: 0, length: attributedString.length),
                to: result,
                preservesAttachments: preservesAttachments
            )
            return result
        }

        return sanitizedAttributedStringWithNormalizedLists(
            attributedString,
            preservesAttachments: preservesAttachments
        )
    }

    private static func sanitizedAttributedStringWithNormalizedLists(
        _ attributedString: NSAttributedString,
        preservesAttachments: Bool
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let string = attributedString.string as NSString
        var location = 0
        var orderedListCounters: [ObjectIdentifier: Int] = [:]

        while location < string.length {
            var paragraphStart = 0
            var paragraphEnd = 0
            var contentsEnd = 0
            string.getParagraphStart(
                &paragraphStart,
                end: &paragraphEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: location, length: 0)
            )

            let paragraphRange = NSRange(
                location: paragraphStart,
                length: paragraphEnd - paragraphStart
            )
            let contentRange = NSRange(
                location: paragraphStart,
                length: contentsEnd - paragraphStart
            )

            if let list = listStyle(in: attributedString, paragraphRange: paragraphRange) {
                appendListParagraph(
                    from: attributedString,
                    contentRange: contentRange,
                    paragraphRange: paragraphRange,
                    list: list,
                    orderedListCounters: &orderedListCounters,
                    to: result,
                    preservesAttachments: preservesAttachments
                )
            } else {
                appendSanitizedContent(
                    from: attributedString,
                    range: paragraphRange,
                    to: result,
                    preservesAttachments: preservesAttachments
                )
            }

            location = max(paragraphEnd, location + 1)
        }

        return result
    }

    private static func appendListParagraph(
        from attributedString: NSAttributedString,
        contentRange: NSRange,
        paragraphRange: NSRange,
        list: NSTextList,
        orderedListCounters: inout [ObjectIdentifier: Int],
        to result: NSMutableAttributedString,
        preservesAttachments: Bool
    ) {
        let content = (attributedString.string as NSString).substring(with: contentRange)
        let markerLength = importedListMarkerLength(in: content, list: list)
        let bodyRange = NSRange(
            location: contentRange.location + markerLength,
            length: max(0, contentRange.length - markerLength)
        )

        result.append(
            NSAttributedString(
                string: markdownListMarker(
                    for: list,
                    content: content,
                    orderedListCounters: &orderedListCounters
                ),
                attributes: defaultTextAttributes
            )
        )
        appendSanitizedContent(
            from: attributedString,
            range: bodyRange,
            to: result,
            preservesAttachments: preservesAttachments
        )

        let trailingRange = NSRange(
            location: contentRange.endLocation,
            length: paragraphRange.endLocation - contentRange.endLocation
        )
        appendSanitizedContent(
            from: attributedString,
            range: trailingRange,
            to: result,
            preservesAttachments: preservesAttachments
        )
    }

    private static func appendSanitizedContent(
        from attributedString: NSAttributedString,
        range: NSRange,
        to result: NSMutableAttributedString,
        preservesAttachments: Bool
    ) {
        guard range.length > 0 else {
            return
        }

        attributedString.enumerateAttribute(.attachment, in: range) { value, effectiveRange, _ in
            if let attachment = value as? NSTextAttachment {
                if preservesAttachments {
                    result.append(NSAttributedString(attachment: copyAttachment(attachment)))
                }
                return
            }

            let text = (attributedString.string as NSString)
                .substring(with: effectiveRange)
                .replacingOccurrences(of: "\u{fffc}", with: "")
            guard !text.isEmpty else {
                return
            }

            result.append(NSAttributedString(string: text, attributes: defaultTextAttributes))
        }
    }

    private static func copyAttachment(_ attachment: NSTextAttachment) -> NSTextAttachment {
        let copiedAttachment = NSTextAttachment()
        copiedAttachment.fileWrapper = attachment.fileWrapper
        copiedAttachment.image = attachment.image
        copiedAttachment.bounds = attachment.bounds
        return copiedAttachment
    }

    private static func listStyle(
        in attributedString: NSAttributedString,
        paragraphRange: NSRange
    ) -> NSTextList? {
        guard paragraphRange.length > 0 else {
            return nil
        }

        let style = attributedString.attribute(
            .paragraphStyle,
            at: paragraphRange.location,
            effectiveRange: nil
        ) as? NSParagraphStyle
        return style?.textLists.last
    }

    private static func markdownListMarker(
        for list: NSTextList,
        content: String,
        orderedListCounters: inout [ObjectIdentifier: Int]
    ) -> String {
        if isUnorderedList(list) {
            return "- "
        }

        let listID = ObjectIdentifier(list)
        if let importedNumber = importedOrderedListNumber(in: content) {
            orderedListCounters[listID] = importedNumber + 1
            return "\(importedNumber). "
        }

        let itemNumber = orderedListCounters[listID] ?? list.startingItemNumber
        orderedListCounters[listID] = itemNumber + 1
        return "\(itemNumber). "
    }

    private static func importedListMarkerLength(in content: String, list: NSTextList) -> Int {
        let string = content as NSString
        var location = skipHorizontalWhitespace(in: string, startingAt: 0)
        let tokenStart = location

        while location < string.length,
              !isHorizontalWhitespace(string.character(at: location)) {
            location += 1
        }

        guard tokenStart < location else {
            return 0
        }

        let token = string.substring(with: NSRange(location: tokenStart, length: location - tokenStart))
        guard isImportedListMarker(token, for: list) else {
            return 0
        }

        return skipHorizontalWhitespace(in: string, startingAt: location)
    }

    private static func isImportedListMarker(_ token: String, for list: NSTextList) -> Bool {
        if isUnorderedList(list) {
            return unorderedListMarkers.contains(token)
        }

        let trimmedToken = token.trimmingCharacters(in: CharacterSet(charactersIn: ".):"))
        return !trimmedToken.isEmpty && trimmedToken.allSatisfy(\.isNumber)
    }

    private static func importedOrderedListNumber(in content: String) -> Int? {
        let string = content as NSString
        let tokenStart = skipHorizontalWhitespace(in: string, startingAt: 0)
        var location = tokenStart

        while location < string.length,
              !isHorizontalWhitespace(string.character(at: location)) {
            location += 1
        }

        guard tokenStart < location else {
            return nil
        }

        let token = string.substring(with: NSRange(location: tokenStart, length: location - tokenStart))
        return Int(token.trimmingCharacters(in: CharacterSet(charactersIn: ".):")))
    }

    private static func isUnorderedList(_ list: NSTextList) -> Bool {
        let marker = list.marker(forItemNumber: max(1, list.startingItemNumber))
        if unorderedListMarkers.contains(marker) {
            return true
        }

        let format = list.markerFormat.rawValue.lowercased()
        return format.contains("disc") ||
            format.contains("circle") ||
            format.contains("square") ||
            format.contains("bullet") ||
            format.contains("hyphen")
    }

    private static func skipHorizontalWhitespace(in string: NSString, startingAt location: Int) -> Int {
        var location = location
        while location < string.length,
              isHorizontalWhitespace(string.character(at: location)) {
            location += 1
        }
        return location
    }

    private static func isHorizontalWhitespace(_ character: unichar) -> Bool {
        character == 9 || character == 32
    }

    private static let unorderedListMarkers: Set<String> = [
        "-",
        "*",
        "•",
        "◦",
        "▪",
        "▫",
        "‣",
        "⁃"
    ]
}

private extension NSRange {
    var endLocation: Int {
        location + length
    }
}
