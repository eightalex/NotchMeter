import Foundation
import Observation

/// Налаштування збору й показу статистики. Вікно статистики читає їх
/// напряму, тож будь-яка зміна в налаштуваннях одразу видна у вікні, а
/// перемикачі у вікні зберігаються сюди ж.
@MainActor
@Observable
final class StatsPreferences {
    static let shared = StatsPreferences()

    struct Values: Codable, Equatable {
        // MARK: Запис

        var recording = true
        var recordLimits = true
        var storePrompts = true
        var retention: StatsRetention = .forever

        // MARK: Вікно статистики

        var period: StatsPeriod = .week
        var agentFilter: AgentFilter = .all
        var metric: StatsMetric = .tokens
        var grouping: StatsGrouping = .agent
        var chartStyle: StatsChartStyle = .bars
        var bucket: StatsBucketChoice = .automatic
        var includeSubagents = true
        var numberStyle: StatsNumberStyle = .compact
        var weekStartsMonday = true

        // MARK: Які токени рахувати

        var tokensInput = true
        var tokensOutput = true
        var tokensCacheWrite = true
        var tokensCacheRead = false

        // MARK: Розділи

        var showSummary = true
        var showComparison = true
        var showChart = true
        var showHeatmap = true
        var showLimits = true
        var limitsShowFiveHour = true
        var limitsShowWeek = true
        var limitsShowOther = false
        var showProjects = true
        var projectsCount = 8
        var showModels = true
        var showLog = true

        // MARK: Журнал

        var logTime = true
        var logAgent = true
        var logProject = true
        var logTitle = true
        var logModel = false
        var logDuration = true
        var logTokens = true
        var logApiCalls = false
        var logToolCalls = false
        var logPrompt = true
        var logRows = 100

        // MARK: Панель біля вирізу

        var panelShowsToday = false
        var panelTodayTurns = true
        var panelTodayTime = true
        var panelTodayTokens = true

        static let defaults = Values()
    }

    private static let key = "statsPreferences"

    var values: Values {
        didSet {
            guard values != oldValue, let data = try? JSONEncoder().encode(values) else { return }
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    var isDefault: Bool { values == .defaults }

    /// Скидає лише вигляд — що й як записувати, лишається як було.
    func resetDisplay() {
        var fresh = Values.defaults
        fresh.recording = values.recording
        fresh.recordLimits = values.recordLimits
        fresh.storePrompts = values.storePrompts
        fresh.retention = values.retention
        values = fresh
    }

    private init() {
        values = Self.load()
    }

    /// Збережене накладаємо на типові значення: поля, яких тоді ще не було,
    /// отримують типові, і нові налаштування не скидають старих.
    private static func load() -> Values {
        guard let stored = UserDefaults.standard.data(forKey: key),
              let storedObject = try? JSONSerialization.jsonObject(with: stored) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(Values.defaults),
              let defaultsObject = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any]
        else { return .defaults }

        let merged = defaultsObject.merging(storedObject) { _, stored in stored }
        guard let data = try? JSONSerialization.data(withJSONObject: merged),
              let values = try? JSONDecoder().decode(Values.self, from: data)
        else { return .defaults }
        return values
    }
}

// MARK: - Варіанти

enum StatsRetention: String, Codable, CaseIterable {
    case month, quarter, year, forever

    var title: String {
        switch self {
        case .month: return "30 днів"
        case .quarter: return "90 днів"
        case .year: return "Рік"
        case .forever: return "Завжди"
        }
    }

    var days: Int? {
        switch self {
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        case .forever: return nil
        }
    }
}

enum StatsPeriod: String, Codable, CaseIterable {
    case today, week, month, quarter, year, all

    var title: String {
        switch self {
        case .today: return "Сьогодні"
        case .week: return "7 днів"
        case .month: return "30 днів"
        case .quarter: return "90 днів"
        case .year: return "Рік"
        case .all: return "Усе"
        }
    }

    /// Скільки днів охоплює період, включно з сьогоднішнім; nil — уся історія.
    var days: Int? {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        case .all: return nil
        }
    }
}

enum AgentFilter: String, Codable, CaseIterable {
    case all, codex, claude

    var title: String {
        switch self {
        case .all: return "Усі агенти"
        case .codex: return Tool.codex.displayName
        case .claude: return Tool.claude.displayName
        }
    }

    var tool: Tool? {
        switch self {
        case .all: return nil
        case .codex: return .codex
        case .claude: return .claude
        }
    }
}

enum StatsMetric: String, Codable, CaseIterable {
    case tokens, turns, activeTime, apiCalls, toolCalls

    var title: String {
        switch self {
        case .tokens: return "Токени"
        case .turns: return "Ходи"
        case .activeTime: return "Час роботи"
        case .apiCalls: return "Запити до моделі"
        case .toolCalls: return "Виклики інструментів"
        }
    }
}

enum StatsGrouping: String, Codable, CaseIterable {
    case agent, project, model, none

    var title: String {
        switch self {
        case .agent: return "За агентом"
        case .project: return "За проєктом"
        case .model: return "За моделлю"
        case .none: return "Разом"
        }
    }
}

enum StatsChartStyle: String, Codable, CaseIterable {
    case bars, line, area

    var title: String {
        switch self {
        case .bars: return "Стовпці"
        case .line: return "Лінії"
        case .area: return "Області"
        }
    }
}

enum StatsBucketChoice: String, Codable, CaseIterable {
    case automatic, hour, day, week, month

    var title: String {
        switch self {
        case .automatic: return "Автоматично"
        case .hour: return "Година"
        case .day: return "День"
        case .week: return "Тиждень"
        case .month: return "Місяць"
        }
    }
}

enum StatsNumberStyle: String, Codable, CaseIterable {
    case compact, full

    var title: String {
        switch self {
        case .compact: return "Скорочено (1,2 млн)"
        case .full: return "Повністю (1 234 567)"
        }
    }
}
