import AppKit
import XCTest
@testable import ShiningCore

final class IdeaStoreTests: XCTestCase {
    func testEmptyDocumentStartsWithZeroSavedTimestampBlockCount() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)

        XCTAssertEqual(store.savedTimestampBlockCount, 0)
    }

    func testEmptyDocumentInsertsTimestampAndReturnsCursorAtEnd() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        let cursorRange = store.insertTimestamp(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        )
        let expectedDocument = "2026-06-02 08:40\n"

        XCTAssertEqual(store.document.string, expectedDocument)
        XCTAssertEqual(cursorRange.location, expectedDocument.utf16.count)
        XCTAssertEqual(cursorRange.length, 0)
        XCTAssertTrue(store.hasContent)
        XCTAssertEqual(store.savedTimestampBlockCount, 1)

        try assertUsesTimestampAttributes(store.document, at: 0)
    }

    func testExistingDocumentInsertsTimestampAboveContentAndReturnsBodyStart() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: "older idea"))

        let cursorRange = store.insertTimestamp(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        )
        let timestampBlock = "2026-06-02 08:40\n"

        XCTAssertEqual(
            store.document.string,
            "\(timestampBlock)\n\nolder idea"
        )
        XCTAssertEqual(cursorRange.location, timestampBlock.utf16.count)
        XCTAssertEqual(cursorRange.length, 0)
        try assertUsesBodyAttributes(
            store.document,
            in: NSRange(location: timestampBlock.utf16.count, length: 2)
        )
    }

    func testEmptyDocumentInsertsSelectedTextAndReturnsSelectedRange() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        let selectedText = "captured idea"
        let cursorRange = store.insertTimestamp(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40),
            selectedText: selectedText
        )
        let timestampBlock = "2026-06-02 08:40\n"

        XCTAssertEqual(store.document.string, "\(timestampBlock)\(selectedText)")
        XCTAssertEqual(cursorRange.location, timestampBlock.utf16.count)
        XCTAssertEqual(cursorRange.length, selectedText.utf16.count)
        XCTAssertEqual(
            (store.document.string as NSString).substring(with: cursorRange),
            selectedText
        )
        XCTAssertEqual(store.savedTimestampBlockCount, 1)
        try assertUsesBodyAttributes(store.document, in: cursorRange)
    }

    func testExistingDocumentInsertsSelectedTextAboveContentAndReturnsSelectedRange() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: "older idea"))

        let selectedText = "captured idea"
        let cursorRange = store.insertTimestamp(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40),
            selectedText: selectedText
        )
        let timestampBlock = "2026-06-02 08:40\n"

        XCTAssertEqual(
            store.document.string,
            "\(timestampBlock)\(selectedText)\n\nolder idea"
        )
        XCTAssertEqual(cursorRange.location, timestampBlock.utf16.count)
        XCTAssertEqual(cursorRange.length, selectedText.utf16.count)
        XCTAssertEqual(
            (store.document.string as NSString).substring(with: cursorRange),
            selectedText
        )
    }

    func testSelectedTextInsertionPreservesMultilineUnicodeAndReturnsUTF16Range() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        let selectedText = "第一行\nsecond 😀 line"
        let cursorRange = store.insertTimestamp(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40),
            selectedText: selectedText
        )
        let timestampBlock = "2026-06-02 08:40\n"

        XCTAssertEqual(store.document.string, "\(timestampBlock)\(selectedText)")
        XCTAssertEqual(cursorRange.location, timestampBlock.utf16.count)
        XCTAssertEqual(cursorRange.length, selectedText.utf16.count)
        XCTAssertEqual(
            (store.document.string as NSString).substring(with: cursorRange),
            selectedText
        )
    }

    func testSelectedTextInsertionTrimsOuterWhitespaceAndReturnsTrimmedRange() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        let selectedText = "  captured idea\n"
        let trimmedText = "captured idea"
        let cursorRange = store.insertTimestamp(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40),
            selectedText: selectedText
        )
        let timestampBlock = "2026-06-02 08:40\n"

        XCTAssertEqual(store.document.string, "\(timestampBlock)\(trimmedText)")
        XCTAssertEqual(cursorRange.location, timestampBlock.utf16.count)
        XCTAssertEqual(cursorRange.length, trimmedText.utf16.count)
        XCTAssertEqual(
            (store.document.string as NSString).substring(with: cursorRange),
            trimmedText
        )
        try assertUsesBodyAttributes(store.document, in: cursorRange)
    }

    func testEmptySelectedTextKeepsTimestampOnlyInsertionBehavior() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        let cursorRange = store.insertTimestamp(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40),
            selectedText: ""
        )
        let expectedDocument = "2026-06-02 08:40\n"

        XCTAssertEqual(store.document.string, expectedDocument)
        XCTAssertEqual(cursorRange.location, expectedDocument.utf16.count)
        XCTAssertEqual(cursorRange.length, 0)
    }

    func testDelayedSelectionTimestampInsertionReturnsCursorImmediately() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        let insertion = store.insertTimestampForDelayedSelection(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        )
        let expectedDocument = "2026-06-02 08:40\n"

        XCTAssertEqual(store.document.string, expectedDocument)
        XCTAssertEqual(insertion.cursorRange.location, expectedDocument.utf16.count)
        XCTAssertEqual(insertion.cursorRange.length, 0)
        XCTAssertNil(
            store.insertSelectedText(nil, for: insertion.pendingSelectionInsertion)
        )
        XCTAssertEqual(store.document.string, expectedDocument)
    }

    func testPendingSelectionInsertionAddsCapturedText() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: "older idea"))

        let insertion = store.insertTimestampForDelayedSelection(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        )
        let selectedText = "captured idea"
        let selectedRange = try XCTUnwrap(
            store.insertSelectedText(
                selectedText,
                for: insertion.pendingSelectionInsertion
            )
        )
        let timestampBlock = "2026-06-02 08:40\n"

        XCTAssertEqual(
            store.document.string,
            "\(timestampBlock)\(selectedText)\n\nolder idea"
        )
        XCTAssertEqual(selectedRange.location, timestampBlock.utf16.count)
        XCTAssertEqual(selectedRange.length, selectedText.utf16.count)
        XCTAssertEqual(
            (store.document.string as NSString).substring(with: selectedRange),
            selectedText
        )
    }

    func testPendingSelectionInsertionTrimsOuterWhitespace() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        let insertion = store.insertTimestampForDelayedSelection(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        )
        let selectedText = "\n\tsecond capture  "
        let trimmedText = "second capture"
        let selectedRange = try XCTUnwrap(
            store.insertSelectedText(
                selectedText,
                for: insertion.pendingSelectionInsertion
            )
        )
        let timestampBlock = "2026-06-02 08:40\n"

        XCTAssertEqual(store.document.string, "\(timestampBlock)\(trimmedText)")
        XCTAssertEqual(selectedRange.location, timestampBlock.utf16.count)
        XCTAssertEqual(selectedRange.length, trimmedText.utf16.count)
        XCTAssertEqual(
            (store.document.string as NSString).substring(with: selectedRange),
            trimmedText
        )
    }

    func testPendingSelectionInsertionNormalizesCapturedRichTextList() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        let insertion = store.insertTimestampForDelayedSelection(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        )
        let selectedRange = try XCTUnwrap(
            store.insertSelectedContent(
                makeUnorderedListAttributedString("A\nB"),
                for: insertion.pendingSelectionInsertion
            )
        )
        let timestampBlock = "2026-06-02 08:40\n"
        let selectedText = "- A\n- B"

        XCTAssertEqual(store.document.string, "\(timestampBlock)\(selectedText)")
        XCTAssertEqual(selectedRange.location, timestampBlock.utf16.count)
        XCTAssertEqual(selectedRange.length, selectedText.utf16.count)
        XCTAssertEqual(
            (store.document.string as NSString).substring(with: selectedRange),
            selectedText
        )
        try assertUsesBodyAttributes(store.document, in: selectedRange)
    }

    func testPendingSelectionInsertionTrimsOuterWhitespaceAroundRichTextList() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        let insertion = store.insertTimestampForDelayedSelection(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        )
        let selectedContent = NSMutableAttributedString(string: "\n")
        selectedContent.append(makeUnorderedListAttributedString("A\nB"))
        selectedContent.append(NSAttributedString(string: "\n"))

        let selectedRange = try XCTUnwrap(
            store.insertSelectedContent(
                selectedContent,
                for: insertion.pendingSelectionInsertion
            )
        )
        let timestampBlock = "2026-06-02 08:40\n"
        let selectedText = "- A\n- B"

        XCTAssertEqual(store.document.string, "\(timestampBlock)\(selectedText)")
        XCTAssertEqual(selectedRange.location, timestampBlock.utf16.count)
        XCTAssertEqual(selectedRange.length, selectedText.utf16.count)
        XCTAssertEqual(
            (store.document.string as NSString).substring(with: selectedRange),
            selectedText
        )
        try assertUsesBodyAttributes(store.document, in: selectedRange)
    }

    func testPendingSelectionInsertionSkipsAfterUserEdit() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        let insertion = store.insertTimestampForDelayedSelection(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        )
        let editedDocument = NSAttributedString(
            string: "\(store.document.string)typed before capture"
        )
        store.replaceDocument(editedDocument)

        XCTAssertNil(
            store.insertSelectedText(
                "captured idea",
                for: insertion.pendingSelectionInsertion
            )
        )
        XCTAssertEqual(store.document.string, editedDocument.string)
    }

    func testEarlierPendingSelectionDoesNotModifyAfterSecondTimestamp() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        let date = makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        let firstInsertion = store.insertTimestampForDelayedSelection(date: date)
        let secondInsertion = store.insertTimestampForDelayedSelection(date: date)

        XCTAssertNil(
            store.insertSelectedText(
                "first capture",
                for: firstInsertion.pendingSelectionInsertion
            )
        )

        let selectedText = "second capture"
        let selectedRange = try XCTUnwrap(
            store.insertSelectedText(
                selectedText,
                for: secondInsertion.pendingSelectionInsertion
            )
        )
        let timestampBlock = "2026-06-02 08:40\n"

        XCTAssertEqual(
            store.document.string,
            "\(timestampBlock)\(selectedText)"
        )
        XCTAssertEqual(selectedRange.location, timestampBlock.utf16.count)
        XCTAssertEqual(selectedRange.length, selectedText.utf16.count)
    }

    func testConsecutiveTimestampsInsertInReverseOrder() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        store.insertTimestamp(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        )
        let cursorRange = store.insertTimestamp(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 41)
        )
        let latestTimestampBlock = "2026-06-02 08:41\n"

        XCTAssertEqual(
            store.document.string,
            latestTimestampBlock
        )
        XCTAssertEqual(cursorRange.location, latestTimestampBlock.utf16.count)
        XCTAssertEqual(cursorRange.length, 0)
        XCTAssertEqual(store.savedTimestampBlockCount, 1)
    }

    func testTimestampInsertPreservesExistingTimestampBlockSpacing() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let existingDocument = "2026-06-02 08:39\nolder idea"
        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: existingDocument))

        let cursorRange = store.insertTimestamp(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        )
        let timestampBlock = "2026-06-02 08:40\n"

        XCTAssertEqual(
            store.document.string,
            "\(timestampBlock)\n\n\(existingDocument)"
        )
        XCTAssertEqual(cursorRange.location, timestampBlock.utf16.count)
        XCTAssertEqual(cursorRange.length, 0)
    }

    func testTimestampInsertNormalizesExistingTimestampLineAttributes() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }
        let existingDocument = makeDocumentWithLargeTimestampLine(
            timestamp: "2026-06-02 08:39",
            body: "older idea"
        )

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(existingDocument)

        _ = store.insertTimestamp(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        )

        let oldTimestampLocation = (store.document.string as NSString)
            .range(of: "2026-06-02 08:39")
            .location
        try assertUsesTimestampLineAttributes(
            store.document,
            lineStartingAt: 0
        )
        try assertUsesTimestampLineAttributes(
            store.document,
            lineStartingAt: oldTimestampLocation
        )
    }

    func testSavedTimestampBlockCountUpdatesOnlyAfterSave() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = [
            "2026-06-02 08:42",
            "",
            "first",
            "",
            "2026-06-02 08:41",
            "",
            "",
            "2026-06-02 08:40",
            "",
            "older"
        ].joined(separator: "\n")

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: document))

        XCTAssertEqual(store.savedTimestampBlockCount, 0)

        store.saveNow()

        XCTAssertEqual(store.savedTimestampBlockCount, 3)
    }

    func testSavedTimestampBlockCountLoadsFromExistingFile() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = [
            "2026-06-02 08:41",
            "",
            "newer",
            "",
            "2026-06-02 08:40",
            "",
            "older"
        ].joined(separator: "\n")

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: document))
        store.saveNow()

        let reloaded = IdeaStore(fileURL: fileURL)

        XCTAssertEqual(reloaded.savedTimestampBlockCount, 2)
    }

    func testLoadingExistingFileNormalizesTimestampLineAttributes() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = makeDocumentWithLargeTimestampLine(
            timestamp: "2026-06-02 08:40",
            body: "older idea"
        )

        try RichTextDocument.save(document, to: fileURL)

        let store = IdeaStore(fileURL: fileURL)

        XCTAssertEqual(store.document.string, "2026-06-02 08:40\nolder idea")
        try assertUsesTimestampLineAttributes(
            store.document,
            lineStartingAt: 0
        )
        try assertUsesBodyAttributes(
            store.document,
            in: NSRange(
                location: "2026-06-02 08:40\n".utf16.count,
                length: "older idea".utf16.count
            )
        )
    }

    func testHashPrefixedTimestampFormatIsNotCountedOrCleanedAsTimestampBlock() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = "# 2026-06-02 08:40\n\nold body\n\n# 2026-06-02 08:39"

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: document))
        store.saveNow()

        XCTAssertEqual(store.savedTimestampBlockCount, 0)
        XCTAssertFalse(store.cleanUpDocument(saveImmediately: true))
        XCTAssertEqual(store.document.string, document)
    }

    func testTimestampLineRangesAreNotUserEditable() throws {
        let timestamp = "2026-06-02 08:40"
        let document = NSAttributedString(string: "\(timestamp)\n\nbody")

        XCTAssertFalse(
            RichTextDocument.isUserEditableRange(
                NSRange(location: 0, length: 0),
                in: document
            )
        )
        XCTAssertFalse(
            RichTextDocument.isUserEditableRange(
                NSRange(location: 2, length: 0),
                in: document
            )
        )
        XCTAssertFalse(
            RichTextDocument.isUserEditableRange(
                NSRange(location: 2, length: 1),
                in: document
            )
        )
        XCTAssertFalse(
            RichTextDocument.isUserEditableRange(
                NSRange(location: 2, length: 3),
                in: document
            )
        )
    }

    func testTimestampLineEndingIsNotUserEditable() throws {
        let timestamp = "2026-06-02 08:40"
        let document = NSAttributedString(string: "\(timestamp)\n\nbody")

        XCTAssertFalse(
            RichTextDocument.isUserEditableRange(
                NSRange(location: timestamp.utf16.count, length: 0),
                in: document
            )
        )
        XCTAssertFalse(
            RichTextDocument.isUserEditableRange(
                NSRange(location: timestamp.utf16.count, length: 1),
                in: document
            )
        )
        XCTAssertFalse(
            RichTextDocument.isUserDeletableRange(
                NSRange(location: timestamp.utf16.count, length: 1),
                in: document
            )
        )
    }

    func testNewlineInsertionAtTimestampLineEndIsUserEditable() throws {
        let timestamp = "2026-06-02 08:40"
        let document = NSAttributedString(string: "\(timestamp)\n\nbody")

        XCTAssertTrue(
            RichTextDocument.isTimestampLineContentEnd(
                timestamp.utf16.count,
                in: document
            )
        )
        XCTAssertTrue(
            RichTextDocument.isUserEditableRange(
                NSRange(location: timestamp.utf16.count, length: 0),
                replacementString: "\n",
                in: document
            )
        )
        XCTAssertFalse(
            RichTextDocument.isUserEditableRange(
                NSRange(location: timestamp.utf16.count, length: 0),
                replacementString: "x",
                in: document
            )
        )
        XCTAssertFalse(
            RichTextDocument.isTimestampLineContentEnd(
                2,
                in: document
            )
        )
        XCTAssertFalse(
            RichTextDocument.isUserEditableRange(
                NSRange(location: 2, length: 0),
                replacementString: "\n",
                in: document
            )
        )
    }

    func testNewlineInsertionAtTimestampLineStartIsUserEditable() throws {
        let timestamp = "2026-06-02 08:40"
        let document = NSAttributedString(string: "\(timestamp)\n\nbody")

        XCTAssertTrue(
            RichTextDocument.isTimestampLineContentBoundary(
                0,
                in: document
            )
        )
        XCTAssertTrue(
            RichTextDocument.isUserEditableRange(
                NSRange(location: 0, length: 0),
                replacementString: "\n",
                in: document
            )
        )
        XCTAssertFalse(
            RichTextDocument.isUserEditableRange(
                NSRange(location: 0, length: 0),
                replacementString: "x",
                in: document
            )
        )
        XCTAssertFalse(
            RichTextDocument.isUserEditableRange(
                NSRange(location: 2, length: 0),
                replacementString: "\n",
                in: document
            )
        )
        XCTAssertFalse(
            RichTextDocument.isUserEditableRange(
                NSRange(location: 0, length: 1),
                replacementString: "\n",
                in: document
            )
        )
    }

    func testNewlineInsertionAtLaterTimestampLineStartIsUserEditable() throws {
        let documentString = [
            "2026-06-02 08:41",
            "newer",
            "",
            "2026-06-02 08:40",
            "older"
        ].joined(separator: "\n")
        let document = NSAttributedString(string: documentString)
        let timestampLocation = (documentString as NSString)
            .range(of: "2026-06-02 08:40")
            .location

        XCTAssertTrue(
            RichTextDocument.isTimestampLineContentBoundary(
                timestampLocation,
                in: document
            )
        )
        XCTAssertTrue(
            RichTextDocument.isUserEditableRange(
                NSRange(location: timestampLocation, length: 0),
                replacementString: "\n",
                in: document
            )
        )
    }

    func testNewlineInsertionAtUnterminatedTimestampLineEndIsUserEditable() throws {
        let timestamp = "2026-06-02 08:40"
        let document = NSAttributedString(string: timestamp)

        XCTAssertTrue(
            RichTextDocument.isTimestampLineContentEnd(
                timestamp.utf16.count,
                in: document
            )
        )
        XCTAssertTrue(
            RichTextDocument.isUserEditableRange(
                NSRange(location: timestamp.utf16.count, length: 0),
                replacementString: "\n",
                in: document
            )
        )
        XCTAssertFalse(
            RichTextDocument.isUserEditableRange(
                NSRange(location: timestamp.utf16.count, length: 0),
                in: document
            )
        )
    }

    func testTimestampSeparatorAndBodyRangesAreUserEditable() throws {
        let timestamp = "2026-06-02 08:40"
        let document = NSAttributedString(string: "\(timestamp)\n\nbody")
        let separatorLocation = timestamp.utf16.count + 1
        let bodyLocation = (document.string as NSString).range(of: "body").location

        XCTAssertTrue(
            RichTextDocument.isUserEditableRange(
                NSRange(location: separatorLocation, length: 1),
                in: document
            )
        )
        XCTAssertTrue(
            RichTextDocument.isUserDeletableRange(
                NSRange(location: separatorLocation, length: 1),
                in: document
            )
        )
        XCTAssertTrue(
            RichTextDocument.isUserEditableRange(
                NSRange(location: bodyLocation, length: 0),
                in: document
            )
        )
        XCTAssertTrue(
            RichTextDocument.isUserEditableRange(
                NSRange(location: bodyLocation, length: 4),
                in: document
            )
        )
        XCTAssertTrue(
            RichTextDocument.isUserDeletableRange(
                NSRange(location: bodyLocation, length: 4),
                in: document
            )
        )
    }

    func testHashPrefixedTimestampFormatIsUserEditable() throws {
        let document = NSAttributedString(string: "# 2026-06-02 08:40\n\nbody")

        XCTAssertTrue(
            RichTextDocument.isUserEditableRange(
                NSRange(location: 0, length: 1),
                in: document
            )
        )
        XCTAssertTrue(
            RichTextDocument.isUserEditableRange(
                NSRange(location: 2, length: 0),
                in: document
            )
        )
    }

    func testCompleteTimestampLineRangeIsUserDeletable() throws {
        let timestamp = "2026-06-02 08:40"
        let document = NSAttributedString(string: "\(timestamp)\n\nbody")

        XCTAssertTrue(
            RichTextDocument.isUserDeletableRange(
                NSRange(location: 0, length: timestamp.utf16.count + 1),
                in: document
            )
        )
    }

    func testPartialTimestampLineRangeIsNotUserDeletable() throws {
        let timestamp = "2026-06-02 08:40"
        let document = NSAttributedString(string: "\(timestamp)\n\nbody")

        XCTAssertFalse(
            RichTextDocument.isUserDeletableRange(
                NSRange(location: 0, length: 1),
                in: document
            )
        )
        XCTAssertFalse(
            RichTextDocument.isUserDeletableRange(
                NSRange(location: 0, length: timestamp.utf16.count),
                in: document
            )
        )
        XCTAssertFalse(
            RichTextDocument.isUserDeletableRange(
                NSRange(location: 2, length: timestamp.utf16.count),
                in: document
            )
        )
    }

    func testWholeDocumentRangeWithTimestampIsUserDeletable() throws {
        let document = NSAttributedString(string: "2026-06-02 08:40\n\nbody")

        XCTAssertTrue(
            RichTextDocument.isUserDeletableRange(
                NSRange(location: 0, length: document.length),
                in: document
            )
        )
    }

    func testTimestampBlockRangeForFirstBlockEndsBeforeNextTimestamp() throws {
        let documentString = [
            "2026-06-02 08:41",
            "newer",
            "",
            "2026-06-02 08:40",
            "older"
        ].joined(separator: "\n")
        let document = NSAttributedString(string: documentString)
        let string = documentString as NSString
        let range = try XCTUnwrap(
            RichTextDocument.timestampBlockRange(
                containing: string.range(of: "newer").location,
                in: document
            )
        )

        XCTAssertEqual(string.substring(with: range), "2026-06-02 08:41\nnewer\n\n")
    }

    func testMovingTimestampBlockToTopReordersWholeBlock() throws {
        let documentString = [
            "2026-06-02 08:42",
            "latest",
            "",
            "2026-06-02 08:41",
            "middle",
            "",
            "2026-06-02 08:40",
            "older"
        ].joined(separator: "\n")
        let document = NSAttributedString(string: documentString)

        let result = try XCTUnwrap(
            RichTextDocument.moveTimestampBlock(from: 1, to: 0, in: document)
        )

        XCTAssertEqual(
            result.document.string,
            [
                "2026-06-02 08:41",
                "middle",
                "",
                "2026-06-02 08:42",
                "latest",
                "",
                "2026-06-02 08:40",
                "older"
            ].joined(separator: "\n")
        )
        XCTAssertEqual(result.movedBlockRange.location, 0)
    }

    func testMovingTimestampBlockToEndReordersWholeBlock() throws {
        let documentString = [
            "2026-06-02 08:42",
            "latest",
            "",
            "2026-06-02 08:41",
            "middle",
            "",
            "2026-06-02 08:40",
            "older"
        ].joined(separator: "\n")
        let document = NSAttributedString(string: documentString)

        let result = try XCTUnwrap(
            RichTextDocument.moveTimestampBlock(from: 0, to: 3, in: document)
        )

        XCTAssertEqual(
            result.document.string,
            [
                "2026-06-02 08:41",
                "middle",
                "",
                "2026-06-02 08:40",
                "older",
                "",
                "2026-06-02 08:42",
                "latest"
            ].joined(separator: "\n")
        )
        XCTAssertEqual(
            result.movedBlockRange.location,
            (result.document.string as NSString).range(of: "2026-06-02 08:42").location
        )
    }

    func testMovingTimestampBlockPreservesImageAttachment() throws {
        let document = NSMutableAttributedString(string: [
            "2026-06-02 08:42",
            "latest",
            "",
            "2026-06-02 08:41",
            "image:"
        ].joined(separator: "\n"))
        document.append(NSAttributedString(string: "\n"))
        document.append(makeImageAttributedString())
        document.append(NSAttributedString(string: "\n\n2026-06-02 08:40\nolder"))

        let result = try XCTUnwrap(
            RichTextDocument.moveTimestampBlock(from: 1, to: 3, in: document)
        )
        let movedBlock = result.document.attributedSubstring(from: result.movedBlockRange)

        XCTAssertTrue(result.document.string.hasPrefix("2026-06-02 08:42\nlatest\n\n2026-06-02 08:40\nolder"))
        XCTAssertTrue(movedBlock.string.hasPrefix("2026-06-02 08:41\nimage:\n"))
        XCTAssertTrue(containsAttachment(movedBlock))
    }

    func testMovingTimestampBlockReturnsNilForCurrentBoundary() throws {
        let document = NSAttributedString(
            string: "2026-06-02 08:41\nnewer\n\n2026-06-02 08:40\nolder"
        )

        XCTAssertNil(RichTextDocument.moveTimestampBlock(from: 0, to: 0, in: document))
        XCTAssertNil(RichTextDocument.moveTimestampBlock(from: 0, to: 1, in: document))
    }

    func testTimestampBlockDeletionRangeForMiddleBlockLeavesNeighborsAdjacent() throws {
        let documentString = [
            "2026-06-02 08:42",
            "latest",
            "",
            "2026-06-02 08:41",
            "middle",
            "",
            "2026-06-02 08:40",
            "older"
        ].joined(separator: "\n")
        let document = NSAttributedString(string: documentString)
        let string = documentString as NSString
        let range = try XCTUnwrap(
            RichTextDocument.timestampBlockDeletionRange(
                containing: string.range(of: "middle").location,
                in: document
            )
        )
        let result = NSMutableAttributedString(attributedString: document)

        result.deleteCharacters(in: range)

        XCTAssertEqual(
            result.string,
            "2026-06-02 08:42\nlatest\n\n2026-06-02 08:40\nolder"
        )
    }

    func testTimestampBlockDeletionRangeForLastBlockRemovesLeadingSeparator() throws {
        let documentString = [
            "2026-06-02 08:41",
            "newer",
            "",
            "2026-06-02 08:40",
            "older"
        ].joined(separator: "\n")
        let document = NSAttributedString(string: documentString)
        let string = documentString as NSString
        let range = try XCTUnwrap(
            RichTextDocument.timestampBlockDeletionRange(
                containing: string.range(of: "older").location,
                in: document
            )
        )
        let result = NSMutableAttributedString(attributedString: document)

        result.deleteCharacters(in: range)

        XCTAssertEqual(result.string, "2026-06-02 08:41\nnewer")
    }

    func testTimestampBlockRangeReturnsNilOutsideTimestampBlocks() throws {
        let document = NSAttributedString(string: "prefix\n\n2026-06-02 08:40\nbody")

        XCTAssertNil(
            RichTextDocument.timestampBlockRange(
                containing: 0,
                in: document
            )
        )
    }

    func testTimestampLineDeletionRangeForBackwardDelete() throws {
        let timestamp = "2026-06-02 08:40"
        let document = NSAttributedString(string: "\(timestamp)\n\nbody")
        let deletionRange = try XCTUnwrap(
            RichTextDocument.timestampLineDeletionRangeForBackwardDelete(
                at: timestamp.utf16.count,
                in: document
            )
        )

        XCTAssertEqual(deletionRange.location, 0)
        XCTAssertEqual(deletionRange.length, timestamp.utf16.count + 1)
        XCTAssertNil(
            RichTextDocument.timestampLineDeletionRangeForBackwardDelete(
                at: timestamp.utf16.count + 1,
                in: document
            )
        )
    }

    func testTimestampLineEndLocationForBackwardDeleteFromNextLineStart() throws {
        let timestamp = "2026-06-02 08:40"
        let document = NSAttributedString(string: "\(timestamp)\n\nbody")

        XCTAssertEqual(
            RichTextDocument.timestampLineEndLocationForBackwardDelete(
                at: timestamp.utf16.count + 1,
                in: document
            ),
            timestamp.utf16.count
        )
        XCTAssertNil(
            RichTextDocument.timestampLineEndLocationForBackwardDelete(
                at: timestamp.utf16.count,
                in: document
            )
        )
    }

    func testTimestampLineDeletionRangeForForwardDelete() throws {
        let timestamp = "2026-06-02 08:40"
        let document = NSAttributedString(string: "\(timestamp)\n\nbody")
        let deletionRange = try XCTUnwrap(
            RichTextDocument.timestampLineDeletionRangeForForwardDelete(
                at: 0,
                in: document
            )
        )

        XCTAssertEqual(deletionRange.location, 0)
        XCTAssertEqual(deletionRange.length, timestamp.utf16.count + 1)
        XCTAssertNil(
            RichTextDocument.timestampLineDeletionRangeForForwardDelete(
                at: 1,
                in: document
            )
        )
    }

    func testMultipleTimestampLinesAreNotUserEditable() throws {
        let documentString = [
            "2026-06-02 08:41",
            "",
            "newer",
            "",
            "2026-06-02 08:40",
            "",
            "older"
        ].joined(separator: "\n")
        let document = NSAttributedString(string: documentString)
        let string = documentString as NSString
        let firstTimestampLocation = string.range(of: "2026-06-02 08:41").location
        let secondTimestampLocation = string.range(of: "2026-06-02 08:40").location
        let newerRange = string.range(of: "newer")

        XCTAssertFalse(
            RichTextDocument.isUserEditableRange(
                NSRange(location: firstTimestampLocation, length: 1),
                in: document
            )
        )
        XCTAssertFalse(
            RichTextDocument.isUserEditableRange(
                NSRange(location: secondTimestampLocation + 2, length: 0),
                in: document
            )
        )
        XCTAssertTrue(
            RichTextDocument.isUserEditableRange(newerRange, in: document)
        )
        XCTAssertFalse(
            RichTextDocument.isUserEditableRange(
                NSRange(
                    location: newerRange.location,
                    length: secondTimestampLocation + 1 - newerRange.location
                ),
                in: document
            )
        )
        XCTAssertTrue(
            RichTextDocument.isUserDeletableRange(
                NSRange(
                    location: secondTimestampLocation,
                    length: "2026-06-02 08:40\n".utf16.count
                ),
                in: document
            )
        )
        XCTAssertFalse(
            RichTextDocument.isUserDeletableRange(
                NSRange(location: secondTimestampLocation, length: 1),
                in: document
            )
        )
    }

    func testDeletingLineBreakBeforeTimestampIsNotUserDeletable() throws {
        let timestamp = "2026-06-02 08:40"
        let documentString = "older\n\(timestamp)\n\nbody"
        let document = NSAttributedString(string: documentString)
        let timestampLocation = (documentString as NSString).range(of: timestamp).location

        XCTAssertFalse(
            RichTextDocument.isUserDeletableRange(
                NSRange(location: timestampLocation - 1, length: 1),
                in: document
            )
        )
    }

    func testCleanUpRemovesEmptyTimestampBlocksAndTrimsKeptBodies() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = [
            "2026-06-02 08:43",
            "",
            "",
            "2026-06-02 08:42",
            "",
            " keep me ",
            "",
            "2026-06-02 08:41",
            "",
            "",
            "2026-06-02 08:40",
            "",
            " older ",
            ""
        ].joined(separator: "\n")

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: document))

        XCTAssertTrue(store.cleanUpDocument(saveImmediately: true))
        XCTAssertEqual(
            store.document.string,
            "2026-06-02 08:42\nkeep me\n\n2026-06-02 08:40\nolder"
        )
        XCTAssertEqual(store.savedTimestampBlockCount, 2)
    }

    func testCleanUpPreservesImageOnlyTimestampBlock() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = NSMutableAttributedString(string: "2026-06-02 08:40\n\n  \n")
        document.append(makeImageAttributedString())
        document.append(NSAttributedString(string: "\n\n2026-06-02 08:39\n\n"))

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(document)

        XCTAssertTrue(store.cleanUpDocument(saveImmediately: true))
        XCTAssertTrue(store.document.string.hasPrefix("2026-06-02 08:40\n"))
        XCTAssertFalse(store.document.string.hasPrefix("2026-06-02 08:40\n\n"))
        XCTAssertFalse(store.document.string.contains("2026-06-02 08:39"))
        XCTAssertTrue(containsAttachment(store.document))
    }

    func testCleanUpTrimsPlainDocumentWithoutTimestamps() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: " \n plain note \n "))

        XCTAssertTrue(store.cleanUpDocument(saveImmediately: true))
        XCTAssertEqual(store.document.string, "plain note")
    }

    func testCleanUpIncrementsRevisionAndPersistsChanges() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: "2026-06-02 08:40\n\n idea \n"))

        XCTAssertEqual(store.revision, 0)
        XCTAssertTrue(store.cleanUpDocument(saveImmediately: true))
        XCTAssertEqual(store.revision, 1)

        let reloaded = IdeaStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.document.string, "2026-06-02 08:40\nidea")
    }

    func testCleanUpNormalizesTimestampLineAttributes() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(
            makeDocumentWithLargeTimestampLine(
                timestamp: "2026-06-02 08:40",
                body: "idea"
            )
        )

        XCTAssertTrue(store.cleanUpDocument(saveImmediately: true))
        XCTAssertEqual(store.document.string, "2026-06-02 08:40\nidea")
        try assertUsesTimestampLineAttributes(
            store.document,
            lineStartingAt: 0
        )
    }

    func testStorePersistsRTFDText() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: "edited content"))
        store.saveNow()

        let reloaded = IdeaStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.document.string, "edited content")
    }

    func testStorePersistsImageAttachment() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = NSMutableAttributedString(string: "image:\n")
        document.append(makeImageAttributedString())

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(document)
        store.saveNow()

        let reloaded = IdeaStore(fileURL: fileURL)
        XCTAssertTrue(containsAttachment(reloaded.document))
    }

    func testTimestampInsertPreservesExistingImageAttachment() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = NSMutableAttributedString(string: "image:\n")
        document.append(makeImageAttributedString())
        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(document)

        let cursorRange = store.insertTimestamp(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        )
        let timestampBlock = "2026-06-02 08:40\n"

        XCTAssertTrue(store.document.string.hasPrefix("\(timestampBlock)\n\nimage:\n"))
        XCTAssertEqual(cursorRange.location, timestampBlock.utf16.count)
        XCTAssertEqual(cursorRange.length, 0)
        XCTAssertTrue(containsAttachment(store.document))
    }
}

private func makeTemporaryFileURL(name: String) -> (URL, URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    return (directory, directory.appendingPathComponent(name))
}

private func makeImageAttributedString() -> NSAttributedString {
    let data = makePNGData()
    let attachment = NSTextAttachment(data: data, ofType: "public.png")
    attachment.bounds = NSRect(x: 0, y: 0, width: 8, height: 8)
    return NSAttributedString(attachment: attachment)
}

private func makeUnorderedListAttributedString(_ string: String) -> NSAttributedString {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.textLists = [NSTextList(markerFormat: .disc, options: 0)]
    return NSAttributedString(
        string: string,
        attributes: [
            .font: NSFont.boldSystemFont(ofSize: 24),
            .foregroundColor: NSColor.systemRed,
            .paragraphStyle: paragraphStyle
        ]
    )
}

private func makeDocumentWithLargeTimestampLine(
    timestamp: String,
    body: String
) -> NSAttributedString {
    let document = NSMutableAttributedString(
        string: "\(timestamp)\n",
        attributes: [
            .font: NSFont.boldSystemFont(ofSize: 24),
            .foregroundColor: NSColor.systemRed,
            .paragraphStyle: RichTextFormatting.bodyParagraphStyle
        ]
    )
    document.append(
        NSAttributedString(
            string: body,
            attributes: RichTextFormatting.bodyAttributes
        )
    )
    return document
}

private func makePNGData() -> Data {
    let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 4,
        pixelsHigh: 4,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )

    return representation?.representation(using: .png, properties: [:]) ?? Data()
}

private func makeLocalDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current

    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return calendar.date(from: components)!
}

private func containsAttachment(_ document: NSAttributedString) -> Bool {
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

private func assertUsesTimestampAttributes(
    _ document: NSAttributedString,
    at location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let font = try XCTUnwrap(
        document.attribute(.font, at: location, effectiveRange: nil) as? NSFont,
        file: file,
        line: line
    )
    XCTAssertEqual(font.pointSize, NSFont.smallSystemFontSize, accuracy: 0.001, file: file, line: line)
    assertRegularFontWeight(font, file: file, line: line)
    assertUsesMonospacedDigits(font, file: file, line: line)

    let color = try XCTUnwrap(
        document.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor,
        file: file,
        line: line
    )
    XCTAssertTrue(color.isEqual(NSColor.secondaryLabelColor), file: file, line: line)

    let paragraphStyle = try XCTUnwrap(
        document.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle,
        file: file,
        line: line
    )
    XCTAssertEqual(paragraphStyle.alignment, .left, file: file, line: line)
    XCTAssertEqual(paragraphStyle.minimumLineHeight, 22, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(paragraphStyle.maximumLineHeight, 22, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(paragraphStyle.paragraphSpacingBefore, 0, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(paragraphStyle.paragraphSpacing, 0, accuracy: 0.001, file: file, line: line)

    let baselineOffset = try XCTUnwrap(
        document.attribute(.baselineOffset, at: location, effectiveRange: nil) as? CGFloat,
        file: file,
        line: line
    )
    XCTAssertEqual(
        baselineOffset,
        RichTextFormatting.timestampBaselineOffset,
        accuracy: 0.001,
        file: file,
        line: line
    )
}

private func assertUsesTimestampLineAttributes(
    _ document: NSAttributedString,
    lineStartingAt location: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let string = document.string as NSString
    var lineStart = 0
    var lineEnd = 0
    var contentsEnd = 0
    string.getLineStart(
        &lineStart,
        end: &lineEnd,
        contentsEnd: &contentsEnd,
        for: NSRange(location: location, length: 0)
    )

    XCTAssertEqual(lineStart, location, file: file, line: line)
    XCTAssertGreaterThan(lineEnd, lineStart, file: file, line: line)

    try assertUsesTimestampAttributes(
        document,
        at: lineStart,
        file: file,
        line: line
    )
    try assertUsesTimestampAttributes(
        document,
        at: contentsEnd - 1,
        file: file,
        line: line
    )

    if contentsEnd < lineEnd {
        try assertUsesTimestampAttributes(
            document,
            at: contentsEnd,
            file: file,
            line: line
        )
    }
}

private func assertUsesBodyAttributes(
    _ document: NSAttributedString,
    in range: NSRange,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    try assertValidRange(range, in: document, file: file, line: line)

    document.enumerateAttributes(in: range) { attributes, effectiveRange, _ in
        let text = (document.string as NSString).substring(with: effectiveRange)
        guard !text.isEmpty else {
            return
        }

        guard let font = attributes[.font] as? NSFont else {
            XCTFail("Missing body font", file: file, line: line)
            return
        }
        XCTAssertEqual(font.pointSize, 14, accuracy: 0.001, file: file, line: line)
        assertRegularFontWeight(font, file: file, line: line)

        let color = attributes[.foregroundColor] as? NSColor
        XCTAssertTrue(color?.isEqual(NSColor.labelColor) ?? false, file: file, line: line)

        guard let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle else {
            XCTFail("Missing body paragraph style", file: file, line: line)
            return
        }
        XCTAssertEqual(paragraphStyle.minimumLineHeight, 22, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(paragraphStyle.maximumLineHeight, 22, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(paragraphStyle.paragraphSpacing, 7, accuracy: 0.001, file: file, line: line)
    }
}

private func assertValidRange(
    _ range: NSRange,
    in document: NSAttributedString,
    file: StaticString,
    line: UInt
) throws {
    let isValid = range.location >= 0 &&
        range.length >= 0 &&
        range.location <= document.length &&
        range.length <= document.length - range.location
    _ = try XCTUnwrap(isValid ? true : nil, "Invalid range \(range)", file: file, line: line)
}

private func assertRegularFontWeight(
    _ font: NSFont,
    file: StaticString,
    line: UInt
) {
    guard let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any],
          let weight = traits[.weight] as? CGFloat else {
        XCTFail("Missing font weight", file: file, line: line)
        return
    }
    XCTAssertEqual(weight, NSFont.Weight.regular.rawValue, accuracy: 0.001, file: file, line: line)
}

private func assertUsesMonospacedDigits(
    _ font: NSFont,
    file: StaticString,
    line: UInt
) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let digitWidths = (0...9).map {
        (String($0) as NSString).size(withAttributes: attributes).width
    }

    guard let firstWidth = digitWidths.first else {
        return
    }

    for width in digitWidths {
        XCTAssertEqual(width, firstWidth, accuracy: 0.001, file: file, line: line)
    }
}
