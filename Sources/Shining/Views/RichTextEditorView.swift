import AppKit
import ShiningCore
import SwiftUI
import UniformTypeIdentifiers

struct RichTextEditorView: NSViewRepresentable {
    let document: NSAttributedString
    let revision: Int
    let focusRequest: RichTextEditorFocusRequest
    let textContainerInset: NSSize
    let onChange: (NSAttributedString) -> Void

    init(
        document: NSAttributedString,
        revision: Int,
        focusRequest: RichTextEditorFocusRequest,
        textContainerInset: NSSize = NSSize(width: 8, height: 8),
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
            guard !isApplyingExternalChange,
                  let textStorage = textView.textStorage else {
                return true
            }

            let document = NSAttributedString(attributedString: textStorage)
            if replacementString == "" {
                return RichTextDocument.isUserDeletableRange(
                    affectedCharRange,
                    in: document
                )
            }

            return RichTextDocument.isUserEditableRange(
                affectedCharRange,
                in: document
            )
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalChange,
                  let textView = notification.object as? RichTextView,
                  let textStorage = textView.textStorage else {
                return
            }

            textView.constrainImageAttachmentsToTextWidth()
            parent.onChange(NSAttributedString(attributedString: textStorage))
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
    static var defaultTypingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor
        ]
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
        super.paste(sender)
        constrainImageAttachmentsToTextWidth()
    }

    override func deleteBackward(_ sender: Any?) {
        guard selectedRange().length == 0,
              deleteTimestampLineForBackwardDeleteIfNeeded() else {
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

        let availableWidth = max(120, bounds.width - textContainerInset.width * 2 - 8)
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
        importsGraphics = true
        allowsImageEditing = true
        drawsBackground = false
        usesAdaptiveColorMappingForDarkAppearance = true
        font = .systemFont(ofSize: NSFont.systemFontSize)
        typingAttributes = Self.defaultTypingAttributes
    }

    private func insertImages(_ urls: [URL], replacing range: NSRange) {
        let images = urls.compactMap(makeImageAttachment)
        guard !images.isEmpty,
              shouldChangeText(in: range, replacementString: nil) else {
            return
        }

        let insertedText = NSMutableAttributedString()
        for attachment in images {
            if insertedText.length > 0 {
                insertedText.append(NSAttributedString(string: "\n"))
            }
            insertedText.append(NSAttributedString(attachment: attachment))
        }

        textStorage?.replaceCharacters(in: range, with: insertedText)
        didChangeText()
        constrainImageAttachmentsToTextWidth()
    }

    private func deleteTimestampLineForBackwardDeleteIfNeeded() -> Bool {
        guard let textStorage else {
            return false
        }

        let document = NSAttributedString(attributedString: textStorage)
        guard let deletionRange = RichTextDocument.timestampLineDeletionRangeForBackwardDelete(
            at: selectedRange().location,
            in: document
        ) else {
            return false
        }

        return deleteCharacters(in: deletionRange)
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
        let availableWidth = max(120, bounds.width - textContainerInset.width * 2 - 8)
        guard imageSize.width > availableWidth else {
            return NSRect(origin: .zero, size: imageSize)
        }

        let scale = availableWidth / imageSize.width
        return NSRect(
            x: 0,
            y: 0,
            width: availableWidth,
            height: imageSize.height * scale
        )
    }

    private func intrinsicImageSize(for attachment: NSTextAttachment) -> NSSize? {
        if let image = attachment.image {
            return image.size
        }

        if let contents = attachment.fileWrapper?.regularFileContents,
           let image = NSImage(data: contents) {
            return image.size
        }

        if attachment.bounds.size.width > 0, attachment.bounds.size.height > 0 {
            return attachment.bounds.size
        }

        return nil
    }
}
