import AppKit
import Combine
import Foundation

public final class CaptureDraftStore: ObservableObject {
    @Published public private(set) var document: NSAttributedString
    @Published public private(set) var revision = 0

    private let fileURL: URL
    private var pendingSave: DispatchWorkItem?

    public init(fileURL: URL = CaptureDraftStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.document = RichTextDocument.load(from: fileURL)
    }

    public var hasContent: Bool {
        RichTextDocument.hasMeaningfulContent(document)
    }

    public static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return baseURL
            .appendingPathComponent("Shining", isDirectory: true)
            .appendingPathComponent("capture-draft.rtfd", isDirectory: true)
    }

    public func replaceDocument(_ document: NSAttributedString) {
        self.document = RichTextDocument.copy(document)
        scheduleSave()
    }

    public func clear() {
        pendingSave?.cancel()
        pendingSave = nil
        document = RichTextDocument.empty()
        revision += 1
        removeDraftFile()
    }

    public func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil

        guard hasContent else {
            removeDraftFile()
            return
        }

        do {
            try RichTextDocument.save(document, to: fileURL)
        } catch {
            assertionFailure("Failed to save capture draft: \(error)")
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        pendingSave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
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
