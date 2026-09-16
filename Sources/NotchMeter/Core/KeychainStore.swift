import Foundation
import Security

/// Доступ до запису Keychain, у якому Claude Code тримає свої облікові дані.
/// Запис містить не лише OAuth підписки, а й токени MCP-серверів, тому при
/// оновленні ми переписуємо словник цілком, змінюючи тільки потрібну гілку.
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

    static func writeCredentials(_ credentials: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: credentials, options: [])
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }
}
