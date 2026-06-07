import AppKit
import XCTest
@testable import ShiningCore

final class CaptureDraftStoreTests: XCTestCase {
    func testLoadsExistingRTFDDraft() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "capture-draft.rtfd")
        let original = CaptureDraftStore(fileURL: fileURL)
        original.replaceDocument(NSAttributedString(string: "unfinished thought"))
        original.saveNow()

        let store = CaptureDraftStore(fileURL: fileURL)

        XCTAssertEqual(store.document.string, "unfinished thought")

        try? FileManager.default.removeItem(at: directory)
    }

    func testPersistsEditedDraft() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "capture-draft.rtfd")

        let store = CaptureDraftStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: "partial capture"))
        store.saveNow()

        let reloaded = CaptureDraftStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.document.string, "partial capture")

        try? FileManager.default.removeItem(at: directory)
    }

    func testClearRemovesPersistedDraft() throws {
        let (directory, fileURL) = makeTemporaryFileURL(name: "capture-draft.rtfd")

        let store = CaptureDraftStore(fileURL: fileURL)
        store.replaceDocument(NSAttributedString(string: "partial capture"))
        store.saveNow()
        store.clear()

        let reloaded = CaptureDraftStore(fileURL: fileURL)
        XCTAssertFalse(store.hasContent)
        XCTAssertFalse(reloaded.hasContent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        store.saveNow()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        try? FileManager.default.removeItem(at: directory)
    }
}

private func makeTemporaryFileURL(name: String) -> (URL, URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    return (directory, directory.appendingPathComponent(name))
}
