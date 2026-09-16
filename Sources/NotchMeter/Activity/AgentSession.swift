import Foundation

enum AgentState: String, Codable {
    /// Агент зараз виконує хід.
    case working
    /// Агент зупинився і чекає на відповідь людини.
    case needsInput
    /// Сесія відкрита, але нічого не робить.
    case idle
}

struct AgentSession: Identifiable, Hashable {
    let id: String
    let tool: String
    let title: String
    let directory: String
    let state: AgentState
    /// Коли почався поточний стан — з цього рахуємо тривалість ходу.
    let since: Date?
    /// Кроків, виконаних у поточному ході (доступно для Codex).
    let steps: Int?

    var elapsedDescription: String? {
        guard let since else { return nil }
        let interval = Date().timeIntervalSince(since)
        guard interval >= 0 else { return nil }
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

protocol SessionScanner: Sendable {
    var tool: String { get }
    func scan() -> [AgentSession]
}
