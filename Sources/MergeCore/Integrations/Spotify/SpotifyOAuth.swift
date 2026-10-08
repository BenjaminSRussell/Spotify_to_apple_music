import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Spotify app registration. Create an app at https://developer.spotify.com/dashboard and add
/// the redirect URI there. PKCE is used, so no client secret is needed or stored (#6).
public struct SpotifyOAuthConfig: Sendable, Equatable {
    public var clientID: String
    public var redirectURI: String
    public var scopes: [String]

    public static let defaultRedirectURI = "http://127.0.0.1:8888/callback"
    public static let defaultScopes = ["user-library-read", "playlist-read-private", "playlist-read-collaborative"]

    public init(clientID: String, redirectURI: String = SpotifyOAuthConfig.defaultRedirectURI, scopes: [String] = SpotifyOAuthConfig.defaultScopes) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
    }

    /// `SPOTIFY_CLIENT_ID` (required) and `SPOTIFY_REDIRECT_URI` (optional).
    public static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> SpotifyOAuthConfig? {
        guard let id = env["SPOTIFY_CLIENT_ID"], !id.isEmpty else { return nil }
        return SpotifyOAuthConfig(clientID: id, redirectURI: env["SPOTIFY_REDIRECT_URI"] ?? defaultRedirectURI)
    }
}

/// PKCE verifier/challenge pair (RFC 7636, S256).
public struct PKCEPair: Sendable, Equatable {
    public let verifier: String
    public let challenge: String

    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = PKCEPair.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public static func generate() -> PKCEPair {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return PKCEPair(verifier: String((0..<64).map { _ in alphabet.randomElement(using: &generator)! }))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public enum SpotifyOAuthError: Error, Equatable, LocalizedError {
    case notConfigured
    case stateMismatch
    case denied(String)
    case missingCode
    case invalidTokenResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "Set SPOTIFY_CLIENT_ID (see README → Spotify setup)."
        case .stateMismatch: return "OAuth state mismatch; start the login again."
        case .denied(let reason): return "Spotify authorization was denied: \(reason)"
        case .missingCode: return "The redirect URL has no authorization code."
        case .invalidTokenResponse: return "Spotify returned an unexpected token response."
        }
    }
}

/// Authorization Code + PKCE against accounts.spotify.com.
public struct SpotifyOAuthClient: Sendable {
    public let config: SpotifyOAuthConfig
    private let transport: HTTPTransport
    private let tokenURL: URL
    private let authorizeURL: URL

    public init(
        config: SpotifyOAuthConfig,
        transport: HTTPTransport = URLSessionTransport(),
        accountsBaseURL: URL = URL(string: "https://accounts.spotify.com")!
    ) {
        self.config = config
        self.transport = transport
        self.tokenURL = accountsBaseURL.appendingPathComponent("api/token")
        self.authorizeURL = accountsBaseURL.appendingPathComponent("authorize")
    }

    public func authorizationURL(state: String, pkce: PKCEPair) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge)
        ]
        return components.url!
    }

    /// Extract the authorization code from the redirect URL the browser landed on.
    public static func code(fromRedirect redirect: String, expectedState: String) throws -> String {
        guard let components = URLComponents(string: redirect.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SpotifyOAuthError.missingCode
        }
        let items = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        if let error = items["error"] { throw SpotifyOAuthError.denied(error) }
        guard items["state"] == expectedState else { throw SpotifyOAuthError.stateMismatch }
        guard let code = items["code"], !code.isEmpty else { throw SpotifyOAuthError.missingCode }
        return code
    }

    public func exchange(code: String, pkce: PKCEPair, now: Date = Date()) async throws -> OAuthTokens {
        try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI,
            "client_id": config.clientID,
            "code_verifier": pkce.verifier
        ], now: now, previousRefreshToken: nil)
    }

    public func refresh(_ tokens: OAuthTokens, now: Date = Date()) async throws -> OAuthTokens {
        guard let refreshToken = tokens.refreshToken else { throw MergeError.authRequired(service: .spotify) }
        return try await tokenRequest([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID
        ], now: now, previousRefreshToken: refreshToken)
    }

    private func tokenRequest(_ form: [String: String], now: Date, previousRefreshToken: String?) async throws -> OAuthTokens {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode(form).utf8)
        let data = try await transport.sendChecked(request)

        struct Response: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
            let scope: String?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw SpotifyOAuthError.invalidTokenResponse
        }
        return OAuthTokens(
            accessToken: response.access_token,
            // Spotify may omit refresh_token on refresh; keep the old one.
            refreshToken: response.refresh_token ?? previousRefreshToken,
            expiresAt: response.expires_in.map { now.addingTimeInterval($0) },
            scope: response.scope
        )
    }

    static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.keys.sorted().map { key in
            let value = form[key]!.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(key)=\(value)"
        }.joined(separator: "&")
    }
}
