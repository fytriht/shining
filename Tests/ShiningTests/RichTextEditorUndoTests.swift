import AppKit
import XCTest
@testable import Shining
@testable import ShiningCore

final class RichTextEditorUndoTests: XCTestCase {
    @MainActor
    func testUndoRestoresTimestampBlockDeletedThroughEditor() throws {
        _ = NSApplication.shared

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
        let sourceString = documentString as NSString
        let deletionRange = try XCTUnwrap(
            RichTextDocument.timestampBlockDeletionRange(
                containing: sourceString.range(of: "middle").location,
                in: document
            )
        )

        let textView = RichTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = textView
        window.makeFirstResponder(textView)

        let editor = RichTextEditorView(
            document: document,
            revision: 0,
            focusRequest: .none,
            onChange: { _ in }
        )
        let coordinator = RichTextEditorView.Coordinator(editor)
        textView.delegate = coordinator
        textView.textStorage?.setAttributedString(document)

        XCTAssertTrue(textView.shouldChangeText(in: deletionRange, replacementString: ""))
        textView.textStorage?.replaceCharacters(in: deletionRange, with: "")
        textView.setSelectedRange(NSRange(location: deletionRange.location, length: 0))
        textView.didChangeText()

        XCTAssertTrue(textView.undoManager?.canUndo ?? false)

        textView.undoManager?.undo()

        XCTAssertEqual(textView.string, documentString)
    }

    @MainActor
    func testDeleteCurrentTimestampBlockActionDeletesBlockAtSelection() throws {
        let documentString = makeThreeBlockDocumentString()
        let sourceString = documentString as NSString
        let fixture = makeEditorFixture(documentString: documentString)
        let middleBlockStart = sourceString.range(of: "2026-06-02 08:41").location
        fixture.textView.setSelectedRange(
            NSRange(location: sourceString.range(of: "middle").location, length: 0)
        )

        fixture.textView.deleteCurrentTimestampBlock(nil)

        XCTAssertEqual(fixture.textView.string, makeDocumentStringAfterDeletingMiddleBlock())
        XCTAssertEqual(
            fixture.textView.selectedRange(),
            NSRange(location: middleBlockStart, length: 0)
        )
    }

    @MainActor
    func testCommandShiftDeleteDeletesCurrentTimestampBlock() throws {
        let documentString = makeThreeBlockDocumentString()
        let fixture = makeEditorFixture(documentString: documentString)
        fixture.textView.setSelectedRange(
            NSRange(location: (documentString as NSString).range(of: "middle").location, length: 0)
        )
        let event = try makeCommandShiftDeleteEvent(window: fixture.window)

        XCTAssertTrue(fixture.textView.performKeyEquivalent(with: event))

        XCTAssertEqual(fixture.textView.string, makeDocumentStringAfterDeletingMiddleBlock())
    }

    private func makeThreeBlockDocumentString() -> String {
        [
            "2026-06-02 08:42",
            "latest",
            "",
            "2026-06-02 08:41",
            "middle",
            "",
            "2026-06-02 08:40",
            "older"
        ].joined(separator: "\n")
    }

    private func makeDocumentStringAfterDeletingMiddleBlock() -> String {
        [
            "2026-06-02 08:42",
            "latest",
            "",
            "2026-06-02 08:40",
            "older"
        ].joined(separator: "\n")
    }

    @MainActor
    private func makeEditorFixture(
        documentString: String
    ) -> (
        textView: RichTextView,
        window: NSWindow,
        coordinator: RichTextEditorView.Coordinator
    ) {
        _ = NSApplication.shared

        let document = NSAttributedString(string: documentString)
        let textView = RichTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = textView
        window.makeFirstResponder(textView)

        let editor = RichTextEditorView(
            document: document,
            revision: 0,
            focusRequest: .none,
            onChange: { _ in }
        )
        let coordinator = RichTextEditorView.Coordinator(editor)
        textView.delegate = coordinator
        textView.textStorage?.setAttributedString(document)

        return (textView, window, coordinator)
    }

    private func makeCommandShiftDeleteEvent(window: NSWindow) throws -> NSEvent {
        let deleteCharacter = String(UnicodeScalar(NSDeleteCharacter)!)
        return try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .shift],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: deleteCharacter,
                charactersIgnoringModifiers: deleteCharacter,
                isARepeat: false,
                keyCode: 51
            )
        )
    }
}
