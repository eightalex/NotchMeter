import Foundation

/// Невеликі користувацькі налаштування. Дані самих лімітів кешуються тут же,
/// щоб після перезапуску одразу було що показати.
enum Settings {
    private static let defaults = UserDefaults.standard

    enum Key {
        static let refreshMultiplier = "refreshMultiplier"
        static let cachedUsage = "cachedUsage"
    }

    /// Множник до базових інтервалів провайдерів: 1 — як задумано, 2 — удвічі рідше.
    static var refreshMultiplier: Double {
        get {
            let value = defaults.double(forKey: Key.refreshMultiplier)
            return value > 0 ? value : 1
        }
        set { defaults.set(newValue, forKey: Key.refreshMultiplier) }
    }

    static func loadCachedUsage() -> [ProviderUsage] {
        guard let data = defaults.data(forKey: Key.cachedUsage),
              let usage = try? JSONDecoder().decode([ProviderUsage].self, from: data)
        else { return [] }
        return usage
    }

    static func saveCachedUsage(_ usage: [ProviderUsage]) {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        defaults.set(data, forKey: Key.cachedUsage)
    }
}
