import AppKit
import Foundation

public enum RichTextDocument {
    public static func empty() -> NSAttributedString {
        NSAttributedString(string: "")
    }

    public static func copy(_ document: NSAttributedString) -> NSAttributedString {
        NSAttributedString(attributedString: document)
    }

    public static func timestampBlockCount(in document: NSAttributedString) -> Int {
        findTimestampLines(in: document).count
    }

    public static func isUserEditableRange(
        _ range: NSRange,
        in document: NSAttributedString
    ) -> Bool {
        guard isValidRange(range, in: document) else {
            return false
        }

        return findTimestampLines(in: document).allSatisfy { timestampLine in
            !timestampLine.protectsEdit(range, documentLength: document.length)
        }
    }

    public static func isUserEditableRange(
        _ range: NSRange,
        replacementString: String?,
        in document: NSAttributedString
    ) -> Bool {
        if replacementString == "" {
            return isUserDeletableRange(range, in: document)
        }

        guard isValidRange(range, in: document) else {
            return false
        }

        if replacementString == "\n",
           range.length == 0,
           isTimestampLineContentEnd(range.location, in: document) {
            return true
        }

        return isUserEditableRange(range, in: document)
    }

    public static func isTimestampLineContentEnd(
        _ location: Int,
        in document: NSAttributedString
    ) -> Bool {
        guard location >= 0, location <= document.length else {
            return false
        }

        return findTimestampLines(in: document).contains {
            $0.contentRange.endLocation == location
        }
    }

    public static func isUserDeletableRange(
        _ range: NSRange,
        in document: NSAttributedString
    ) -> Bool {
        guard isValidRange(range, in: document) else {
            return false
        }

        guard range.length > 0 else {
            return true
        }

        let string = document.string as NSString
        return findTimestampLines(in: document).allSatisfy { timestampLine in
            timestampLine.allowsDeletion(range, in: string)
        }
    }

    public static func timestampLineDeletionRangeForBackwardDelete(
        at location: Int,
        in document: NSAttributedString
    ) -> NSRange? {
        guard location >= 0, location <= document.length else {
            return nil
        }

        return findTimestampLines(in: document)
            .first { $0.contentRange.endLocation == location }?
            .lineRange
    }

    public static func timestampLineEndLocationForBackwardDelete(
        at location: Int,
        in document: NSAttributedString
    ) -> Int? {
        guard location >= 0, location <= document.length else {
            return nil
        }

        return findTimestampLines(in: document)
            .first {
                $0.lineRange.endLocation == location &&
                    $0.contentRange.endLocation < $0.lineRange.endLocation
            }?
            .contentRange
            .endLocation
    }

    public static func timestampLineDeletionRangeForForwardDelete(
        at location: Int,
        in document: NSAttributedString
    ) -> NSRange? {
        guard location >= 0, location <= document.length else {
            return nil
        }

        return findTimestampLines(in: document)
            .first { $0.lineRange.location == location }?
            .lineRange
    }

    public static func cleaned(_ document: NSAttributedString) -> NSAttributedString {
        let timestampLines = findTimestampLines(in: document)
        guard !timestampLines.isEmpty else {
            return trimmedCopy(
                of: document,
                in: NSRange(location: 0, length: document.length)
            )
        }

        let result = NSMutableAttributedString()
        let prefixRange = NSRange(location: 0, length: timestampLines[0].lineRange.location)
        appendSection(
            trimmedCopy(of: document, in: prefixRange),
            to: result
        )

        for index in timestampLines.indices {
            let timestampLine = timestampLines[index]
            let nextBlockLocation: Int
            if index < timestampLines.index(before: timestampLines.endIndex) {
                let nextIndex = timestampLines.index(after: index)
                nextBlockLocation = timestampLines[nextIndex].lineRange.location
            } else {
                nextBlockLocation = document.length
            }

            let bodyStart = timestampLine.lineRange.endLocation
            let bodyRange = NSRange(
                location: bodyStart,
                length: max(0, nextBlockLocation - bodyStart)
            )
            let body = trimmedCopy(of: document, in: bodyRange)
            guard hasMeaningfulContent(body) else {
                continue
            }

            let block = NSMutableAttributedString()
            block.append(document.attributedSubstring(from: timestampLine.contentRange))
            block.append(bodyText("\n\n"))
            block.append(body)
            appendSection(block, to: result)
        }

        return result
    }

    public static func hasMeaningfulContent(_ document: NSAttributedString) -> Bool {
        if !document.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        var hasAttachment = false
        document.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: document.length)
        ) { value, _, stop in
            if value is NSTextAttachment {
                hasAttachment = true
                stop.pointee = true
            }
        }

        return hasAttachment
    }

    static func bodyText(_ string: String) -> NSAttributedString {
        NSAttributedString(
            string: string,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    public static func load(from fileURL: URL) -> NSAttributedString {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return empty()
        }

        do {
            let wrapper = try FileWrapper(url: fileURL, options: [])
            return NSAttributedString(
                rtfdFileWrapper: wrapper,
                documentAttributes: nil
            ) ?? empty()
        } catch {
            assertionFailure("Failed to load RTFD document: \(error)")
            return empty()
        }
    }

    public static func save(_ document: NSAttributedString, to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let wrapper = try document.fileWrapper(
            from: NSRange(location: 0, length: document.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.rtfd
            ]
        )

        let originalURL = FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
        try wrapper.write(
            to: fileURL,
            options: .atomic,
            originalContentsURL: originalURL
        )
    }

    private static func appendSection(
        _ section: NSAttributedString,
        to result: NSMutableAttributedString
    ) {
        guard hasMeaningfulContent(section) else {
            return
        }

        if result.length > 0 {
            result.append(bodyText("\n\n"))
        }
        result.append(section)
    }

    private static func trimmedCopy(
        of document: NSAttributedString,
        in range: NSRange
    ) -> NSAttributedString {
        let trimmedRange = trimmedRange(in: document.string as NSString, range: range)
        guard trimmedRange.length > 0 else {
            return empty()
        }

        return document.attributedSubstring(from: trimmedRange)
    }

    private static func trimmedRange(in string: NSString, range: NSRange) -> NSRange {
        var start = range.location
        var end = range.endLocation

        while start < end, isWhitespace(string.character(at: start)) {
            start += 1
        }

        while end > start, isWhitespace(string.character(at: end - 1)) {
            end -= 1
        }

        return NSRange(location: start, length: end - start)
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        guard let scalar = UnicodeScalar(Int(character)) else {
            return false
        }

        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private static func isValidRange(
        _ range: NSRange,
        in document: NSAttributedString
    ) -> Bool {
        guard range.location >= 0,
              range.length >= 0,
              range.location <= document.length else {
            return false
        }

        return range.length <= document.length - range.location
    }

    private static func findTimestampLines(in document: NSAttributedString) -> [TimestampLine] {
        let string = document.string as NSString
        var lines: [TimestampLine] = []
        var location = 0

        while location < string.length {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            string.getLineStart(
                &lineStart,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: location, length: 0)
            )

            let contentRange = NSRange(
                location: lineStart,
                length: contentsEnd - lineStart
            )
            if isTimestampLine(string.substring(with: contentRange)) {
                lines.append(
                    TimestampLine(
                        lineRange: NSRange(location: lineStart, length: lineEnd - lineStart),
                        contentRange: contentRange
                    )
                )
            }

            location = max(lineEnd, location + 1)
        }

        return lines
    }

    private static func isTimestampLine(_ line: String) -> Bool {
        guard line.count == 18 else {
            return false
        }

        let characters = Array(line)
        let digitPositions = [2, 3, 4, 5, 7, 8, 10, 11, 13, 14, 16, 17]
        for position in digitPositions where !isASCIIDigit(characters[position]) {
            return false
        }

        return characters[0] == "#"
            && characters[1] == " "
            && characters[6] == "-"
            && characters[9] == "-"
            && characters[12] == " "
            && characters[15] == ":"
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.only else {
            return false
        }

        return scalar.value >= 48 && scalar.value <= 57
    }

    private struct TimestampLine {
        let lineRange: NSRange
        let contentRange: NSRange

        func protectsEdit(_ range: NSRange, documentLength: Int) -> Bool {
            if range.length == 0 {
                return protectsInsertion(at: range.location, documentLength: documentLength)
            }

            if NSIntersectionRange(range, lineRange).length > 0 {
                return true
            }

            return range.endLocation == lineRange.location
        }

        private func protectsInsertion(at location: Int, documentLength: Int) -> Bool {
            if NSLocationInRange(location, lineRange) {
                return true
            }

            let hasTerminatingNewline = lineRange.endLocation > contentRange.endLocation
            return !hasTerminatingNewline &&
                lineRange.endLocation == documentLength &&
                location == lineRange.endLocation
        }

        func allowsDeletion(_ range: NSRange, in string: NSString) -> Bool {
            if NSIntersectionRange(range, lineRange).length > 0 {
                return range.location <= lineRange.location &&
                    range.endLocation >= lineRange.endLocation
            }

            guard range.endLocation == lineRange.location else {
                return true
            }

            if range.location == 0 {
                return true
            }

            return isLineEnding(string.character(at: range.location - 1))
        }

        private func isLineEnding(_ character: unichar) -> Bool {
            character == 10 || character == 13
        }
    }
}

private extension String.UnicodeScalarView {
    var only: UnicodeScalar? {
        count == 1 ? first : nil
    }
}

public enum IdeaTimestampInserter {
    public struct Insertion {
        public let document: NSAttributedString
        public let cursorRange: NSRange
    }

    public static func insert(
        timestamp: String,
        selectedText: String? = nil,
        into existing: NSAttributedString
    ) -> Insertion {
        let result = NSMutableAttributedString()
        let timestampBlock = timestampLine(timestamp)
        result.append(timestampBlock)

        let selectedBody = selectedText.flatMap { text in
            text.isEmpty ? nil : RichTextDocument.bodyText(text)
        }
        let cursorRange: NSRange
        if let selectedBody {
            let selectionLocation = result.length
            result.append(selectedBody)
            cursorRange = NSRange(location: selectionLocation, length: selectedBody.length)
        } else {
            cursorRange = NSRange(location: timestampBlock.length, length: 0)
        }

        if RichTextDocument.hasMeaningfulContent(existing) {
            result.append(RichTextDocument.bodyText("\n\n"))
            result.append(RichTextDocument.copy(existing))
        }

        return Insertion(document: result, cursorRange: cursorRange)
    }

    private static func timestampLine(_ timestamp: String) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: "# \(timestamp)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium)
            ]
        )
        result.append(RichTextDocument.bodyText("\n\n"))
        return result
    }
}

private extension NSRange {
    var endLocation: Int {
        location + length
    }
}
