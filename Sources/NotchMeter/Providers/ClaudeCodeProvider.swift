import Foundation

/// Ліміти Claude Code віддає той самий OAuth-ендпоінт, який використовує
/// команда `/usage`. Токен лежить у Keychain; якщо він протух, оновлюємо його
/// і повертаємо оновлену пару назад у Keychain, щоб Claude Code продовжив
/// працювати з тими самими даними.
actor ClaudeCodeProvider: LimitProvider {
    nonisolated let id = "claude"
    nonisolated let displayName = "Claude"
    nonisolated let refreshInterval: TimeInterval = 120

    /// Публічний client_id Claude Code — узятий із самого CLI.
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    private static let oauthBeta = "oauth-2025-04-20"

    /// Токен вважаємо простроченим трохи раніше за реальний строк, щоб не
    /// впертись у гонку між перевіркою і запитом.
    private static let expiryMargin: TimeInterval = 120

    private let session: URLSession
    private var keychainWriteFailed = false

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch() async -> ProviderUsage {
        do {
            let credentials = try KeychainStore.readCredentials()
            guard let oauth = credentials["claudeAiOauth"] as? [String: Any] else {
                return .failed(id: id, displayName: displayName, message: "Claude Code не авторизований")
            }

            let plan = oauth["subscriptionType"] as? String
            let token = try await validAccessToken(credentials: credentials, oauth: oauth)
            var usage = try await requestUsage(token: token, plan: plan)
            if keychainWriteFailed {
                usage.error = "токен оновлено, але не збережено в Keychain"
            }
            return usage
        } catch let error as ProviderError {
            if case .throttled(let until) = error {
                return .failed(id: id, displayName: displayName,
                               message: "забагато запитів, пауза", retryAfter: until)
            }
            return .failed(id: id, displayName: displayName,
                           message: error.errorDescription ?? "невідома помилка")
        } catch {
            return .failed(id: id, displayName: displayName,
                           message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Токен

    private func validAccessToken(credentials: [String: Any], oauth: [String: Any]) async throws -> String {
        guard let accessToken = oauth["accessToken"] as? String else {
            throw ProviderError.message("у Keychain немає access-токена")
        }

        let expiresAt = (oauth["expiresAt"] as? Double).map { $0 / 1000 } ?? 0
        if Date().timeIntervalSince1970 + Self.expiryMargin < expiresAt {
            return accessToken
        }

        guard let refreshToken = oauth["refreshToken"] as? String else {
            throw ProviderError.message("токен протух, а refresh-токена немає")
        }

        // Коли протух і refresh-токен, оновити його вже нічим — потрібен новий вхід.
        // Запис у Keychain оновлює сам Claude Code, тому досить запустити CLI.
        let refreshExpiresAt = (oauth["refreshTokenExpiresAt"] as? Double).map { $0 / 1000 } ?? .greatestFiniteMagnitude
        guard Date().timeIntervalSince1970 < refreshExpiresAt else {
            throw ProviderError.message("потрібен вхід: claude auth login")
        }

        return try await refresh(using: refreshToken, credentials: credentials, oauth: oauth)
    }

    private func refresh(using refreshToken: String,
                         credentials: [String: Any],
                         oauth: [String: Any]) async throws -> String {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            // 400 тут майже завжди означає відхилений refresh-токен.
            if code == 400 || code == 401 {
                throw ProviderError.message("потрібен вхід: claude auth login")
            }
            throw ProviderError.message("не вдалося оновити токен (HTTP \(code))")
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccess = payload["access_token"] as? String
        else {
            throw ProviderError.message("несподівана відповідь на оновлення токена")
        }

        store(newAccess: newAccess, payload: payload, credentials: credentials, oauth: oauth)
        return newAccess
    }

    /// Переписуємо лише гілку `claudeAiOauth`, решта запису (токени MCP-серверів
    /// і десктопної авторизації) лишається недоторканою.
    private func store(newAccess: String,
                       payload: [String: Any],
                       credentials: [String: Any],
                       oauth: [String: Any]) {
        var updatedOAuth = oauth
        updatedOAuth["accessToken"] = newAccess
        if let newRefresh = payload["refresh_token"] as? String {
            updatedOAuth["refreshToken"] = newRefresh
        }
        if let expiresIn = payload["expires_in"] as? Double {
            updatedOAuth["expiresAt"] = (Date().timeIntervalSince1970 + expiresIn) * 1000
        }

        var updated = credentials
        updated["claudeAiOauth"] = updatedOAuth

        do {
            try KeychainStore.writeCredentials(updated)
            keychainWriteFailed = false
        } catch {
            // Не критично: свіжий токен усе одно спрацює для цього циклу.
            keychainWriteFailed = true
        }
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
        guard http.statusCode == 200 else {
            throw ProviderError.message("API лімітів відповів HTTP \(http.statusCode)")
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.message("несподівана відповідь API лімітів")
        }

        let windows = Self.parseWindows(payload)
        return ProviderUsage(
            id: id,
            displayName: displayName,
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

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .throttled: return "забагато запитів, пауза"
        }
    }
}
