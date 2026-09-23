import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let usage = UsageStore.makeDefault()
    private let activity = ActivityStore.makeDefault()
    private lazy var controller = NotchWindowController(usage: usage, activity: activity)
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        usage.start()
        activity.start()
        controller.start()
        statusItem = StatusItemController { [unowned self] in controller.makeMenu() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        usage.stop()
        activity.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
