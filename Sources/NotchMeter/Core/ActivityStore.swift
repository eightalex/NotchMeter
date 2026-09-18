import Foundation
import Observation

/// Стежить за тим, які агенти зараз працюють. Джерела дешеві (локальні файли),
/// тому оновлюємось за подіями файлової системи і лише страхуємось таймером.
@MainActor
@Observable
final class ActivityStore {
    private(set) var sessions: [AgentSession] = []
    /// Оновлюється щосекунди, щоб лічильники тривалості ходу йшли рівно.
    private(set) var tick: Date = .now

    @ObservationIgnored private let scanners: [any SessionScanner]
    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isScanning = false
    @ObservationIgnored private var pendingScan = false

    init(scanners: [any SessionScanner]) {
        self.scanners = scanners
    }

    static func makeDefault() -> ActivityStore {
        ActivityStore(scanners: [CodexSessionScanner(), ClaudeSessionScanner()])
    }

    func start() {
        scan()

        let home = FileManager.default.homeDirectoryForCurrentUser
        watcher = DirectoryWatcher(paths: [
            home.appendingPathComponent(".claude/sessions").path,
            CodexPaths.sessionsRoot.path,
        ]) { [weak self] in
            Task { @MainActor in self?.scan() }
        }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.heartbeat() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        watcher = nil
    }

    private var heartbeatCount = 0

    private func heartbeat() {
        tick = .now
        heartbeatCount += 1
        // Повне сканування раз на три секунди — на випадок, якщо FSEvents щось проґавив.
        if heartbeatCount % 3 == 0 { scan() }
    }

    func scan() {
        guard !isScanning else {
            pendingScan = true
            return
        }
        isScanning = true

        let scanners = self.scanners
        Task.detached(priority: .utility) {
            let found = scanners.flatMap { $0.scan() }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.sessions = found
                self.isScanning = false
                if self.pendingScan {
                    self.pendingScan = false
                    self.scan()
                }
            }
        }
    }

    // MARK: - Зведення для UI

    func sessions(for tool: Tool) -> [AgentSession] {
        sessions.filter { $0.tool == tool }
    }

    func count(for tool: Tool, state: AgentState) -> Int {
        sessions.reduce(0) { $0 + (($1.tool == tool && $1.state == state) ? 1 : 0) }
    }

    var activeSessions: [AgentSession] {
        sessions
            .filter { $0.state != .idle }
            .sorted { lhs, rhs in
                if lhs.state != rhs.state { return lhs.state == .needsInput }
                return (lhs.since ?? .distantPast) < (rhs.since ?? .distantPast)
            }
    }

    var totalWorking: Int { sessions.reduce(0) { $0 + ($1.state == .working ? 1 : 0) } }
    var totalNeedsInput: Int { sessions.reduce(0) { $0 + ($1.state == .needsInput ? 1 : 0) } }
}
