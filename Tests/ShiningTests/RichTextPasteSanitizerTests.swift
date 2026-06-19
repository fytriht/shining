import AppKit
import XCTest
@testable import ShiningCore

final class RichTextPasteSanitizerTests: XCTestCase {
    func testStyledHTMLPastesAsPlainText() throws {
        let document = try sanitizedHTML(
            """
            <html><body><span style="color: red; font-size: 32px; font-weight: bold;">Styled</span></body></html>
            """
        )

        XCTAssertEqual(document.string.trimmingCharacters(in: .newlines), "Styled")
        assertUsesDefaultTextAttributes(document)
    }

    func testHTMLUnorderedListConvertsToMarkdownMarkers() throws {
        let document = try sanitizedHTML("<html><body><ul><li>A</li><li>B</li></ul></body></html>")

        XCTAssertEqual(document.string.trimmingCharacters(in: .newlines), "- A\n- B")
        assertUsesDefaultTextAttributes(document)
    }

    func testHTMLOrderedListConvertsToMarkdownMarkers() throws {
        let document = try sanitizedHTML("<html><body><ol><li>A</li><li>B</li></ol></body></html>")

        XCTAssertEqual(document.string.trimmingCharacters(in: .newlines), "1. A\n2. B")
        assertUsesDefaultTextAttributes(document)
    }

    func testPasteboardHTMLListConvertsToMarkdownMarkers() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        XCTAssertTrue(
            pasteboard.setData(
                Data("<html><body><ul><li>A</li><li>B</li></ul></body></html>".utf8),
                forType: .html
            )
        )

        let document = try XCTUnwrap(RichTextPasteSanitizer.sanitizedPasteboardText(from: pasteboard))

        XCTAssertEqual(document.string, "- A\n- B")
        assertUsesDefaultTextAttributes(document)
    }

    func testPasteboardPlainTextTrimsOuterWhitespace() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("  hello\n", forType: .string))

        let document = try XCTUnwrap(RichTextPasteSanitizer.sanitizedPasteboardText(from: pasteboard))

        XCTAssertEqual(document.string, "hello")
        assertUsesDefaultTextAttributes(document)
    }

    func testPasteboardRichTextTrimsOuterWhitespace() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let source = NSAttributedString(
            string: "\n  Styled\t\n",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 28),
                .foregroundColor: NSColor.red
            ]
        )
        let data = try XCTUnwrap(
            source.rtf(
                from: NSRange(location: 0, length: source.length),
                documentAttributes: [:]
            )
        )
        XCTAssertTrue(pasteboard.setData(data, forType: .rtf))

        let document = try XCTUnwrap(RichTextPasteSanitizer.sanitizedPasteboardText(from: pasteboard))

        XCTAssertEqual(document.string, "Styled")
        assertUsesDefaultTextAttributes(document)
    }

    func testWhitespaceOnlyPasteboardTextIsIgnored() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(" \n\t ", forType: .string))

        XCTAssertNil(RichTextPasteSanitizer.sanitizedPasteboardText(from: pasteboard))
    }

    func testPlainTextMarkersArePreserved() {
        let document = RichTextPasteSanitizer.sanitizedPlainText("- A\n* B")

        XCTAssertEqual(document.string, "- A\n* B")
        assertUsesDefaultTextAttributes(document)
    }

    func testPlainTextSanitizerKeepsStructuralNewlines() {
        let document = RichTextPasteSanitizer.sanitizedPlainText("\n")

        XCTAssertEqual(document.string, "\n")
        assertUsesDefaultTextAttributes(document)
    }

    func testAttributedStringPreservesImageAttachmentAndRemovesStyles() {
        let source = NSMutableAttributedString(
            string: "Before ",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 28),
                .foregroundColor: NSColor.red
            ]
        )
        source.append(makeImageAttributedString())
        source.append(
            NSAttributedString(
                string: " After",
                attributes: [
                    .link: URL(string: "https://example.com")!,
                    .foregroundColor: NSColor.blue
                ]
            )
        )

        let document = RichTextPasteSanitizer.sanitizedAttributedString(source)

        XCTAssertEqual(document.string, "Before \u{fffc} After")
        XCTAssertTrue(containsAttachment(document))
        XCTAssertNil(document.attribute(.link, at: document.length - 1, effectiveRange: nil))
        assertUsesDefaultTextAttributes(document)
    }

    func testTrimmedAttributedStringPreservesAttachment() {
        let source = NSMutableAttributedString(string: " \n")
        source.append(makeImageAttributedString())
        source.append(NSAttributedString(string: "\t "))

        let document = RichTextPasteSanitizer.sanitizedTrimmedAttributedString(source)

        XCTAssertEqual(document.string, "\u{fffc}")
        XCTAssertTrue(containsAttachment(document))
    }
}

private func sanitizedHTML(_ html: String) throws -> NSAttributedString {
    try XCTUnwrap(
        RichTextPasteSanitizer.sanitizedImportedRichText(
            data: Data(html.utf8),
            documentType: .html,
            preservesAttachments: false
        )
    )
}

private func assertUsesDefaultTextAttributes(
    _ document: NSAttributedString,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    document.enumerateAttributes(in: NSRange(location: 0, length: document.length)) { attributes, range, _ in
        if attributes[.attachment] is NSTextAttachment {
            return
        }

        let text = (document.string as NSString).substring(with: range)
        guard !text.isEmpty else {
            return
        }

        XCTAssertNil(attributes[.link], file: file, line: line)
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

private func makeImageAttributedString() -> NSAttributedString {
    let attachment = NSTextAttachment(data: makePNGData(), ofType: "public.png")
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
