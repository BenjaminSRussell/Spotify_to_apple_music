import Foundation

/// Protocol for Spotify authentication
public protocol SpotifyAuthService: Sendable {
    func authorize() async throws
    func refreshTokenIfNeeded() async throws
    var isAuthorized: Bool { get async }
    /// Remove stored tokens (sign out)
    func signOut() async throws
    /// A non-expired access token, refreshing (and persisting) it first if needed.
    func validAccessToken() async throws -> String
}

/// Shows the authorization URL and returns the redirect URL the user landed on.
/// The CLI prints the URL and reads the pasted redirect; the app can use a web view.
public typealias AuthorizationPrompt = @Sendable (_ authorizationURL: URL) async throws -> String

/// Spotify Authorization Code + PKCE flow with Keychain-backed tokens (#6, #11).
public final class SpotifyAuthServiceImpl: SpotifyAuthService {
    /// Token persistence: Keychain in production, injectable for tests (#11)
    private let credentials: CredentialStore
    private let client: SpotifyOAuthClient?
    private let prompt: AuthorizationPrompt?
    private let clock: @Sendable () -> Date

    public init(
        credentials: CredentialStore = CredentialStores.platformDefault(),
        config: SpotifyOAuthConfig? = SpotifyOAuthConfig.fromEnvironment(),
        transport: HTTPTransport = URLSessionTransport(),
        prompt: AuthorizationPrompt? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.client = config.map { SpotifyOAuthClient(config: $0, transport: transport) }
        self.prompt = prompt
        self.clock = clock
    }

    public func authorize() async throws {
        guard let client else { throw SpotifyOAuthError.notConfigured }
        guard let prompt else {
            Log.info("Run `merge-cli auth login --spotify` to sign in to Spotify")
            throw MergeError.authRequired(service: .spotify)
        }
        let pkce = PKCEPair.generate()
        let state = UUID().uuidString
        let redirect = try await prompt(client.authorizationURL(state: state, pkce: pkce))
        let code = try SpotifyOAuthClient.code(fromRedirect: redirect, expectedState: state)
        try store(try await client.exchange(code: code, pkce: pkce, now: clock()))
    }

    public func refreshTokenIfNeeded() async throws {
        _ = try await validAccessToken()
    }

    public func validAccessToken() async throws -> String {
        guard let tokens = try credentials.load(for: .spotify) else {
            throw MergeError.authRequired(service: .spotify)
        }
        guard tokens.isExpired(now: clock()) else { return tokens.accessToken }
        guard let client else { throw SpotifyOAuthError.notConfigured }
        let refreshed = try await client.refresh(tokens, now: clock())
        try store(refreshed)
        return refreshed.accessToken
    }

    /// Authorized when stored tokens exist and are either unexpired or refreshable
    public var isAuthorized: Bool {
        get async {
            guard let tokens = try? credentials.load(for: .spotify) else { return false }
            return !tokens.isExpired(now: clock()) || tokens.refreshToken != nil
        }
    }

    /// Persist tokens from the OAuth exchange / refresh (Keychain via `CredentialStore`)
    public func store(_ tokens: OAuthTokens) throws {
        try credentials.save(tokens, for: .spotify)
        Log.info("Stored Spotify credentials: \(tokens.redactedDescription)")
    }

    public func signOut() async throws {
        try credentials.delete(for: .spotify)
    }
}
