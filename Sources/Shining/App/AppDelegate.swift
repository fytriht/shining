import AppKit
import ShiningCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator: WindowCoordinator

    override init() {
        self.coordinator = WindowCoordinator(store: IdeaStore())
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppMenuBuilder.installMainMenu()
        SystemSelectionService.requestSyntheticEventAccessIfNeeded()
        coordinator.start()
        coordinator.openEditorAndInsertTimestamp(capturesSelection: false)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        coordinator.handleReopen(hasVisibleWindows: flag)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}
