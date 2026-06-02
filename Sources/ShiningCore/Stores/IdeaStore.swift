import Combine
import Foundation

public final class IdeaStore: ObservableObject {
    @Published public var text: String

    private let fileURL: URL
    private let timestampFormatter: DateFormatter

    public init(fileURL: URL = IdeaStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.timestampFormatter = IdeaStore.makeTimestampFormatter()
        self.text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    public var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return baseURL
            .appendingPathComponent("Shining", isDirectory: true)
            .appendingPathComponent("ideas.md", isDirectory: false)
    }

    public func appendCapture(_ capture: String, date: Date = Date()) -> Bool {
        let timestamp = timestampFormatter.string(from: date)
        let updatedText = IdeaTextAppender.append(
            existing: text,
            capture: capture,
            timestamp: timestamp
        )

        guard updatedText != text else {
            return false
        }

        text = updatedText
        save()
        return true
    }

    public func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            assertionFailure("Failed to save ideas: \(error)")
        }
    }

    private static func makeTimestampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }
}
