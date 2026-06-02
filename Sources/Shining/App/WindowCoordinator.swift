import AppKit
import ShiningCore
import SwiftUI

final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let store: IdeaStore
    private var hotKeyService: HotKeyService?
    private var captureWindow: NSWindow?
    private var mainWindow: NSWindow?
    private var dockIconIsVisible = false

    init(store: IdeaStore) {
        self.store = store
        super.init()
    }

    func start() {
        let hotKeyService = HotKeyService { [weak self] in
            self?.showCaptureWindow()
        }
        hotKeyService.register()
        self.hotKeyService = hotKeyService
    }

    func stop() {
        hotKeyService?.unregister()
        store.save()
    }

    func showCaptureWindow() {
        if let captureWindow {
            NSApp.activate(ignoringOtherApps: true)
            captureWindow.makeKeyAndOrderFront(nil)
            return
        }

        let view = CaptureView { [weak self] capture in
            self?.saveCapture(capture)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "闪念"
        window.contentViewController = NSHostingController(rootView: view)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 300)
        window.maxSize = NSSize(width: 400, height: 300)
        window.delegate = self
        window.center()

        captureWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func showMainWindow() {
        ensureDockIconVisible()

        if mainWindow == nil {
            let view = MainEditorView(store: store)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = ShiningApp.name
            window.contentViewController = NSHostingController(rootView: view)
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 520, height: 360)
            window.delegate = self
            window.center()
            mainWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === mainWindow {
            if store.hasContent, !confirmMainWindowHide() {
                return false
            }

            sender.orderOut(nil)
            return false
        }

        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        if window === captureWindow {
            captureWindow = nil
        }
    }

    private func saveCapture(_ capture: String) {
        guard store.appendCapture(capture) else {
            return
        }

        ensureDockIconVisible()
        closeCaptureWindow()
    }

    private func closeCaptureWindow() {
        captureWindow?.delegate = nil
        captureWindow?.orderOut(nil)
        captureWindow?.close()
        captureWindow = nil
    }

    private func ensureDockIconVisible() {
        guard !dockIconIsVisible else {
            return
        }

        NSApp.setActivationPolicy(.regular)
        dockIconIsVisible = true
    }

    private func confirmMainWindowHide() -> Bool {
        let alert = NSAlert()
        alert.messageText = "隐藏 Shining？"
        alert.informativeText = "窗口会隐藏，内容仍会保存在本机。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "隐藏")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
