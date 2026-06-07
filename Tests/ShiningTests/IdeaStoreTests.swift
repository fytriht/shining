import AppKit
import XCTest
@testable import ShiningCore

final class IdeaStoreTests: XCTestCase {
    func testEmptyDocumentInsertsTimestampAndReturnsCursorAtEnd() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        let cursorRange = store.insertTimestamp(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        )
        let expectedDocument = "2026-06-02 08:40\n\n"

        XCTAssertEqual(store.document.string, expectedDocument)
        XCTAssertEqual(cursorRange.location, expectedDocument.utf16.count)
        XCTAssertEqual(cursorRange.length, 0)
        XCTAssertTrue(store.hasContent)
    }

    func testExistingDocumentInsertsTimestampAboveContentAndReturnsBodyStart() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: "older idea"))

        let cursorRange = store.insertTimestamp(
            date: makeLocalDate(year: 2026, month: 6, day: 2, hour: 8, minute: 40)
        )
        let timestampBlock = "2026-06-02 08:40\n\n"

        XCTAssertEqual(
            store.document.string,
            "\(timestampBlock)\n\nolder idea"
        )
        XCTAssertEqual(cursorRange.location, timestampBlock.utf16.count)
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
        let latestTimestampBlock = "2026-06-02 08:41\n\n"

        XCTAssertEqual(
            store.document.string,
            "\(latestTimestampBlock)\n\n2026-06-02 08:40\n\n"
        )
        XCTAssertEqual(cursorRange.location, latestTimestampBlock.utf16.count)
        XCTAssertEqual(cursorRange.length, 0)
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
        let timestampBlock = "2026-06-02 08:40\n\n"

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
