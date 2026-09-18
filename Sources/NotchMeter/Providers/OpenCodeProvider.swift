import Foundation

/// Заготовка під opencode — поки що не провайдер.
///
/// OpenCode Zen не публікує API квот — усі ендпоінти виду `/zen/v1/billing`
/// віддають 404, тож показувати «ліміт» поки що нема з чого. Коли таке API
/// з'явиться (або коли вирішимо рахувати витрати з локальної бази
/// `~/.local/share/opencode/opencode.db`, де таблиця `session` уже містить
/// готові `cost` і `tokens_*`), треба буде:
///
/// 1. додати `case opencode` у `Tool` — компілятор покаже, що ще доповнити;
/// 2. підписати цю структуру під `LimitProvider` і дописати `fetch()`;
/// 3. додати провайдера до `UsageStore.makeDefault()`;
/// 4. вирішити, як третій агент уживається з двома крилами біля вирізу —
///    `DisplayPreferences` зараз розрахований рівно на пару.
struct OpenCodeProvider {
    let refreshInterval: TimeInterval = 60

    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/opencode.db")
    }
}
