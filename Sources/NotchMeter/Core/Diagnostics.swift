import Foundation

/// Текстовий зріз стану — для перевірки, що джерела даних читаються правильно.
enum Diagnostics {
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
                let reset = window.resetDescription.map { " · скидається через \($0)" } ?? ""
                print(String(format: "  %-14@ %5.1f%%%@", window.label as NSString, window.usedPercent, reset))
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
