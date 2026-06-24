import AppKit
import Combine
import ShiningCore
import SwiftUI

final class WindowCoordinator: NSObject, NSWindowDelegate {
    private static let mainWindowFrameAutosaveName = NSWindow.FrameAutosaveName(
        "\(ShiningApp.bundleIdentifier).main-window"
    )

    private let store: IdeaStore
    private let systemSelectionService: SystemSelectionService
    private let editorFocusController = EditorFocusController()
    private var hotKeyService: HotKeyService?
    private var mainWindow: NSWindow?
    private var dockBadgeCancellable: AnyCancellable?

    init(
        store: IdeaStore,
        systemSelectionService: SystemSelectionService = SystemSelectionService()
    ) {
        self.store = store
        self.systemSelectionService = systemSelectionService
        super.init()
    }

    func start() {
        startDockBadgeUpdates()

        let hotKeyService = HotKeyService { [weak self] in
            self?.openEditorAndInsertTimestamp(capturesSelection: true)
        }
        hotKeyService.register()
        self.hotKeyService = hotKeyService
    }

    func stop() {
        dockBadgeCancellable?.cancel()
        dockBadgeCancellable = nil
        hotKeyService?.unregister()
        saveMainWindowFrame()
        store.cleanUpDocument(saveImmediately: false)
        store.saveNow()
    }

    func openEditorAndInsertTimestamp(capturesSelection: Bool) {
        guard capturesSelection, !NSApp.isActive else {
            insertTimestampAndShowEditor(selectedContent: nil)
            return
        }

        openEditorAndInsertTimestampWithDelayedSelectionCapture()
    }

    func handleReopen(hasVisibleWindows: Bool) {
        if shouldInsertTimestampOnReopen(hasVisibleWindows: hasVisibleWindows) {
            openEditorAndInsertTimestamp(capturesSelection: false)
            return
        }

        showMainWindow()
    }

    private func openEditorAndInsertTimestampWithDelayedSelectionCapture() {
        let delayedSelectionCapture = DelayedSelectionCapture()
        systemSelectionService.selectedContent { [weak self, delayedSelectionCapture] selectedContent in
            delayedSelectionCapture.selectedContent = selectedContent
            delayedSelectionCapture.didReceiveSelectedContent = true

            guard let pendingSelectionInsertion =
                delayedSelectionCapture.pendingSelectionInsertion else {
                return
            }

            self?.insertDelayedSelection(
                selectedContent,
                for: pendingSelectionInsertion
            )
        }

        let insertion = store.insertTimestampForDelayedSelection()
        delayedSelectionCapture.pendingSelectionInsertion = insertion.pendingSelectionInsertion
        if delayedSelectionCapture.didReceiveSelectedContent {
            insertDelayedSelection(
                delayedSelectionCapture.selectedContent,
                for: insertion.pendingSelectionInsertion
            )
        }
        showMainWindow(focusRange: insertion.cursorRange, cleanUpBeforeShowing: false)
    }

    private func insertTimestampAndShowEditor(selectedContent: NSAttributedString?) {
        let cursorRange = store.insertTimestamp(selectedContent: selectedContent)
        showMainWindow(focusRange: cursorRange, cleanUpBeforeShowing: false)
    }

    private func shouldInsertTimestampOnReopen(hasVisibleWindows: Bool) -> Bool {
        guard hasVisibleWindows, let mainWindow else {
            return true
        }

        return !mainWindow.isVisible || mainWindow.isMiniaturized
    }

    private func insertDelayedSelection(
        _ selectedContent: NSAttributedString?,
        for pendingSelectionInsertion: IdeaStore.PendingSelectionInsertion
    ) {
        guard let selectedRange = store.insertSelectedContent(
            selectedContent,
            for: pendingSelectionInsertion
        ) else {
            return
        }

        editorFocusController.requestFocus(selectedRange: selectedRange)
    }

    func showMainWindow(
        focusRange: NSRange? = nil,
        cleanUpBeforeShowing: Bool = true
    ) {
        if cleanUpBeforeShowing {
            store.cleanUpDocument(saveImmediately: true)
        }

        let window = mainWindow ?? makeMainWindow()

        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let hostingController = NSHostingController(rootView: view)
        configureTransparentHostingView(hostingController.view)

        window.title = ShiningApp.name
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 360)
        window.delegate = self
        configureLightweightChrome(for: window)
        configureAlwaysOnTopBehavior(for: window)

        if !window.setFrameUsingName(Self.mainWindowFrameAutosaveName) {
            window.centerOnCurrentScreen()
        }
        window.setFrameAutosaveName(Self.mainWindowFrameAutosaveName)

        mainWindow = window
        return window
    }

    private func configureLightweightChrome(for window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
    }

    private func configureTransparentHostingView(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
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

    private func startDockBadgeUpdates() {
        dockBadgeCancellable = store.$savedTimestampBlockCount
            .receive(on: RunLoop.main)
            .sink { count in
                NSApp.dockTile.badgeLabel = count > 0 ? " " : nil
            }
    }
}

private final class DelayedSelectionCapture {
    var pendingSelectionInsertion: IdeaStore.PendingSelectionInsertion?
    var selectedContent: NSAttributedString?
    var didReceiveSelectedContent = false
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
