import AppKit
import Observation
import ServiceManagement

/// Те, що бачить і змінює вікно налаштувань. Налаштування вигляду панелі
/// живуть у `DisplayPreferences`, а тут — решта: частота оновлення й
/// автозапуск, у яких є побічні дії.
@MainActor
@Observable
final class SettingsModel {
    @ObservationIgnored private let usage: UsageStore
    @ObservationIgnored private let activity: ActivityStore
    @ObservationIgnored private let onPreview: (NotchState?) -> Void

    /// Який стан тримати біля вирізу, поки відкрите вікно налаштувань.
    var preview: NotchPreviewMode = .off {
        didSet {
            guard preview != oldValue else { return }
            onPreview(preview.state)
        }
    }

    /// Множник до базових інтервалів провайдерів: 1 — як задумано.
    var refreshMultiplier: Double {
        didSet {
            guard refreshMultiplier != oldValue else { return }
            Settings.refreshMultiplier = refreshMultiplier
            // Таймери провайдерів беруть інтервал під час запуску.
            usage.start()
        }
    }

    /// Зростає, коли під'єднують чи від'єднують монітор, — щоб список
    /// моніторів у налаштуваннях перебудувався.
    private(set) var screenRevision = 0
    @ObservationIgnored private var screenObserver: NSObjectProtocol?

    private(set) var launchAtLogin: Bool
    /// Користувач має підтвердити автозапуск у Системних параметрах.
    private(set) var loginNeedsApproval = false
    private(set) var loginError: String?

    static let refreshOptions: [(multiplier: Double, title: String)] = [
        (1, "Звичайна"),
        (2, "Удвічі рідше"),
        (5, "Уп'ятеро рідше"),
    ]

    init(usage: UsageStore, activity: ActivityStore, onPreview: @escaping (NotchState?) -> Void) {
        self.usage = usage
        self.activity = activity
        self.onPreview = onPreview
        refreshMultiplier = Settings.refreshMultiplier
        launchAtLogin = false
        syncLoginStatus()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenRevision += 1 }
        }
    }

    var lastUpdated: Date? { usage.lastUpdated }

    /// «Claude — раз на 2 хв, Codex — раз на 20 с» для обраної частоти.
    var refreshSummary: String {
        usage.refreshIntervals(multiplier: refreshMultiplier)
            .sorted { $0.tool.displayName < $1.tool.displayName }
            .map { "\($0.tool.displayName) — раз на \(Self.duration($0.interval))" }
            .joined(separator: ", ")
    }

    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let minutes = total / 60
        let seconds = total % 60
        switch (minutes, seconds) {
        case (0, _): return "\(seconds) с"
        case (_, 0): return "\(minutes) хв"
        default: return "\(minutes) хв \(seconds) с"
        }
    }

    func refreshNow() {
        usage.refreshAll(force: true)
        activity.scan()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = error.localizedDescription
        }
        syncLoginStatus()
    }

    /// Стан автозапуску може змінитися й поза застосунком — у Системних
    /// параметрах, тож перечитуємо його щоразу, коли відкривається вікно.
    func syncLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
    }
}

/// Перегляд вигляду просто з налаштувань, без наведення й кліків.
enum NotchPreviewMode: String, CaseIterable {
    case off
    case compact
    case expanded

    var title: String {
        switch self {
        case .off: return "Як звичайно"
        case .compact: return "Стан наведення"
        case .expanded: return "Панель"
        }
    }

    var state: NotchState? {
        switch self {
        case .off: return nil
        case .compact: return .compact
        case .expanded: return .expanded
        }
    }
}
