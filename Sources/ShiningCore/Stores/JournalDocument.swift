import Foundation

public struct JournalDocument: Codable, Equatable {
    public var schemaVersion: Int
    public var entries: [JournalEntry]

    public init(schemaVersion: Int = 1, entries: [JournalEntry] = []) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    public var nonEmptyEntryCount: Int {
        entries.filter(\.hasMeaningfulContent).count
    }

    public func cleaned() -> JournalDocument {
        JournalDocument(
            schemaVersion: schemaVersion,
            entries: entries.filter(\.hasMeaningfulContent)
        )
    }
}

public struct JournalEntry: Codable, Equatable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var blocks: [JournalBlock]

    public init(
        id: UUID = UUID(),
        createdAt: Date,
        blocks: [JournalBlock]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.blocks = blocks
    }

    public var hasMeaningfulContent: Bool {
        blocks.contains(where: \.hasMeaningfulContent)
    }
}

public enum JournalBlock: Codable, Equatable, Identifiable {
    case paragraph(JournalParagraphBlock)
    case image(JournalImageBlock)

    public var id: UUID {
        switch self {
        case let .paragraph(block):
            block.id
        case let .image(block):
            block.id
        }
    }

    public var hasMeaningfulContent: Bool {
        switch self {
        case let .paragraph(block):
            !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image:
            true
        }
    }

    private enum BlockType: String, Codable {
        case paragraph
        case image
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case text
        case assetID
        case originalFilename
        case pixelSize
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(BlockType.self, forKey: .type)

        switch type {
        case .paragraph:
            self = .paragraph(
                JournalParagraphBlock(
                    id: try container.decode(UUID.self, forKey: .id),
                    text: try container.decode(String.self, forKey: .text)
                )
            )
        case .image:
            self = .image(
                JournalImageBlock(
                    id: try container.decode(UUID.self, forKey: .id),
                    assetID: try container.decode(String.self, forKey: .assetID),
                    originalFilename: try container.decode(String.self, forKey: .originalFilename),
                    pixelSize: try container.decode(JournalImageSize.self, forKey: .pixelSize)
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .paragraph(block):
            try container.encode(BlockType.paragraph, forKey: .type)
            try container.encode(block.id, forKey: .id)
            try container.encode(block.text, forKey: .text)
        case let .image(block):
            try container.encode(BlockType.image, forKey: .type)
            try container.encode(block.id, forKey: .id)
            try container.encode(block.assetID, forKey: .assetID)
            try container.encode(block.originalFilename, forKey: .originalFilename)
            try container.encode(block.pixelSize, forKey: .pixelSize)
        }
    }
}

public struct JournalParagraphBlock: Codable, Equatable, Identifiable {
    public var id: UUID
    public var text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

public struct JournalImageBlock: Codable, Equatable, Identifiable {
    public var id: UUID
    public var assetID: String
    public var originalFilename: String
    public var pixelSize: JournalImageSize

    public init(
        id: UUID = UUID(),
        assetID: String,
        originalFilename: String,
        pixelSize: JournalImageSize
    ) {
        self.id = id
        self.assetID = assetID
        self.originalFilename = originalFilename
        self.pixelSize = pixelSize
    }
}

public struct JournalImageSize: Codable, Equatable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct JournalTextSelection: Equatable {
    public var entryID: UUID
    public var blockID: UUID
    public var range: NSRange

    public init(entryID: UUID, blockID: UUID, range: NSRange) {
        self.entryID = entryID
        self.blockID = blockID
        self.range = range
    }

    public static func == (lhs: JournalTextSelection, rhs: JournalTextSelection) -> Bool {
        lhs.entryID == rhs.entryID &&
            lhs.blockID == rhs.blockID &&
            lhs.range.location == rhs.range.location &&
            lhs.range.length == rhs.range.length
    }
}
