import AppKit
import ShiningCore
import SwiftUI
import UniformTypeIdentifiers

struct RichTextEditorView: NSViewRepresentable {
    private static let bottomContentInset: CGFloat = 32

    let document: NSAttributedString
    let revision: Int
    let focusRequest: RichTextEditorFocusRequest
    let textContainerInset: NSSize
    let onChange: (NSAttributedString) -> Void

    init(
        document: NSAttributedString,
        revision: Int,
        focusRequest: RichTextEditorFocusRequest,
        textContainerInset: NSSize = NSSize(width: 8, height: 0),
        onChange: @escaping (NSAttributedString) -> Void
    ) {
        self.document = document
        self.revision = revision
        self.focusRequest = focusRequest
        self.textContainerInset = textContainerInset
        self.onChange = onChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> RichTextScrollView {
        let scrollView = RichTextScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(
            top: 0,
            left: 0,
            bottom: max(0, Self.bottomContentInset - textContainerInset.height),
            right: 0
        )

        let textView = scrollView.richTextView
        textView.delegate = context.coordinator
        textView.textContainerInset = textContainerInset
        textView.textStorage?.setAttributedString(document)
        textView.constrainImageAttachmentsToTextWidth()

        context.coordinator.appliedRevision = revision
        context.coordinator.appliedFocusRequestID = focusRequest.id
        if focusRequest.id > 0 {
            DispatchQueue.main.async {
                Self.applyFocusRequest(focusRequest, to: scrollView)
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: RichTextScrollView, context: Context) {
        context.coordinator.parent = self

        let textView = scrollView.richTextView
        textView.textContainerInset = textContainerInset
        scrollView.contentInsets = NSEdgeInsets(
            top: 0,
            left: 0,
            bottom: max(0, Self.bottomContentInset - textContainerInset.height),
            right: 0
        )

        if context.coordinator.appliedRevision != revision {
            context.coordinator.isApplyingExternalChange = true
            textView.textStorage?.setAttributedString(document)
            textView.constrainImageAttachmentsToTextWidth()
            context.coordinator.isApplyingExternalChange = false
            context.coordinator.appliedRevision = revision
        }

        if context.coordinator.appliedFocusRequestID != focusRequest.id {
            context.coordinator.appliedFocusRequestID = focusRequest.id
            DispatchQueue.main.async {
                Self.applyFocusRequest(focusRequest, to: scrollView)
            }
        }
    }

    private static func applyFocusRequest(
        _ request: RichTextEditorFocusRequest,
        to scrollView: RichTextScrollView
    ) {
        guard request.id > 0 else {
            return
        }

        let textView = scrollView.richTextView
        scrollView.window?.makeFirstResponder(textView)

        if let selectedRange = request.selectedRange {
            let documentLength = textView.textStorage?.length ?? 0
            let location = min(max(0, selectedRange.location), documentLength)
            let length = min(max(0, selectedRange.length), documentLength - location)
            let clampedRange = NSRange(location: location, length: length)
            textView.setSelectedRange(clampedRange)
            textView.scrollRangeToVisible(NSRange(location: location, length: 0))
        }

        textView.typingAttributes = RichTextView.defaultTypingAttributes
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditorView
        var appliedRevision: Int
        var appliedFocusRequestID: Int
        var isApplyingExternalChange = false
        private var resetsTypingAttributesAfterChange = false

        init(_ parent: RichTextEditorView) {
            self.parent = parent
            self.appliedRevision = parent.revision
            self.appliedFocusRequestID = parent.focusRequest.id
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            resetsTypingAttributesAfterChange = false
            guard !isApplyingExternalChange,
                  let textStorage = textView.textStorage else {
                return true
            }

            let document = NSAttributedString(attributedString: textStorage)
            let isEditable = RichTextDocument.isUserEditableRange(
                affectedCharRange,
                replacementString: replacementString,
                in: document
            )
            resetsTypingAttributesAfterChange = isEditable &&
                replacementString == "\n" &&
                affectedCharRange.length == 0 &&
                RichTextDocument.isTimestampLineContentEnd(
                    affectedCharRange.location,
                    in: document
                )
            return isEditable
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalChange else {
                resetsTypingAttributesAfterChange = false
                return
            }
            guard let textView = notification.object as? RichTextView,
                  let textStorage = textView.textStorage else {
                resetsTypingAttributesAfterChange = false
                return
            }

            textView.constrainImageAttachmentsToTextWidth()
            if resetsTypingAttributesAfterChange {
                textView.typingAttributes = RichTextView.defaultTypingAttributes
            }
            resetsTypingAttributesAfterChange = false
            parent.onChange(NSAttributedString(attributedString: textStorage))
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingExternalChange,
                  let textView = notification.object as? RichTextView else {
                return
            }

            textView.invalidateImageAttachmentDisplay()
        }
    }
}

final class RichTextScrollView: NSScrollView {
    let richTextView = RichTextView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureTextView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTextView()
    }

    private func configureTextView() {
        richTextView.minSize = NSSize(width: 0, height: contentSize.height)
        richTextView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        richTextView.isVerticallyResizable = true
        richTextView.isHorizontallyResizable = false
        richTextView.autoresizingMask = [.width]
        richTextView.textContainer?.containerSize = NSSize(
            width: contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        richTextView.textContainer?.widthTracksTextView = true
        documentView = richTextView
    }
}

final class RichTextView: NSTextView {
    private static let imageDisplayScale: CGFloat = 0.5
    private static let minimumImageAvailableWidth: CGFloat = 120
    private static let imageHorizontalPadding: CGFloat = 8

    static var defaultTypingAttributes: [NSAttributedString.Key: Any] {
        RichTextFormatting.bodyAttributes
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    @objc func insertImage(_ sender: Any?) {
        let selectedRange = selectedRange()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK else {
                return
            }

            self?.insertImages(panel.urls, replacing: selectedRange)
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    override func paste(_ sender: Any?) {
        guard let pastedContent = sanitizedPasteboardContents(from: .general),
              pastedContent.length > 0 else {
            return
        }

        let selectedRange = selectedRange()
        let replacementContent = imageBlockInsertionContent(
            pastedContent,
            replacing: selectedRange
        )
        guard shouldChangeText(in: selectedRange, replacementString: replacementContent.string) else {
            return
        }

        textStorage?.replaceCharacters(in: selectedRange, with: replacementContent)
        setSelectedRange(NSRange(location: selectedRange.location + replacementContent.length, length: 0))
        didChangeText()
        constrainImageAttachmentsToTextWidth()
        typingAttributes = Self.defaultTypingAttributes
    }

    override func deleteBackward(_ sender: Any?) {
        guard selectedRange().length == 0,
              handleTimestampLineBackwardDeleteIfNeeded() else {
            super.deleteBackward(sender)
            return
        }
    }

    override func deleteForward(_ sender: Any?) {
        guard selectedRange().length == 0,
              deleteTimestampLineForForwardDeleteIfNeeded() else {
            super.deleteForward(sender)
            return
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        constrainImageAttachmentsToTextWidth()
    }

    func constrainImageAttachmentsToTextWidth() {
        guard let textStorage else {
            return
        }

        let availableWidth = imageAttachmentAvailableWidth
        var didChangeAttachmentLayout = false
        var didChangeAttachmentDisplay = false
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.enumerateAttribute(.attachment, in: fullRange) { value, _, _ in
            guard let attachment = value as? NSTextAttachment,
                  let imageSize = Self.imageSize(for: attachment) else {
                return
            }

            if !(attachment.attachmentCell is SelectableImageAttachmentCell) {
                let cell = SelectableImageAttachmentCell()
                cell.attachment = attachment
                attachment.attachmentCell = cell
                didChangeAttachmentDisplay = true
            }

            let scale = min(Self.imageDisplayScale, availableWidth / imageSize.width)
            let newBounds = NSRect(
                x: 0,
                y: 0,
                width: imageSize.width * scale,
                height: imageSize.height * scale
            )

            if attachment.bounds != newBounds {
                attachment.bounds = newBounds
                didChangeAttachmentLayout = true
            }
        }

        if didChangeAttachmentLayout {
            layoutManager?.invalidateLayout(
                forCharacterRange: fullRange,
                actualCharacterRange: nil
            )
            layoutManager?.invalidateDisplay(forCharacterRange: fullRange)
        } else if didChangeAttachmentDisplay {
            layoutManager?.invalidateDisplay(forCharacterRange: fullRange)
        }
    }

    func invalidateImageAttachmentDisplay() {
        guard let textStorage,
              let layoutManager,
              let textContainer else {
            return
        }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            guard value is NSTextAttachment else {
                return
            }

            layoutManager.ensureLayout(forCharacterRange: range)
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            let containerRect = layoutManager.boundingRect(
                forGlyphRange: glyphRange,
                in: textContainer
            )
            let viewRect = containerRect
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
                .insetBy(dx: -4, dy: -4)
            setNeedsDisplay(viewRect)
        }
    }

    private func configure() {
        allowsUndo = true
        isEditable = true
        isSelectable = true
        isRichText = true
        importsGraphics = true
        allowsImageEditing = true
        drawsBackground = false
        usesAdaptiveColorMappingForDarkAppearance = true
        font = RichTextFormatting.bodyFont
        typingAttributes = Self.defaultTypingAttributes
    }

    private func sanitizedPasteboardContents(from pasteboard: NSPasteboard) -> NSAttributedString? {
        let pasteboardImages = imageAttachments(from: pasteboard)
        let imageSourceURLs = pasteboardImages.compactMap(\.sourceURL)
        let result = NSMutableAttributedString()

        if let richText = RichTextPasteSanitizer.sanitizedPasteboardRichText(from: pasteboard),
           RichTextDocument.hasMeaningfulContent(richText) {
            result.append(richText)
        } else if let plainText = pasteboard.string(forType: .string),
                  shouldUsePlainText(plainText, whenImageSourceURLsAre: imageSourceURLs),
                  let trimmedPlainText = RichTextPasteSanitizer.sanitizedTrimmedPlainText(plainText) {
            result.append(trimmedPlainText)
        }

        if !pasteboardImages.isEmpty, !containsAttachment(result) {
            appendImages(pasteboardImages.map(\.attachment), to: result)
        }

        guard result.length > 0 else {
            return nil
        }
        return result
    }

    private func shouldUsePlainText(
        _ plainText: String,
        whenImageSourceURLsAre imageSourceURLs: [URL]
    ) -> Bool {
        guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard !imageSourceURLs.isEmpty else {
            return true
        }

        let pastedLines = plainText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !pastedLines.isEmpty else {
            return false
        }

        let imageURLRepresentations = Set(
            imageSourceURLs.flatMap { url in
                [url.absoluteString, url.path, url.relativePath]
            }
        )
        return !pastedLines.allSatisfy { imageURLRepresentations.contains($0) }
    }

    private func imageAttachments(from pasteboard: NSPasteboard) -> [PasteboardImageAttachment] {
        guard let items = pasteboard.pasteboardItems else {
            return []
        }

        return items.compactMap { item in
            if let attachment = imageAttachment(fromImageDataIn: item) {
                return PasteboardImageAttachment(attachment: attachment, sourceURL: nil)
            }

            guard let fileURL = imageFileURL(from: item),
                  let attachment = makeImageAttachment(for: fileURL) else {
                return nil
            }
            return PasteboardImageAttachment(attachment: attachment, sourceURL: fileURL)
        }
    }

    private func imageAttachment(fromImageDataIn item: NSPasteboardItem) -> NSTextAttachment? {
        for pasteboardType in imagePasteboardTypes {
            guard let data = item.data(forType: pasteboardType),
                  let image = NSImage(data: data) else {
                continue
            }

            let attachment = NSTextAttachment(data: data, ofType: pasteboardType.rawValue)
            attachment.bounds = scaledBounds(for: image.size)
            return attachment
        }

        return nil
    }

    private func imageFileURL(from item: NSPasteboardItem) -> URL? {
        guard let fileURLString = item.string(forType: .fileURL),
              let fileURL = URL(string: fileURLString),
              fileURL.isFileURL else {
            return nil
        }

        return fileURL
    }

    private func appendImages(
        _ attachments: [NSTextAttachment],
        to result: NSMutableAttributedString
    ) {
        for attachment in attachments {
            if result.length > 0 {
                result.append(RichTextPasteSanitizer.sanitizedPlainText("\n"))
            }
            result.append(NSAttributedString(attachment: attachment))
        }
    }

    private func containsAttachment(_ attributedString: NSAttributedString) -> Bool {
        var hasAttachment = false
        attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, stop in
            if value is NSTextAttachment {
                hasAttachment = true
                stop.pointee = true
            }
        }
        return hasAttachment
    }

    private func insertImages(_ urls: [URL], replacing range: NSRange) {
        let images = urls.compactMap(makeImageAttachment)
        guard !images.isEmpty else {
            return
        }

        let insertedText = NSMutableAttributedString()
        for attachment in images {
            if insertedText.length > 0 {
                insertedText.append(NSAttributedString(string: "\n"))
            }
            insertedText.append(NSAttributedString(attachment: attachment))
        }

        let replacementContent = imageBlockInsertionContent(insertedText, replacing: range)
        guard shouldChangeText(in: range, replacementString: replacementContent.string) else {
            return
        }

        textStorage?.replaceCharacters(in: range, with: replacementContent)
        setSelectedRange(NSRange(location: range.location + replacementContent.length, length: 0))
        didChangeText()
        constrainImageAttachmentsToTextWidth()
    }

    private func handleTimestampLineBackwardDeleteIfNeeded() -> Bool {
        guard let textStorage else {
            return false
        }

        let document = NSAttributedString(attributedString: textStorage)
        let location = selectedRange().location
        guard let deletionRange = RichTextDocument.timestampLineDeletionRangeForBackwardDelete(
            at: location,
            in: document
        ) else {
            return moveToTimestampLineEndForBackwardDeleteIfNeeded(
                at: location,
                in: document
            )
        }

        return deleteCharacters(in: deletionRange)
    }

    private func moveToTimestampLineEndForBackwardDeleteIfNeeded(
        at location: Int,
        in document: NSAttributedString
    ) -> Bool {
        guard let lineEndLocation = RichTextDocument.timestampLineEndLocationForBackwardDelete(
            at: location,
            in: document
        ) else {
            return false
        }

        let lineEndRange = NSRange(location: lineEndLocation, length: 0)
        setSelectedRange(lineEndRange)
        scrollRangeToVisible(lineEndRange)
        return true
    }

    private func deleteTimestampLineForForwardDeleteIfNeeded() -> Bool {
        guard let textStorage else {
            return false
        }

        let document = NSAttributedString(attributedString: textStorage)
        guard let deletionRange = RichTextDocument.timestampLineDeletionRangeForForwardDelete(
            at: selectedRange().location,
            in: document
        ) else {
            return false
        }

        return deleteCharacters(in: deletionRange)
    }

    private func deleteCharacters(in range: NSRange) -> Bool {
        guard shouldChangeText(in: range, replacementString: "") else {
            return false
        }

        textStorage?.replaceCharacters(in: range, with: "")
        setSelectedRange(NSRange(location: range.location, length: 0))
        didChangeText()
        return true
    }

    private func imageBlockInsertionContent(
        _ content: NSAttributedString,
        replacing range: NSRange
    ) -> NSAttributedString {
        guard containsAttachment(content),
              let textStorage else {
            return content
        }

        let currentString = textStorage.string as NSString
        let result = NSMutableAttributedString()

        if needsLeadingImageBlockSeparator(
            before: range,
            content: content,
            in: currentString
        ) {
            result.append(Self.imageBlockSeparator())
        }

        result.append(content)

        if needsTrailingImageBlockSeparator(
            after: range,
            content: content,
            in: currentString
        ) {
            result.append(Self.imageBlockSeparator())
        }

        return result
    }

    private func needsLeadingImageBlockSeparator(
        before range: NSRange,
        content: NSAttributedString,
        in currentString: NSString
    ) -> Bool {
        guard range.location > 0,
              !startsWithNewline(content) else {
            return false
        }

        return !isNewline(at: range.location - 1, in: currentString)
    }

    private func needsTrailingImageBlockSeparator(
        after range: NSRange,
        content: NSAttributedString,
        in currentString: NSString
    ) -> Bool {
        guard !endsWithNewline(content) else {
            return false
        }

        let upperBound = NSMaxRange(range)
        guard upperBound < currentString.length else {
            return true
        }

        return !isNewline(at: upperBound, in: currentString)
    }

    private func startsWithNewline(_ attributedString: NSAttributedString) -> Bool {
        guard attributedString.length > 0 else {
            return false
        }

        return isNewline(at: 0, in: attributedString.string as NSString)
    }

    private func endsWithNewline(_ attributedString: NSAttributedString) -> Bool {
        guard attributedString.length > 0 else {
            return false
        }

        return isNewline(
            at: attributedString.length - 1,
            in: attributedString.string as NSString
        )
    }

    private func isNewline(at location: Int, in string: NSString) -> Bool {
        guard location >= 0, location < string.length else {
            return false
        }

        let character = string.substring(with: NSRange(location: location, length: 1))
        return character.rangeOfCharacter(from: .newlines) != nil
    }

    private static func imageBlockSeparator() -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: defaultTypingAttributes)
    }

    private func makeImageAttachment(for fileURL: URL) -> NSTextAttachment? {
        guard let image = NSImage(contentsOf: fileURL) else {
            return nil
        }

        do {
            let wrapper = try FileWrapper(url: fileURL, options: .immediate)
            wrapper.preferredFilename = fileURL.lastPathComponent

            let attachment = NSTextAttachment(fileWrapper: wrapper)
            attachment.bounds = scaledBounds(for: image.size)
            return attachment
        } catch {
            NSSound.beep()
            return nil
        }
    }

    private func scaledBounds(for imageSize: NSSize) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }

        let scale = min(Self.imageDisplayScale, imageAttachmentAvailableWidth / imageSize.width)
        return NSRect(
            x: 0,
            y: 0,
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }

    private var imageAttachmentAvailableWidth: CGFloat {
        max(
            Self.minimumImageAvailableWidth,
            bounds.width - textContainerInset.width * 2 - Self.imageHorizontalPadding
        )
    }

    fileprivate static func image(for attachment: NSTextAttachment) -> NSImage? {
        if let image = attachment.image {
            return image
        }

        if let contents = attachment.contents,
           let image = NSImage(data: contents) {
            return image
        }

        if let contents = attachment.fileWrapper?.regularFileContents,
           let image = NSImage(data: contents) {
            return image
        }

        return nil
    }

    private static func imageSize(for attachment: NSTextAttachment) -> NSSize? {
        guard let size = image(for: attachment)?.size,
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        return size
    }

    private var imagePasteboardTypes: [NSPasteboard.PasteboardType] {
        [
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("public.heif")
        ]
    }

    private struct PasteboardImageAttachment {
        let attachment: NSTextAttachment
        let sourceURL: URL?
    }
}

private final class SelectableImageAttachmentCell: NSTextAttachmentCell {
    override func draw(
        withFrame cellFrame: NSRect,
        in controlView: NSView?,
        characterIndex charIndex: Int,
        layoutManager: NSLayoutManager
    ) {
        drawImage(withFrame: cellFrame, in: controlView)

        if isSelected(characterIndex: charIndex, in: controlView) {
            drawSelectionHighlight(withFrame: cellFrame, in: controlView)
        }
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        drawImage(withFrame: cellFrame, in: controlView)

        if isSelected(in: controlView) {
            drawSelectionHighlight(withFrame: cellFrame, in: controlView)
        }
    }

    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard flag else {
            return
        }

        drawSelectionHighlight(withFrame: cellFrame, in: controlView)
    }

    override func cellSize() -> NSSize {
        if let bounds = attachment?.bounds,
           bounds.size.width > 0,
           bounds.size.height > 0 {
            return bounds.size
        }

        if let attachment,
           let image = RichTextView.image(for: attachment) {
            return image.size
        }

        return super.cellSize()
    }

    private func drawImage(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard let attachment,
              let image = RichTextView.image(for: attachment) else {
            super.draw(withFrame: cellFrame, in: controlView)
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: cellFrame,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private func isSelected(characterIndex: Int, in controlView: NSView?) -> Bool {
        guard let textView = controlView as? NSTextView else {
            return false
        }

        return textView.selectedRanges.contains { selectedRangeValue in
            let selectedRange = selectedRangeValue.rangeValue
            return selectedRange.length > 0 && NSLocationInRange(characterIndex, selectedRange)
        }
    }

    private func isSelected(in controlView: NSView?) -> Bool {
        guard let attachment,
              let textView = controlView as? NSTextView,
              let textStorage = textView.textStorage else {
            return false
        }

        var isSelected = false
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttribute(.attachment, in: fullRange) { value, range, stop in
            guard let rangeAttachment = value as? NSTextAttachment,
                  rangeAttachment === attachment else {
                return
            }

            isSelected = textView.selectedRanges.contains { selectedRangeValue in
                let selectedRange = selectedRangeValue.rangeValue
                return selectedRange.length > 0 &&
                    NSIntersectionRange(selectedRange, range).length > 0
            }
            stop.pointee = true
        }
        return isSelected
    }

    private func drawSelectionHighlight(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard cellFrame.width > 2,
              cellFrame.height > 2 else {
            return
        }

        let selectionColor = selectionBackgroundColor(for: controlView)
        let fillPath = NSBezierPath(rect: cellFrame)
        let strokePath = NSBezierPath(rect: cellFrame.insetBy(dx: 1, dy: 1))

        selectionColor.withAlphaComponent(0.16).setFill()
        fillPath.fill()

        selectionColor.withAlphaComponent(0.9).setStroke()
        strokePath.lineWidth = 2
        strokePath.stroke()
    }

    private func selectionBackgroundColor(for controlView: NSView?) -> NSColor {
        guard let textView = controlView as? NSTextView,
              textView.window?.isKeyWindow == true,
              textView.window?.firstResponder === textView else {
            return .unemphasizedSelectedContentBackgroundColor
        }

        return .selectedTextBackgroundColor
    }
}
