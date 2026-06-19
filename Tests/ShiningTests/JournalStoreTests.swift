import AppKit
import XCTest
@testable import ShiningCore

final class JournalStoreTests: XCTestCase {
    func testNewJournalStartsWithZeroSavedEntryCount() throws {
        let urls = makeTemporaryJournalURLs()
        defer { try? FileManager.default.removeItem(at: urls.directory) }

        let store = JournalStore(
            documentURL: urls.documentURL,
            attachmentsDirectory: urls.attachmentsDirectory
        )

        XCTAssertEqual(store.savedEntryCount, 0)
        XCTAssertEqual(store.document.entries.count, 0)
    }

    func testInsertEntryPlacesNewestEntryAtTop() throws {
        let urls = makeTemporaryJournalURLs()
        defer { try? FileManager.default.removeItem(at: urls.directory) }
        let store = JournalStore(
            documentURL: urls.documentURL,
            attachmentsDirectory: urls.attachmentsDirectory
        )

        let olderDate = makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        let newerDate = makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 41)
        store.insertEntry(date: olderDate, selectedText: "older idea")
        let selection = store.insertEntry(date: newerDate, selectedText: "newer idea")

        XCTAssertEqual(store.document.entries.map(\.createdAt), [newerDate, olderDate])
        XCTAssertEqual(paragraphText(in: store.document.entries[0]), "newer idea")
        XCTAssertEqual(selection.entryID, store.document.entries[0].id)
        XCTAssertEqual(selection.range.location, 0)
        XCTAssertEqual(selection.range.length, "newer idea".utf16.count)
        XCTAssertEqual(store.savedEntryCount, 2)
    }

    func testDelayedSelectedTextInsertionUpdatesPendingEmptyParagraph() throws {
        let urls = makeTemporaryJournalURLs()
        defer { try? FileManager.default.removeItem(at: urls.directory) }
        let store = JournalStore(
            documentURL: urls.documentURL,
            attachmentsDirectory: urls.attachmentsDirectory
        )

        let insertion = store.insertEntryForDelayedSelection(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        )
        let selection = try XCTUnwrap(
            store.insertSelectedText("captured idea", for: insertion.pendingSelectionInsertion)
        )

        XCTAssertEqual(paragraphText(in: store.document.entries[0]), "captured idea")
        XCTAssertEqual(selection.entryID, store.document.entries[0].id)
        XCTAssertEqual(selection.range.location, 0)
        XCTAssertEqual(selection.range.length, "captured idea".utf16.count)
        XCTAssertEqual(store.savedEntryCount, 1)
    }

    func testEmptyEntryIsCleanedAndDoesNotCountForBadge() throws {
        let urls = makeTemporaryJournalURLs()
        defer { try? FileManager.default.removeItem(at: urls.directory) }
        let store = JournalStore(
            documentURL: urls.documentURL,
            attachmentsDirectory: urls.attachmentsDirectory
        )

        store.insertEntry(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        )

        XCTAssertEqual(store.document.entries.count, 1)
        XCTAssertEqual(store.savedEntryCount, 0)
        XCTAssertTrue(store.cleanUpDocument(saveImmediately: true))
        XCTAssertEqual(store.document.entries.count, 0)
        XCTAssertEqual(store.savedEntryCount, 0)
    }

    func testJSONSaveAndLoadPreservesParagraphAndImageMetadata() throws {
        let urls = makeTemporaryJournalURLs()
        defer { try? FileManager.default.removeItem(at: urls.directory) }
        let entryID = UUID()
        let paragraphID = UUID()
        let imageID = UUID()
        let document = JournalDocument(
            entries: [
                JournalEntry(
                    id: entryID,
                    createdAt: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40),
                    blocks: [
                        .paragraph(JournalParagraphBlock(id: paragraphID, text: "body")),
                        .image(
                            JournalImageBlock(
                                id: imageID,
                                assetID: "asset.png",
                                originalFilename: "source.png",
                                pixelSize: JournalImageSize(width: 320, height: 180)
                            )
                        )
                    ]
                )
            ]
        )
        let store = JournalStore(
            documentURL: urls.documentURL,
            attachmentsDirectory: urls.attachmentsDirectory
        )

        store.replaceDocument(document)
        store.saveNow()

        let reloaded = JournalStore(
            documentURL: urls.documentURL,
            attachmentsDirectory: urls.attachmentsDirectory
        )
        XCTAssertEqual(reloaded.document, document)
        XCTAssertEqual(reloaded.savedEntryCount, 1)
    }

    func testProjectionCreatesProtectedTimestampAndParagraphSelectionRange() throws {
        let entry = JournalEntry(
            createdAt: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40),
            blocks: [.paragraph(JournalParagraphBlock(text: "body"))]
        )
        let document = JournalDocument(entries: [entry])
        let projection = JournalProjection.make(document: document) { _ in nil }

        let timestampRange = try XCTUnwrap(
            projection.ranges.first { $0.role == .timestampSeparator }
        )
        let paragraphRange = try XCTUnwrap(
            projection.ranges.first { $0.role == .paragraph }
        )
        let paragraph = try XCTUnwrap(entry.blocks.first)
        guard case let .paragraph(paragraphBlock) = paragraph else {
            XCTFail("Expected paragraph")
            return
        }

        XCTAssertEqual(
            (projection.attributedString.string as NSString).substring(with: timestampRange.range),
            JournalProjection.formattedTimestamp(entry.createdAt)
        )
        XCTAssertNotNil(projection.protectedRange(forChangeIn: timestampRange.range))
        XCTAssertNil(projection.protectedRange(forChangeIn: paragraphRange.range))
        XCTAssertEqual(
            projection.selectionRange(
                for: JournalTextSelection(
                    entryID: entry.id,
                    blockID: paragraphBlock.id,
                    range: NSRange(location: 1, length: 2)
                )
            ),
            NSRange(location: paragraphRange.range.location + 1, length: 2)
        )
    }

    func testProjectionRebuildsDocumentAfterParagraphEdit() throws {
        let paragraph = JournalParagraphBlock(text: "body")
        let entry = JournalEntry(
            createdAt: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40),
            blocks: [.paragraph(paragraph)]
        )
        let document = JournalDocument(entries: [entry])
        let projection = JournalProjection.make(document: document) { _ in nil }
        let paragraphRange = try XCTUnwrap(
            projection.ranges.first { $0.role == .paragraph }
        )
        let mutable = NSMutableAttributedString(attributedString: projection.attributedString)
        mutable.replaceCharacters(
            in: paragraphRange.range,
            with: NSAttributedString(
                string: "changed",
                attributes: JournalProjection.paragraphAttributes(
                    entryID: entry.id,
                    blockID: paragraph.id
                )
            )
        )

        let rebuilt = JournalProjection.document(
            from: mutable,
            fallbackDocument: document
        )

        XCTAssertEqual(paragraphText(in: rebuilt.entries[0]), "changed")
    }

    func testProjectionKeepsUnattributedTextInsertedInsideParagraph() throws {
        let paragraph = JournalParagraphBlock(text: "")
        let entry = JournalEntry(
            createdAt: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40),
            blocks: [.paragraph(paragraph)]
        )
        let document = JournalDocument(entries: [entry])
        let projection = JournalProjection.make(document: document) { _ in nil }
        let paragraphRange = try XCTUnwrap(
            projection.ranges.first { $0.role == .paragraph }
        )
        let mutable = NSMutableAttributedString(attributedString: projection.attributedString)
        mutable.insert(
            NSAttributedString(
                string: "中文输入",
                attributes: [.font: NSFont.systemFont(ofSize: 15)]
            ),
            at: paragraphRange.range.location
        )

        let rebuilt = JournalProjection.document(
            from: mutable,
            fallbackDocument: document
        )

        XCTAssertEqual(paragraphText(in: rebuilt.entries[0]), "中文输入")
    }

    func testProjectionKeepsUnattributedTextInsertedBeforeOlderEntry() throws {
        let newerParagraph = JournalParagraphBlock(text: "")
        let olderParagraph = JournalParagraphBlock(text: "都")
        let newerEntry = JournalEntry(
            createdAt: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 41),
            blocks: [.paragraph(newerParagraph)]
        )
        let olderEntry = JournalEntry(
            createdAt: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40),
            blocks: [.paragraph(olderParagraph)]
        )
        let document = JournalDocument(entries: [newerEntry, olderEntry])
        let projection = JournalProjection.make(document: document) { _ in nil }
        let newerParagraphRange = try XCTUnwrap(
            projection.ranges.first {
                $0.entryID == newerEntry.id && $0.role == .paragraph
            }
        )
        let mutable = NSMutableAttributedString(attributedString: projection.attributedString)
        mutable.insert(
            NSAttributedString(
                string: "d'd",
                attributes: [.font: NSFont.systemFont(ofSize: 15)]
            ),
            at: newerParagraphRange.range.location
        )

        let rebuilt = JournalProjection.document(
            from: mutable,
            fallbackDocument: document
        )

        XCTAssertEqual(rebuilt.entries.map(\.id), [newerEntry.id, olderEntry.id])
        XCTAssertEqual(paragraphText(in: rebuilt.entries[0]), "d'd")
        XCTAssertEqual(paragraphText(in: rebuilt.entries[1]), "都")
    }

    func testProjectionRejectsTimestampEdits() throws {
        let entry = JournalEntry(
            createdAt: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40),
            blocks: [.paragraph(JournalParagraphBlock(text: "body"))]
        )
        let projection = JournalProjection.make(
            document: JournalDocument(entries: [entry])
        ) { _ in nil }
        let timestampRange = try XCTUnwrap(
            projection.ranges.first { $0.role == .timestampSeparator }
        )

        XCTAssertNotNil(
            projection.protectedRange(
                forChangeIn: NSRange(location: timestampRange.range.location + 2, length: 1)
            )
        )
        XCTAssertNotNil(
            projection.protectedRange(
                forChangeIn: NSRange(location: timestampRange.range.location, length: 0)
            )
        )
    }

    private func paragraphText(in entry: JournalEntry) -> String? {
        guard let block = entry.blocks.first else {
            return nil
        }

        if case let .paragraph(paragraph) = block {
            return paragraph.text
        }
        return nil
    }

    private func makeTemporaryJournalURLs() -> (
        directory: URL,
        documentURL: URL,
        attachmentsDirectory: URL
    ) {
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let journalDirectory = directory.appendingPathComponent("journal", isDirectory: true)
        return (
            directory,
            journalDirectory.appendingPathComponent("document.json"),
            journalDirectory.appendingPathComponent("attachments", isDirectory: true)
        )
    }

    private func makeLocalDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
