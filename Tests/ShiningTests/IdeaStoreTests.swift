import AppKit
import XCTest
@testable import ShiningCore

final class IdeaStoreTests: XCTestCase {
    func testEmptyInputDoesNotAppend() {
        let existing = NSAttributedString(string: "already here")

        let result = IdeaRichTextAppender.append(
            existing: existing,
            capture: NSAttributedString(string: "  \n\t "),
            timestamp: "2026-06-02 08:40"
        )

        XCTAssertEqual(result.string, existing.string)
        XCTAssertFalse(containsAttachment(result))
    }

    func testNonEmptyInputAppendsWithTimestamp() {
        let result = IdeaRichTextAppender.append(
            existing: NSAttributedString(string: ""),
            capture: NSAttributedString(string: "first idea"),
            timestamp: "2026-06-02 08:40"
        )

        XCTAssertEqual(
            result.string,
            """
            2026-06-02 08:40

            first idea
            """
        )
    }

    func testStorePersistsRTFDText() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: "edited content"))
        store.saveNow()

        let reloaded = IdeaStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.document.string, "edited content")

        try? FileManager.default.removeItem(at: directory)
    }

    func testStorePersistsImageAttachment() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        let document = NSMutableAttributedString(string: "image:\n")
        document.append(makeImageAttributedString())

        let store = IdeaStore(fileURL: fileURL)
        store.replaceDocument(document)
        store.saveNow()

        let reloaded = IdeaStore(fileURL: fileURL)
        XCTAssertTrue(containsAttachment(reloaded.document))

        try? FileManager.default.removeItem(at: directory)
    }

    func testImageOnlyCaptureAppends() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "ideas.rtfd")
        let store = IdeaStore(fileURL: fileURL)

        XCTAssertTrue(store.appendCapture(
            makeImageAttributedString(),
            date: Date(timeIntervalSince1970: 1_780_390_800)
        ))
        XCTAssertTrue(store.hasContent)
        XCTAssertTrue(containsAttachment(store.document))

        try? FileManager.default.removeItem(at: directory)
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
