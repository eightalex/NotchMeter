import Foundation

/// Текстовий зріз стану — для перевірки, що джерела даних читаються правильно.
enum Diagnostics {
    static func stats(databasePath: String?) async {
        let database = databasePath.map { StatsDatabase(url: URL(fileURLWithPath: $0)) } ?? StatsDatabase()
        let importer = StatsImporter(database: database)
        let started = Date()
        let changed = await importer.importChanged(
            options: StatsImporter.Options(storePrompts: true, keepSince: nil)
        ) { _ in }
        let imported = Date()
        let snapshot = await importer.load()
        print(String(format: "перечитано файлів: %d за %.1f с, читання бази %.2f с",
                     changed, imported.timeIntervalSince(started), Date().timeIntervalSince(imported)))

        for tool in Tool.allCases {
            let turns = snapshot.turns.filter { $0.tool == tool }
            let main = turns.filter { !$0.isSubagent }
            let tokens = turns.reduce(TokenUsage()) { $0 + $1.tokens }
            let time = main.reduce(0) { $0 + $1.duration }
            print("\(tool.displayName): ходів \(main.count), субагентів \(turns.count - main.count), "
                  + "сесій \(Set(turns.map(\.session)).count), час \(Int(time / 3600)) год, "
                  + "токени in \(tokens.input) out \(tokens.output) cacheR \(tokens.cacheRead) cacheW \(tokens.cacheWrite)")
            if let first = turns.first, let last = turns.last {
                print("  з \(format(first.started)) по \(format(last.started))")
            }
            for turn in main.suffix(3) {
                print("  · \(format(turn.started)) \(Int(turn.duration)) с \(turn.projectName) [\(turn.model ?? "?")] "
                      + "\(turn.prompt.map { String($0.prefix(60)) } ?? "—")")
            }
        }
        print("вимірів лімітів: \(snapshot.limits.count)")
    }

    static func run() async {
        let providers: [any LimitProvider] = [CodexProvider(), ClaudeCodeProvider()]

        print("— Ліміти —")
        for provider in providers {
            let result = await provider.fetch()
            let plan = result.planName.map { " [\($0)]" } ?? ""
            print("\(result.displayName)\(plan)")
            if result.windows.isEmpty {
                print("  (нічого) \(result.error ?? "")")
            }
            for window in result.windows {
                let reset = window.resetDescription.map { window.hasReset ? " · \($0)" : " · скидається через \($0)" } ?? ""
                print(String(format: "  %-14@ %5.1f%%%@", window.label as NSString, window.currentPercent, reset))
            }
            if !result.windows.isEmpty, let error = result.error {
                print("  ! \(error)")
            }
            print("  знімок: \(format(result.capturedAt))")
        }

        print("\n— Сесії —")
        let scanners: [any SessionScanner] = [CodexSessionScanner(), ClaudeSessionScanner()]
        let sessions = scanners.flatMap { $0.scan() }
        if sessions.isEmpty {
            print("  немає відкритих сесій")
        }
        for session in sessions {
            let elapsed = session.elapsedDescription.map { " \($0)" } ?? ""
            let steps = session.steps.map { " \($0) кр." } ?? ""
            print("  [\(session.tool.rawValue)] \(session.state.rawValue)\(elapsed)\(steps) — \(session.title) · \(session.directory)")
        }
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
