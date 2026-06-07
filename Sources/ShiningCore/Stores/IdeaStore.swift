import AppKit
import Combine
import Foundation

public final class IdeaStore: ObservableObject {
    @Published public private(set) var document: NSAttributedString
    @Published public private(set) var revision = 0

    private let fileURL: URL
    private let timestampFormatter: DateFormatter
    private var pendingSave: DispatchWorkItem?

    public init(fileURL: URL = IdeaStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.timestampFormatter = IdeaStore.makeTimestampFormatter()
        self.document = RichTextDocument.load(from: fileURL)
    }

    public var hasContent: Bool {
        RichTextDocument.hasMeaningfulContent(document)
    }

    public static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return baseURL
            .appendingPathComponent("Shining", isDirectory: true)
            .appendingPathComponent("ideas.rtfd", isDirectory: true)
    }

    public func replaceDocument(_ document: NSAttributedString) {
        self.document = RichTextDocument.copy(document)
        scheduleSave()
    }

    public func appendCapture(_ capture: NSAttributedString, date: Date = Date()) -> Bool {
        guard RichTextDocument.hasMeaningfulContent(capture) else {
            return false
        }

        let timestamp = timestampFormatter.string(from: date)
        let updatedDocument = IdeaRichTextAppender.append(
            existing: document,
            capture: capture,
            timestamp: timestamp
        )

        document = updatedDocument
        revision += 1
        saveNow()
        return true
    }

    public func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil

        do {
            try RichTextDocument.save(document, to: fileURL)
        } catch {
            assertionFailure("Failed to save ideas: \(error)")
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        pendingSave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    private static func makeTimestampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }
}
