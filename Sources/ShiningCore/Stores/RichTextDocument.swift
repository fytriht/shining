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

public enum IdeaRichTextAppender {
    public static func append(
        existing: NSAttributedString,
        capture: NSAttributedString,
        timestamp: String
    ) -> NSAttributedString {
        guard RichTextDocument.hasMeaningfulContent(capture) else {
            return RichTextDocument.copy(existing)
        }

        let result = NSMutableAttributedString(attributedString: existing)
        trimTrailingNewlines(in: result)

        if RichTextDocument.hasMeaningfulContent(result) {
            result.append(NSAttributedString(string: "\n\n"))
        }

        result.append(timestampLine(timestamp))
        result.append(RichTextDocument.copy(capture))
        trimTrailingNewlines(in: result)
        return result
    }

    private static func timestampLine(_ timestamp: String) -> NSAttributedString {
        NSAttributedString(
            string: "\(timestamp)\n\n",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            ]
        )
    }

    private static func trimTrailingNewlines(in document: NSMutableAttributedString) {
        while let last = document.string.unicodeScalars.last,
              CharacterSet.newlines.contains(last) {
            document.deleteCharacters(in: NSRange(location: document.length - 1, length: 1))
        }
    }
}
