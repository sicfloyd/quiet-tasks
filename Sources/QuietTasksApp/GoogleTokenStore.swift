import Foundation
import Security
import Darwin

protocol TokenVault {
    func load() throws -> String?
    func save(_ token: String) throws
    func delete() throws
}

struct KeychainTokenVault: TokenVault {
    let service: String
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "google-refresh-token",
         kSecAttrSynchronizable as String: false]
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            // Status only: no token, request body, or Keychain item contents in errors.
            throw GoogleSyncError.apiError("Keychain operation failed (status \(status)). Unlock your login Keychain and try again.")
        }
    }
    func load() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty
        else { throw StorageError.invalidData }
        return token
    }
    func save(_ token: String) throws {
        guard !token.isEmpty else { throw StorageError.invalidData }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            try check(SecItemAdd(item as CFDictionary, nil))
        } else { try check(status) }
        guard try load() == token else { throw StorageError.invalidData }
    }
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
        guard try load() == nil else { throw StorageError.cleanupRequired }
    }
}

// This type is injectable for tests; legacy files are only read or deleted.
struct MigratingTokenStore {
    let vault: any TokenVault
    let legacyURLs: [URL]
    var migrationAllowed = true
    private struct LegacyToken: Decodable { let refreshToken: String }

    func load() throws -> String? {
        if !migrationAllowed {
            // A completed migration/disconnect must never resurrect a credential from a stale copy.
            try cleanup()
            return try vault.load()
        }
        let stored = try vault.load()
        var legacy: [String] = []
        for url in legacyURLs {
            if let data = try SafeFile.read(url, maximumSize: 64 * 1024) {
                guard let value = try? JSONDecoder().decode(LegacyToken.self, from: data),
                      !value.refreshToken.isEmpty else { throw StorageError.invalidData }
                legacy.append(value.refreshToken)
            }
        }
        // Never guess between credentials for different accounts.
        let values = Set(legacy + (stored.map { [$0] } ?? []))
        guard values.count <= 1 else { throw StorageError.legacyConflict }
        guard let token = stored ?? legacy.first else { return nil }
        if stored == nil { try vault.save(token) }
        guard try vault.load() == token else { throw StorageError.invalidData }
        try cleanup()
        return token
    }
    func save(_ token: String) throws {
        try vault.save(token)
        try cleanup()
    }
    func cleanup() throws {
        var failed = false
        for url in legacyURLs {
            do { try SafeFile.remove(url) } catch { failed = true }
        }
        if failed { throw StorageError.cleanupRequired }
    }
    func revocationCandidates() -> (tokens: Set<String>, complete: Bool) {
        // Disconnect must still revoke readable credentials when migration/cleanup cannot finish.
        var values = Set<String>()
        var complete = true
        do { if let token = try vault.load() { values.insert(token) } } catch { complete = false }
        for url in legacyURLs {
            do {
                if let data = try SafeFile.read(url, maximumSize: 64 * 1024) {
                    let value = try JSONDecoder().decode(LegacyToken.self, from: data)
                    guard !value.refreshToken.isEmpty else { throw StorageError.invalidData }
                    values.insert(value.refreshToken)
                }
            } catch { complete = false }
        }
        return (values, complete)
    }
    func delete() throws {
        // Attempt all cleanup even if one operation fails. Disconnect never migrates a token back.
        var failed = false
        do { try vault.delete() } catch { failed = true }
        do { try cleanup() } catch { failed = true }
        if failed { throw StorageError.cleanupRequired }
    }
}

enum GoogleTokenStore {
    static var legacyURLs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let realHome = URL(fileURLWithPath: NSHomeDirectoryForUser(NSUserName()) ?? home.path)
        var directories = [
            home.appendingPathComponent("Library/Application Support/QuietTasks"),
            realHome.appendingPathComponent("Library/Application Support/QuietTasks"),
            URL(fileURLWithPath: "/Users/Shared/QuietTasks")
        ]
        for id in ["group.ai.aifund.quiettasks", "group.com.rakeshutekar.quiettasksnative"] {
            directories.append(realHome.appendingPathComponent("Library/Group Containers/\(id)/QuietTasks"))
        }
        if let group = try? SharedFiles.store() { directories.append(group.directory) }
        var seen = Set<String>()
        return directories.map { $0.appendingPathComponent("google-token.json") }
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
    static var store: MigratingTokenStore {
        MigratingTokenStore(vault: KeychainTokenVault(service: (Bundle.main.bundleIdentifier ?? "QuietTasks") + ".GoogleOAuth"),
                            legacyURLs: legacyURLs)
    }
    private static func markMigrationComplete() throws {
        try SharedFiles.store().write(Data("1".utf8), name: "token-migration-complete")
    }
    static func saveRefreshToken(_ token: String) throws {
        try store.save(token)
        try markMigrationComplete()
    }
    static func loadRefreshToken() throws -> String? {
        var current = store
        current.migrationAllowed = try SharedFiles.store().read("token-migration-complete") == nil
        let token = try current.load()
        try markMigrationComplete()
        return token
    }
    static func deleteRefreshToken() throws {
        var failed = false
        // Persist the tombstone even if deletion fails, so later launches cannot reimport old files.
        do { try markMigrationComplete() } catch { failed = true }
        do { try store.delete() } catch { failed = true }
        if failed { throw StorageError.cleanupRequired }
    }
}
