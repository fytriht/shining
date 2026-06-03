import Combine
import Foundation

public final class CaptureDraftStore: ObservableObject {
    @Published public var text: String {
        didSet {
            guard text != oldValue else {
                return
            }

            save()
        }
    }

    private let fileURL: URL

    public init(fileURL: URL = CaptureDraftStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    public static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return baseURL
            .appendingPathComponent("Shining", isDirectory: true)
            .appendingPathComponent("capture-draft.txt", isDirectory: false)
    }

    public func clear() {
        text = ""
        removeDraftFile()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            assertionFailure("Failed to save capture draft: \(error)")
        }
    }

    private func removeDraftFile() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            assertionFailure("Failed to remove capture draft: \(error)")
        }
    }
}
