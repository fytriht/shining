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

    func selectedText(completion: @escaping (String?) -> Void) {
        guard let targetApplication = NSWorkspace.shared.frontmostApplication,
              targetApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            completion(nil)
            return
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let originalChangeCount = pasteboard.changeCount

        guard postCopyShortcut(to: targetApplication) else {
            completion(nil)
            return
        }

        PasteboardTextPoller(
            pasteboard: pasteboard,
            snapshot: snapshot,
            changeCount: originalChangeCount,
            timeout: Self.copyTimeout,
            interval: Self.pollingInterval,
            completion: completion
        ).start()
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

}

private struct PasteboardSnapshot {
    private typealias StoredItem = [(type: NSPasteboard.PasteboardType, data: Data)]

    private let items: [StoredItem]

    init(pasteboard: NSPasteboard) {
        self.items = pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { data in
                    (type: type, data: data)
                }
            }
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let restoredItems = items.compactMap { storedItem -> NSPasteboardItem? in
            guard !storedItem.isEmpty else {
                return nil
            }

            let item = NSPasteboardItem()
            for representation in storedItem {
                item.setData(representation.data, forType: representation.type)
            }
            return item
        }

        if !restoredItems.isEmpty {
            _ = pasteboard.writeObjects(restoredItems)
        }
    }
}

private final class PasteboardTextPoller {
    private let pasteboard: NSPasteboard
    private let snapshot: PasteboardSnapshot
    private let changeCount: Int
    private let deadline: Date
    private let interval: TimeInterval
    private let completion: (String?) -> Void
    private var timer: Timer?
    private var retainedSelf: PasteboardTextPoller?

    init(
        pasteboard: NSPasteboard,
        snapshot: PasteboardSnapshot,
        changeCount: Int,
        timeout: TimeInterval,
        interval: TimeInterval,
        completion: @escaping (String?) -> Void
    ) {
        self.pasteboard = pasteboard
        self.snapshot = snapshot
        self.changeCount = changeCount
        self.deadline = Date().addingTimeInterval(timeout)
        self.interval = interval
        self.completion = completion
    }

    func start() {
        retainedSelf = self
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    private func poll() {
        if pasteboard.changeCount != changeCount {
            let text = pasteboard.string(forType: .string)
            finish(text?.isEmpty == false ? text : nil, restorePasteboard: true)
            return
        }

        if Date() >= deadline {
            finish(nil, restorePasteboard: false)
        }
    }

    private func finish(_ text: String?, restorePasteboard: Bool) {
        timer?.invalidate()
        timer = nil
        if restorePasteboard {
            snapshot.restore(to: pasteboard)
        }

        let completion = self.completion
        retainedSelf = nil
        completion(text)
    }
}
