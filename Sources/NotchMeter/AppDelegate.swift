import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let usage = UsageStore.makeDefault()
    private let activity = ActivityStore.makeDefault()
    private lazy var controller = NotchWindowController(usage: usage, activity: activity)
    private lazy var settings = SettingsWindowController(usage: usage, activity: activity) { [unowned self] state in
        controller.pin(state)
    }
    private lazy var statsWindow = StatsWindowController { [unowned self] in settings.show(tab: .stats) }
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        usage.onUpdate = { StatsStore.shared.record($0) }
        usage.start()
        activity.start()
        StatsStore.shared.start()
        settings.onOpenStats = { [unowned self] in statsWindow.show() }
        controller.onOpenSettings = { [unowned self] in settings.show() }
        controller.onOpenStats = { [unowned self] in statsWindow.show() }
        controller.start()
        statusItem = StatusItemController { [unowned self] in controller.makeMenu() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        usage.stop()
        activity.stop()
        StatsStore.shared.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
