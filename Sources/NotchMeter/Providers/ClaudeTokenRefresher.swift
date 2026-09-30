import Foundation

/// Коли токен Claude Code у Keychain протух, просимо сам Claude Code його
/// оновити: запускаємо у фоні `claude -p /usage`. Це локальна команда — до
/// моделі вона не звертається і квоту не витрачає, — але перед запитом
/// лімітів CLI штатно оновлює свій токен і сам записує його у свій запис.
///
/// Так NotchMeter лишається лише читачем: Keychain і OAuth-сесією керує
/// тільки Claude Code, а без цього дані застигали, поки ви працюєте лише в
/// десктопному застосунку, — той свій токен тримає окремо й цей запис не
/// оновлює.
actor ClaudeTokenRefresher {
    static let shared = ClaudeTokenRefresher()

    /// Не частіше: якщо оновити не вдалося, немає сенсу смикати CLI щоразу.
    private static let minimumGap: TimeInterval = 10 * 60
    private static let timeout: TimeInterval = 45

    private var lastAttempt: Date?

    /// PID-и запущених нами процесів: на час роботи CLI реєструється як
    /// звичайна сесія, і без цього біля вирізу блимала б фантомна крапка.
    nonisolated static let spawned = SpawnedProcesses()

    /// `true`, якщо CLI відпрацював і токен варто перечитати.
    func refresh() async -> Bool {
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < Self.minimumGap {
            return false
        }
        lastAttempt = Date()

        guard let cli = Self.locateCLI() else { return false }
        return await Self.run(cli)
    }

    /// Застосунок, запущений із Finder, не бачить PATH користувача — шукаємо
    /// CLI у типових місцях установлення.
    static func locateCLI() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/claude"),
            home.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func run(_ cli: URL) async -> Bool {
        let process = Process()
        process.executableURL = cli
        // Без збереження сесії та без MCP-серверів: нам потрібне лише
        // оновлення токена, а не слід у історії чи запуск ваших інтеграцій.
        process.arguments = ["-p", "/usage", "--no-session-persistence", "--strict-mcp-config"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // Якщо NotchMeter запустили з сесії Claude Code, її змінні
        // видавали б фоновий CLI за частину тієї сесії.
        var environment = ProcessInfo.processInfo.environment
        environment["CLAUDECODE"] = nil
        environment["CLAUDE_CODE_ENTRYPOINT"] = nil
        process.environment = environment

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                spawned.remove(finished.processIdentifier)
                continuation.resume(returning: finished.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
                return
            }
            // Процес міг завершитися ще до цього рядка — тоді обробник уже
            // відпрацював, і PID не має лишитися в наборі назавжди.
            spawned.insert(process.processIdentifier)
            if !process.isRunning { spawned.remove(process.processIdentifier) }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}

/// Потокобезпечний набір PID-ів: пишемо з обробника завершення процесу,
/// читаємо зі сканера сесій у фоновій задачі.
final class SpawnedProcesses: @unchecked Sendable {
    private let lock = NSLock()
    private var pids: Set<Int32> = []

    func insert(_ pid: Int32) {
        lock.lock(); defer { lock.unlock() }
        pids.insert(pid)
    }

    func remove(_ pid: Int32) {
        lock.lock(); defer { lock.unlock() }
        pids.remove(pid)
    }

    func contains(_ pid: Int32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return pids.contains(pid)
    }
}
