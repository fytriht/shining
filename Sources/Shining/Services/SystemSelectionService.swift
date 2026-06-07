import ApplicationServices
import AppKit
import Carbon.HIToolbox

struct SystemSelectionService {
    private static let copyTimeout: TimeInterval = 0.45
    private static let pollingInterval: TimeInterval = 0.01
    private static var didOpenPrivacySettings = false

    static func requestSyntheticEventAccessIfNeeded() {
        _ = canPostSyntheticEvents()
    }

    func selectedText() -> String? {
        guard let targetApplication = NSWorkspace.shared.frontmostApplication,
              targetApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        let clearedChangeCount = pasteboard.changeCount
        defer {
            snapshot.restore(to: pasteboard)
        }

        guard postCopyShortcut(to: targetApplication) else {
            return nil
        }

        return waitForCopiedText(
            from: pasteboard,
            after: clearedChangeCount
        )
    }

    private static func canPostSyntheticEvents() -> Bool {
        if CGPreflightPostEventAccess() {
            return true
        }

        requestAccessibilityTrustPrompt()
        if CGRequestPostEventAccess() || CGPreflightPostEventAccess() {
            return true
        }

        openAccessibilityPrivacySettingsOnce()
        return false
    }

    private static func requestAccessibilityTrustPrompt() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static func openAccessibilityPrivacySettingsOnce() {
        guard !Self.didOpenPrivacySettings,
              let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
              ) else {
            return
        }

        Self.didOpenPrivacySettings = true
        NSWorkspace.shared.open(url)
    }

    private func postCopyShortcut(to application: NSRunningApplication) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_C),
            keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_C),
            keyDown: false
        ) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(application.processIdentifier)
        keyUp.postToPid(application.processIdentifier)
        return true
    }

    private func waitForCopiedText(
        from pasteboard: NSPasteboard,
        after changeCount: Int
    ) -> String? {
        let deadline = Date().addingTimeInterval(Self.copyTimeout)

        while Date() < deadline {
            if pasteboard.changeCount != changeCount,
               let text = pasteboard.string(forType: .string),
               !text.isEmpty {
                return text
            }

            Thread.sleep(forTimeInterval: Self.pollingInterval)
        }

        return nil
    }
}

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        self.items = pasteboard.pasteboardItems?.map { item in
            var storedItem: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    storedItem[type] = data
                }
            }
            return storedItem
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let restoredItems = items.compactMap { storedItem -> NSPasteboardItem? in
            guard !storedItem.isEmpty else {
                return nil
            }

            let item = NSPasteboardItem()
            for (type, data) in storedItem {
                item.setData(data, forType: type)
            }
            return item
        }

        if !restoredItems.isEmpty {
            _ = pasteboard.writeObjects(restoredItems)
        }
    }
}
