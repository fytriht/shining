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
}
