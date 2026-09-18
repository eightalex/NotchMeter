import Foundation
import SQLite3

/// У Codex немає реєстру статусів, зате в логах кожен хід обрамлений парою
/// подій `task_started` / `task_complete`. Якщо остання з них — `task_started`,
/// агент зараз працює. Перелік самих тредів беремо з бази стану.
struct CodexSessionScanner: SessionScanner {
    let tool = Tool.codex

    /// Треди, яких не чіпали більше доби, до активних точно не належать.
    private static let threadHorizon: TimeInterval = 24 * 60 * 60
    /// Читати хвіст лога має сенс лише для нещодавно змінених файлів.
    private static let rolloutHorizon: TimeInterval = 30 * 60

    private let databaseURL: URL

    init(databaseURL: URL = CodexPaths.stateDatabase) {
        self.databaseURL = databaseURL
    }

    func scan() -> [AgentSession] {
        CodexStateDatabase.recentThreads(at: databaseURL, since: Date().addingTimeInterval(-Self.threadHorizon))
            .compactMap(session(for:))
            .sorted { $0.title < $1.title }
    }

    private func session(for thread: CodexStateDatabase.Thread) -> AgentSession? {
        let url = thread.rolloutURL
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

        /// Застосовує одну подію лога; мітку часу розбираємо лише для початку ходу.
        mutating func apply(_ event: RolloutEvent, timestamp: @autoclosure () -> Date?) {
            switch event {
            case .taskStarted:
                self = Turn(isRunning: true, startedAt: timestamp(), steps: 0)
            case .taskComplete:
                self = Turn()
            case .itemCompleted:
                if isRunning { steps += 1 }
            }
        }
    }

    enum RolloutEvent {
        case taskStarted, taskComplete, itemCompleted

        /// Шукаємо послідовність із неекранованими лапками: усередині тексту
        /// повідомлень чи виводу інструментів лапки завжди `\"`, тож згадка
        /// «task_started» у коді чи логах сюди не потрапить.
        init?(line: Data) {
            if line.range(of: Self.started) != nil { self = .taskStarted }
            else if line.range(of: Self.complete) != nil { self = .taskComplete }
            else if line.range(of: Self.item) != nil { self = .itemCompleted }
            else { return nil }
        }

        var isBoundary: Bool { self != .itemCompleted }

        private static let started = Data(#""payload":{"type":"task_started""#.utf8)
        private static let complete = Data(#""payload":{"type":"task_complete""#.utf8)
        private static let item = Data(#""payload":{"type":"item_completed""#.utf8)
    }

    static func currentTurn(in url: URL) -> Turn {
        RolloutTurnTracker.shared.turn(in: url)
    }

    static func timestamp(in line: Data) -> Date? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
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
}

/// Перелік тредів Codex з його бази стану. Логи лежать у каталогах за датою
/// *створення* сесії, тож продовжену через кілька днів сесію знайти можна
/// лише звідси.
enum CodexStateDatabase {
    struct Thread {
        let id: String
        let rolloutPath: String
        let title: String
        let cwd: String

        var rolloutURL: URL { URL(fileURLWithPath: rolloutPath) }
    }

    /// Треди, змінені не раніше за `since`, від найсвіжішого.
    static func recentThreads(at databaseURL: URL = CodexPaths.stateDatabase,
                              since: Date, limit: Int = 40) -> [Thread] {
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

        let sql = """
        SELECT id, rollout_path, title, cwd
        FROM threads
        WHERE archived = 0
          AND COALESCE(updated_at_ms, updated_at * 1000) >= ?
        ORDER BY COALESCE(updated_at_ms, updated_at * 1000) DESC
        LIMIT ?
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let query = statement else {
            return []
        }
        defer { sqlite3_finalize(query) }
        sqlite3_bind_int64(query, 1, Int64(since.timeIntervalSince1970 * 1000))
        sqlite3_bind_int64(query, 2, Int64(limit))

        var result: [Thread] = []
        while sqlite3_step(query) == SQLITE_ROW {
            guard let id = column(query, 0), let path = column(query, 1) else { continue }
            result.append(Thread(id: id, rolloutPath: path, title: column(query, 2) ?? "", cwd: column(query, 3) ?? ""))
        }
        return result
    }

    private static func column(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }
}

/// Пам'ятає для кожного лога, докуди його дочитано і в якому стані хід.
///
/// Хід Codex легко набирає мегабайти викликів інструментів після
/// `task_started`, тож «хвіст фіксованого розміру» маркер губить, і довга
/// задача виглядає простоєм. Натомість при першій зустрічі з файлом шукаємо
/// останню межу ходу з кінця — хоч би як далеко, — а далі дочитуємо лише
/// дописане. Сканування йде кожні кілька секунд, тож читати щоразу мегабайти
/// не годиться.
final class RolloutTurnTracker: @unchecked Sendable {
    static let shared = RolloutTurnTracker()

    private struct Entry {
        /// Байт одразу після останнього обробленого повного рядка.
        var offset: UInt64
        var turn: CodexSessionScanner.Turn
    }

    private var entries: [String: Entry] = [:]
    private let lock = NSLock()

    func turn(in url: URL) -> CodexSessionScanner.Turn {
        lock.lock()
        defer { lock.unlock() }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return .init() }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return .init() }

        var entry: Entry
        if let known = entries[url.path], known.offset <= size {
            entry = known
        } else {
            // Новий файл або його переписали коротшим — починаємо з останньої межі.
            entry = Entry(offset: Self.lastBoundary(in: handle, size: size), turn: .init())
        }

        guard size > entry.offset,
              (try? handle.seek(toOffset: entry.offset)) != nil,
              let data = try? handle.readToEnd()
        else {
            entries[url.path] = entry
            return entry.turn
        }

        // Останній рядок може бути ще недописаним — його візьмемо наступного разу.
        guard let lastNewline = data.lastIndex(of: 0x0A) else {
            entries[url.path] = entry
            return entry.turn
        }
        for line in data[data.startIndex...lastNewline].split(separator: 0x0A) {
            let line = Data(line)
            guard let event = CodexSessionScanner.RolloutEvent(line: line) else { continue }
            entry.turn.apply(event, timestamp: CodexSessionScanner.timestamp(in: line))
        }
        entry.offset += UInt64(data.distance(from: data.startIndex, to: lastNewline) + 1)

        entries[url.path] = entry
        return entry.turn
    }

    /// Зсув початку рядка з останньою межею ходу. Вікно подвоюється, доки межу
    /// не знайдено; без жодної межі — з початку файлу.
    private static func lastBoundary(in handle: FileHandle, size: UInt64) -> UInt64 {
        var window: UInt64 = 256 * 1024
        while true {
            let start = size > window ? size - window : 0
            guard (try? handle.seek(toOffset: start)) != nil,
                  let data = try? handle.read(upToCount: Int(size - start))
            else { return 0 }

            var lineEnd = data.endIndex
            while lineEnd > data.startIndex {
                let lineStart = data[data.startIndex..<lineEnd].lastIndex(of: 0x0A).map { $0 + 1 } ?? data.startIndex
                // Перший рядок вікна може бути обрізаним — довіряємо йому лише
                // тоді, коли вікно почалося з самого початку файлу.
                if lineStart == data.startIndex, start > 0 { break }
                if let event = CodexSessionScanner.RolloutEvent(line: Data(data[lineStart..<lineEnd])),
                   event.isBoundary {
                    return start + UInt64(data.distance(from: data.startIndex, to: lineStart))
                }
                lineEnd = lineStart > data.startIndex ? lineStart - 1 : data.startIndex
            }

            if start == 0 { return 0 }
            window *= 2
        }
    }
}
