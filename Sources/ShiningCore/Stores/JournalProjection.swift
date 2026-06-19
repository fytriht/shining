import AppKit
import Foundation

public enum JournalTextRole: String {
    case timestampSeparator
    case timestampBoundary
    case paragraph
    case image
    case spacer
}

public extension NSAttributedString.Key {
    static let shiningRole = NSAttributedString.Key("com.fytriht.shining.role")
    static let shiningProtected = NSAttributedString.Key("com.fytriht.shining.protected")
    static let shiningEntryID = NSAttributedString.Key("com.fytriht.shining.entryID")
    static let shiningBlockID = NSAttributedString.Key("com.fytriht.shining.blockID")
    static let shiningImageAssetID = NSAttributedString.Key("com.fytriht.shining.image.assetID")
    static let shiningImageOriginalFilename =
        NSAttributedString.Key("com.fytriht.shining.image.originalFilename")
    static let shiningImagePixelWidth =
        NSAttributedString.Key("com.fytriht.shining.image.pixelWidth")
    static let shiningImagePixelHeight =
        NSAttributedString.Key("com.fytriht.shining.image.pixelHeight")
}

public struct JournalProjectedRange: Equatable {
    public let role: JournalTextRole
    public let entryID: UUID
    public let blockID: UUID?
    public let range: NSRange
    public let isProtected: Bool

    public init(
        role: JournalTextRole,
        entryID: UUID,
        blockID: UUID?,
        range: NSRange,
        isProtected: Bool
    ) {
        self.role = role
        self.entryID = entryID
        self.blockID = blockID
        self.range = range
        self.isProtected = isProtected
    }
}

public struct JournalProjection {
    public let attributedString: NSAttributedString
    public let ranges: [JournalProjectedRange]

    public init(attributedString: NSAttributedString, ranges: [JournalProjectedRange]) {
        self.attributedString = attributedString
        self.ranges = ranges
    }

    public static func make(
        document: JournalDocument,
        attachmentURL: (String) -> URL?
    ) -> JournalProjection {
        let result = NSMutableAttributedString()
        var ranges: [JournalProjectedRange] = []

        for entryIndex in document.entries.indices {
            let entry = document.entries[entryIndex]
            if entryIndex > 0 {
                let range = append(
                    "\n\n",
                    to: result,
                    attributes: spacerAttributes(entryID: entry.id)
                )
                ranges.append(
                    JournalProjectedRange(
                        role: .spacer,
                        entryID: entry.id,
                        blockID: nil,
                        range: range,
                        isProtected: false
                    )
                )
            }

            let timestampRange = append(
                formattedTimestamp(entry.createdAt),
                to: result,
                attributes: timestampAttributes(entryID: entry.id)
            )
            ranges.append(
                JournalProjectedRange(
                    role: .timestampSeparator,
                    entryID: entry.id,
                    blockID: nil,
                    range: timestampRange,
                    isProtected: true
                )
            )

            let boundaryRange = append(
                "\n",
                to: result,
                attributes: timestampBoundaryAttributes(entryID: entry.id)
            )
            ranges.append(
                JournalProjectedRange(
                    role: .timestampBoundary,
                    entryID: entry.id,
                    blockID: nil,
                    range: boundaryRange,
                    isProtected: true
                )
            )

            appendBlocks(
                entry.blocks,
                entryID: entry.id,
                attachmentURL: attachmentURL,
                to: result,
                ranges: &ranges
            )
        }

        return JournalProjection(attributedString: result, ranges: ranges)
    }

    public func selectionRange(for selection: JournalTextSelection) -> NSRange? {
        guard let blockRange = ranges.first(where: {
            $0.entryID == selection.entryID &&
                $0.blockID == selection.blockID &&
                $0.role == .paragraph
        }) else {
            return nil
        }

        let location = min(
            max(0, selection.range.location),
            blockRange.range.length
        )
        let length = min(
            max(0, selection.range.length),
            blockRange.range.length - location
        )
        return NSRange(
            location: blockRange.range.location + location,
            length: length
        )
    }

    public func protectedRange(forChangeIn range: NSRange) -> JournalProjectedRange? {
        ranges.first { projectedRange in
            guard projectedRange.isProtected else {
                return false
            }

            if range.length == 0 {
                return NSLocationInRange(range.location, projectedRange.range)
            }
            return NSIntersectionRange(range, projectedRange.range).length > 0
        }
    }

    public func protectedRange(before location: Int) -> JournalProjectedRange? {
        guard location > 0 else {
            return nil
        }

        return ranges.first { projectedRange in
            projectedRange.isProtected &&
                NSLocationInRange(location - 1, projectedRange.range)
        }
    }

    public func protectedRange(at location: Int) -> JournalProjectedRange? {
        ranges.first { projectedRange in
            projectedRange.isProtected &&
                NSLocationInRange(location, projectedRange.range)
        }
    }

    public func paragraphAttributesForInsertion(at location: Int) -> [NSAttributedString.Key: Any]? {
        if let range = paragraphRange(containingInsertionAt: location) {
            return Self.paragraphAttributes(entryID: range.entryID, blockID: range.blockID!)
        }

        return ranges.last(where: { $0.role == .paragraph }).flatMap { range in
            guard let blockID = range.blockID else {
                return nil
            }
            return Self.paragraphAttributes(entryID: range.entryID, blockID: blockID)
        }
    }

    public static func document(
        from attributedString: NSAttributedString,
        fallbackDocument: JournalDocument
    ) -> JournalDocument {
        let normalizedString = normalizedAttributedString(
            attributedString,
            fallbackDocument: fallbackDocument
        )
        var builders = fallbackDocument.entries.map { EntryBuilder(entry: $0) }
        var indexByEntryID = Dictionary(
            uniqueKeysWithValues: builders.enumerated().map { ($0.element.id, $0.offset) }
        )

        func builderIndex(for entryID: UUID, createdAt: Date) -> Int {
            if let index = indexByEntryID[entryID] {
                return index
            }

            let builder = EntryBuilder(id: entryID, createdAt: createdAt)
            builders.append(builder)
            let index = builders.index(before: builders.endIndex)
            indexByEntryID[entryID] = index
            return index
        }

        let fullRange = NSRange(location: 0, length: normalizedString.length)
        normalizedString.enumerateAttributes(in: fullRange) { attributes, range, _ in
            guard let entryID = attributes.uuidValue(for: .shiningEntryID) else {
                return
            }

            let createdAt = fallbackDocument.entries.first(where: { $0.id == entryID })?.createdAt ?? Date()
            let index = builderIndex(for: entryID, createdAt: createdAt)
            guard let role = attributes.roleValue else {
                return
            }

            switch role {
            case .paragraph:
                let text = (normalizedString.string as NSString).substring(with: range)
                guard !text.isSeparatorOnly else {
                    return
                }
                builders[index].appendParagraph(
                    text,
                    sourceBlockID: attributes.uuidValue(for: .shiningBlockID)
                )
            case .image:
                guard let image = Self.imageBlock(from: attributes) else {
                    return
                }
                builders[index].appendImage(image)
            case .timestampSeparator, .timestampBoundary, .spacer:
                return
            }
        }

        return JournalDocument(
            schemaVersion: fallbackDocument.schemaVersion,
            entries: builders.map(\.entry)
        )
    }

    public static func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    public static func paragraphAttributes(
        entryID: UUID,
        blockID: UUID
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: bodyParagraphStyle(),
            .shiningRole: JournalTextRole.paragraph.rawValue,
            .shiningEntryID: entryID.uuidString,
            .shiningBlockID: blockID.uuidString
        ]
    }

    public static func imageAttributes(
        block: JournalImageBlock,
        entryID: UUID
    ) -> [NSAttributedString.Key: Any] {
        [
            .paragraphStyle: bodyParagraphStyle(),
            .shiningRole: JournalTextRole.image.rawValue,
            .shiningEntryID: entryID.uuidString,
            .shiningBlockID: block.id.uuidString,
            .shiningImageAssetID: block.assetID,
            .shiningImageOriginalFilename: block.originalFilename,
            .shiningImagePixelWidth: block.pixelSize.width,
            .shiningImagePixelHeight: block.pixelSize.height
        ]
    }

    private static func appendBlocks(
        _ blocks: [JournalBlock],
        entryID: UUID,
        attachmentURL: (String) -> URL?,
        to result: NSMutableAttributedString,
        ranges: inout [JournalProjectedRange]
    ) {
        for blockIndex in blocks.indices {
            if blockIndex > 0 {
                _ = append(
                    "\n",
                    to: result,
                    attributes: paragraphSeparatorAttributes(entryID: entryID)
                )
            }

            switch blocks[blockIndex] {
            case let .paragraph(block):
                let range = append(
                    block.text,
                    to: result,
                    attributes: paragraphAttributes(entryID: entryID, blockID: block.id)
                )
                ranges.append(
                    JournalProjectedRange(
                        role: .paragraph,
                        entryID: entryID,
                        blockID: block.id,
                        range: range,
                        isProtected: false
                    )
                )
            case let .image(block):
                let attachment = NSTextAttachment()
                if let fileURL = attachmentURL(block.assetID),
                   let image = NSImage(contentsOf: fileURL) {
                    attachment.image = image
                    attachment.fileWrapper = try? FileWrapper(url: fileURL, options: .immediate)
                    attachment.bounds = NSRect(origin: .zero, size: image.size)
                }

                var attributes = imageAttributes(block: block, entryID: entryID)
                attributes[.attachment] = attachment
                let range = append(
                    NSAttributedString(attachment: attachment, attributes: attributes),
                    to: result
                )
                ranges.append(
                    JournalProjectedRange(
                        role: .image,
                        entryID: entryID,
                        blockID: block.id,
                        range: range,
                        isProtected: false
                    )
                )
            }
        }
    }

    private func paragraphRange(containingInsertionAt location: Int) -> JournalProjectedRange? {
        ranges.first { range in
            guard range.role == .paragraph else {
                return false
            }

            if range.range.length == 0 {
                return range.range.location == location
            }

            return location >= range.range.location &&
                location <= range.range.location + range.range.length
        }
    }

    private static func append(
        _ string: String,
        to result: NSMutableAttributedString,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSRange {
        let range = NSRange(location: result.length, length: string.utf16.count)
        result.append(NSAttributedString(string: string, attributes: attributes))
        return range
    }

    private static func append(
        _ attributedString: NSAttributedString,
        to result: NSMutableAttributedString
    ) -> NSRange {
        let range = NSRange(location: result.length, length: attributedString.length)
        result.append(attributedString)
        return range
    }

    private static func timestampAttributes(entryID: UUID) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: timestampParagraphStyle(),
            .shiningRole: JournalTextRole.timestampSeparator.rawValue,
            .shiningProtected: true,
            .shiningEntryID: entryID.uuidString
        ]
    }

    private static func timestampBoundaryAttributes(entryID: UUID) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: timestampParagraphStyle(),
            .shiningRole: JournalTextRole.timestampBoundary.rawValue,
            .shiningProtected: true,
            .shiningEntryID: entryID.uuidString
        ]
    }

    private static func spacerAttributes(entryID: UUID) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: bodyParagraphStyle(),
            .shiningRole: JournalTextRole.spacer.rawValue,
            .shiningEntryID: entryID.uuidString
        ]
    }

    private static func paragraphSeparatorAttributes(entryID: UUID) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: bodyParagraphStyle(),
            .shiningRole: JournalTextRole.paragraph.rawValue,
            .shiningEntryID: entryID.uuidString
        ]
    }

    private static func bodyParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 23
        style.maximumLineHeight = 23
        style.paragraphSpacing = 8
        style.lineBreakMode = .byWordWrapping
        return style
    }

    private static func timestampParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.minimumLineHeight = 14
        style.maximumLineHeight = 14
        style.paragraphSpacingBefore = 24
        style.paragraphSpacing = 16
        style.lineBreakMode = .byTruncatingTail
        return style
    }

    private static func imageBlock(from attributes: [NSAttributedString.Key: Any]) -> JournalImageBlock? {
        guard let blockID = attributes.uuidValue(for: .shiningBlockID),
              let assetID = attributes[.shiningImageAssetID] as? String else {
            return nil
        }

        let originalFilename = attributes[.shiningImageOriginalFilename] as? String ?? assetID
        let width = attributes.doubleValue(for: .shiningImagePixelWidth)
        let height = attributes.doubleValue(for: .shiningImagePixelHeight)

        return JournalImageBlock(
            id: blockID,
            assetID: assetID,
            originalFilename: originalFilename,
            pixelSize: JournalImageSize(width: width, height: height)
        )
    }

    private static func normalizedAttributedString(
        _ attributedString: NSAttributedString,
        fallbackDocument: JournalDocument
    ) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        guard mutable.length > 0 else {
            return mutable
        }

        let fallbackProjection = make(document: fallbackDocument) { _ in nil }
        let fullRange = NSRange(location: 0, length: mutable.length)
        var actualTimestampRanges: [NSRange] = []

        mutable.enumerateAttribute(.shiningRole, in: fullRange) { value, range, _ in
            guard let rawValue = value as? String,
                  JournalTextRole(rawValue: rawValue) == .timestampSeparator else {
                return
            }
            actualTimestampRanges.append(range)
        }

        for projectedRange in fallbackProjection.ranges where projectedRange.role == .paragraph {
            guard let blockID = projectedRange.blockID else {
                continue
            }

            let start = min(max(0, projectedRange.range.location), mutable.length)
            let end = actualTimestampRanges
                .map(\.location)
                .filter { $0 > start }
                .min() ?? mutable.length
            guard end > start else {
                continue
            }

            let attributes = paragraphAttributes(
                entryID: projectedRange.entryID,
                blockID: blockID
            )
            var rangesNeedingAttributes: [NSRange] = []
            mutable.enumerateAttribute(
                .shiningRole,
                in: NSRange(location: start, length: end - start)
            ) { value, range, _ in
                guard value == nil else {
                    return
                }
                rangesNeedingAttributes.append(range)
            }
            for range in rangesNeedingAttributes {
                mutable.addAttributes(attributes, range: range)
            }
        }

        return mutable
    }
}

private struct EntryBuilder {
    let id: UUID
    let createdAt: Date
    private var blocks: [JournalBlock] = []
    private var usedParagraphBlockIDs: Set<UUID> = []

    init(entry: JournalEntry) {
        self.id = entry.id
        self.createdAt = entry.createdAt
    }

    init(id: UUID, createdAt: Date) {
        self.id = id
        self.createdAt = createdAt
    }

    var entry: JournalEntry {
        let finalBlocks: [JournalBlock]
        if blocks.isEmpty {
            finalBlocks = [.paragraph(JournalParagraphBlock(text: ""))]
        } else {
            finalBlocks = blocks
        }
        return JournalEntry(id: id, createdAt: createdAt, blocks: finalBlocks)
    }

    mutating func appendParagraph(_ text: String, sourceBlockID: UUID?) {
        guard !text.isEmpty else {
            return
        }

        if case var .paragraph(lastParagraph) = blocks.last,
           lastParagraph.id == sourceBlockID {
            lastParagraph.text += text
            blocks[blocks.index(before: blocks.endIndex)] = .paragraph(lastParagraph)
            return
        }

        let blockID: UUID
        if let sourceBlockID, !usedParagraphBlockIDs.contains(sourceBlockID) {
            blockID = sourceBlockID
        } else {
            blockID = UUID()
        }
        usedParagraphBlockIDs.insert(blockID)
        blocks.append(.paragraph(JournalParagraphBlock(id: blockID, text: text)))
    }

    mutating func appendImage(_ image: JournalImageBlock) {
        blocks.append(.image(image))
    }
}

private extension Dictionary where Key == NSAttributedString.Key, Value == Any {
    var roleValue: JournalTextRole? {
        guard let rawValue = self[.shiningRole] as? String else {
            return nil
        }
        return JournalTextRole(rawValue: rawValue)
    }

    func uuidValue(for key: NSAttributedString.Key) -> UUID? {
        guard let string = self[key] as? String else {
            return nil
        }
        return UUID(uuidString: string)
    }

    func doubleValue(for key: NSAttributedString.Key) -> Double {
        if let double = self[key] as? Double {
            return double
        }
        if let number = self[key] as? NSNumber {
            return number.doubleValue
        }
        return 0
    }
}

private extension String {
    var isSeparatorOnly: Bool {
        !isEmpty && allSatisfy { $0 == "\n" || $0 == "\r" }
    }
}

private extension NSAttributedString {
    convenience init(
        attachment: NSTextAttachment,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let result = NSMutableAttributedString(attachment: attachment)
        result.addAttributes(
            attributes,
            range: NSRange(location: 0, length: result.length)
        )
        self.init(attributedString: result)
    }
}
