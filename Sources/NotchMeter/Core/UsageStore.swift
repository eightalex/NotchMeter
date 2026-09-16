import Foundation
import Observation

/// Опитує провайдерів квот і тримає останній відомий стан.
@MainActor
@Observable
final class UsageStore {
    private(set) var usage: [ProviderUsage] = []
    private(set) var lastUpdated: Date?

    @ObservationIgnored private let providers: [any LimitProvider]
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var lastAttempt: [String: Date] = [:]
    @ObservationIgnored private var pausedUntil: [String: Date] = [:]

    /// Панель просить оновлення щоразу, коли з'являється на очі, — без цієї
    /// паузи кілька наведень поспіль вичерпують ліміт запитів до API.
    private static let onDemandGap: TimeInterval = 20

    init(providers: [any LimitProvider]) {
        self.providers = providers
        usage = Settings.loadCachedUsage()
    }

    static func makeDefault() -> UsageStore {
        // OpenCodeProvider свідомо не підключений: у Zen поки немає API квот.
        UsageStore(providers: [CodexProvider(), ClaudeCodeProvider()])
    }

    func start() {
        stop()
        for provider in providers {
            refresh(provider, force: true)
            let interval = provider.refreshInterval * Settings.refreshMultiplier
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh(provider, force: true) }
            }
            timer.tolerance = interval * 0.2
            timers.append(timer)
        }
    }

    func stop() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
    }

    /// `force` — для пункту меню «Оновити зараз»: там чекати не треба.
    func refreshAll(force: Bool = false) {
        for provider in providers {
            refresh(provider, force: force)
        }
    }

    private func refresh(_ provider: any LimitProvider, force: Bool = false) {
        guard !inFlight.contains(provider.id) else { return }

        if let until = pausedUntil[provider.id], Date() < until, !force { return }
        if !force, let last = lastAttempt[provider.id],
           Date().timeIntervalSince(last) < Self.onDemandGap { return }

        lastAttempt[provider.id] = Date()
        inFlight.insert(provider.id)

        Task { [weak self] in
            let result = await provider.fetch()
            await MainActor.run {
                guard let self else { return }
                self.inFlight.remove(provider.id)
                self.apply(result)
            }
        }
    }

    /// Невдале опитування не має стирати з екрана те, що ми вже знаємо, —
    /// лишаємо старі цифри і лише позначаємо помилку.
    private func apply(_ result: ProviderUsage) {
        if let until = result.retryAfter {
            pausedUntil[result.id] = until
        } else {
            pausedUntil[result.id] = nil
        }

        var merged = result
        if result.windows.isEmpty,
           let previous = usage.first(where: { $0.id == result.id }),
           !previous.windows.isEmpty {
            merged.windows = previous.windows
            merged.planName = previous.planName ?? result.planName
            merged.capturedAt = previous.capturedAt
        }

        if let index = usage.firstIndex(where: { $0.id == merged.id }) {
            usage[index] = merged
        } else {
            usage.append(merged)
        }
        // Порядок у панелі має збігатися з порядком крил біля вирізу.
        // Сортуємо щоразу: кеш із попередніх версій міг зберегтися в іншому порядку.
        let order = providers.map(\.id)
        usage.sort { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }

        lastUpdated = Date()
        Settings.saveCachedUsage(usage)
    }

    func usage(for id: String) -> ProviderUsage? {
        usage.first { $0.id == id }
    }
}
