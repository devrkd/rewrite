import Foundation
import Security

/// Credential storage for Fluent.
///
/// TESTING ONLY: `useKeychain` is set to `false` so credentials are persisted to a
/// plain file on disk instead of the macOS Keychain. This avoids the repeated
/// "Fluent wants to use your confidential information" password prompt that
/// shows up on every app restart while the binary is unsigned/ad-hoc-signed
/// during development (each rebuild is treated as a different app by Keychain
/// ACLs).
///
/// TODO: flip `useKeychain` back to `true` before shipping so credentials go
/// back through Security.framework (Keychain) instead of a plaintext file.
enum KeychainStore {

    private static let useKeychain = false

    private static let service = "com.fluent.app"

    // MARK: - Save

    static func save(key: String, account: String) throws {
        if useKeychain {
            try saveToKeychain(key: key, account: account)
        } else {
            try TempFileStore.save(key: key, account: account)
        }
    }

    // MARK: - Load

    static func load(account: String) -> String? {
        useKeychain ? loadFromKeychain(account: account) : TempFileStore.load(account: account)
    }

    // MARK: - Delete

    static func delete(account: String) {
        if useKeychain {
            deleteFromKeychain(account: account)
        } else {
            TempFileStore.delete(account: account)
        }
    }

    static func hasKey(account: String) -> Bool {
        load(account: account) != nil
    }

    // MARK: - Keychain backend (production)

    private static func saveToKeychain(key: String, account: String) throws {
        let data = key.data(using: .utf8)!
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  account,
        ]

        // Try update first; fall back to add if the item doesn't exist yet.
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.saveFailed(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.saveFailed(updateStatus)
        }
    }

    private static func loadFromKeychain(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  account,
            kSecReturnData:   true,
            kSecMatchLimit:   kSecMatchLimitOne,
        ]
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    private static func deleteFromKeychain(account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        if case .saveFailed(let code) = self {
            return "Keychain error \(code). Try again or check Keychain Access."
        }
        return nil
    }
}

// MARK: - Temp file backend (testing only, NOT secure)

/// Stores credentials as plaintext JSON in the system temp directory.
/// This intentionally trades security for convenience during development —
/// do not ship this backend.
private enum TempFileStore {

    private static let fileURL: URL = {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("com.fluent.app", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("credentials.json")
    }()

    private static func readAll() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    private static func writeAll(_ dict: [String: String]) throws {
        let data = try JSONEncoder().encode(dict)
        try data.write(to: fileURL, options: .atomic)
    }

    static func save(key: String, account: String) throws {
        var all = readAll()
        all[account] = key
        try writeAll(all)
    }

    static func load(account: String) -> String? {
        readAll()[account]
    }

    static func delete(account: String) {
        var all = readAll()
        all.removeValue(forKey: account)
        try? writeAll(all)
    }
}
