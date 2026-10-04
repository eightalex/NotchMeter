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
        replacePreviousInstances()
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

    /// Дві копії малювали б дві панелі одна на одній. Нова копія (Play у
    /// Xcode, `make run`, повторне відкриття) завжди замінює стару: так
    /// працює саме той застосунок, який щойно запустили.
    private func replacePreviousInstances() {
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != me else { return false }
            // Копія з Xcode — голий виконуваний файл без ідентифікатора застосунку.
            return app.bundleIdentifier == Bundle.main.bundleIdentifier && app.bundleIdentifier != nil
                || app.executableURL?.lastPathComponent == "NotchMeter"
        }
        for app in others {
            app.terminate()
            // Якщо стара копія не відповідає на звичайне завершення — примусово.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if !app.isTerminated { app.forceTerminate() }
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
