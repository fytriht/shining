import AppKit
import ShiningCore
import SwiftUI

final class WindowCoordinator: NSObject, NSWindowDelegate {
    private static let mainWindowFrameAutosaveName = NSWindow.FrameAutosaveName(
        "\(ShiningApp.bundleIdentifier).main-window"
    )

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
        saveMainWindowFrame()
        store.cleanUpDocument(saveImmediately: false)
        store.saveNow()
    }

    func showEditorAndInsertTimestamp() {
        let cursorRange = store.insertTimestamp()
        showMainWindow(focusRange: cursorRange, cleanUpBeforeShowing: false)
    }

    func showMainWindow(
        focusRange: NSRange? = nil,
        cleanUpBeforeShowing: Bool = true
    ) {
        if cleanUpBeforeShowing {
            store.cleanUpDocument(saveImmediately: true)
        }

        let window = mainWindow ?? makeMainWindow()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        editorFocusController.requestFocus(selectedRange: focusRange)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === mainWindow {
            saveMainWindowFrame()
            store.cleanUpDocument(saveImmediately: true)
            sender.orderOut(nil)
            return false
        }

        return true
    }

    private func makeMainWindow() -> NSWindow {
        let view = MainEditorView(
            store: store,
            focusController: editorFocusController
        )
        let window = EscClosableWindow(
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
        configureAlwaysOnTopBehavior(for: window)

        if !window.setFrameUsingName(Self.mainWindowFrameAutosaveName) {
            window.centerOnCurrentScreen()
        }
        window.setFrameAutosaveName(Self.mainWindowFrameAutosaveName)

        mainWindow = window
        return window
    }

    private func configureAlwaysOnTopBehavior(for window: NSWindow) {
        window.level = .floating

        var collectionBehavior = window.collectionBehavior
        collectionBehavior.insert(.moveToActiveSpace)
        collectionBehavior.insert(.fullScreenAuxiliary)
        window.collectionBehavior = collectionBehavior
    }

    private func saveMainWindowFrame() {
        mainWindow?.saveFrame(usingName: Self.mainWindowFrameAutosaveName)
    }
}

private final class EscClosableWindow: NSWindow {
    private static let escapeKeyCode: UInt16 = 53

    override func sendEvent(_ event: NSEvent) {
        if shouldPerformClose(for: event) {
            performClose(nil)
            return
        }

        super.sendEvent(event)
    }

    private func shouldPerformClose(for event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              attachedSheet == nil,
              NSApp.modalWindow == nil else {
            return false
        }

        let closeModifiers: NSEvent.ModifierFlags = [
            .command,
            .control,
            .option,
            .shift
        ]
        guard event.modifierFlags.intersection(closeModifiers).isEmpty else {
            return false
        }

        return event.keyCode == Self.escapeKeyCode ||
            event.charactersIgnoringModifiers == "\u{1B}"
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
