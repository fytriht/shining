import AppKit
import Combine
import Foundation

public final class JournalStore: ObservableObject {
    public struct PendingSelectionInsertion {
        fileprivate let revision: Int
        fileprivate let documentAfterEntry: JournalDocument
        fileprivate let insertionSelection: JournalTextSelection
    }

    public struct DelayedSelectionEntryInsertion {
        public let cursorSelection: JournalTextSelection
        public let pendingSelectionInsertion: PendingSelectionInsertion
    }

    @Published public private(set) var document: JournalDocument
    @Published public private(set) var revision = 0
    @Published public private(set) var savedEntryCount: Int

    private let documentURL: URL
    private let attachmentsDirectory: URL
    private var pendingSave: DispatchWorkItem?

    public init(
        documentURL: URL = JournalStore.defaultDocumentURL(),
        attachmentsDirectory: URL? = nil
    ) {
        self.documentURL = documentURL
        self.attachmentsDirectory = attachmentsDirectory ??
            documentURL
            .deletingLastPathComponent()
            .appendingPathComponent("attachments", isDirectory: true)

        let loadedDocument = Self.load(from: documentURL).cleaned()
        self.document = loadedDocument
        self.savedEntryCount = loadedDocument.nonEmptyEntryCount
    }

    public var hasContent: Bool {
        document.nonEmptyEntryCount > 0
    }

    public static func defaultDocumentURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return baseURL
            .appendingPathComponent("Shining", isDirectory: true)
            .appendingPathComponent("journal", isDirectory: true)
            .appendingPathComponent("document.json")
    }

    public func attachmentURL(for assetID: String) -> URL {
        attachmentsDirectory.appendingPathComponent(assetID, isDirectory: false)
    }

    public func replaceDocument(_ document: JournalDocument) {
        self.document = document
        scheduleSave()
    }

    @discardableResult
    public func cleanUpDocument(saveImmediately: Bool = false) -> Bool {
        let cleanedDocument = document.cleaned()
        guard cleanedDocument != document else {
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
    public func insertEntry(
        date: Date = Date(),
        selectedText: String? = nil
    ) -> JournalTextSelection {
        cleanUpDocument()

        let paragraph = JournalParagraphBlock(text: selectedText ?? "")
        let entry = JournalEntry(
            createdAt: date,
            blocks: [.paragraph(paragraph)]
        )

        document.entries.insert(entry, at: 0)
        revision += 1
        saveNow()

        return JournalTextSelection(
            entryID: entry.id,
            blockID: paragraph.id,
            range: NSRange(location: 0, length: paragraph.text.utf16.count)
        )
    }

    public func insertEntryForDelayedSelection(
        date: Date = Date()
    ) -> DelayedSelectionEntryInsertion {
        let selection = insertEntry(date: date)
        return DelayedSelectionEntryInsertion(
            cursorSelection: selection,
            pendingSelectionInsertion: PendingSelectionInsertion(
                revision: revision,
                documentAfterEntry: document,
                insertionSelection: selection
            )
        )
    }

    @discardableResult
    public func insertSelectedText(
        _ selectedText: String?,
        for pendingInsertion: PendingSelectionInsertion
    ) -> JournalTextSelection? {
        guard let selectedText,
              !selectedText.isEmpty,
              revision == pendingInsertion.revision,
              document == pendingInsertion.documentAfterEntry,
              pendingInsertion.insertionSelection.range.location == 0,
              pendingInsertion.insertionSelection.range.length == 0,
              let entryIndex = document.entries.firstIndex(where: {
                  $0.id == pendingInsertion.insertionSelection.entryID
              }),
              let blockIndex = document.entries[entryIndex].blocks.firstIndex(where: {
                  $0.id == pendingInsertion.insertionSelection.blockID
              }) else {
            return nil
        }

        guard case var .paragraph(paragraph) = document.entries[entryIndex].blocks[blockIndex],
              paragraph.text.isEmpty else {
            return nil
        }

        paragraph.text = selectedText
        document.entries[entryIndex].blocks[blockIndex] = .paragraph(paragraph)
        revision += 1
        saveNow()

        return JournalTextSelection(
            entryID: pendingInsertion.insertionSelection.entryID,
            blockID: paragraph.id,
            range: NSRange(location: 0, length: selectedText.utf16.count)
        )
    }

    public func importImageFile(_ fileURL: URL) -> JournalImageBlock? {
        guard let image = NSImage(contentsOf: fileURL) else {
            return nil
        }

        let sourceExtension = fileURL.pathExtension.isEmpty ? "image" : fileURL.pathExtension
        let assetID = "\(UUID().uuidString).\(sourceExtension)"
        let destinationURL = attachmentURL(for: assetID)

        do {
            try FileManager.default.createDirectory(
                at: attachmentsDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: fileURL, to: destinationURL)
            return JournalImageBlock(
                assetID: assetID,
                originalFilename: fileURL.lastPathComponent,
                pixelSize: Self.pixelSize(of: image)
            )
        } catch {
            assertionFailure("Failed to import image: \(error)")
            return nil
        }
    }

    public func importImage(
        _ image: NSImage,
        originalFilename: String = "Pasted Image.tiff"
    ) -> JournalImageBlock? {
        guard let data = image.tiffRepresentation else {
            return nil
        }

        let assetID = "\(UUID().uuidString).tiff"
        let destinationURL = attachmentURL(for: assetID)

        do {
            try FileManager.default.createDirectory(
                at: attachmentsDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: destinationURL, options: .atomic)
            return JournalImageBlock(
                assetID: assetID,
                originalFilename: originalFilename,
                pixelSize: Self.pixelSize(of: image)
            )
        } catch {
            assertionFailure("Failed to import pasted image: \(error)")
            return nil
        }
    }

    public func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil

        do {
            try Self.save(document, to: documentURL)
            savedEntryCount = document.nonEmptyEntryCount
        } catch {
            assertionFailure("Failed to save journal: \(error)")
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

    private static func load(from fileURL: URL) -> JournalDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return JournalDocument()
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let document = try decoder.decode(JournalDocument.self, from: data)
            guard document.schemaVersion == 1 else {
                return JournalDocument()
            }
            return document
        } catch {
            assertionFailure("Failed to load journal: \(error)")
            return JournalDocument()
        }
    }

    private static func save(_ document: JournalDocument, to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func pixelSize(of image: NSImage) -> JournalImageSize {
        let representation = image.representations.max { lhs, rhs in
            lhs.pixelsWide * lhs.pixelsHigh < rhs.pixelsWide * rhs.pixelsHigh
        }

        let width = representation?.pixelsWide ?? Int(image.size.width)
        let height = representation?.pixelsHigh ?? Int(image.size.height)
        return JournalImageSize(width: Double(width), height: Double(height))
    }
}
