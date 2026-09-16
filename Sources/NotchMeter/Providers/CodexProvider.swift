import Foundation

/// Ліміти Codex читаються з локальних логів сесій — CLI записує туди знімок
/// `rate_limits`, який приходить у кожній відповіді API. Мережа не потрібна.
struct CodexProvider: LimitProvider {
    let id = "codex"
    let displayName = "Codex"
    let refreshInterval: TimeInterval = 20

    private let sessionsRoot: URL

    init(sessionsRoot: URL = CodexPaths.sessionsRoot) {
        self.sessionsRoot = sessionsRoot
    }

    func fetch() async -> ProviderUsage {
        guard let url = CodexPaths.latestRollout(in: sessionsRoot, daysBack: 3) else {
            return .failed(id: id, displayName: displayName, message: "немає сесій Codex")
        }
        guard let snapshot = Self.latestSnapshot(in: url) else {
            return .failed(id: id, displayName: displayName, message: "немає даних про ліміти")
        }
        return snapshot.usage(id: id, displayName: displayName)
    }

    /// Останній запис `token_count` у файлі — він несе актуальний `rate_limits`.
    static func latestSnapshot(in url: URL) -> TokenCountEvent? {
        let decoder = JSONDecoder()
        for line in FileTail.lines(of: url, maxBytes: 256 * 1024) {
            guard line.contains("\"token_count\""), let data = line.data(using: .utf8) else { continue }
            guard let event = try? decoder.decode(TokenCountEvent.self, from: data),
                  event.payload.type == "token_count",
                  event.payload.rateLimits != nil
            else { continue }
            return event
        }
        return nil
    }
}

// MARK: - Формат подій rollout-*.jsonl

struct TokenCountEvent: Decodable {
    struct Payload: Decodable {
        let type: String
        let rateLimits: RateLimits?

        enum CodingKeys: String, CodingKey {
            case type
            case rateLimits = "rate_limits"
        }
    }

    struct Window: Decodable {
        let usedPercent: Double
        let windowMinutes: Int?
        let resetsAt: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowMinutes = "window_minutes"
            case resetsAt = "resets_at"
        }

        func limitWindow(fallbackLabel: String) -> LimitWindow {
            let label = windowMinutes.map(LimitWindow.label(forWindowMinutes:)) ?? fallbackLabel
            let reset = resetsAt.map { Date(timeIntervalSince1970: $0) }
            return LimitWindow(label: label, usedPercent: usedPercent, resetsAt: reset)
        }
    }

    struct RateLimits: Decodable {
        let primary: Window?
        let secondary: Window?
        let planType: String?

        enum CodingKeys: String, CodingKey {
            case primary, secondary
            case planType = "plan_type"
        }
    }

    let timestamp: Date?
    let payload: Payload

    enum CodingKeys: String, CodingKey {
        case timestamp, payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        payload = try container.decode(Payload.self, forKey: .payload)
        if let raw = try? container.decode(String.self, forKey: .timestamp) {
            timestamp = ISO8601DateFormatter.codex.date(from: raw)
        } else {
            timestamp = nil
        }
    }

    func usage(id: String, displayName: String) -> ProviderUsage {
        var windows: [LimitWindow] = []
        if let primary = payload.rateLimits?.primary {
            windows.append(primary.limitWindow(fallbackLabel: "Сесія"))
        }
        if let secondary = payload.rateLimits?.secondary {
            windows.append(secondary.limitWindow(fallbackLabel: "Тиждень"))
        }
        return ProviderUsage(
            id: id,
            displayName: displayName,
            windows: windows,
            planName: payload.rateLimits?.planType,
            capturedAt: timestamp ?? Date(),
            error: windows.isEmpty ? "немає даних про ліміти" : nil
        )
    }
}

// MARK: - Розташування файлів Codex

enum CodexPaths {
    static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    static var sessionsRoot: URL {
        home.appendingPathComponent("sessions")
    }

    static var stateDatabase: URL {
        home.appendingPathComponent("state_5.sqlite")
    }

    /// Логи розкладені по `sessions/РРРР/ММ/ДД`, тож обходимо лише кілька
    /// останніх днів замість рекурсивного сканування всього архіву.
    static func latestRollout(in root: URL, daysBack: Int) -> URL? {
        var newest: (url: URL, date: Date)?
        for url in rollouts(in: root, daysBack: daysBack) {
            guard let date = FileTail.modificationDate(of: url) else { continue }
            if newest == nil || date > newest!.date {
                newest = (url, date)
            }
        }
        return newest?.url
    }

    static func rollouts(in root: URL, daysBack: Int) -> [URL] {
        let calendar = Calendar(identifier: .gregorian)
        let manager = FileManager.default
        var result: [URL] = []

        for offset in 0...max(0, daysBack) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            guard let year = parts.year, let month = parts.month, let dayOfMonth = parts.day else { continue }
            let directory = root
                .appendingPathComponent(String(format: "%04d", year))
                .appendingPathComponent(String(format: "%02d", month))
                .appendingPathComponent(String(format: "%02d", dayOfMonth))
            guard let entries = try? manager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            result.append(contentsOf: entries.filter { $0.pathExtension == "jsonl" })
        }
        return result
    }
}

extension ISO8601DateFormatter {
    /// Codex пише мітки часу з мілісекундами: `2026-09-16T19:50:06.019Z`.
    static let codex: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
