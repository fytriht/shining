import AppKit
import Foundation

public enum RichTextDocument {
    public static func empty() -> NSAttributedString {
        NSAttributedString(string: "")
    }

    public static func copy(_ document: NSAttributedString) -> NSAttributedString {
        NSAttributedString(attributedString: document)
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
}

public enum IdeaTimestampInserter {
    public struct Insertion {
        public let document: NSAttributedString
        public let cursorRange: NSRange
    }

    public static func insert(
        timestamp: String,
        into existing: NSAttributedString
    ) -> Insertion {
        let result = NSMutableAttributedString()
        let timestampBlock = timestampLine(timestamp)
        result.append(timestampBlock)

        let cursorRange = NSRange(location: timestampBlock.length, length: 0)

        if RichTextDocument.hasMeaningfulContent(existing) {
            result.append(bodyText("\n\n"))
            result.append(RichTextDocument.copy(existing))
        }

        return Insertion(document: result, cursorRange: cursorRange)
    }

    private static func timestampLine(_ timestamp: String) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: timestamp,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            ]
        )
        result.append(bodyText("\n\n"))
        return result
    }

    private static func bodyText(_ string: String) -> NSAttributedString {
        NSAttributedString(
            string: string,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }
}
