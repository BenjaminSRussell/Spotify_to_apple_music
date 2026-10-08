import Foundation
#if canImport(Security)
import Security
#endif

/// OAuth tokens for one service. Only ever persisted through a `CredentialStore` (#11).
public struct OAuthTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?
    public var scope: String?

    public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil, scope: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }

    /// True when the access token is expired, or will be within `leeway` seconds
    public func isExpired(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt = expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) <= leeway
    }

    /// Never print token values
    public var redactedDescription: String {
        "OAuthTokens(access: ***, refresh: \(refreshToken == nil ? "none" : "***"), expiresAt: \(expiresAt.map { "\($0)" } ?? "n/a"))"
    }
}

public enum CredentialStoreError: Error, Equatable, CustomStringConvertible {
    case keychain(status: Int32, operation: String)
    case corrupt(String)

    public var description: String {
        switch self {
        case .keychain(let status, let op): return "Keychain \(op) failed (OSStatus \(status))"
        case .corrupt(let s): return "Stored credentials unreadable: \(s)"
        }
    }
}

/// Where OAuth tokens live. Production uses the macOS Keychain; tests inject `InMemoryCredentialStore`.
/// There is deliberately **no file-backed implementation**: tokens are never written to disk in plaintext.
public protocol CredentialStore: Sendable {
    func save(_ tokens: OAuthTokens, for service: MusicService) throws
    func load(for service: MusicService) throws -> OAuthTokens?
    func delete(for service: MusicService) throws
}

public extension CredentialStore {
    /// Delete tokens for every service (CLI `merge-cli auth reset`)
    func deleteAll() throws {
        for service in [MusicService.spotify, .appleMusic] {
            try delete(for: service)
        }
    }
}

/// Process-local store for tests and for platforms without a Keychain. Nothing touches disk.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [MusicService: OAuthTokens] = [:]

    public init(_ initial: [MusicService: OAuthTokens] = [:]) {
        self.items = initial
    }

    public func save(_ tokens: OAuthTokens, for service: MusicService) throws {
        lock.lock(); defer { lock.unlock() }
        items[service] = tokens
    }

    public func load(for service: MusicService) throws -> OAuthTokens? {
        lock.lock(); defer { lock.unlock() }
        return items[service]
    }

    public func delete(for service: MusicService) throws {
        lock.lock(); defer { lock.unlock() }
        items[service] = nil
    }
}

#if canImport(Security)
/// macOS Keychain store: one generic-password item per service, JSON-encoded tokens as the secret.
/// Items are `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (not synced, not in backups).
public struct KeychainCredentialStore: CredentialStore {
    public static let defaultServiceName = "com.benjaminsrussell.SpotifyAppleMerge.oauth"
    public let serviceName: String

    public init(serviceName: String = KeychainCredentialStore.defaultServiceName) {
        self.serviceName = serviceName
    }

    private func baseQuery(_ service: MusicService) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: service.rawValue,
        ]
    }

    public func save(_ tokens: OAuthTokens, for service: MusicService) throws {
        let data = try JSONEncoder().encode(tokens)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(baseQuery(service) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(service)
            add.merge(attributes) { _, new in new }
            add[kSecAttrLabel as String] = "SpotifyAppleMerge \(service.rawValue) OAuth"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status: status, operation: "save") }
    }

    public func load(for service: MusicService) throws -> OAuthTokens? {
        var query = baseQuery(service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status: status, operation: "load") }
        guard let data = result as? Data else { throw CredentialStoreError.corrupt("no data") }
        do {
            return try JSONDecoder().decode(OAuthTokens.self, from: data)
        } catch {
            throw CredentialStoreError.corrupt("\(error)")
        }
    }

    public func delete(for service: MusicService) throws {
        let status = SecItemDelete(baseQuery(service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status: status, operation: "delete")
        }
    }
}
#endif

public enum CredentialStores {
    /// Keychain on Apple platforms; elsewhere an in-memory store (tokens last for the process only).
    public static func platformDefault() -> CredentialStore {
        #if canImport(Security)
        return KeychainCredentialStore()
        #else
        Log.warning("No Keychain on this platform: OAuth tokens are kept in memory only")
        return InMemoryCredentialStore()
        #endif
    }
}
