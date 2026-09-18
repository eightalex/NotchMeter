import Foundation
import Security

/// Читання запису Keychain, у якому Claude Code тримає свої облікові дані.
/// Писати в нього свідомо не вміємо: запис належить Claude Code, і чужа
/// зміна ламає йому доступ (див. ClaudeCodeProvider).
enum KeychainStore {
    static let service = "Claude Code-credentials"

    enum KeychainError: LocalizedError {
        case notFound
        case malformed
        case status(OSStatus)

        var errorDescription: String? {
            switch self {
            case .notFound: return "запис Claude Code не знайдено в Keychain"
            case .malformed: return "не вдалося розібрати запис Keychain"
            case .status(let code):
                let message = SecCopyErrorMessageString(code, nil) as String? ?? "код \(code)"
                return "Keychain: \(message)"
            }
        }
    }

    static var account: String { NSUserName() }

    static func readCredentials() throws -> [String: Any] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw KeychainError.notFound }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = item as? Data,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { throw KeychainError.malformed }
        return dictionary
    }
}
