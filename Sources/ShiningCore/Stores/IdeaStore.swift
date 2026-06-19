import AppKit
import Combine
import Foundation

public final class IdeaStore: ObservableObject {
    public struct PendingSelectionInsertion {
        fileprivate let revision: Int
        fileprivate let documentAfterTimestamp: NSAttributedString
        fileprivate let insertionRange: NSRange
    }

    public struct DelayedSelectionTimestampInsertion {
        public let cursorRange: NSRange
        public let pendingSelectionInsertion: PendingSelectionInsertion
    }

    @Published public private(set) var document: NSAttributedString
    @Published public private(set) var revision = 0
    @Published public private(set) var savedTimestampBlockCount: Int

    private let fileURL: URL
    private let timestampFormatter: DateFormatter
    private var pendingSave: DispatchWorkItem?

    public init(fileURL: URL = IdeaStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.timestampFormatter = IdeaStore.makeTimestampFormatter()
        let document = RichTextDocument.load(from: fileURL)
        self.document = document
        self.savedTimestampBlockCount = RichTextDocument.timestampBlockCount(in: document)
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

    @discardableResult
    public func cleanUpDocument(saveImmediately: Bool = false) -> Bool {
        let cleanedDocument = RichTextDocument.cleaned(document)
        guard !document.isEqual(to: cleanedDocument) else {
            if saveImmediately {
                saveNow()
            }
            return false
        }

        document = cleanedDocument
        revision += 1

        if saveImmediately {
            saveNow()
        } else {
            scheduleSave()
        }
        return true
    }

    @discardableResult
    public func insertTimestamp(
        date: Date = Date(),
        selectedText: String? = nil
    ) -> NSRange {
        let selectedContent = selectedText.flatMap { text in
            RichTextPasteSanitizer.sanitizedTrimmedPlainText(text)
        }
        return insertTimestamp(date: date, selectedContent: selectedContent)
    }

    @discardableResult
    public func insertTimestamp(
        date: Date = Date(),
        selectedContent: NSAttributedString?
    ) -> NSRange {
        cleanUpDocument()

        let timestamp = timestampFormatter.string(from: date)
        let insertion = IdeaTimestampInserter.insert(
            timestamp: timestamp,
            selectedContent: selectedContent,
            into: document
        )

        document = insertion.document
        revision += 1
        saveNow()
        return insertion.cursorRange
    }

    public func insertTimestampForDelayedSelection(
        date: Date = Date()
    ) -> DelayedSelectionTimestampInsertion {
        let cursorRange = insertTimestamp(date: date)
        return DelayedSelectionTimestampInsertion(
            cursorRange: cursorRange,
            pendingSelectionInsertion: PendingSelectionInsertion(
                revision: revision,
                documentAfterTimestamp: RichTextDocument.copy(document),
                insertionRange: cursorRange
            )
        )
    }

    @discardableResult
    public func insertSelectedText(
        _ selectedText: String?,
        for pendingInsertion: PendingSelectionInsertion
    ) -> NSRange? {
        let selectedContent = selectedText.flatMap { text in
            RichTextPasteSanitizer.sanitizedTrimmedPlainText(text)
        }
        return insertSelectedContent(selectedContent, for: pendingInsertion)
    }

    @discardableResult
    public func insertSelectedContent(
        _ selectedContent: NSAttributedString?,
        for pendingInsertion: PendingSelectionInsertion
    ) -> NSRange? {
        guard let selectedContent,
              selectedContent.length > 0,
              revision == pendingInsertion.revision,
              document.isEqual(to: pendingInsertion.documentAfterTimestamp),
              pendingInsertion.insertionRange.length == 0,
              pendingInsertion.insertionRange.location >= 0,
              pendingInsertion.insertionRange.location <= document.length else {
            return nil
        }

        let selectedBody = RichTextPasteSanitizer.sanitizedTrimmedAttributedString(
            selectedContent,
            normalizesLists: true
        )
        guard selectedBody.length > 0 else {
            return nil
        }

        let selectedRange = NSRange(
            location: pendingInsertion.insertionRange.location,
            length: selectedBody.length
        )
        let updatedDocument = NSMutableAttributedString(attributedString: document)
        updatedDocument.insert(selectedBody, at: pendingInsertion.insertionRange.location)

        document = updatedDocument
        revision += 1
        saveNow()
        return selectedRange
    }

    public func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil

        do {
            try RichTextDocument.save(document, to: fileURL)
            savedTimestampBlockCount = RichTextDocument.timestampBlockCount(in: document)
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
