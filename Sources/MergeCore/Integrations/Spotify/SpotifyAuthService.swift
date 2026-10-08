import Foundation
// import SpotifyAPI  // Uncomment when implementing

/// Protocol for Spotify authentication
public protocol SpotifyAuthService: Sendable {
    func authorize() async throws
    func refreshTokenIfNeeded() async throws
    var isAuthorized: Bool { get async }
    /// Remove stored tokens (sign out)
    func signOut() async throws
}

/// Spotify authentication implementation using SpotifyAPI
public final class SpotifyAuthServiceImpl: SpotifyAuthService {
    // TODO: Add SpotifyAPI instance
    // private let spotify: SpotifyAPI<AuthorizationCodeFlowManager>

    /// Token persistence: Keychain in production, injectable for tests (#11)
    private let credentials: CredentialStore

    public init(credentials: CredentialStore = CredentialStores.platformDefault()) {
        self.credentials = credentials
        // TODO: Initialize SpotifyAPI with credentials
        // self.spotify = SpotifyAPI(
        //     authorizationManager: AuthorizationCodeFlowManager(
        //         clientId: Configuration.spotifyClientID,
        //         clientSecret: Configuration.spotifyClientSecret
        //     )
        // )
    }

    public func authorize() async throws {
        // TODO: Implement OAuth flow
        //
        // 1. Generate authorization URL with required scopes:
        //    - user-library-read (for saved tracks)
        //    - playlist-read-private (for playlists)
        //    - user-read-private (for user info)
        //
        // 2. Open authorization URL in browser or present web view
        //
        // 3. Handle redirect with authorization code
        //
        // 4. Exchange code for access/refresh tokens:
        //    try await spotify.authorizationManager.requestAccessAndRefreshTokens(code: code)
        //
        // 5. Store tokens in Keychain for persistence: try store(tokens)
        //
        // Example:
        // let authURL = spotify.authorizationManager.makeAuthorizationURL(
        //     redirectURI: URL(string: "spotifymerge://callback")!,
        //     showDialog: true,
        //     scopes: [
        //         .userLibraryRead,
        //         .playlistReadPrivate,
        //         .userReadPrivate
        //     ]
        // )
        // // Open authURL, wait for callback, get code
        // try await spotify.authorizationManager.requestAccessAndRefreshTokens(code: code)

        Log.info("Spotify authorization not yet implemented")
        throw MergeError.authRequired(service: .spotify)
    }

    public func refreshTokenIfNeeded() async throws {
        // TODO: Implement token refresh
        //
        // 1. Check if current token is expired:
        //    guard spotify.authorizationManager.isAuthorized(for: [.userLibraryRead]) else {
        //        try await spotify.authorizationManager.refreshTokens()
        //        return
        //    }
        //
        // 2. Save refreshed tokens to Keychain

        Log.debug("Token refresh not yet implemented")
    }

    /// Authorized when stored tokens exist and are either unexpired or refreshable
    public var isAuthorized: Bool {
        get async {
            guard let tokens = try? credentials.load(for: .spotify) else { return false }
            return !tokens.isExpired() || tokens.refreshToken != nil
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

