import XCTest
@testable import ShiningCore

final class IdeaStoreTests: XCTestCase {
    func testEmptyInputDoesNotAppend() {
        let existing = "already here"

        let result = IdeaTextAppender.append(
            existing: existing,
            capture: "  \n\t ",
            timestamp: "2026-06-02 08:40"
        )

        XCTAssertEqual(result, existing)
    }

    func testNonEmptyInputAppendsWithTimestamp() {
        let result = IdeaTextAppender.append(
            existing: "",
            capture: "first idea",
            timestamp: "2026-06-02 08:40"
        )

        XCTAssertEqual(
            result,
            """
            ## 2026-06-02 08:40

            first idea
            """
        )
    }

    func testExistingContentGetsSeparatedBeforeAppend() {
        let result = IdeaTextAppender.append(
            existing: "old idea\n\n",
            capture: "new idea",
            timestamp: "2026-06-02 09:10"
        )

        XCTAssertEqual(
            result,
            """
            old idea

            ## 2026-06-02 09:10

            new idea
            """
        )
    }

    func testStorePersistsEditedText() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("ideas.md")

        let store = IdeaStore(fileURL: fileURL)
        store.text = "edited content"
        store.save()

        let reloaded = IdeaStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.text, "edited content")

        try? FileManager.default.removeItem(at: directory)
    }
}
