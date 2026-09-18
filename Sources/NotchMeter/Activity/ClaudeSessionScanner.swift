import Foundation

/// Claude Code тримає по файлу на кожну живу сесію у `~/.claude/sessions`,
/// і сам же підтримує в них поле `status`. Це найточніше джерело — не треба
/// вгадувати активність за файловою активністю.
struct ClaudeSessionScanner: SessionScanner {
    let tool = Tool.claude

    private let directory: URL

    init(directory: URL = ClaudeSessionScanner.defaultDirectory) {
        self.directory = directory
    }

    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions")
    }

    func scan() -> [AgentSession] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .filter { $0.pathExtension == "json" }
            .compactMap(session(from:))
            .sorted { $0.title < $1.title }
    }

    private func session(from url: URL) -> AgentSession? {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = payload["pid"] as? Int32
        else { return nil }

        // Після аварійного завершення файл лишається на диску, тому перевіряємо,
        // що процес справді живий.
        guard ProcessProbe.isAlive(pid) else { return nil }

        let cwd = payload["cwd"] as? String ?? ""
        let name = payload["name"] as? String
        let sessionID = payload["sessionId"] as? String ?? String(pid)
        let state = Self.state(for: payload["status"] as? String)
        let since = (payload["statusUpdatedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }

        return AgentSession(
            id: "claude-\(pid)",
            tool: tool,
            title: name ?? String(sessionID.prefix(8)),
            directory: cwd.isEmpty ? "—" : (cwd as NSString).lastPathComponent,
            state: state,
            since: since,
            steps: nil
        )
    }

    /// Значення, які трапляються в реєстрі: інтерактивні сесії користуються
    /// `busy`/`idle`/`needs_input`, фонові агенти — `running`/`completed` тощо.
    static func state(for status: String?) -> AgentState {
        switch status {
        case "busy", "running", "thinking": return .working
        case "needs_input": return .needsInput
        default: return .idle
        }
    }
}

enum ProcessProbe {
    static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        // Процес існує, але належить іншому користувачеві — для нас теж «живий».
        return errno == EPERM
    }
}
