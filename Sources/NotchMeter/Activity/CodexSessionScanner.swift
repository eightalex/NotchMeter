import Foundation
import SQLite3

/// У Codex немає реєстру статусів, зате в логах кожен хід обрамлений парою
/// подій `task_started` / `task_complete`. Якщо остання з них — `task_started`,
/// агент зараз працює. Перелік самих тредів беремо з бази стану.
struct CodexSessionScanner: SessionScanner {
    let tool = "codex"

    /// Треди, яких не чіпали більше доби, до активних точно не належать.
    private static let threadHorizon: TimeInterval = 24 * 60 * 60
    /// Читати хвіст лога має сенс лише для нещодавно змінених файлів.
    private static let rolloutHorizon: TimeInterval = 30 * 60

    private let databaseURL: URL

    init(databaseURL: URL = CodexPaths.stateDatabase) {
        self.databaseURL = databaseURL
    }

    func scan() -> [AgentSession] {
        threads()
            .compactMap(session(for:))
            .sorted { $0.title < $1.title }
    }

    private func session(for thread: Thread) -> AgentSession? {
        let url = URL(fileURLWithPath: thread.rolloutPath)
        guard let modified = FileTail.modificationDate(of: url),
              Date().timeIntervalSince(modified) < Self.rolloutHorizon
        else { return nil }

        let turn = Self.currentTurn(in: url)
        return AgentSession(
            id: "codex-\(thread.id)",
            tool: tool,
            title: Self.shorten(thread.title),
            directory: thread.cwd.isEmpty ? "—" : (thread.cwd as NSString).lastPathComponent,
            state: turn.isRunning ? .working : .idle,
            since: turn.startedAt,
            steps: turn.isRunning ? turn.steps : nil
        )
    }

    struct Turn {
        var isRunning = false
        var startedAt: Date?
        var steps = 0
    }

    /// Ідемо з кінця лога: рахуємо завершені кроки, доки не впремося в межу ходу.
    static func currentTurn(in url: URL) -> Turn {
        var turn = Turn()
        var steps = 0

        for line in FileTail.lines(of: url, maxBytes: 64 * 1024) {
            if line.contains("\"item_completed\"") {
                steps += 1
                continue
            }
            if line.contains("\"task_complete\"") {
                return turn
            }
            if line.contains("\"task_started\"") {
                turn.isRunning = true
                turn.steps = steps
                turn.startedAt = timestamp(in: line)
                return turn
            }
        }
        return turn
    }

    private static func timestamp(in line: String) -> Date? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["timestamp"] as? String
        else { return nil }
        return ISO8601DateFormatter.codex.date(from: raw)
    }

    /// Заголовок треда — це перше повідомлення користувача, тож він буває
    /// багаторядковим і довгим.
    static func shorten(_ title: String, limit: Int = 42) -> String {
        let firstLine = title.split(whereSeparator: \.isNewline).first.map(String.init) ?? title
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Без назви" }
        return trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
    }

    // MARK: - Читання бази стану

    struct Thread {
        let id: String
        let rolloutPath: String
        let title: String
        let cwd: String
    }

    private func threads() -> [Thread] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }

        var handle: OpaquePointer?
        let uri = "file:\(databaseURL.path)?mode=ro"
        guard sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let database = handle
        else {
            if handle != nil { sqlite3_close(handle) }
            return []
        }
        defer { sqlite3_close(database) }

        let cutoff = Int64((Date().timeIntervalSince1970 - Self.threadHorizon) * 1000)
        let sql = """
        SELECT id, rollout_path, title, cwd
        FROM threads
        WHERE archived = 0
          AND COALESCE(updated_at_ms, updated_at * 1000) >= ?
        ORDER BY COALESCE(updated_at_ms, updated_at * 1000) DESC
        LIMIT 40
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let query = statement else {
            return []
        }
        defer { sqlite3_finalize(query) }
        sqlite3_bind_int64(query, 1, cutoff)

        var result: [Thread] = []
        while sqlite3_step(query) == SQLITE_ROW {
            guard let id = column(query, 0), let path = column(query, 1) else { continue }
            result.append(Thread(id: id, rolloutPath: path, title: column(query, 2) ?? "", cwd: column(query, 3) ?? ""))
        }
        return result
    }

    private func column(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }
}
