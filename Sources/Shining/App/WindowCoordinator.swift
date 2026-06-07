import AppKit
import ShiningCore
import SwiftUI

final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let store: IdeaStore
    private let editorFocusController = EditorFocusController()
    private var hotKeyService: HotKeyService?
    private var mainWindow: NSWindow?

    init(store: IdeaStore) {
        self.store = store
        super.init()
    }

    func start() {
        let hotKeyService = HotKeyService { [weak self] in
            self?.showEditorAndInsertTimestamp()
        }
        hotKeyService.register()
        self.hotKeyService = hotKeyService
    }

    func stop() {
        hotKeyService?.unregister()
        store.saveNow()
    }

    func showEditorAndInsertTimestamp() {
        let cursorRange = store.insertTimestamp()
        showMainWindow(focusRange: cursorRange)
    }

    func showMainWindow(focusRange: NSRange? = nil) {
        if mainWindow == nil {
            let view = MainEditorView(
                store: store,
                focusController: editorFocusController
            )
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
        editorFocusController.requestFocus(selectedRange: focusRange)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === mainWindow {
            sender.orderOut(nil)
            return false
        }

        return true
    }
}

private extension NSWindow {
    func centerOnCurrentScreen(contentSize: NSSize? = nil) {
        let screen = NSScreen.screens.first { screen in
            screen.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main

        guard let visibleFrame = screen?.visibleFrame else {
            center()
            return
        }

        let frameSize = centeredFrameSize(contentSize: contentSize)
        let origin = NSPoint(
            x: visibleFrame.midX - frameSize.width / 2,
            y: visibleFrame.midY - frameSize.height / 2
        )
        setFrame(NSRect(origin: origin, size: frameSize), display: false)
    }

    private func centeredFrameSize(contentSize: NSSize?) -> NSSize {
        guard let contentSize else {
            return frame.size
        }

        return frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
    }
}
