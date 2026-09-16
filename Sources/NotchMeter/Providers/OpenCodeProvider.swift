import Foundation

/// Заготовка під opencode.
///
/// OpenCode Zen не публікує API квот — усі ендпоінти виду `/zen/v1/billing`
/// віддають 404, тож показувати «ліміт» поки що нема з чого. Коли таке API
/// з'явиться (або коли вирішимо рахувати витрати з локальної бази
/// `~/.local/share/opencode/opencode.db`, де таблиця `session` уже містить
/// готові `cost` і `tokens_*`), достатньо буде дописати `fetch()` і додати
/// провайдера до `UsageStore.makeDefault()`.
struct OpenCodeProvider: LimitProvider {
    let id = "opencode"
    let displayName = "OpenCode"
    let refreshInterval: TimeInterval = 60

    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/opencode.db")
    }

    func fetch() async -> ProviderUsage {
        .failed(id: id, displayName: displayName, message: "ще не підтримується")
    }
}
