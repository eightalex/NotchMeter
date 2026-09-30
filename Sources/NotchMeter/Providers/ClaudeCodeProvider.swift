import Foundation

/// Ліміти Claude Code віддає той самий OAuth-ендпоінт, який використовує
/// команда `/usage`. Токен лежить у Keychain, і ми його лише читаємо.
///
/// Оновлювати його самим не можна: refresh-токен при оновленні ротується,
/// і запущені сесії Claude Code лишаються зі старим, а запис у чужий елемент
/// Keychain ламає самому Claude Code доступ до нього — macOS починає питати
/// пароль для `security` щоразу, коли CLI читає токен. Тому протухлий токен
/// просимо оновити сам Claude Code — див. `ClaudeTokenRefresher`.
actor ClaudeCodeProvider: LimitProvider {
    nonisolated let tool = Tool.claude
    nonisolated let refreshInterval: TimeInterval = 120

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let oauthBeta = "oauth-2025-04-20"

    /// Токен вважаємо простроченим трохи раніше за реальний строк, щоб не
    /// впертись у гонку між перевіркою і запитом.
    private static let expiryMargin: TimeInterval = 120

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch() async -> ProviderUsage {
        do {
            var oauth = try readOAuth()

            // Десктопний Claude тримає свій токен окремо, тож поки працюєте
            // лише в ньому, цей запис ніхто не оновлює. Просимо CLI.
            if isExpired(oauth), !isRefreshExpired(oauth), await ClaudeTokenRefresher.shared.refresh() {
                oauth = try readOAuth()
            }

            let plan = oauth["subscriptionType"] as? String
            let token = try validAccessToken(oauth: oauth)
            do {
                return try await requestUsage(token: token, plan: plan)
            } catch ProviderError.unauthorized {
                // Токен відкликали раніше строку — одна спроба через CLI.
                guard await ClaudeTokenRefresher.shared.refresh() else {
                    throw ProviderError.message("токен відкликано, а Claude Code не зміг його оновити")
                }
                let fresh = try readOAuth()
                return try await requestUsage(token: try validAccessToken(oauth: fresh), plan: plan)
            }
        } catch let error as ProviderError {
            if case .throttled(let until) = error {
                return .failed(tool: tool, message: "забагато запитів, пауза", retryAfter: until)
            }
            return .failed(tool: tool, message: error.errorDescription ?? "невідома помилка")
        } catch {
            return .failed(tool: tool, message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Токен

    private func readOAuth() throws -> [String: Any] {
        let credentials = try KeychainStore.readCredentials()
        guard let oauth = credentials["claudeAiOauth"] as? [String: Any] else {
            throw ProviderError.message("Claude Code не авторизований")
        }
        return oauth
    }

    private func isExpired(_ oauth: [String: Any]) -> Bool {
        let expiresAt = (oauth["expiresAt"] as? Double).map { $0 / 1000 } ?? 0
        return Date().timeIntervalSince1970 + Self.expiryMargin >= expiresAt
    }

    /// Коли протух і refresh-токен, сам Claude Code теж не оновиться —
    /// потрібен новий вхід.
    private func isRefreshExpired(_ oauth: [String: Any]) -> Bool {
        let refreshExpiresAt = (oauth["refreshTokenExpiresAt"] as? Double).map { $0 / 1000 } ?? .greatestFiniteMagnitude
        return Date().timeIntervalSince1970 >= refreshExpiresAt
    }

    private func validAccessToken(oauth: [String: Any]) throws -> String {
        guard let accessToken = oauth["accessToken"] as? String else {
            throw ProviderError.message("у Keychain немає access-токена")
        }
        guard isExpired(oauth) else { return accessToken }

        if isRefreshExpired(oauth) {
            throw ProviderError.message("потрібен вхід: claude auth login")
        }
        if ClaudeTokenRefresher.locateCLI() == nil {
            throw ProviderError.message("токен протух, а Claude Code CLI не знайдено")
        }
        throw ProviderError.message("токен протух, Claude Code не зміг його оновити")
    }

    // MARK: - Ліміти

    private func requestUsage(token: String, plan: String?) async throws -> ProviderUsage {
        var request = URLRequest(url: Self.usageURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.oauthBeta, forHTTPHeaderField: "anthropic-beta")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.message("немає відповіді від API")
        }
        if http.statusCode == 429 {
            // Сервер сам каже, скільки чекати; якщо ні — беремо п'ять хвилин.
            let seconds = (http.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)) ?? 300
            throw ProviderError.throttled(until: Date().addingTimeInterval(seconds))
        }
        if http.statusCode == 401 {
            throw ProviderError.unauthorized
        }
        guard http.statusCode == 200 else {
            throw ProviderError.message("API лімітів відповів HTTP \(http.statusCode)")
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.message("несподівана відповідь API лімітів")
        }

        let windows = Self.parseWindows(payload)
        return ProviderUsage(
            tool: tool,
            windows: windows,
            planName: plan,
            capturedAt: Date(),
            error: windows.isEmpty ? "API не повернув жодного вікна ліміту" : nil
        )
    }

    /// Набір вікон у відповіді відрізняється залежно від передплати, а самі
    /// поля історично звуться по-різному — тому розбираємо м'яко.
    static func parseWindows(_ payload: [String: Any]) -> [LimitWindow] {
        let known: [(key: String, label: String)] = [
            ("five_hour", "5 год"),
            ("seven_day", "Тиждень"),
            ("seven_day_opus", "Opus / тиж"),
            ("seven_day_oauth_apps", "Застосунки / тиж"),
        ]

        return known.compactMap { entry in
            guard let section = payload[entry.key] as? [String: Any] else { return nil }
            guard let used = doubleValue(section["utilization"]) ?? doubleValue(section["used_percentage"])
            else { return nil }
            return LimitWindow(label: entry.label, usedPercent: used, resetsAt: date(from: section["resets_at"]))
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private static func date(from value: Any?) -> Date? {
        if let seconds = doubleValue(value) {
            // Мітки приходять і в секундах, і в мілісекундах.
            return Date(timeIntervalSince1970: seconds > 3_000_000_000 ? seconds / 1000 : seconds)
        }
        if let text = value as? String {
            return ISO8601DateFormatter.codex.date(from: text) ?? ISO8601DateFormatter().date(from: text)
        }
        return nil
    }

    private static let userAgent = "NotchMeter/1.0 (macOS)"
}

enum ProviderError: LocalizedError {
    case message(String)
    case throttled(until: Date)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .throttled: return "забагато запитів, пауза"
        case .unauthorized: return "токен відкликано"
        }
    }
}
