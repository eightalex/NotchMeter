import Foundation
import Observation

/// Що саме показувати при наведенні на виріз і в розгорнутій панелі.
/// Спостережувана: панель перемальовується, щойно щось змінено в налаштуваннях.
@MainActor
@Observable
final class ContentPreferences {
    static let shared = ContentPreferences()

    struct Values: Codable, Equatable {
        // MARK: При наведенні

        var hoverLabel: AgentLabelStyle = .logo
        var hoverShowsGauge = true
        var hoverShowsPercent = true
        var hoverPercentMode: PercentMode = .used
        var hoverShowsWindowTag = true
        var hoverShowsResetTime = false
        var hoverGaugeColoring: GaugeColoring = .thresholds
        var hoverShowsActivity = true
        var hoverShowsBadge = true
        /// Відступ вмісту від зовнішнього краю крила, pt.
        var hoverEdgePadding: Double = 10

        // MARK: Панель — ліміти

        var panelShowsCodex = true
        var panelShowsClaude = true
        var panelShowsPlan = true
        var panelShowsProviderLogo = true
        var panelShowsFiveHour = true
        var panelShowsWeek = true
        var panelShowsOpusWeek = true
        var panelShowsAppsWeek = true
        var panelShowsGauge = true
        var panelGaugeWidth: Double = 96
        var panelPercentMode: PercentMode = .used
        var panelResetFormat: ResetFormat = .relative
        var panelGaugeColoring: GaugeColoring = .thresholds
        var panelShowsStale = true
        var panelShowsErrors = true

        // MARK: Панель — сесії

        var panelShowsSessions = true
        var panelIncludesIdleSessions = false
        var panelMaxSessions = 6
        var panelSessionUsesLogo = true
        var panelSessionShowsTitle = true
        var panelSessionShowsDirectory = true
        var panelSessionShowsState = true
        var panelSessionShowsElapsed = true
        var panelSessionShowsSteps = true
        var panelShowsUpdatedAt = true

        static let defaults = Values()

        init() {}

        /// Поля, яких у збереженому ще не було, беруть типові значення —
        /// нові налаштування в наступних версіях не скидатимуть старі.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let base = Values()
            func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
                (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
            }
            hoverLabel = read(.hoverLabel, base.hoverLabel)
            hoverShowsGauge = read(.hoverShowsGauge, base.hoverShowsGauge)
            hoverShowsPercent = read(.hoverShowsPercent, base.hoverShowsPercent)
            hoverPercentMode = read(.hoverPercentMode, base.hoverPercentMode)
            hoverShowsWindowTag = read(.hoverShowsWindowTag, base.hoverShowsWindowTag)
            hoverShowsResetTime = read(.hoverShowsResetTime, base.hoverShowsResetTime)
            hoverGaugeColoring = read(.hoverGaugeColoring, base.hoverGaugeColoring)
            hoverShowsActivity = read(.hoverShowsActivity, base.hoverShowsActivity)
            hoverShowsBadge = read(.hoverShowsBadge, base.hoverShowsBadge)
            hoverEdgePadding = read(.hoverEdgePadding, base.hoverEdgePadding)
            panelShowsCodex = read(.panelShowsCodex, base.panelShowsCodex)
            panelShowsClaude = read(.panelShowsClaude, base.panelShowsClaude)
            panelShowsPlan = read(.panelShowsPlan, base.panelShowsPlan)
            panelShowsProviderLogo = read(.panelShowsProviderLogo, base.panelShowsProviderLogo)
            panelShowsFiveHour = read(.panelShowsFiveHour, base.panelShowsFiveHour)
            panelShowsWeek = read(.panelShowsWeek, base.panelShowsWeek)
            panelShowsOpusWeek = read(.panelShowsOpusWeek, base.panelShowsOpusWeek)
            panelShowsAppsWeek = read(.panelShowsAppsWeek, base.panelShowsAppsWeek)
            panelShowsGauge = read(.panelShowsGauge, base.panelShowsGauge)
            panelGaugeWidth = read(.panelGaugeWidth, base.panelGaugeWidth)
            panelPercentMode = read(.panelPercentMode, base.panelPercentMode)
            panelResetFormat = read(.panelResetFormat, base.panelResetFormat)
            panelGaugeColoring = read(.panelGaugeColoring, base.panelGaugeColoring)
            panelShowsStale = read(.panelShowsStale, base.panelShowsStale)
            panelShowsErrors = read(.panelShowsErrors, base.panelShowsErrors)
            panelShowsSessions = read(.panelShowsSessions, base.panelShowsSessions)
            panelIncludesIdleSessions = read(.panelIncludesIdleSessions, base.panelIncludesIdleSessions)
            panelMaxSessions = read(.panelMaxSessions, base.panelMaxSessions)
            panelSessionUsesLogo = read(.panelSessionUsesLogo, base.panelSessionUsesLogo)
            panelSessionShowsTitle = read(.panelSessionShowsTitle, base.panelSessionShowsTitle)
            panelSessionShowsDirectory = read(.panelSessionShowsDirectory, base.panelSessionShowsDirectory)
            panelSessionShowsState = read(.panelSessionShowsState, base.panelSessionShowsState)
            panelSessionShowsElapsed = read(.panelSessionShowsElapsed, base.panelSessionShowsElapsed)
            panelSessionShowsSteps = read(.panelSessionShowsSteps, base.panelSessionShowsSteps)
            panelShowsUpdatedAt = read(.panelShowsUpdatedAt, base.panelShowsUpdatedAt)
        }

        /// Чи показувати в панелі вікно такого виду.
        func panelShows(_ kind: LimitWindow.Kind) -> Bool {
            switch kind {
            case .fiveHour: return panelShowsFiveHour
            case .week: return panelShowsWeek
            case .opusWeek: return panelShowsOpusWeek
            case .appsWeek: return panelShowsAppsWeek
            case .other: return true
            }
        }

        func panelShows(_ tool: Tool) -> Bool {
            switch tool {
            case .codex: return panelShowsCodex
            case .claude: return panelShowsClaude
            }
        }
    }

    private static let key = "contentPreferences"

    var values: Values {
        didSet {
            guard values != oldValue, let data = try? JSONEncoder().encode(values) else { return }
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    var isDefault: Bool { values == .defaults }

    func reset() {
        values = .defaults
    }

    private init() {
        values = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Values.self, from: $0) } ?? .defaults
        migrateToLogos()
    }

    /// Логотипи стали типовими вже після того, як налаштування встигли
    /// зберегтися з літерами CX/CC. Перемикаємо один раз — і лише ті місця,
    /// де лишалось старе типове значення, а не обране вручну.
    private func migrateToLogos() {
        let flag = "contentPreferencesLogosByDefault"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        var migrated = values
        if migrated.hoverLabel == .short { migrated.hoverLabel = .logo }
        migrated.panelShowsProviderLogo = true
        migrated.panelSessionUsesLogo = true
        values = migrated
    }
}

/// Як підписати агента біля вирізу.
enum AgentLabelStyle: String, Codable, CaseIterable {
    case short
    case full
    case logo
    case logoAndShort
    case hidden

    var title: String {
        switch self {
        case .short: return "Коротко (CX, CC)"
        case .full: return "Повністю (Codex, Claude)"
        case .logo: return "Логотип"
        case .logoAndShort: return "Логотип і CX, CC"
        case .hidden: return "Без назви"
        }
    }
}

/// Скільки ліміту витрачено чи скільки ще лишилось.
enum PercentMode: String, Codable, CaseIterable {
    case used
    case remaining

    var title: String {
        switch self {
        case .used: return "Використано"
        case .remaining: return "Залишок"
        }
    }

    /// Значення для показу; шкала заповнюється тим самим числом.
    func value(fromUsed used: Double) -> Double {
        switch self {
        case .used: return used
        case .remaining: return max(0, 100 - used)
        }
    }
}

/// Колір шкали: за заповненням (зелений → жовтий → червоний) або фірмовий
/// колір агента.
enum GaugeColoring: String, Codable, CaseIterable {
    case thresholds
    case accent

    var title: String {
        switch self {
        case .thresholds: return "За заповненням"
        case .accent: return "Колір агента"
        }
    }
}

/// Як показувати момент скидання ліміту в панелі.
enum ResetFormat: String, Codable, CaseIterable {
    case relative
    case absolute
    case both
    case hidden

    var title: String {
        switch self {
        case .relative: return "Скільки лишилось"
        case .absolute: return "Точний час"
        case .both: return "Обидва"
        case .hidden: return "Не показувати"
        }
    }
}
