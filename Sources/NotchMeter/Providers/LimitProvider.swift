import Foundation

/// Одне вікно ліміту — наприклад «5 год» або «Тиждень».
struct LimitWindow: Codable, Hashable, Identifiable {
    var id: String { label }

    let label: String
    let usedPercent: Double
    let resetsAt: Date?

    /// Людський опис часу до скидання: «2 год 14 хв», «12 хв», nil якщо дати немає.
    var resetDescription: String? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSinceNow
        guard remaining > 0 else { return "ось-ось" }
        return Self.duration(remaining)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return hours > 0 ? "\(days) д \(hours) год" : "\(days) д" }
        if hours > 0 { return minutes > 0 ? "\(hours) год \(minutes) хв" : "\(hours) год" }
        if minutes > 0 { return "\(minutes) хв" }
        return "\(total) с"
    }

    /// Коротка мітка для компактного вигляду: «5г», «7д». Виводимо з назви,
    /// а не зберігаємо окремо, — так кеш старого формату лишається сумісним.
    var shortLabel: String {
        if label == "Тиждень" || label.hasSuffix("/ тиж") { return "7д" }
        let parts = label.split(separator: " ")
        guard parts.count == 2, let value = Int(parts[0]) else { return label }
        switch parts[1] {
        case "тиж": return "\(value * 7)д"
        case "д": return "\(value)д"
        case "год": return "\(value)г"
        case "хв": return "\(value)хв"
        default: return label
        }
    }

    /// Назва вікна за його тривалістю у хвилинах (формат Codex).
    static func label(forWindowMinutes minutes: Int) -> String {
        switch minutes {
        case 300: return "5 год"
        case 10080: return "Тиждень"
        case let m where m % 10080 == 0: return "\(m / 10080) тиж"
        case let m where m % 1440 == 0: return "\(m / 1440) д"
        case let m where m % 60 == 0: return "\(m / 60) год"
        default: return "\(minutes) хв"
        }
    }
}

/// Стан квот одного інструменту.
struct ProviderUsage: Codable, Hashable, Identifiable {
    let id: String
    let displayName: String
    var windows: [LimitWindow]
    var planName: String?
    var capturedAt: Date
    var error: String?
    /// Коли сервер попросив зачекати (HTTP 429) — доки не звертатись.
    var retryAfter: Date?

    /// Найбільш заповнене вікно — до нього зараз найближче.
    var primaryWindow: LimitWindow? {
        windows.max { $0.usedPercent < $1.usedPercent }
    }

    /// Вікно для компактного вигляду. Якщо обраного вікна в інструмента немає
    /// (скажімо, план без 5-годинного ліміту), беремо найзаповненіше — мітка
    /// поруч однаково скаже, що саме показано.
    func window(for choice: CompactWindowChoice) -> LimitWindow? {
        switch choice {
        case .automatic:
            return primaryWindow
        case .fiveHours:
            return windows.first { $0.shortLabel == "5г" } ?? primaryWindow
        case .week:
            // Загальний тижневий ліміт важливіший за окремий для Opus.
            return windows.first { $0.label == "Тиждень" }
                ?? windows.first { $0.shortLabel == "7д" }
                ?? primaryWindow
        }
    }

    var isStale: Bool {
        Date().timeIntervalSince(capturedAt) > 30 * 60
    }

    static func failed(id: String, displayName: String, message: String,
                       retryAfter: Date? = nil) -> ProviderUsage {
        ProviderUsage(id: id, displayName: displayName, windows: [],
                      planName: nil, capturedAt: Date(), error: message, retryAfter: retryAfter)
    }
}

protocol LimitProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// Мінімальний інтервал між опитуваннями, секунди.
    var refreshInterval: TimeInterval { get }
    func fetch() async -> ProviderUsage
}
