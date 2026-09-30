import Foundation
import Observation

/// Невеликі користувацькі налаштування. Дані самих лімітів кешуються тут же,
/// щоб після перезапуску одразу було що показати.
enum Settings {
    private static let defaults = UserDefaults.standard

    enum Key {
        static let refreshMultiplier = "refreshMultiplier"
        static let cachedUsage = "cachedUsage"
        static let leftTool = "leftTool"
        static let compactWindow = "compactWindow"
        static let externalBarHeight = "externalBarHeight"
        static let screenChoice = "screenChoice"
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

/// Яке вікно ліміту показувати в індикаторі біля вирізу.
enum CompactWindowChoice: String, CaseIterable {
    /// Найзаповненіше з усіх — до нього ви зараз найближче.
    case automatic
    case fiveHours
    case week

    var menuTitle: String {
        switch self {
        case .automatic: return "Автоматично (найзаповненіший)"
        case .fiveHours: return "5 годин"
        case .week: return "Тиждень"
        }
    }
}

/// На якому моніторі показувати виріз.
enum ScreenChoice: Hashable, Codable {
    /// Екран зі справжнім вирізом, а без нього — той, де рядок меню.
    case automatic
    /// Завжди той екран, де рядок меню («головний» у Системних параметрах).
    case main
    /// Конкретний монітор. Назву зберігаємо, щоб показати його в налаштуваннях,
    /// навіть коли він від'єднаний.
    case display(uuid: String, name: String)
}

/// Налаштування вигляду панелі. На відміну від `Settings`, спостережувані:
/// панель перемальовується одразу після вибору в меню.
@MainActor
@Observable
final class DisplayPreferences {
    static let shared = DisplayPreferences()

    /// Обабіч вирізу рівно два крила, тож і агентів тут рівно двоє. Третьому
    /// доведеться спершу знайти місце в розмітці.
    static let tools: [Tool] = [.codex, .claude]

    /// Інструмент ліворуч від вирізу; другий автоматично стає праворуч.
    var leftTool: Tool {
        didSet { UserDefaults.standard.set(leftTool.rawValue, forKey: Settings.Key.leftTool) }
    }

    var compactWindow: CompactWindowChoice {
        didSet { UserDefaults.standard.set(compactWindow.rawValue, forKey: Settings.Key.compactWindow) }
    }

    /// Висота вирізу на екрані без справжнього вирізу; 0 — як у рядка меню.
    var externalBarHeight: Double {
        didSet { UserDefaults.standard.set(externalBarHeight, forKey: Settings.Key.externalBarHeight) }
    }

    var screenChoice: ScreenChoice {
        didSet {
            guard let data = try? JSONEncoder().encode(screenChoice) else { return }
            UserDefaults.standard.set(data, forKey: Settings.Key.screenChoice)
        }
    }

    var rightTool: Tool {
        Self.tools.first { $0 != leftTool } ?? .claude
    }

    /// Інструменти в порядку зліва направо — так само їх перелічує й
    /// розгорнута панель.
    var orderedTools: [Tool] { [leftTool, rightTool] }

    private init() {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: Settings.Key.leftTool).flatMap(Tool.init(rawValue:))
        leftTool = stored.flatMap { Self.tools.contains($0) ? $0 : nil } ?? .codex
        compactWindow = defaults.string(forKey: Settings.Key.compactWindow)
            .flatMap(CompactWindowChoice.init(rawValue:)) ?? .automatic
        externalBarHeight = defaults.double(forKey: Settings.Key.externalBarHeight)
        screenChoice = defaults.data(forKey: Settings.Key.screenChoice)
            .flatMap { try? JSONDecoder().decode(ScreenChoice.self, from: $0) } ?? .automatic
    }
}
