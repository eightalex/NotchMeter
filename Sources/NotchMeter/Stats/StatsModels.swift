import Foundation

/// Один хід агента: від вашого запиту до останньої відповіді на нього.
/// Субагенти Claude записуються окремими ходами з `isSubagent` — їхні
/// токени рахуються, а час і кількість ходів ні: вони йдуть паралельно з
/// ходом, що їх запустив.
struct TurnRecord: Identifiable, Hashable, Sendable {
    let id: String
    let tool: Tool
    let session: String
    let project: String
    var title: String?
    let model: String?
    let started: Date
    let ended: Date
    /// Скільки агент реально працював — без довгих пауз усередині ходу.
    let active: TimeInterval
    let prompt: String?
    let apiCalls: Int
    let toolCalls: Int
    let tokens: TokenUsage
    let isSubagent: Bool

    var duration: TimeInterval { max(0, active) }

    /// Остання частина шляху — так проєкт упізнають найшвидше.
    var projectName: String {
        let name = (project as NSString).lastPathComponent
        return name.isEmpty ? "—" : name
    }
}

/// Токени за видами. `input` — без кешу (у Codex його віднімаємо, щоб
/// агенти рахувались однаково).
struct TokenUsage: Hashable, Sendable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    /// Частина `output`, витрачена на міркування, — окремо не додається.
    var reasoning = 0

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            reasoning: lhs.reasoning + rhs.reasoning
        )
    }

    static func - (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input - rhs.input,
            output: lhs.output - rhs.output,
            cacheRead: lhs.cacheRead - rhs.cacheRead,
            cacheWrite: lhs.cacheWrite - rhs.cacheWrite,
            reasoning: lhs.reasoning - rhs.reasoning
        )
    }

    var isNegative: Bool {
        input < 0 || output < 0 || cacheRead < 0 || cacheWrite < 0
    }
}

/// Значення ліміту в певний момент — з них малюється історія лімітів.
struct LimitSample: Hashable, Sendable {
    let tool: Tool
    let label: String
    let at: Date
    let percent: Double
    let resetsAt: Date?
}

/// Що вдалося видобути з одного файлу журналу агента.
struct ParsedLog: Sendable {
    var turns: [TurnRecord] = []
    var limits: [LimitSample] = []
}
