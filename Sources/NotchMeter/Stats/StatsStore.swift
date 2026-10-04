import AppKit
import Observation

/// Статистика в пам'яті та керування її збором. Записів — тисячі, тож
/// тримаємо їх усі й рахуємо зведення на льоту: так будь-який фільтр у
/// вікні спрацьовує миттєво.
@MainActor
@Observable
final class StatsStore {
    static let shared = StatsStore()

    private(set) var turns: [TurnRecord] = []
    private(set) var limits: [LimitSample] = []
    private(set) var isImporting = false
    /// 0…1, поки йде імпорт.
    private(set) var progress: Double = 0
    private(set) var lastImport: Date?
    private(set) var isAvailable = true

    @ObservationIgnored private let importer = StatsImporter()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pendingImport = false
    @ObservationIgnored private var lastLive: [String: LimitSample] = [:]

    /// Журнали активних сесій змінюються постійно; хвилини вистачає, щоб
    /// статистика була свіжою і не навантажувала диск.
    private static let importInterval: TimeInterval = 60

    private var preferences: StatsPreferences.Values { StatsPreferences.shared.values }

    private init() {}

    // MARK: - Життєвий цикл

    func start() {
        Task {
            isAvailable = await importer.isAvailable
            await reload()
            applyRecordingPreference()
        }
    }

    /// Вмикає чи вимикає збір відповідно до налаштувань.
    func applyRecordingPreference() {
        timer?.invalidate()
        timer = nil
        guard preferences.recording else { return }
        importNow()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.importInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.importNow() }
        }
        timer.tolerance = 10
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Імпорт

    func importNow() {
        guard preferences.recording else { return }
        guard !isImporting else {
            pendingImport = true
            return
        }
        isImporting = true
        progress = 0

        let options = StatsImporter.Options(storePrompts: preferences.storePrompts, keepSince: keepSince)
        Task {
            let changed = await importer.importChanged(options: options) { value in
                Task { @MainActor [weak self] in self?.progress = value }
            }
            if changed > 0 || turns.isEmpty { await reload() }
            lastImport = Date()
            isImporting = false
            if pendingImport {
                pendingImport = false
                importNow()
            }
        }
    }

    /// Перечитує всі журнали з нуля — після зміни того, що зберігається.
    func rebuild() {
        Task {
            await importer.forgetSources()
            importNow()
        }
    }

    func clearAll() {
        Task {
            await importer.clearAll()
            lastLive.removeAll()
            await reload()
        }
    }

    private var keepSince: Date? {
        preferences.retention.days.map { Date().addingTimeInterval(-Double($0) * 86400) }
    }

    private func reload() async {
        let snapshot = await importer.load()
        turns = snapshot.turns
        limits = snapshot.limits
    }

    // MARK: - Живі ліміти

    /// Пишемо новий вимір, лише коли щось змінилось або минуло пів години:
    /// інакше історія лімітів розросталася б щохвилини однаковими точками.
    func record(_ usage: ProviderUsage) {
        guard preferences.recording, preferences.recordLimits, usage.error == nil else { return }
        var fresh: [LimitSample] = []
        for window in usage.windows {
            let sample = LimitSample(
                tool: usage.tool, label: window.label, at: usage.capturedAt,
                percent: window.usedPercent, resetsAt: window.resetsAt
            )
            let key = "\(usage.tool.rawValue):\(window.label)"
            if let previous = lastLive[key],
               previous.percent == sample.percent,
               previous.resetsAt == sample.resetsAt,
               sample.at.timeIntervalSince(previous.at) < 30 * 60 {
                continue
            }
            lastLive[key] = sample
            fresh.append(sample)
        }
        guard !fresh.isEmpty else { return }
        limits.append(contentsOf: fresh)
        Task { await importer.recordLive(fresh) }
    }

    // MARK: - Сервіс

    var databaseURL: URL { StatsDatabase.defaultURL }

    var databaseSize: Int {
        let base = databaseURL.path
        return ["", "-wal", "-shm"].reduce(0) { total, suffix in
            let attributes = try? FileManager.default.attributesOfItem(atPath: base + suffix)
            return total + ((attributes?[.size] as? Int) ?? 0)
        }
    }

    func revealDatabase() {
        NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
    }

    var firstRecord: Date? { turns.first?.started }
}
