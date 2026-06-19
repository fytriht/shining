import AppKit
import ShiningCore
import SwiftUI
import UniformTypeIdentifiers

struct JournalEditorFocusRequest {
    static let none = JournalEditorFocusRequest(id: 0, selection: nil)

    let id: Int
    let selection: JournalTextSelection?
}

final class EditorFocusController: ObservableObject {
    @Published private(set) var request = JournalEditorFocusRequest.none

    func requestFocus(selection: JournalTextSelection? = nil) {
        request = JournalEditorFocusRequest(
            id: request.id + 1,
            selection: selection
        )
    }
}

struct JournalEditorView: NSViewRepresentable {
    let document: JournalDocument
    let revision: Int
    let focusRequest: JournalEditorFocusRequest
    let attachmentURL: (String) -> URL
    let importImageFile: (URL) -> JournalImageBlock?
    let importImage: (NSImage, String) -> JournalImageBlock?
    let onChange: (JournalDocument) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> JournalEditorScrollView {
        let scrollView = JournalEditorScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = scrollView.journalTextView
        configure(textView, context: context)
        context.coordinator.apply(document: document, revision: revision, to: textView)

        if focusRequest.id > 0 {
            DispatchQueue.main.async {
                Self.applyFocusRequest(focusRequest, to: textView)
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: JournalEditorScrollView, context: Context) {
        context.coordinator.parent = self
        let textView = scrollView.journalTextView
        configure(textView, context: context)

        if context.coordinator.appliedRevision != revision {
            context.coordinator.apply(document: document, revision: revision, to: textView)
        }

        if context.coordinator.appliedFocusRequestID != focusRequest.id {
            context.coordinator.appliedFocusRequestID = focusRequest.id
            DispatchQueue.main.async {
                Self.applyFocusRequest(focusRequest, to: textView)
            }
        }
    }

    private func configure(_ textView: JournalTextView, context: Context) {
        textView.delegate = context.coordinator
        textView.journalCoordinator = context.coordinator
    }

    private static func applyFocusRequest(
        _ request: JournalEditorFocusRequest,
        to textView: JournalTextView
    ) {
        guard request.id > 0 else {
            return
        }

        textView.window?.makeFirstResponder(textView)
        if let selection = request.selection,
           let range = textView.projection?.selectionRange(for: selection) {
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(NSRange(location: range.location, length: 0))
            textView.updateTypingAttributesForCurrentSelection()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JournalEditorView
        var appliedRevision: Int
        var appliedFocusRequestID: Int
        var isApplyingExternalChange = false
        private var fallbackDocument: JournalDocument

        init(_ parent: JournalEditorView) {
            self.parent = parent
            self.appliedRevision = parent.revision
            self.appliedFocusRequestID = parent.focusRequest.id
            self.fallbackDocument = parent.document
        }

        func apply(
            document: JournalDocument,
            revision: Int,
            to textView: JournalTextView
        ) {
            isApplyingExternalChange = true
            let projection = makeProjection(for: document)
            textView.projection = projection
            textView.textStorage?.setAttributedString(projection.attributedString)
            textView.constrainImageAttachmentsToColumnWidth()
            textView.needsDisplay = true
            fallbackDocument = document
            isApplyingExternalChange = false
            appliedRevision = revision
        }

        func makeProjection(for document: JournalDocument) -> JournalProjection {
            JournalProjection.make(document: document) { [parent] assetID in
                parent.attachmentURL(assetID)
            }
        }

        func importImageFile(_ fileURL: URL) -> JournalImageBlock? {
            parent.importImageFile(fileURL)
        }

        func importImage(_ image: NSImage, originalFilename: String) -> JournalImageBlock? {
            parent.importImage(image, originalFilename)
        }

        func attachmentURL(for assetID: String) -> URL {
            parent.attachmentURL(assetID)
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard !isApplyingExternalChange,
                  let textView = textView as? JournalTextView else {
                return true
            }

            if textView.protectedRangeForCurrentTextStorage(forChangeIn: affectedCharRange) != nil {
                return false
            }

            if replacementString != nil,
               !textView.hasMarkedText() {
                textView.updateTypingAttributesForCurrentSelection()
            }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalChange,
                  let textView = notification.object as? JournalTextView else {
                return
            }

            guard !textView.hasMarkedText() else {
                textView.needsDisplay = true
                return
            }

            synchronizeTextStorage(from: textView)
        }

        func synchronizeTextStorage(from textView: JournalTextView) {
            guard !isApplyingExternalChange,
                  !textView.hasMarkedText(),
                  let textStorage = textView.textStorage else {
                return
            }

            textView.constrainImageAttachmentsToColumnWidth()
            let previousDocument = fallbackDocument
            let nextDocument = JournalProjection.document(
                from: NSAttributedString(attributedString: textStorage),
                fallbackDocument: fallbackDocument
            )
            fallbackDocument = nextDocument
            textView.projection = makeProjection(for: nextDocument)
            textView.needsDisplay = true
            if nextDocument != previousDocument {
                parent.onChange(nextDocument)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? JournalTextView else {
                return
            }
            guard !textView.hasMarkedText() else {
                return
            }
            textView.updateTypingAttributesForCurrentSelection()
        }
    }
}

final class JournalEditorScrollView: NSScrollView {
    let journalTextView = JournalTextView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureTextView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTextView()
    }

    private func configureTextView() {
        journalTextView.minSize = NSSize(width: 0, height: contentSize.height)
        journalTextView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        journalTextView.isVerticallyResizable = true
        journalTextView.isHorizontallyResizable = false
        journalTextView.autoresizingMask = [.width]
        journalTextView.updateTextContainerWidth(for: contentSize.width)
        documentView = journalTextView
    }
}

final class JournalTextView: NSTextView {
    private static let maxColumnWidth: CGFloat = 640
    private static let minHorizontalMargin: CGFloat = 32
    private static let topInset: CGFloat = 32
    fileprivate static let imageCornerRadius: CGFloat = 6

    weak var journalCoordinator: JournalEditorView.Coordinator?
    var projection: JournalProjection?

    override var textContainerOrigin: NSPoint {
        guard let textContainer else {
            return super.textContainerOrigin
        }

        let x = max(
            Self.minHorizontalMargin,
            (bounds.width - textContainer.containerSize.width) / 2
        )
        return NSPoint(x: x, y: textContainerInset.height)
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
            self?.insertImageFiles(panel.urls, replacing: selectedRange)
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL],
            insertImageFiles(urls, replacing: selectedRange()) {
            return
        }

        if let image = NSImage(pasteboard: pasteboard),
           insertImages([image], replacing: selectedRange()) {
            return
        }

        if let string = pasteboard.string(forType: .string) {
            insertPlainText(string, replacing: selectedRange())
            return
        }

        NSSound.beep()
    }

    override func deleteBackward(_ sender: Any?) {
        guard !hasMarkedText() else {
            super.deleteBackward(sender)
            return
        }

        journalCoordinator?.synchronizeTextStorage(from: self)
        guard selectedRange().length == 0,
              let protectedRange = protectedRangeForCurrentTextStorage(
                before: selectedRange().location
              ) else {
            super.deleteBackward(sender)
            return
        }

        setSelectedRange(NSRange(location: protectedRange.location, length: 0))
    }

    override func deleteForward(_ sender: Any?) {
        guard !hasMarkedText() else {
            super.deleteForward(sender)
            return
        }

        journalCoordinator?.synchronizeTextStorage(from: self)
        guard selectedRange().length == 0,
              let protectedRange = protectedRangeForCurrentTextStorage(
                at: selectedRange().location
              ) else {
            super.deleteForward(sender)
            return
        }

        setSelectedRange(NSRange(location: protectedRange.endLocation, length: 0))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTextContainerWidth(for: newSize.width)
        constrainImageAttachmentsToColumnWidth()
    }

    override func draw(_ dirtyRect: NSRect) {
        drawTimestampSeparators()
        super.draw(dirtyRect)
    }

    func updateTextContainerWidth(for availableWidth: CGFloat) {
        let columnWidth = min(
            Self.maxColumnWidth,
            max(120, availableWidth - Self.minHorizontalMargin * 2)
        )
        textContainer?.containerSize = NSSize(
            width: columnWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        textContainer?.widthTracksTextView = false
        textContainerInset = NSSize(width: 0, height: Self.topInset)
    }

    func updateTypingAttributesForCurrentSelection() {
        let location = selectedRange().location
        if let attributes = projection?.paragraphAttributesForInsertion(at: location) {
            typingAttributes = attributes
        }
    }

    fileprivate func protectedRangeForCurrentTextStorage(forChangeIn range: NSRange) -> NSRange? {
        guard range.location != NSNotFound else {
            return nil
        }

        if range.length == 0 {
            return protectedRangeForCurrentTextStorage(at: range.location)
        }

        return protectedRangesForCurrentTextStorage().first { protectedRange in
            NSIntersectionRange(range, protectedRange).length > 0
        }
    }

    fileprivate func protectedRangeForCurrentTextStorage(before location: Int) -> NSRange? {
        guard location > 0 else {
            return nil
        }
        return protectedRangeForCurrentTextStorage(at: location - 1)
    }

    fileprivate func protectedRangeForCurrentTextStorage(at location: Int) -> NSRange? {
        protectedRangesForCurrentTextStorage().first { range in
            NSLocationInRange(location, range)
        }
    }

    func constrainImageAttachmentsToColumnWidth() {
        guard let textStorage else {
            return
        }

        let availableWidth = textContainer?.containerSize.width ?? Self.maxColumnWidth
        var didChangeAttachmentBounds = false
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.enumerateAttribute(.attachment, in: fullRange) { value, _, _ in
            guard let attachment = value as? NSTextAttachment,
                  let imageSize = intrinsicImageSize(for: attachment) else {
                return
            }

            let scale = min(1, availableWidth / imageSize.width)
            let newBounds = NSRect(
                x: 0,
                y: 0,
                width: imageSize.width * scale,
                height: imageSize.height * scale
            )

            if attachment.bounds.size != newBounds.size {
                attachment.bounds = newBounds
                didChangeAttachmentBounds = true
            }
            if let image = image(for: attachment) {
                attachment.attachmentCell = JournalImageAttachmentCell(
                    image: image,
                    displaySize: newBounds.size
                )
            }
        }

        if didChangeAttachmentBounds {
            layoutManager?.invalidateDisplay(forCharacterRange: fullRange)
        }
    }

    private func configure() {
        allowsUndo = true
        isEditable = true
        isSelectable = true
        isRichText = true
        importsGraphics = false
        allowsImageEditing = true
        drawsBackground = false
        usesAdaptiveColorMappingForDarkAppearance = true
        font = .systemFont(ofSize: 15)
        insertionPointColor = .labelColor
        updateTextContainerWidth(for: bounds.width)
    }

    private func insertPlainText(_ string: String, replacing range: NSRange) {
        guard shouldChangeText(in: range, replacementString: string) else {
            return
        }

        let attributes = projection?.paragraphAttributesForInsertion(at: range.location) ??
            typingAttributes
        let attributedString = NSAttributedString(string: string, attributes: attributes)
        textStorage?.replaceCharacters(in: range, with: attributedString)
        didChangeText()
    }

    @discardableResult
    private func insertImageFiles(_ urls: [URL], replacing range: NSRange) -> Bool {
        let images = urls.compactMap { url in
            journalCoordinator?.importImageFile(url)
        }
        return insertImageBlocks(images, replacing: range)
    }

    @discardableResult
    private func insertImages(_ images: [NSImage], replacing range: NSRange) -> Bool {
        let imageBlocks = images.compactMap { image in
            journalCoordinator?.importImage(image, originalFilename: "Pasted Image.tiff")
        }
        return insertImageBlocks(imageBlocks, replacing: range)
    }

    @discardableResult
    private func insertImageBlocks(_ blocks: [JournalImageBlock], replacing range: NSRange) -> Bool {
        guard !blocks.isEmpty,
              shouldChangeText(in: range, replacementString: nil),
              let projection else {
            return false
        }

        let entryID = projection
            .ranges
            .last(where: { $0.role == .paragraph && $0.range.location <= range.location })?
            .entryID ?? projection.ranges.first?.entryID
        guard let entryID else {
            return false
        }

        let insertedText = NSMutableAttributedString()
        let paragraphAttributes = projection.paragraphAttributesForInsertion(at: range.location) ??
            JournalProjection.paragraphAttributes(entryID: entryID, blockID: UUID())

        if range.location > 0,
           textStorage?.string.utf16CodeUnit(at: range.location - 1) != 10 {
            insertedText.append(NSAttributedString(string: "\n", attributes: paragraphAttributes))
        }

        for (index, block) in blocks.enumerated() {
            if index > 0 {
                insertedText.append(NSAttributedString(string: "\n", attributes: paragraphAttributes))
            }
            insertedText.append(attributedImage(for: block, entryID: entryID))
        }

        if range.location < (textStorage?.length ?? 0),
           textStorage?.string.utf16CodeUnit(at: range.location) != 10 {
            insertedText.append(NSAttributedString(string: "\n", attributes: paragraphAttributes))
        }

        textStorage?.replaceCharacters(in: range, with: insertedText)
        didChangeText()
        constrainImageAttachmentsToColumnWidth()
        return true
    }

    private func attributedImage(
        for block: JournalImageBlock,
        entryID: UUID
    ) -> NSAttributedString {
        let attachment = NSTextAttachment()
        if let url = journalCoordinator?.attachmentURL(for: block.assetID),
           let image = NSImage(contentsOf: url) {
            attachment.image = image
            attachment.bounds = NSRect(origin: .zero, size: image.size)
        }

        var attributes = JournalProjection.imageAttributes(block: block, entryID: entryID)
        attributes[.attachment] = attachment
        let attributedString = NSMutableAttributedString(attachment: attachment)
        attributedString.addAttributes(
            attributes,
            range: NSRange(location: 0, length: attributedString.length)
        )
        return attributedString
    }

    private func drawTimestampSeparators() {
        guard let layoutManager,
              let textContainer else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let origin = textContainerOrigin
        let lineColor = NSColor.separatorColor.withAlphaComponent(0.55)
        lineColor.setStroke()

        for range in timestampSeparatorRangesForCurrentTextStorage() {
            guard range.length > 0 else {
                continue
            }

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            let labelRect = layoutManager
                .boundingRect(forGlyphRange: glyphRange, in: textContainer)
                .offsetBy(dx: origin.x, dy: origin.y)
            let y = floor(labelRect.midY) + 0.5
            let leftEnd = labelRect.minX - 10
            let rightStart = labelRect.maxX + 10
            let lineStart = origin.x
            let lineEnd = origin.x + textContainer.containerSize.width

            if leftEnd > lineStart {
                drawLine(from: NSPoint(x: lineStart, y: y), to: NSPoint(x: leftEnd, y: y))
            }
            if lineEnd > rightStart {
                drawLine(from: NSPoint(x: rightStart, y: y), to: NSPoint(x: lineEnd, y: y))
            }
        }
    }

    private func drawLine(from start: NSPoint, to end: NSPoint) {
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: start)
        path.line(to: end)
        path.stroke()
    }

    private func intrinsicImageSize(for attachment: NSTextAttachment) -> NSSize? {
        if let image = image(for: attachment) {
            return image.size
        }

        if attachment.bounds.size.width > 0, attachment.bounds.size.height > 0 {
            return attachment.bounds.size
        }

        return nil
    }

    private func image(for attachment: NSTextAttachment) -> NSImage? {
        if let image = attachment.image {
            return image
        }

        if let contents = attachment.fileWrapper?.regularFileContents,
           let image = NSImage(data: contents) {
            return image
        }

        return nil
    }

    private func protectedRangesForCurrentTextStorage() -> [NSRange] {
        guard let textStorage,
              textStorage.length > 0 else {
            return []
        }

        var ranges: [NSRange] = []
        textStorage.enumerateAttribute(
            .shiningProtected,
            in: NSRange(location: 0, length: textStorage.length)
        ) { value, range, _ in
            guard Self.isProtectedAttribute(value) else {
                return
            }
            ranges.append(range)
        }

        return ranges.coalescingAdjacentRanges()
    }

    private func timestampSeparatorRangesForCurrentTextStorage() -> [NSRange] {
        guard let textStorage,
              textStorage.length > 0 else {
            return []
        }

        var ranges: [NSRange] = []
        textStorage.enumerateAttribute(
            .shiningRole,
            in: NSRange(location: 0, length: textStorage.length)
        ) { value, range, _ in
            guard let rawValue = value as? String,
                  JournalTextRole(rawValue: rawValue) == .timestampSeparator else {
                return
            }
            ranges.append(range)
        }
        return ranges
    }

    private static func isProtectedAttribute(_ value: Any?) -> Bool {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return false
    }
}

private final class JournalImageAttachmentCell: NSTextAttachmentCell {
    private let sourceImage: NSImage
    private let displaySize: NSSize

    init(image: NSImage, displaySize: NSSize) {
        self.sourceImage = image
        self.displaySize = displaySize
        super.init(imageCell: image)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func cellSize() -> NSSize {
        displaySize
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let imageRect = NSRect(origin: cellFrame.origin, size: displaySize)
        let path = NSBezierPath(
            roundedRect: imageRect,
            xRadius: JournalTextView.imageCornerRadius,
            yRadius: JournalTextView.imageCornerRadius
        )

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        sourceImage.draw(
            in: imageRect,
            from: NSRect(origin: .zero, size: sourceImage.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()

        NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

private extension String {
    func utf16CodeUnit(at location: Int) -> unichar? {
        guard location >= 0, location < utf16.count else {
            return nil
        }
        return (self as NSString).character(at: location)
    }
}

private extension NSRange {
    var endLocation: Int {
        location + length
    }
}

private extension Array where Element == NSRange {
    func coalescingAdjacentRanges() -> [NSRange] {
        guard !isEmpty else {
            return []
        }

        let sortedRanges = sorted {
            if $0.location == $1.location {
                return $0.length < $1.length
            }
            return $0.location < $1.location
        }

        var result: [NSRange] = []
        for range in sortedRanges {
            guard var last = result.popLast() else {
                result.append(range)
                continue
            }

            if range.location <= last.endLocation {
                let endLocation = Swift.max(last.endLocation, range.endLocation)
                last.length = endLocation - last.location
                result.append(last)
            } else {
                result.append(last)
                result.append(range)
            }
        }
        return result
    }
}
