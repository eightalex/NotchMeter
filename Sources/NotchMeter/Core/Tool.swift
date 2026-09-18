import AppKit

/// Агент, за яким стежить застосунок. Усе, що відрізняє агентів у
/// інтерфейсі, живе тут: новий `case` змусить компілятор показати кожне
/// місце, яке треба доповнити, замість того щоб агент тихо видавав себе за
/// іншого.
///
/// Сирі значення — стабільні ідентифікатори: під ними лежать кеш лімітів і
/// налаштування розташування, тож міняти їх не можна.
enum Tool: String, CaseIterable, Codable, Sendable {
    case codex
    case claude

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        }
    }

    /// Двобуквена мітка для тісних місць біля вирізу.
    var shortName: String {
        switch self {
        case .codex: return "CX"
        case .claude: return "CC"
        }
    }

    /// Фірмові акценти: Claude — помаранчевий, Codex — синій.
    var accent: NSColor {
        switch self {
        case .codex: return NSColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 1)
        case .claude: return NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)
        }
    }
}
