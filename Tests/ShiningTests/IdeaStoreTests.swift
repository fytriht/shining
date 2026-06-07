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
        let expectedDocument = "# 2026-06-02 08:40\n\n"

        XCTAssertEqual(store.document.string, expectedDocument)
        XCTAssertEqual(cursorRange.location, expectedDocument.utf16.count)
        XCTAssertEqual(cursorRange.length, 0)
        XCTAssertTrue(store.hasContent)
        XCTAssertEqual(store.savedTimestampBlockCount, 1)

        let font = try XCTUnwrap(store.document.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font.pointSize, 10)
        let traits = try XCTUnwrap(
            font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        )
        let weight = try XCTUnwrap(traits[.weight] as? CGFloat)
        XCTAssertEqual(weight, NSFont.Weight.medium.rawValue, accuracy: 0.001)
    }

    func testExistingDocumentInsertsTimestampAboveContentAndReturnsBodyStart() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: "older idea"))

        let cursorRange = store.insertTimestamp(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        )
        let timestampBlock = "# 2026-06-02 08:40\n\n"

        XCTAssertEqual(
            store.document.string,
            "\(timestampBlock)\n\nolder idea"
        )
        XCTAssertEqual(cursorRange.location, timestampBlock.utf16.count)
        XCTAssertEqual(cursorRange.length, 0)
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
        let timestampBlock = "# 2026-06-02 08:40\n\n"

        XCTAssertEqual(store.document.string, "\(timestampBlock)\(selectedText)")
        XCTAssertEqual(cursorRange.location, timestampBlock.utf16.count)
        XCTAssertEqual(cursorRange.length, selectedText.utf16.count)
        XCTAssertEqual(
            (store.document.string as NSString).substring(with: cursorRange),
            selectedText
        )
        XCTAssertEqual(store.savedTimestampBlockCount, 1)
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
        let timestampBlock = "# 2026-06-02 08:40\n\n"

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
        let timestampBlock = "# 2026-06-02 08:40\n\n"

        XCTAssertEqual(store.document.string, "\(timestampBlock)\(selectedText)")
        XCTAssertEqual(cursorRange.location, timestampBlock.utf16.count)
        XCTAssertEqual(cursorRange.length, selectedText.utf16.count)
        XCTAssertEqual(
            (store.document.string as NSString).substring(with: cursorRange),
            selectedText
        )
    }

    func testEmptySelectedTextKeepsTimestampOnlyInsertionBehavior() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        let cursorRange = store.insertTimestamp(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40),
            selectedText: ""
        )
        let expectedDocument = "# 2026-06-02 08:40\n\n"

        XCTAssertEqual(store.document.string, expectedDocument)
        XCTAssertEqual(cursorRange.location, expectedDocument.utf16.count)
        XCTAssertEqual(cursorRange.length, 0)
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
        let latestTimestampBlock = "# 2026-06-02 08:41\n\n"

        XCTAssertEqual(
            store.document.string,
            latestTimestampBlock
        )
        XCTAssertEqual(cursorRange.location, latestTimestampBlock.utf16.count)
        XCTAssertEqual(cursorRange.length, 0)
        XCTAssertEqual(store.savedTimestampBlockCount, 1)
    }

    func testSavedTimestampBlockCountUpdatesOnlyAfterSave() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = [
            "# 2026-06-02 08:42",
            "",
            "first",
            "",
            "# 2026-06-02 08:41",
            "",
            "",
            "# 2026-06-02 08:40",
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
            "# 2026-06-02 08:41",
            "",
            "newer",
            "",
            "# 2026-06-02 08:40",
            "",
            "older"
        ].joined(separator: "\n")

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: document))
        store.saveNow()

        let reloaded = IdeaStore(fileURL: fileURL)

        XCTAssertEqual(reloaded.savedTimestampBlockCount, 2)
    }

    func testOldTimestampFormatIsNotCountedOrCleanedAsTimestampBlock() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = "2026-06-02 08:40\n\nold body\n\n2026-06-02 08:39"

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: document))
        store.saveNow()

        XCTAssertEqual(store.savedTimestampBlockCount, 0)
        XCTAssertFalse(store.cleanUpDocument(saveImmediately: true))
        XCTAssertEqual(store.document.string, document)
    }

    func testTimestampLineRangesAreNotUserEditable() throws {
        let timestamp = "# 2026-06-02 08:40"
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
        let timestamp = "# 2026-06-02 08:40"
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

    func testTimestampSeparatorAndBodyRangesAreUserEditable() throws {
        let timestamp = "# 2026-06-02 08:40"
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

    func testOldTimestampFormatIsUserEditable() throws {
        let document = NSAttributedString(string: "2026-06-02 08:40\n\nbody")

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
        let timestamp = "# 2026-06-02 08:40"
        let document = NSAttributedString(string: "\(timestamp)\n\nbody")

        XCTAssertTrue(
            RichTextDocument.isUserDeletableRange(
                NSRange(location: 0, length: timestamp.utf16.count + 1),
                in: document
            )
        )
    }

    func testPartialTimestampLineRangeIsNotUserDeletable() throws {
        let timestamp = "# 2026-06-02 08:40"
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
        let document = NSAttributedString(string: "# 2026-06-02 08:40\n\nbody")

        XCTAssertTrue(
            RichTextDocument.isUserDeletableRange(
                NSRange(location: 0, length: document.length),
                in: document
            )
        )
    }

    func testTimestampLineDeletionRangeForBackwardDelete() throws {
        let timestamp = "# 2026-06-02 08:40"
        let document = NSAttributedString(string: "\(timestamp)\n\nbody")
        let deletionRange = try XCTUnwrap(
            RichTextDocument.timestampLineDeletionRangeForBackwardDelete(
                at: timestamp.utf16.count + 1,
                in: document
            )
        )

        XCTAssertEqual(deletionRange.location, 0)
        XCTAssertEqual(deletionRange.length, timestamp.utf16.count + 1)
        XCTAssertNil(
            RichTextDocument.timestampLineDeletionRangeForBackwardDelete(
                at: timestamp.utf16.count,
                in: document
            )
        )
    }

    func testTimestampLineDeletionRangeForForwardDelete() throws {
        let timestamp = "# 2026-06-02 08:40"
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
            "# 2026-06-02 08:41",
            "",
            "newer",
            "",
            "# 2026-06-02 08:40",
            "",
            "older"
        ].joined(separator: "\n")
        let document = NSAttributedString(string: documentString)
        let string = documentString as NSString
        let firstTimestampLocation = string.range(of: "# 2026-06-02 08:41").location
        let secondTimestampLocation = string.range(of: "# 2026-06-02 08:40").location
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
                    length: "# 2026-06-02 08:40\n".utf16.count
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
        let timestamp = "# 2026-06-02 08:40"
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
            "# 2026-06-02 08:43",
            "",
            "",
            "# 2026-06-02 08:42",
            "",
            " keep me ",
            "",
            "# 2026-06-02 08:41",
            "",
            "",
            "# 2026-06-02 08:40",
            "",
            " older ",
            ""
        ].joined(separator: "\n")

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: document))

        XCTAssertTrue(store.cleanUpDocument(saveImmediately: true))
        XCTAssertEqual(
            store.document.string,
            "# 2026-06-02 08:42\n\nkeep me\n\n# 2026-06-02 08:40\n\nolder"
        )
        XCTAssertEqual(store.savedTimestampBlockCount, 2)
    }

    func testCleanUpPreservesImageOnlyTimestampBlock() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = NSMutableAttributedString(string: "# 2026-06-02 08:40\n\n  \n")
        document.append(makeImageAttributedString())
        document.append(NSAttributedString(string: "\n\n# 2026-06-02 08:39\n\n"))

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(document)

        XCTAssertTrue(store.cleanUpDocument(saveImmediately: true))
        XCTAssertTrue(store.document.string.hasPrefix("# 2026-06-02 08:40\n\n"))
        XCTAssertFalse(store.document.string.contains("# 2026-06-02 08:39"))
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
        store.replaceDocument(NSAttributedString(string: "# 2026-06-02 08:40\n\n idea \n"))

        XCTAssertEqual(store.revision, 0)
        XCTAssertTrue(store.cleanUpDocument(saveImmediately: true))
        XCTAssertEqual(store.revision, 1)

        let reloaded = IdeaStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.document.string, "# 2026-06-02 08:40\n\nidea")
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
        let timestampBlock = "# 2026-06-02 08:40\n\n"

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
