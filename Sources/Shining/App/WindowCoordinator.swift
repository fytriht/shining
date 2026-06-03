import AppKit
import ShiningCore
import SwiftUI

final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let store: IdeaStore
    private let draftStore: CaptureDraftStore
    private let captureFocusController = CaptureFocusController()
    private var hotKeyService: HotKeyService?
    private var capturePanel: CapturePanel?
    private var mainWindow: NSWindow?
    private var dockIconIsVisible = false

    init(store: IdeaStore, draftStore: CaptureDraftStore = CaptureDraftStore()) {
        self.store = store
        self.draftStore = draftStore
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
        if let capturePanel {
            NSApp.activate(ignoringOtherApps: true)
            capturePanel.centerOnCurrentScreen()
            capturePanel.makeKeyAndOrderFront(nil)
            captureFocusController.requestFocus()
            return
        }

        let view = CaptureView(
            draftStore: draftStore,
            focusController: captureFocusController
        ) { [weak self] capture in
            self?.saveCapture(capture)
        }

        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "闪念"
        panel.contentViewController = NSHostingController(rootView: view)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace]
        panel.minSize = NSSize(width: 400, height: 300)
        panel.maxSize = NSSize(width: 400, height: 300)
        panel.delegate = self
        panel.centerOnCurrentScreen()

        capturePanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        captureFocusController.requestFocus()
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
            mainWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.centerOnCurrentScreen()
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === mainWindow {
            sender.orderOut(nil)
            return false
        }

        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        if window === capturePanel {
            capturePanel = nil
        }
    }

    private func saveCapture(_ capture: String) {
        guard store.appendCapture(capture) else {
            return
        }

        draftStore.clear()
        ensureDockIconVisible()
        closeCaptureWindow()
    }

    private func closeCaptureWindow() {
        capturePanel?.delegate = nil
        capturePanel?.orderOut(nil)
        capturePanel?.close()
        capturePanel = nil
    }

    private func ensureDockIconVisible() {
        guard !dockIconIsVisible else {
            return
        }

        NSApp.setActivationPolicy(.regular)
        dockIconIsVisible = true
    }

}

private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override func cancelOperation(_ sender: Any?) {
        // Do not close the capture panel on Escape.
    }
}

private extension NSWindow {
    func centerOnCurrentScreen() {
        let screen = NSScreen.screens.first { screen in
            screen.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main

        guard let visibleFrame = screen?.visibleFrame else {
            center()
            return
        }

        let origin = NSPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.midY - frame.height / 2
        )
        setFrameOrigin(origin)
    }
}
