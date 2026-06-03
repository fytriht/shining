import XCTest
@testable import ShiningCore

final class CaptureDraftStoreTests: XCTestCase {
    func testLoadsExistingDraft() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("capture-draft.txt")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try "unfinished thought".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = CaptureDraftStore(fileURL: fileURL)

        XCTAssertEqual(store.text, "unfinished thought")

        try? FileManager.default.removeItem(at: directory)
    }

    func testPersistsEditedDraft() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("capture-draft.txt")

        let store = CaptureDraftStore(fileURL: fileURL)
        store.text = "partial capture"

        let reloaded = CaptureDraftStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.text, "partial capture")

        try? FileManager.default.removeItem(at: directory)
    }

    func testClearRemovesPersistedDraft() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("capture-draft.txt")

        let store = CaptureDraftStore(fileURL: fileURL)
        store.text = "partial capture"
        store.clear()

        let reloaded = CaptureDraftStore(fileURL: fileURL)
        XCTAssertEqual(store.text, "")
        XCTAssertEqual(reloaded.text, "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        try? FileManager.default.removeItem(at: directory)
    }
}
