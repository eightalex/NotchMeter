import SwiftUI

/// Зведення статистики для вікна: фільтри, ряди для графіка, теплова
/// карта, розбивки. Без стану — усе рахується з переданих записів і
/// налаштувань.
@MainActor
struct StatsAnalysis {
    let preferences: StatsPreferences.Values
    let calendar: Calendar

    init(preferences: StatsPreferences.Values? = nil) {
        let preferences = preferences ?? StatsPreferences.shared.values
        self.preferences = preferences
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "uk_UA")
        calendar.timeZone = .current
        calendar.firstWeekday = preferences.weekStartsMonday ? 2 : 1
        self.calendar = calendar
    }

    // MARK: - Період і фільтр

    func interval(for period: StatsPeriod, earliest: Date?, now: Date = Date()) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        guard let days = period.days else {
            let start = earliest.map { calendar.startOfDay(for: $0) } ?? today
            return DateInterval(start: min(start, today), end: now)
        }
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        return DateInterval(start: start, end: now)
    }

    /// Такий самий відрізок одразу перед поточним — для порівняння.
    func previous(of interval: DateInterval) -> DateInterval {
        DateInterval(start: interval.start.addingTimeInterval(-interval.duration), end: interval.start)
    }

    func filter(
        _ turns: [TurnRecord],
        in interval: DateInterval,
        tool: Tool?,
        project: String?,
        search: String = ""
    ) -> [TurnRecord] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return turns.filter { turn in
            guard turn.started >= interval.start, turn.started <= interval.end else { return false }
            if !preferences.includeSubagents, turn.isSubagent { return false }
            if let tool, turn.tool != tool { return false }
            if let project, turn.project != project { return false }
            if !query.isEmpty {
                let haystack = [turn.projectName, turn.title ?? "", turn.prompt ?? "", turn.model ?? ""]
                    .joined(separator: " ")
                    .lowercased()
                if !haystack.contains(query) { return false }
            }
            return true
        }
    }

    // MARK: - Метрики

    /// Токени лише тих видів, що увімкнені в налаштуваннях.
    func countedTokens(_ usage: TokenUsage) -> Int {
        var total = 0
        if preferences.tokensInput { total += usage.input }
        if preferences.tokensOutput { total += usage.output }
        if preferences.tokensCacheWrite { total += usage.cacheWrite }
        if preferences.tokensCacheRead { total += usage.cacheRead }
        return total
    }

    /// Субагенти працюють паралельно з ходом, що їх запустив, тож у ходах і
    /// часі не рахуються — лише в токенах і викликах.
    func value(of turn: TurnRecord, metric: StatsMetric) -> Double {
        switch metric {
        case .tokens: return Double(countedTokens(turn.tokens))
        case .turns: return turn.isSubagent ? 0 : 1
        case .activeTime: return turn.isSubagent ? 0 : turn.duration
        case .apiCalls: return Double(turn.apiCalls)
        case .toolCalls: return Double(turn.toolCalls)
        }
    }

    func total(_ turns: [TurnRecord], metric: StatsMetric) -> Double {
        turns.reduce(0) { $0 + value(of: $1, metric: metric) }
    }

    // MARK: - Підсумки

    struct Summary {
        var turns = 0
        var subagents = 0
        var activeTime: TimeInterval = 0
        var tokens = TokenUsage()
        var countedTokens = 0
        var apiCalls = 0
        var toolCalls = 0
        var sessions = 0
        var projects = 0
        var longestTurn: TimeInterval = 0
        var busiestDay: (date: Date, value: Double)?

        var averageTurn: TimeInterval { turns > 0 ? activeTime / Double(turns) : 0 }
    }

    func summary(_ turns: [TurnRecord], metric: StatsMetric) -> Summary {
        var result = Summary()
        var sessions = Set<String>()
        var projects = Set<String>()
        var days: [Date: Double] = [:]
        for turn in turns {
            if turn.isSubagent {
                result.subagents += 1
            } else {
                result.turns += 1
                result.activeTime += turn.duration
                result.longestTurn = max(result.longestTurn, turn.duration)
            }
            result.tokens = result.tokens + turn.tokens
            result.apiCalls += turn.apiCalls
            result.toolCalls += turn.toolCalls
            sessions.insert("\(turn.tool.rawValue):\(turn.session)")
            if !turn.project.isEmpty { projects.insert(turn.project) }
            days[calendar.startOfDay(for: turn.started), default: 0] += value(of: turn, metric: metric)
        }
        result.countedTokens = countedTokens(result.tokens)
        result.sessions = sessions.count
        result.projects = projects.count
        result.busiestDay = days.max { $0.value < $1.value }.map { ($0.key, $0.value) }
        return result
    }

    // MARK: - Графік

    struct ChartPoint: Identifiable {
        let date: Date
        let series: String
        let value: Double
        var id: String { "\(series)|\(date.timeIntervalSince1970)" }
    }

    func bucket(for interval: DateInterval) -> Calendar.Component {
        switch preferences.bucket {
        case .hour: return .hour
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .automatic:
            let days = interval.duration / 86400
            if days <= 1.01 { return .hour }
            if days <= 45 { return .day }
            if days <= 200 { return .weekOfYear }
            return .month
        }
    }

    func seriesName(for turn: TurnRecord, grouping: StatsGrouping) -> String {
        switch grouping {
        case .agent: return turn.tool.displayName
        case .project: return turn.projectName
        case .model: return turn.model ?? "невідомо"
        case .none: return "Усього"
        }
    }

    nonisolated static let otherSeries = "Інші"

    /// Ряди для графіка з нулями в порожніх проміжках — щоб лінії не
    /// перестрибували через дні без роботи. Для проєктів і моделей лишаємо
    /// шість найбільших, решту зводимо в «Інші».
    func chart(_ turns: [TurnRecord], metric: StatsMetric, grouping: StatsGrouping,
               interval: DateInterval) -> (points: [ChartPoint], series: [String]) {
        let component = bucket(for: interval)

        var totals: [String: Double] = [:]
        for turn in turns { totals[seriesName(for: turn, grouping: grouping), default: 0] += value(of: turn, metric: metric) }
        var ranked = totals.sorted { $0.value > $1.value }.map(\.key)
        var keep = Set(ranked)
        if grouping == .project || grouping == .model, ranked.count > 6 {
            keep = Set(ranked.prefix(6))
            ranked = Array(ranked.prefix(6)) + [Self.otherSeries]
        }
        if grouping == .agent {
            ranked = Tool.allCases.map(\.displayName).filter { totals[$0] != nil }
        }

        var values: [String: [Date: Double]] = [:]
        for turn in turns {
            let raw = seriesName(for: turn, grouping: grouping)
            let name = keep.contains(raw) ? raw : Self.otherSeries
            let start = calendar.dateInterval(of: component, for: turn.started)?.start ?? turn.started
            values[name, default: [:]][start, default: 0] += value(of: turn, metric: metric)
        }

        let buckets = bucketStarts(in: interval, component: component)
        var points: [ChartPoint] = []
        for name in ranked {
            let byDate = values[name] ?? [:]
            for start in buckets {
                points.append(ChartPoint(date: start, series: name, value: byDate[start] ?? 0))
            }
        }
        return (points, ranked)
    }

    func bucketStarts(in interval: DateInterval, component: Calendar.Component) -> [Date] {
        guard var current = calendar.dateInterval(of: component, for: interval.start)?.start else { return [] }
        var result: [Date] = []
        while current <= interval.end, result.count < 2000 {
            result.append(current)
            guard let next = calendar.date(byAdding: component, value: 1, to: current) else { break }
            current = next
        }
        return result
    }

    // MARK: - Теплова карта

    /// 7 рядків (дні тижня з урахуванням першого дня) × 24 години.
    func heatmap(_ turns: [TurnRecord], metric: StatsMetric) -> [[Double]] {
        var grid = Array(repeating: Array(repeating: 0.0, count: 24), count: 7)
        for turn in turns {
            let parts = calendar.dateComponents([.weekday, .hour], from: turn.started)
            guard let weekday = parts.weekday, let hour = parts.hour else { continue }
            let row = (weekday - calendar.firstWeekday + 7) % 7
            grid[row][hour] += value(of: turn, metric: metric)
        }
        return grid
    }

    var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    // MARK: - Розбивки

    struct GroupRow: Identifiable {
        let id: String
        let name: String
        var detail: String?
        var tools: Set<Tool> = []
        var turns = 0
        var activeTime: TimeInterval = 0
        var tokens = 0
        var lastUsed = Date.distantPast
        var metricValue: Double = 0
    }

    func projects(_ turns: [TurnRecord], metric: StatsMetric) -> [GroupRow] {
        var rows = group(turns, metric: metric) { turn in
            (turn.project.isEmpty ? "—" : turn.project, turn.projectName, turn.project)
        }
        // Різні теки з однаковою назвою (`top` і `top/top`) — показуємо ще й батьківську.
        let names = Dictionary(grouping: rows.indices, by: { rows[$0].name })
        for (_, indices) in names where indices.count > 1 {
            for index in indices {
                let components = (rows[index].detail ?? "").split(separator: "/").suffix(2)
                rows[index] = GroupRow(id: rows[index].id, name: components.joined(separator: "/"),
                                       detail: rows[index].detail, tools: rows[index].tools,
                                       turns: rows[index].turns, activeTime: rows[index].activeTime,
                                       tokens: rows[index].tokens, lastUsed: rows[index].lastUsed,
                                       metricValue: rows[index].metricValue)
            }
        }
        return rows
    }

    func models(_ turns: [TurnRecord], metric: StatsMetric) -> [GroupRow] {
        group(turns, metric: metric) { turn in
            let model = turn.model ?? "невідомо"
            return ("\(turn.tool.rawValue):\(model)", model, nil)
        }
    }

    private func group(_ turns: [TurnRecord], metric: StatsMetric,
                       key: (TurnRecord) -> (id: String, name: String, detail: String?)) -> [GroupRow] {
        var rows: [String: GroupRow] = [:]
        for turn in turns {
            let info = key(turn)
            var row = rows[info.id] ?? GroupRow(id: info.id, name: info.name, detail: info.detail)
            row.tools.insert(turn.tool)
            if !turn.isSubagent {
                row.turns += 1
                row.activeTime += turn.duration
            }
            row.tokens += countedTokens(turn.tokens)
            row.lastUsed = max(row.lastUsed, turn.ended)
            row.metricValue += value(of: turn, metric: metric)
            rows[info.id] = row
        }
        return rows.values.sorted { $0.metricValue > $1.metricValue }
    }

    // MARK: - Ліміти

    struct LimitPoint: Identifiable {
        let date: Date
        let series: String
        let tool: Tool
        let percent: Double
        var id: String { "\(series)|\(date.timeIntervalSince1970)" }
    }

    /// Виміри пишуться лише при зміні, тож між ними лінія тримає значення.
    /// Якщо ж вікно ліміту скинулося до наступного виміру, додаємо нуль у
    /// момент скидання — інакше на графіку ліміт «висів» би до нового виміру.
    func limitPoints(_ samples: [LimitSample], in interval: DateInterval, tool: Tool?) -> [LimitPoint] {
        var expanded: [LimitSample] = []
        let grouped = Dictionary(grouping: samples) { "\($0.tool.rawValue):\($0.label)" }
        for (_, series) in grouped {
            let ordered = series.sorted { $0.at < $1.at }
            for (index, sample) in ordered.enumerated() {
                expanded.append(sample)
                let next = index + 1 < ordered.count ? ordered[index + 1].at : Date()
                if let reset = sample.resetsAt, reset > sample.at, reset < next, sample.percent > 0 {
                    expanded.append(LimitSample(tool: sample.tool, label: sample.label, at: reset,
                                                percent: 0, resetsAt: nil))
                }
            }
        }
        return expanded.sorted { $0.at < $1.at }.compactMap { sample in
            guard sample.at >= interval.start, sample.at <= interval.end else { return nil }
            if let tool, sample.tool != tool { return nil }
            let window = LimitWindow(label: sample.label, usedPercent: sample.percent, resetsAt: sample.resetsAt)
            switch window.kind {
            case .fiveHour: guard preferences.limitsShowFiveHour else { return nil }
            case .week: guard preferences.limitsShowWeek else { return nil }
            default: guard preferences.limitsShowOther else { return nil }
            }
            return LimitPoint(date: sample.at, series: "\(sample.tool.displayName) · \(sample.label)",
                              tool: sample.tool, percent: sample.percent)
        }
    }
}

// MARK: - Форматування

@MainActor
enum StatsFormat {
    static func number(_ value: Double, style: StatsNumberStyle? = nil) -> String {
        switch style ?? StatsPreferences.shared.values.numberStyle {
        case .full:
            return fullFormatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value))"
        case .compact:
            let magnitude = abs(value)
            func scaled(_ divisor: Double, _ suffix: String) -> String {
                let scaledValue = value / divisor
                let digits = abs(scaledValue) < 10 ? 1 : 0
                return (compactFormatter(digits).string(from: NSNumber(value: scaledValue)) ?? "") + suffix
            }
            if magnitude >= 1_000_000_000 { return scaled(1_000_000_000, " млрд") }
            if magnitude >= 1_000_000 { return scaled(1_000_000, " млн") }
            if magnitude >= 10_000 { return scaled(1_000, " тис") }
            return fullFormatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value))"
        }
    }

    static func number(_ value: Int) -> String { number(Double(value)) }

    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return minutes > 0 ? "\(hours) год \(minutes) хв" : "\(hours) год" }
        if minutes > 0 { return "\(minutes) хв" }
        return "\(seconds) с"
    }

    static func metric(_ value: Double, _ metric: StatsMetric) -> String {
        metric == .activeTime ? duration(value) : number(value)
    }

    /// Підпис осі: для часу — години, інакше скорочене число.
    static func axis(_ value: Double, _ metric: StatsMetric) -> String {
        if metric == .activeTime {
            let hours = value / 3600
            return hours >= 1 ? "\(compactFormatter(hours < 10 ? 1 : 0).string(from: NSNumber(value: hours)) ?? "") год"
                : "\(Int((value / 60).rounded())) хв"
        }
        return number(value, style: .compact)
    }

    static func percentChange(current: Double, previous: Double) -> String? {
        guard previous > 0 else { return nil }
        let change = (current - previous) / previous * 100
        let rounded = Int(change.rounded())
        return rounded > 0 ? "+\(rounded)%" : "\(rounded)%"
    }

    private static let fullFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "uk_UA")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static var compactCache: [Int: NumberFormatter] = [:]

    private static func compactFormatter(_ digits: Int) -> NumberFormatter {
        if let cached = compactCache[digits] { return cached }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "uk_UA")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = digits
        formatter.minimumFractionDigits = 0
        compactCache[digits] = formatter
        return formatter
    }

    static let time: DateFormatter = formatter("HH:mm")
    static let dayMonth: DateFormatter = formatter("d MMM")
    static let dayMonthTime: DateFormatter = formatter("d MMM, HH:mm")
    static let fullDate: DateFormatter = formatter("d MMMM yyyy")
    static let weekdayDay: DateFormatter = formatter("EEEEEE, d MMM")
    static let monthYear: DateFormatter = formatter("LLLL yyyy")
    static let csv: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "uk_UA")
        formatter.dateFormat = format
        return formatter
    }

    /// Коли саме був хід: сьогодні — лише час, цього року — день і час.
    static func when(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "сьогодні, " + time.string(from: date) }
        if calendar.isDateInYesterday(date) { return "вчора, " + time.string(from: date) }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) { return dayMonthTime.string(from: date) }
        return csv.string(from: date).prefix(16).description
    }

    /// Підпис проміжку графіка залежно від його розміру.
    static func bucket(_ date: Date, component: Calendar.Component) -> String {
        switch component {
        case .hour: return time.string(from: date)
        case .day: return weekdayDay.string(from: date)
        case .weekOfYear: return "тиждень з " + dayMonth.string(from: date)
        case .month: return monthYear.string(from: date)
        default: return dayMonth.string(from: date)
        }
    }
}

/// Кольори рядів: агенти — своїми акцентами, решта — з палітри.
enum StatsPalette {
    static let colors: [Color] = [
        Color(red: 0.36, green: 0.62, blue: 0.98),
        Color(red: 0.95, green: 0.55, blue: 0.35),
        Color(red: 0.42, green: 0.80, blue: 0.55),
        Color(red: 0.78, green: 0.52, blue: 0.95),
        Color(red: 0.98, green: 0.80, blue: 0.35),
        Color(red: 0.40, green: 0.82, blue: 0.86),
        Color(red: 0.93, green: 0.45, blue: 0.62),
    ]

    static func color(for series: String, index: Int) -> Color {
        if let tool = Tool.allCases.first(where: { $0.displayName == series }) {
            return Color(nsColor: tool.accent)
        }
        if series == StatsAnalysis.otherSeries { return Color.gray.opacity(0.6) }
        return colors[index % colors.count]
    }
}
