import AppKit
import Charts
import Observation
import SwiftUI

/// Тимчасовий стан вікна, який не варто зберігати між запусками:
/// пошук, фільтр за проєктом, розгорнутий рядок журналу.
@MainActor
@Observable
final class StatsViewState {
    var search = ""
    var project: String?
    var selectedDate: Date?
    var expandedTurn: String?
    var logLimit = StatsPreferences.shared.values.logRows
    var logSort: LogSort = .newest
}

enum LogSort: String, CaseIterable {
    case newest, oldest, longest, tokens

    var title: String {
        switch self {
        case .newest: return "Спершу нові"
        case .oldest: return "Спершу старі"
        case .longest: return "Найдовші"
        case .tokens: return "Найбільше токенів"
        }
    }
}

/// Вікно статистики. Що саме в ньому показано, задається на вкладці
/// «Статистика» в налаштуваннях; основні перемикачі продубльовано тут.
struct StatsView: View {
    var store: StatsStore
    var preferences: StatsPreferences
    var state: StatsViewState
    var openSettings: () -> Void

    private var values: StatsPreferences.Values { preferences.values }

    var body: some View {
        let analysis = StatsAnalysis(preferences: values)
        let interval = analysis.interval(for: values.period, earliest: store.firstRecord)
        let tool = values.agentFilter.tool
        let turns = analysis.filter(store.turns, in: interval, tool: tool, project: state.project)
        let previous = analysis.filter(store.turns, in: analysis.previous(of: interval), tool: tool,
                                       project: state.project)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(analysis: analysis)

                if store.isImporting {
                    ProgressView(value: store.progress) {
                        Text(store.turns.isEmpty ? "Читаю журнали агентів — уперше це займає кілька секунд…"
                                                 : "Оновлюю статистику…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if !values.recording && store.turns.isEmpty {
                    placeholder(
                        "Збір статистики вимкнено",
                        detail: "Увімкніть його в налаштуваннях — історію буде відновлено з журналів агентів.",
                        action: ("Відкрити налаштування", openSettings)
                    )
                } else if turns.isEmpty && !store.isImporting {
                    placeholder(
                        "За цей період нічого немає",
                        detail: "Оберіть довший період або зніміть фільтри.",
                        action: nil
                    )
                } else if !turns.isEmpty {
                    if values.showSummary {
                        SummarySection(analysis: analysis, turns: turns, previous: previous, metric: values.metric,
                                       showComparison: values.showComparison && values.period != .all)
                    }
                    if values.showChart {
                        ChartSection(analysis: analysis, turns: turns, interval: interval,
                                     preferences: preferences, state: state)
                    }
                    if values.showHeatmap {
                        HeatmapSection(analysis: analysis, turns: turns, metric: values.metric, tool: tool)
                    }
                    if values.showLimits {
                        LimitsSection(analysis: analysis, samples: store.limits, interval: interval, tool: tool)
                    }
                    if values.showProjects || values.showModels {
                        HStack(alignment: .top, spacing: 16) {
                            if values.showProjects {
                                BreakdownSection(
                                    title: "Проєкти",
                                    rows: Array(analysis.projects(turns, metric: values.metric).prefix(values.projectsCount)),
                                    metric: values.metric,
                                    selected: state.project,
                                    onSelect: { row in state.project = state.project == row.detail ? nil : row.detail }
                                )
                            }
                            if values.showModels {
                                BreakdownSection(
                                    title: "Моделі",
                                    rows: Array(analysis.models(turns, metric: values.metric).prefix(values.projectsCount)),
                                    metric: values.metric,
                                    selected: nil,
                                    onSelect: nil
                                )
                            }
                        }
                    }
                    if values.showLog {
                        LogSection(analysis: analysis, turns: analysis.filter(
                            store.turns, in: interval, tool: tool, project: state.project, search: state.search
                        ), preferences: preferences, state: state)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Заголовок

    private func header(analysis: StatsAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Статистика")
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.importNow()
                } label: {
                    Label("Оновити", systemImage: "arrow.clockwise")
                }
                .disabled(store.isImporting || !values.recording)
                .help("Дочитати свіжі записи з журналів агентів")

                Button {
                    exportCSV(analysis: analysis)
                } label: {
                    Label("Експорт", systemImage: "square.and.arrow.up")
                }
                .help("Зберегти ходи за обраний період у CSV")

                Button(action: openSettings) {
                    Label("Налаштувати", systemImage: "slider.horizontal.3")
                }
                .help("Що показувати у вікні статистики")
            }

            HStack(spacing: 12) {
                Picker("Період", selection: Binding(
                    get: { values.period },
                    set: { preferences.values.period = $0; state.selectedDate = nil }
                )) {
                    ForEach(StatsPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Picker("Агент", selection: Binding(
                    get: { values.agentFilter },
                    set: { preferences.values.agentFilter = $0 }
                )) {
                    ForEach(AgentFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()

                if let project = state.project {
                    Button {
                        state.project = nil
                    } label: {
                        Label((project as NSString).lastPathComponent, systemImage: "xmark.circle.fill")
                    }
                    .help("Зняти фільтр за проєктом")
                }
                Spacer()
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let first = store.firstRecord { parts.append("історія з \(StatsFormat.fullDate.string(from: first))") }
        if let last = store.lastImport { parts.append("оновлено \(StatsFormat.time.string(from: last))") }
        return parts.joined(separator: " · ")
    }

    private func placeholder(_ title: String, detail: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary)
            if let action {
                Button(action.0, action: action.1).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Експорт

    private func exportCSV(analysis: StatsAnalysis) {
        let interval = analysis.interval(for: values.period, earliest: store.firstRecord)
        let turns = analysis.filter(store.turns, in: interval, tool: values.agentFilter.tool,
                                    project: state.project, search: state.search)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "notchmeter-\(StatsFormat.csv.string(from: Date()).prefix(10)).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        func field(_ value: String?) -> String {
            let text = value ?? ""
            return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var lines = ["started,ended,active_seconds,agent,project,session,title,model,prompt,api_calls,tool_calls,"
                     + "input_tokens,output_tokens,cache_read_tokens,cache_write_tokens,reasoning_tokens,subagent"]
        for turn in turns {
            lines.append([
                StatsFormat.csv.string(from: turn.started), StatsFormat.csv.string(from: turn.ended),
                String(Int(turn.duration)), turn.tool.rawValue, field(turn.project), field(turn.session),
                field(turn.title), field(turn.model), field(turn.prompt), String(turn.apiCalls),
                String(turn.toolCalls), String(turn.tokens.input), String(turn.tokens.output),
                String(turn.tokens.cacheRead), String(turn.tokens.cacheWrite), String(turn.tokens.reasoning),
                turn.isSubagent ? "1" : "0",
            ].joined(separator: ","))
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Картка розділу

private struct SectionCard<Content: View, Accessory: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                accessory
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07)))
    }
}

extension SectionCard where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = EmptyView()
        self.content = content()
    }
}

// MARK: - Підсумки

private struct SummarySection: View {
    let analysis: StatsAnalysis
    let turns: [TurnRecord]
    let previous: [TurnRecord]
    let metric: StatsMetric
    let showComparison: Bool

    var body: some View {
        let current = analysis.summary(turns, metric: metric)
        let before = analysis.summary(previous, metric: metric)

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            card("Ходи", StatsFormat.number(current.turns),
                 detail: current.subagents > 0 ? "і \(StatsFormat.number(current.subagents)) субагентів" : "ваших запитів",
                 change: change(Double(current.turns), Double(before.turns)))
            card("Час роботи", StatsFormat.duration(current.activeTime),
                 detail: "у середньому \(StatsFormat.duration(current.averageTurn)) на хід",
                 change: change(current.activeTime, before.activeTime))
            card("Токени", StatsFormat.number(current.countedTokens),
                 detail: "вих. \(StatsFormat.number(current.tokens.output)) · кеш \(StatsFormat.number(current.tokens.cacheRead))",
                 change: change(Double(current.countedTokens), Double(before.countedTokens)))
            card("Запити до моделі", StatsFormat.number(current.apiCalls),
                 detail: "інструментів: \(StatsFormat.number(current.toolCalls))",
                 change: change(Double(current.apiCalls), Double(before.apiCalls)))
            card("Сесії", StatsFormat.number(current.sessions),
                 detail: "проєктів: \(current.projects)",
                 change: change(Double(current.sessions), Double(before.sessions)))
            card("Найдовший хід", StatsFormat.duration(current.longestTurn),
                 detail: current.busiestDay.map { "найактивніший день — \(StatsFormat.dayMonth.string(from: $0.date))" } ?? "",
                 change: nil)
        }
    }

    private func change(_ current: Double, _ previous: Double) -> String? {
        showComparison ? StatsFormat.percentChange(current: current, previous: previous) : nil
    }

    private func card(_ title: String, _ value: String, detail: String, change: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let change {
                    Text(change)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(change.hasPrefix("+") ? Color.green : (change == "0%" ? Color.secondary : Color.orange))
                        .help("Порівняно з попереднім таким самим періодом")
                }
            }
            Text(value)
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07)))
    }
}

// MARK: - Графік

private struct ChartSection: View {
    let analysis: StatsAnalysis
    let turns: [TurnRecord]
    let interval: DateInterval
    var preferences: StatsPreferences
    var state: StatsViewState

    var body: some View {
        let values = preferences.values
        let component = analysis.bucket(for: interval)
        let data = analysis.chart(turns, metric: values.metric, grouping: values.grouping, interval: interval)
        let colors = data.series.enumerated().map { StatsPalette.color(for: $1, index: $0) }
        let selectedBucket = state.selectedDate.flatMap {
            analysis.calendar.dateInterval(of: component, for: $0)?.start
        }

        SectionCard(title: values.metric.title, subtitle: subtitle(component)) {
            HStack(spacing: 8) {
                Picker("Метрика", selection: Binding(
                    get: { values.metric },
                    set: { preferences.values.metric = $0 }
                )) {
                    ForEach(StatsMetric.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 190)

                Picker("Групування", selection: Binding(
                    get: { values.grouping },
                    set: { preferences.values.grouping = $0 }
                )) {
                    ForEach(StatsGrouping.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)

                Picker("Вигляд", selection: Binding(
                    get: { values.chartStyle },
                    set: { preferences.values.chartStyle = $0 }
                )) {
                    ForEach(StatsChartStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }
        } content: {
            Chart {
                ForEach(data.points) { point in
                    switch values.chartStyle {
                    case .bars:
                        BarMark(
                            x: .value("Час", point.date, unit: component),
                            y: .value(values.metric.title, point.value)
                        )
                        .foregroundStyle(by: .value("Ряд", point.series))
                    case .line:
                        LineMark(
                            x: .value("Час", point.date, unit: component),
                            y: .value(values.metric.title, point.value)
                        )
                        .foregroundStyle(by: .value("Ряд", point.series))
                        .interpolationMethod(.monotone)
                    case .area:
                        AreaMark(
                            x: .value("Час", point.date, unit: component),
                            y: .value(values.metric.title, point.value)
                        )
                        .foregroundStyle(by: .value("Ряд", point.series))
                        .interpolationMethod(.monotone)
                    }
                }

                if let selectedBucket {
                    RuleMark(x: .value("Обрано", selectedBucket, unit: component))
                        .foregroundStyle(Color.primary.opacity(0.25))
                        .annotation(position: .top, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            tooltip(bucket: selectedBucket, component: component, points: data.points,
                                    series: data.series, colors: colors, metric: values.metric)
                        }
                }
            }
            .chartForegroundStyleScale(domain: data.series, range: colors)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(StatsFormat.axis(number, values.metric))
                        }
                    }
                }
            }
            .chartXSelection(value: Binding(
                get: { state.selectedDate },
                set: { state.selectedDate = $0 }
            ))
            .chartLegend(values.grouping == .none ? .hidden : .automatic)
            .frame(height: 240)
        }
    }

    private func subtitle(_ component: Calendar.Component) -> String {
        switch component {
        case .hour: return "по годинах"
        case .day: return "по днях"
        case .weekOfYear: return "по тижнях"
        case .month: return "по місяцях"
        default: return ""
        }
    }

    private func tooltip(bucket: Date, component: Calendar.Component, points: [StatsAnalysis.ChartPoint],
                         series: [String], colors: [Color], metric: StatsMetric) -> some View {
        let entries = points.filter { $0.date == bucket && $0.value > 0 }
        let total = entries.reduce(0) { $0 + $1.value }
        return VStack(alignment: .leading, spacing: 3) {
            Text(StatsFormat.bucket(bucket, component: component))
                .font(.caption.weight(.semibold))
            ForEach(entries) { entry in
                HStack(spacing: 6) {
                    Circle()
                        .fill(colors[series.firstIndex(of: entry.series) ?? 0])
                        .frame(width: 6, height: 6)
                    Text(entry.series).font(.caption)
                    Spacer(minLength: 12)
                    Text(StatsFormat.metric(entry.value, metric)).font(.caption.monospacedDigit())
                }
            }
            if entries.count > 1 {
                Divider()
                HStack {
                    Text("Разом").font(.caption)
                    Spacer(minLength: 12)
                    Text(StatsFormat.metric(total, metric)).font(.caption.weight(.semibold).monospacedDigit())
                }
            }
            if entries.isEmpty {
                Text("нічого").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(minWidth: 160)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Теплова карта

private struct HeatmapSection: View {
    let analysis: StatsAnalysis
    let turns: [TurnRecord]
    let metric: StatsMetric
    let tool: Tool?

    var body: some View {
        let grid = analysis.heatmap(turns, metric: metric)
        let peak = grid.flatMap { $0 }.max() ?? 0
        let symbols = analysis.weekdaySymbols
        let tint = tool.map { Color(nsColor: $0.accent) } ?? Color.accentColor

        SectionCard(title: "Коли ви працюєте", subtitle: "\(metric.title.lowercased()) за днем тижня й годиною початку ходу") {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<7, id: \.self) { row in
                    HStack(spacing: 3) {
                        Text(symbols[row])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)
                        ForEach(0..<24, id: \.self) { hour in
                            let value = grid[row][hour]
                            RoundedRectangle(cornerRadius: 3)
                                .fill(value > 0 ? tint.opacity(0.18 + 0.82 * value / max(peak, 1)) : Color.primary.opacity(0.05))
                                .frame(maxWidth: .infinity)
                                .frame(height: 16)
                                .help("\(symbols[row]), \(hour):00–\(hour + 1):00 — \(StatsFormat.metric(value, metric))")
                        }
                    }
                }
                HStack(spacing: 3) {
                    Color.clear.frame(width: 24, height: 1)
                    ForEach(0..<24, id: \.self) { hour in
                        Text(hour % 3 == 0 ? "\(hour)" : "")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: - Ліміти

private struct LimitsSection: View {
    let analysis: StatsAnalysis
    let samples: [LimitSample]
    let interval: DateInterval
    let tool: Tool?

    var body: some View {
        let points = analysis.limitPoints(samples, in: interval, tool: tool)
        let tools = Tool.allCases.filter { tool in points.contains { $0.tool == tool } }

        SectionCard(title: "Ліміти", subtitle: "скільки відсотків було використано") {
            if !points.isEmpty, tool == nil, tools.count < Tool.allCases.count {
                Text("Історія лімітів Claude записується, поки працює NotchMeter, — її поки немає за цей період.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if points.isEmpty {
                Text("За цей період вимірів немає. Історія лімітів Codex береться з його журналів, а Claude — записується, поки працює NotchMeter.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Час", point.date),
                        y: .value("Використано", point.percent),
                        series: .value("Ряд", point.series)
                    )
                    .foregroundStyle(by: .value("Агент", point.tool.displayName))
                    .lineStyle(by: .value("Вікно", String(point.series.split(separator: "·").last ?? "").trimmingCharacters(in: .whitespaces)))
                    .interpolationMethod(.stepEnd)
                }
                .chartForegroundStyleScale(domain: tools.map(\.displayName),
                                           range: tools.map { Color(nsColor: $0.accent) })
                .chartXScale(domain: interval.start...interval.end)
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(interval.duration <= 86400 * 1.01
                                     ? StatsFormat.time.string(from: date)
                                     : StatsFormat.dayMonth.string(from: date))
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
                    }
                }
                .frame(height: 180)
            }
        }
    }
}

// MARK: - Проєкти й моделі

private struct BreakdownSection: View {
    let title: String
    let rows: [StatsAnalysis.GroupRow]
    let metric: StatsMetric
    let selected: String?
    let onSelect: ((StatsAnalysis.GroupRow) -> Void)?

    var body: some View {
        let peak = rows.map(\.metricValue).max() ?? 0

        SectionCard(title: title, subtitle: "за метрикою «\(metric.title.lowercased())»") {
            VStack(spacing: 2) {
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            ForEach(Tool.allCases.filter { row.tools.contains($0) }, id: \.self) { tool in
                                Circle().fill(Color(nsColor: tool.accent)).frame(width: 6, height: 6)
                            }
                        }
                        .frame(width: 18, alignment: .leading)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.name)
                                .font(.callout.weight(selected != nil && selected == row.detail ? .semibold : .regular))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.55))
                                    .frame(width: max(2, proxy.size.width * row.metricValue / max(peak, 1)))
                            }
                            .frame(height: 3)
                        }

                        Text(StatsFormat.metric(row.metricValue, metric))
                            .font(.callout.monospacedDigit())
                            .frame(width: 90, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(selected != nil && selected == row.detail ? Color.accentColor.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect?(row) }
                    .help(help(for: row))
                }
            }
        }
    }

    private func help(for row: StatsAnalysis.GroupRow) -> String {
        var lines = [row.detail ?? row.name]
        lines.append("ходів: \(row.turns), час: \(StatsFormat.duration(row.activeTime)), токени: \(StatsFormat.number(row.tokens))")
        lines.append("востаннє: \(StatsFormat.when(row.lastUsed))")
        if onSelect != nil { lines.append("Клік — показати лише цей проєкт") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Журнал

private struct LogSection: View {
    let analysis: StatsAnalysis
    let turns: [TurnRecord]
    var preferences: StatsPreferences
    var state: StatsViewState

    private var values: StatsPreferences.Values { preferences.values }

    var body: some View {
        let sorted = sort(turns)
        let shown = sorted.prefix(max(state.logLimit, values.logRows))

        SectionCard(title: "Журнал", subtitle: "\(StatsFormat.number(turns.count)) записів") {
            HStack(spacing: 8) {
                TextField("Пошук у запитах, проєктах, моделях", text: Binding(
                    get: { state.search },
                    set: { state.search = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)

                Picker("Сортування", selection: Binding(
                    get: { state.logSort },
                    set: { state.logSort = $0 }
                )) {
                    ForEach(LogSort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 170)
            }
        } content: {
            VStack(spacing: 0) {
                headerRow
                Divider()
                LazyVStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, turn in
                        row(turn, index: index)
                    }
                }
                if sorted.count > shown.count {
                    Button("Показати ще \(min(values.logRows, sorted.count - shown.count))") {
                        state.logLimit = shown.count + values.logRows
                    }
                    .padding(.top, 10)
                }
            }
        }
    }

    private func sort(_ turns: [TurnRecord]) -> [TurnRecord] {
        switch state.logSort {
        case .newest: return turns.sorted { $0.started > $1.started }
        case .oldest: return turns.sorted { $0.started < $1.started }
        case .longest: return turns.sorted { $0.duration > $1.duration }
        case .tokens: return turns.sorted { analysis.countedTokens($0.tokens) > analysis.countedTokens($1.tokens) }
        }
    }

    // Ширини колонок — спільні для заголовка й рядків.
    private enum Width {
        static let time: CGFloat = 118
        static let agent: CGFloat = 54
        static let project: CGFloat = 130
        static let model: CGFloat = 130
        static let duration: CGFloat = 72
        static let tokens: CGFloat = 80
        static let calls: CGFloat = 56
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            if values.logTime { column("Коли", Width.time) }
            if values.logAgent { column("Агент", Width.agent) }
            if values.logProject { column("Проєкт", Width.project) }
            if values.logTitle { Text("Сесія").frame(maxWidth: .infinity, alignment: .leading) }
            if values.logPrompt { Text("Запит").frame(maxWidth: .infinity, alignment: .leading) }
            if values.logModel { column("Модель", Width.model) }
            if values.logDuration { column("Час", Width.duration, trailing: true) }
            if values.logTokens { column("Токени", Width.tokens, trailing: true) }
            if values.logApiCalls { column("Запити", Width.calls, trailing: true) }
            if values.logToolCalls { column("Інстр.", Width.calls, trailing: true) }
            if !values.logTitle && !values.logPrompt { Spacer(minLength: 0) }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }

    private func column(_ title: String, _ width: CGFloat, trailing: Bool = false) -> some View {
        Text(title).frame(width: width, alignment: trailing ? .trailing : .leading)
    }

    private func row(_ turn: TurnRecord, index: Int) -> some View {
        let expanded = state.expandedTurn == turn.id
        let color = Color(nsColor: turn.tool.accent)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if values.logTime {
                    Text(StatsFormat.when(turn.started))
                        .monospacedDigit()
                        .frame(width: Width.time, alignment: .leading)
                }
                if values.logAgent {
                    Text(turn.tool.displayName)
                        .foregroundStyle(color)
                        .frame(width: Width.agent, alignment: .leading)
                }
                if values.logProject {
                    Text(turn.projectName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: Width.project, alignment: .leading)
                        .help(turn.project)
                }
                if values.logTitle {
                    HStack(spacing: 4) {
                        if turn.isSubagent {
                            Text("субагент")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                        }
                        Text(turn.title ?? "—").lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if values.logPrompt {
                    Text(turn.prompt.map(singleLine) ?? "—")
                        .lineLimit(1)
                        .foregroundStyle(turn.prompt == nil ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if values.logModel {
                    Text(turn.model ?? "—")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .frame(width: Width.model, alignment: .leading)
                }
                if values.logDuration {
                    Text(StatsFormat.duration(turn.duration))
                        .monospacedDigit()
                        .frame(width: Width.duration, alignment: .trailing)
                }
                if values.logTokens {
                    Text(StatsFormat.number(analysis.countedTokens(turn.tokens)))
                        .monospacedDigit()
                        .frame(width: Width.tokens, alignment: .trailing)
                }
                if values.logApiCalls {
                    Text("\(turn.apiCalls)").monospacedDigit().frame(width: Width.calls, alignment: .trailing)
                }
                if values.logToolCalls {
                    Text("\(turn.toolCalls)").monospacedDigit().frame(width: Width.calls, alignment: .trailing)
                }
                if !values.logTitle && !values.logPrompt { Spacer(minLength: 0) }
            }
            .font(.callout)
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .onTapGesture { state.expandedTurn = expanded ? nil : turn.id }

            if expanded {
                details(turn)
            }
        }
        .background(index % 2 == 1 ? Color.primary.opacity(0.03) : Color.clear)
    }

    private func singleLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
    }

    private func details(_ turn: TurnRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let prompt = turn.prompt {
                Text(prompt)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 3) {
                detailRow("Проєкт", turn.project.isEmpty ? "—" : turn.project)
                detailRow("Сесія", [turn.title, turn.session].compactMap { $0 }.joined(separator: " · "))
                detailRow("Модель", turn.model ?? "—")
                detailRow("Час", "\(StatsFormat.dayMonthTime.string(from: turn.started)) – \(StatsFormat.time.string(from: turn.ended)), "
                          + "активно \(StatsFormat.duration(turn.duration))")
                detailRow("Токени", "вхідні \(StatsFormat.number(turn.tokens.input)) · вихідні \(StatsFormat.number(turn.tokens.output))"
                          + " (міркування \(StatsFormat.number(turn.tokens.reasoning))) · кеш читання \(StatsFormat.number(turn.tokens.cacheRead))"
                          + " · кеш запису \(StatsFormat.number(turn.tokens.cacheWrite))")
                detailRow("Виклики", "запитів до моделі \(turn.apiCalls), інструментів \(turn.toolCalls)")
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.06))
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}
