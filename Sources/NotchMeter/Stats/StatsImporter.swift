import Foundation

/// Переносить журнали агентів у власну базу статистики.
///
/// Перечитуємо лише файли, що змінились з минулого разу (розмір чи час
/// зміни), і завжди цілком: хід може тягнутися через кілька дописувань,
/// а повний перерахунок одного файлу простіший і надійніший за збереження
/// напіврозібраного стану. Рядки, яких уже немає в журналах (Claude Code
/// типово видаляє свої журнали через 30 днів), у базі лишаються — у цьому
/// й сенс власної історії.
actor StatsImporter {
    struct Options: Sendable {
        var storePrompts: Bool
        /// Записи, старші за цю дату, не зберігаються; nil — без обмеження.
        var keepSince: Date?
    }

    struct Snapshot: Sendable {
        var turns: [TurnRecord]
        var limits: [LimitSample]
    }

    private let database: StatsDatabase?

    init(database: StatsDatabase? = StatsDatabase()) {
        self.database = database
    }

    var isAvailable: Bool { database != nil }

    // MARK: - Імпорт

    /// Повертає кількість перечитаних файлів.
    @discardableResult
    func importChanged(options: Options, progress: @Sendable (Double) -> Void) -> Int {
        guard let database else { return 0 }

        var known: [String: (size: Int, mtime: Double)] = [:]
        database.run("SELECT path, size, mtime FROM sources") { row in
            if let path = row.text(0) { known[path] = (row.int(1), row.real(2) ?? 0) }
        }

        let candidates = Self.logFiles()
        let changed = candidates.filter { file in
            guard let previous = known[file.url.path] else { return true }
            return previous.size != file.size || abs(previous.mtime - file.mtime) > 0.001
        }
        guard !changed.isEmpty else {
            applyRetention(options.keepSince)
            return 0
        }

        let titles = changed.contains { $0.tool == .codex } ? CodexStateDatabase.allTitles() : [:]
        let totalBytes = max(1, changed.reduce(0) { $0 + $1.size })
        var processedBytes = 0
        progress(0)

        // Пишемо пачками: одна транзакція на кілька файлів — і швидко, і
        // перерваний імпорт не губить усього зробленого.
        var pending: [(file: LogFile, parsed: ParsedLog)] = []
        func commit() {
            guard !pending.isEmpty else { return }
            database.transaction {
                for item in pending { self.store(item.parsed, for: item.file, keepSince: options.keepSince) }
            }
            pending.removeAll()
        }

        for file in changed {
            let parsed: ParsedLog = autoreleasepool {
                switch file.tool {
                case .claude: return ClaudeLogParser.parse(file.url, storePrompts: options.storePrompts)
                case .codex: return CodexLogParser.parse(file.url, titles: titles, storePrompts: options.storePrompts)
                }
            }
            pending.append((file, parsed))
            processedBytes += file.size
            if pending.count >= 20 {
                commit()
                progress(Double(processedBytes) / Double(totalBytes))
            }
        }
        commit()
        applyRetention(options.keepSince)
        progress(1)
        return changed.count
    }

    private func store(_ parsed: ParsedLog, for file: LogFile, keepSince: Date?) {
        guard let database else { return }
        let path = file.url.path
        database.run("DELETE FROM turns WHERE source = ?", [.text(path)])
        database.run("DELETE FROM limits WHERE source = ?", [.text(path)])

        if let insert = database.prepare("""
            INSERT OR REPLACE INTO turns
            (id, source, tool, session, project, title, model, started, ended, prompt,
             api_calls, tool_calls, input, output, cache_read, cache_write, reasoning, subagent, active)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """) {
            for turn in parsed.turns {
                if let keepSince, turn.started < keepSince { continue }
                insert.run([
                    .text(turn.id), .text(path), .text(turn.tool.rawValue), .text(turn.session),
                    .text(turn.project), .text(turn.title), .text(turn.model),
                    .real(turn.started.timeIntervalSince1970), .real(turn.ended.timeIntervalSince1970),
                    .text(turn.prompt), .int(turn.apiCalls), .int(turn.toolCalls),
                    .int(turn.tokens.input), .int(turn.tokens.output), .int(turn.tokens.cacheRead),
                    .int(turn.tokens.cacheWrite), .int(turn.tokens.reasoning), .int(turn.isSubagent ? 1 : 0),
                    .real(turn.active),
                ])
            }
        }

        insertLimits(parsed.limits, source: path, keepSince: keepSince)

        database.run("INSERT OR REPLACE INTO sources (path, size, mtime) VALUES (?, ?, ?)",
                     [.text(path), .int(file.size), .real(file.mtime)])
    }

    private func insertLimits(_ samples: [LimitSample], source: String, keepSince: Date?) {
        guard let database, !samples.isEmpty,
              let insert = database.prepare(
                "INSERT INTO limits (source, tool, label, at, percent, resets) VALUES (?, ?, ?, ?, ?, ?)")
        else { return }
        for sample in samples {
            if let keepSince, sample.at < keepSince { continue }
            insert.run([
                .text(source), .text(sample.tool.rawValue), .text(sample.label),
                .real(sample.at.timeIntervalSince1970), .real(sample.percent),
                .real(sample.resetsAt?.timeIntervalSince1970),
            ])
        }
    }

    private func applyRetention(_ keepSince: Date?) {
        guard let database, let keepSince else { return }
        let cutoff = keepSince.timeIntervalSince1970
        database.run("DELETE FROM turns WHERE started < ?", [.real(cutoff)])
        database.run("DELETE FROM limits WHERE at < ?", [.real(cutoff)])
    }

    // MARK: - Живі виміри лімітів

    /// Ліміти Claude є лише в API, тож їхню історію пишемо самі, щойно
    /// приходять нові цифри.
    func recordLive(_ samples: [LimitSample]) {
        guard let database else { return }
        database.transaction {
            insertLimits(samples, source: "live", keepSince: nil)
        }
    }

    // MARK: - Читання

    func load() -> Snapshot {
        guard let database else { return Snapshot(turns: [], limits: []) }

        var turns: [TurnRecord] = []
        database.run("""
            SELECT id, tool, session, project, title, model, started, ended, prompt,
                   api_calls, tool_calls, input, output, cache_read, cache_write, reasoning, subagent, active
            FROM turns ORDER BY started
            """) { row in
            guard let id = row.text(0), let tool = row.text(1).flatMap(Tool.init(rawValue:)) else { return }
            turns.append(TurnRecord(
                id: id,
                tool: tool,
                session: row.text(2) ?? "",
                project: row.text(3) ?? "",
                title: row.text(4),
                model: row.text(5),
                started: Date(timeIntervalSince1970: row.real(6) ?? 0),
                ended: Date(timeIntervalSince1970: row.real(7) ?? 0),
                active: row.real(17) ?? 0,
                prompt: row.text(8),
                apiCalls: row.int(9),
                toolCalls: row.int(10),
                tokens: TokenUsage(input: row.int(11), output: row.int(12), cacheRead: row.int(13),
                                   cacheWrite: row.int(14), reasoning: row.int(15)),
                isSubagent: row.int(16) != 0
            ))
        }

        var limits: [LimitSample] = []
        database.run("SELECT tool, label, at, percent, resets FROM limits ORDER BY at") { row in
            guard let tool = row.text(0).flatMap(Tool.init(rawValue:)), let label = row.text(1) else { return }
            limits.append(LimitSample(
                tool: tool,
                label: label,
                at: Date(timeIntervalSince1970: row.real(2) ?? 0),
                percent: row.real(3) ?? 0,
                resetsAt: row.real(4).map { Date(timeIntervalSince1970: $0) }
            ))
        }
        return Snapshot(turns: turns, limits: limits)
    }

    // MARK: - Обслуговування

    /// Забуває, які файли вже прочитано, — наступний імпорт перечитає все.
    /// Самі записи лишаються, доки їх не замінить свіжий розбір.
    func forgetSources() {
        database?.execute("DELETE FROM sources")
    }

    func clearAll() {
        guard let database else { return }
        database.transaction {
            database.execute("DELETE FROM turns")
            database.execute("DELETE FROM limits")
            database.execute("DELETE FROM sources")
        }
        database.execute("VACUUM")
    }

    // MARK: - Пошук журналів

    struct LogFile: Sendable {
        let url: URL
        let tool: Tool
        let size: Int
        let mtime: Double
    }

    static func logFiles() -> [LogFile] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var result: [LogFile] = []
        result += files(under: home.appendingPathComponent(".claude/projects"), tool: .claude) {
            $0.pathExtension == "jsonl"
        }
        for root in [CodexPaths.sessionsRoot, CodexPaths.home.appendingPathComponent("archived_sessions")] {
            result += files(under: root, tool: .codex) {
                $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-")
            }
        }
        return result
    }

    private static func files(under root: URL, tool: Tool, matching: (URL) -> Bool) -> [LogFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [LogFile] = []
        for case let url as URL in enumerator where matching(url) {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            result.append(LogFile(
                url: url,
                tool: tool,
                size: values.fileSize ?? 0,
                mtime: values.contentModificationDate?.timeIntervalSince1970 ?? 0
            ))
        }
        return result
    }
}
