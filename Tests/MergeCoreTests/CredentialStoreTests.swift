import XCTest
@testable import MergeCore

final class CredentialStoreTests: XCTestCase {
    private let tokens = OAuthTokens(
        accessToken: "access-SECRET",
        refreshToken: "refresh-SECRET",
        expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
        scope: "user-library-read"
    )

    func testInMemoryRoundTripAndDelete() throws {
        let store = InMemoryCredentialStore()
        XCTAssertNil(try store.load(for: .spotify))
        try store.save(tokens, for: .spotify)
        XCTAssertEqual(try store.load(for: .spotify), tokens)
        XCTAssertNil(try store.load(for: .appleMusic), "services are separate")
        try store.deleteAll()
        XCTAssertNil(try store.load(for: .spotify))
    }

    func testExpiry() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(OAuthTokens(accessToken: "a").isExpired(now: now), "no expiry = not expired")
        XCTAssertTrue(OAuthTokens(accessToken: "a", expiresAt: now.addingTimeInterval(30)).isExpired(now: now), "within leeway")
        XCTAssertFalse(OAuthTokens(accessToken: "a", expiresAt: now.addingTimeInterval(3_600)).isExpired(now: now))
    }

    func testRedactedDescriptionNeverContainsSecrets() {
        let text = tokens.redactedDescription
        XCTAssertFalse(text.contains("SECRET"), text)
    }

    func testSpotifyAuthUsesInjectedStore() async throws {
        let store = InMemoryCredentialStore()
        let auth = SpotifyAuthServiceImpl(credentials: store)
        var authorized = await auth.isAuthorized
        XCTAssertFalse(authorized)

        try auth.store(tokens)
        authorized = await auth.isAuthorized
        XCTAssertTrue(authorized)
        XCTAssertEqual(try store.load(for: .spotify)?.accessToken, "access-SECRET")

        // Expired without a refresh token -> must sign in again
        try auth.store(OAuthTokens(accessToken: "old", expiresAt: Date(timeIntervalSinceNow: -10)))
        authorized = await auth.isAuthorized
        XCTAssertFalse(authorized)

        try await auth.signOut()
        XCTAssertNil(try store.load(for: .spotify))
    }

    #if canImport(Security)
    func testKeychainRoundTrip() throws {
        // Isolated service name so the real app item is never touched
        let store = KeychainCredentialStore(serviceName: "com.benjaminsrussell.SpotifyAppleMerge.tests.\(UUID().uuidString)")
        do {
            try store.save(tokens, for: .spotify)
        } catch CredentialStoreError.keychain(let status, _) where status == errSecInteractionNotAllowed || status == errSecMissingEntitlement || status == errSecNotAvailable {
            throw XCTSkip("Keychain unavailable in this environment (OSStatus \(status))")
        }
        defer { try? store.delete(for: .spotify) }
        XCTAssertEqual(try store.load(for: .spotify), tokens)

        var updated = tokens
        updated.accessToken = "rotated"
        try store.save(updated, for: .spotify)  // update path
        XCTAssertEqual(try store.load(for: .spotify)?.accessToken, "rotated")

        try store.delete(for: .spotify)
        XCTAssertNil(try store.load(for: .spotify))
        try store.delete(for: .spotify)  // deleting a missing item is fine
    }
    #endif
}
