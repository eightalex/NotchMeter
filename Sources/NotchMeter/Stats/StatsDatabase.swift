import Foundation
import SQLite3

/// Тонка обгортка над SQLite для бази статистики. Живе всередині
/// `StatsImporter` (актора), тож про потоки тут не думаємо.
final class StatsDatabase {
    private var handle: OpaquePointer?

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NotchMeter", isDirectory: true)
            .appendingPathComponent("stats.sqlite")
    }

    init?(url: URL = StatsDatabase.defaultURL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            if handle != nil { sqlite3_close(handle) }
            return nil
        }
        execute("PRAGMA journal_mode=WAL")
        execute("PRAGMA synchronous=NORMAL")
        migrate()
    }

    deinit {
        sqlite3_close(handle)
    }

    /// Версія розбору журналів. Якщо змінилось те, як записи видобуваються
    /// з журналів, — збільшуємо: база перебудується з журналів наново.
    /// Живі виміри лімітів Claude при цьому зберігаються.
    private static let schemaVersion = 2

    private var userVersion: Int {
        var version = 0
        run("PRAGMA user_version") { version = $0.int(0) }
        return version
    }

    private func migrate() {
        if userVersion != Self.schemaVersion {
            execute("DROP TABLE IF EXISTS turns")
            execute("DROP TABLE IF EXISTS sources")
            execute("DELETE FROM limits WHERE source <> 'live'")
            execute("PRAGMA user_version = \(Self.schemaVersion)")
        }
        execute("""
        CREATE TABLE IF NOT EXISTS turns(
            id TEXT PRIMARY KEY,
            source TEXT NOT NULL,
            tool TEXT NOT NULL,
            session TEXT NOT NULL,
            project TEXT NOT NULL,
            title TEXT,
            model TEXT,
            started REAL NOT NULL,
            ended REAL NOT NULL,
            prompt TEXT,
            api_calls INTEGER NOT NULL,
            tool_calls INTEGER NOT NULL,
            input INTEGER NOT NULL,
            output INTEGER NOT NULL,
            cache_read INTEGER NOT NULL,
            cache_write INTEGER NOT NULL,
            reasoning INTEGER NOT NULL,
            subagent INTEGER NOT NULL,
            active REAL NOT NULL DEFAULT 0
        )
        """)
        execute("CREATE INDEX IF NOT EXISTS turns_source ON turns(source)")
        execute("CREATE INDEX IF NOT EXISTS turns_started ON turns(started)")
        execute("""
        CREATE TABLE IF NOT EXISTS limits(
            source TEXT NOT NULL,
            tool TEXT NOT NULL,
            label TEXT NOT NULL,
            at REAL NOT NULL,
            percent REAL NOT NULL,
            resets REAL
        )
        """)
        execute("CREATE INDEX IF NOT EXISTS limits_source ON limits(source)")
        execute("CREATE INDEX IF NOT EXISTS limits_at ON limits(at)")
        execute("""
        CREATE TABLE IF NOT EXISTS sources(
            path TEXT PRIMARY KEY,
            size INTEGER NOT NULL,
            mtime REAL NOT NULL
        )
        """)
    }

    // MARK: - Виконання

    @discardableResult
    func execute(_ sql: String) -> Bool {
        sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK
    }

    func transaction(_ body: () -> Void) {
        execute("BEGIN IMMEDIATE")
        body()
        execute("COMMIT")
    }

    /// Виконує запит із параметрами; `row` викликається для кожного рядка результату.
    func run(_ sql: String, _ bindings: [Value] = [], row: ((Row) -> Void)? = nil) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        bind(bindings, to: statement)
        while sqlite3_step(statement) == SQLITE_ROW {
            row?(Row(statement: statement))
        }
    }

    /// Підготовлений запит для масової вставки.
    func prepare(_ sql: String) -> Statement? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        return Statement(raw: statement)
    }

    enum Value {
        case text(String?)
        case int(Int)
        case real(Double?)
    }

    final class Statement {
        fileprivate let raw: OpaquePointer

        fileprivate init(raw: OpaquePointer) {
            self.raw = raw
        }

        deinit {
            sqlite3_finalize(raw)
        }

        func run(_ bindings: [Value]) {
            sqlite3_reset(raw)
            sqlite3_clear_bindings(raw)
            StatsDatabase.bindValues(bindings, to: raw)
            sqlite3_step(raw)
        }
    }

    struct Row {
        fileprivate let statement: OpaquePointer

        func text(_ index: Int32) -> String? {
            guard let value = sqlite3_column_text(statement, index) else { return nil }
            return String(cString: value)
        }

        func int(_ index: Int32) -> Int {
            Int(sqlite3_column_int64(statement, index))
        }

        func real(_ index: Int32) -> Double? {
            sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_double(statement, index)
        }
    }

    private func bind(_ values: [Value], to statement: OpaquePointer) {
        Self.bindValues(values, to: statement)
    }

    /// SQLite має скопіювати рядок: Swift звільнить буфер одразу після виклику.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    fileprivate static func bindValues(_ values: [Value], to statement: OpaquePointer) {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .text(let text):
                if let text {
                    sqlite3_bind_text(statement, index, text, -1, transient)
                } else {
                    sqlite3_bind_null(statement, index)
                }
            case .int(let number):
                sqlite3_bind_int64(statement, index, Int64(number))
            case .real(let number):
                if let number {
                    sqlite3_bind_double(statement, index, number)
                } else {
                    sqlite3_bind_null(statement, index)
                }
            }
        }
    }
}
