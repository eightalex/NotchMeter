import Foundation

/// Читання запису Keychain, у якому Claude Code тримає свої облікові дані.
///
/// Читаємо не через Security.framework, а тим самим `/usr/bin/security`, яким
/// користується сам Claude Code. Запис створює саме `security`, тож він завжди
/// серед довірених програм запису. NotchMeter же macOS упізнає за хешем
/// ad-hoc підпису: «Завжди дозволяти» злітало після кожної перезбірки і щоразу,
/// коли Claude Code перестворював запис при оновленні токена.
///
/// Писати в запис свідомо не вміємо: він належить Claude Code, і чужа зміна
/// ламає йому доступ (див. ClaudeCodeProvider).
enum KeychainStore {
    static let service = "Claude Code-credentials"

    enum KeychainError: LocalizedError {
        case notFound
        case malformed
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notFound: return "запис Claude Code не знайдено в Keychain"
            case .malformed: return "не вдалося розібрати запис Keychain"
            case .failed(let message): return "Keychain: \(message)"
            }
        }
    }

    static var account: String { NSUserName() }

    /// Код виходу `security`, коли запису немає (errSecItemNotFound).
    private static let itemNotFoundStatus: Int32 = 44

    /// Блокує потік до відповіді `security`. Тайм-аут навмисно не ставимо:
    /// якщо macOS усе ж спитає дозволу, опитування просто чекає на людину, а
    /// UsageStore не запустить друге, тож вікна не множитимуться.
    static func readCredentials() throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-a", account, "-w"]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw KeychainError.failed("не вдалося запустити security: \(error.localizedDescription)")
        }
        // Читаємо до завершення: інакше великий запис заб'є буфер каналу.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus != itemNotFoundStatus else { throw KeychainError.notFound }
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw KeychainError.failed(message?.isEmpty == false
                                       ? message!
                                       : "security завершився з кодом \(process.terminationStatus)")
        }

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { throw KeychainError.malformed }
        return dictionary
    }
}
