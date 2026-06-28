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

    @MainActor
    func testTypingAfterClearingWholeDocumentUsesBodyAttributes() throws {
        let document = makeTimestampDocument()
        let fixture = makeEditorFixture(document: document)
        let typedText = "fresh note"

        fixture.textView.typingAttributes = RichTextFormatting.timestampAttributes
        fixture.textView.setSelectedRange(NSRange(location: 0, length: document.length))
        fixture.textView.deleteBackward(nil)
        fixture.textView.insertText(typedText, replacementRange: fixture.textView.selectedRange())

        XCTAssertEqual(fixture.textView.string, typedText)
        try assertUsesBodyAttributes(
            fixture.textView.attributedString(),
            in: NSRange(location: 0, length: typedText.utf16.count)
        )
    }

    @MainActor
    func testCopyingSelectedImageWritesImagePasteboardType() throws {
        let pngData = makePNGData()
        let attachment = NSTextAttachment(
            data: pngData,
            ofType: NSPasteboard.PasteboardType.png.rawValue
        )
        attachment.bounds = NSRect(x: 0, y: 0, width: 8, height: 8)
        let fixture = makeEditorFixture(document: NSAttributedString(attachment: attachment))
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        defer { snapshot.restore(to: pasteboard) }

        pasteboard.clearContents()
        fixture.textView.setSelectedRange(NSRange(location: 0, length: 1))
        fixture.textView.copy(nil)

        let copiedPNGData = try XCTUnwrap(pasteboard.data(forType: .png))
        XCTAssertNotNil(NSImage(data: copiedPNGData))
        XCTAssertNil(pasteboard.string(forType: .string))
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

    private func makeTimestampDocument() -> NSAttributedString {
        let document = NSMutableAttributedString(
            string: "2026-06-02 08:42\n",
            attributes: RichTextFormatting.timestampAttributes
        )
        document.append(
            NSAttributedString(
                string: "latest",
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
        makeEditorFixture(document: NSAttributedString(string: documentString))
    }

    @MainActor
    private func makeEditorFixture(
        document: NSAttributedString
    ) -> (
        textView: RichTextView,
        window: NSWindow,
        coordinator: RichTextEditorView.Coordinator
    ) {
        _ = NSApplication.shared

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

    private func assertUsesBodyAttributes(
        _ document: NSAttributedString,
        in range: NSRange,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let isValid = range.location >= 0 &&
            range.length >= 0 &&
            range.location <= document.length &&
            range.length <= document.length - range.location
        _ = try XCTUnwrap(isValid ? true : nil, "Invalid range \(range)", file: file, line: line)

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

    private typealias StoredPasteboardItem = [(type: NSPasteboard.PasteboardType, data: Data)]

    private struct PasteboardSnapshot {
        let items: [StoredPasteboardItem]

        init(pasteboard: NSPasteboard) {
            self.items = pasteboard.pasteboardItems?.map { item in
                item.types.compactMap { type in
                    guard let data = item.data(forType: type) else {
                        return nil
                    }
                    return (type: type, data: data)
                }
            } ?? []
        }

        func restore(to pasteboard: NSPasteboard) {
            pasteboard.clearContents()

            let restoredItems = items.compactMap { storedItem -> NSPasteboardItem? in
                guard !storedItem.isEmpty else {
                    return nil
                }

                let item = NSPasteboardItem()
                for representation in storedItem {
                    item.setData(representation.data, forType: representation.type)
                }
                return item
            }

            if !restoredItems.isEmpty {
                pasteboard.writeObjects(restoredItems)
            }
        }
    }
}
