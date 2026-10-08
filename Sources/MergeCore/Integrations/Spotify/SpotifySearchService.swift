import Foundation

/// Protocol for Spotify search operations
public protocol SpotifySearchService: Sendable {
    func search(query: String, limit: Int) async throws -> [SpotifyTrackRef]
}

/// Spotify Web API track search (`GET /v1/search?type=track`) (#7).
public final class SpotifySearchServiceImpl: SpotifySearchService {
    private let transport: HTTPTransport
    private let token: TokenProvider?
    private let baseURL: URL

    /// - Parameter token: OAuth access token provider. Without one, search returns no results.
    public init(
        transport: HTTPTransport = URLSessionTransport(),
        token: TokenProvider? = nil,
        baseURL: URL = URL(string: "https://api.spotify.com/v1")!
    ) {
        self.transport = transport
        self.token = token
        self.baseURL = baseURL
    }

    public func search(query: String, limit: Int = 10) async throws -> [SpotifyTrackRef] {
        guard let token else {
            Log.debug("Spotify search skipped: no access token configured")
            return []
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))
        ]
        let data = try await transport.getJSON(components.url!, headers: ["Authorization": "Bearer \(try await token())"])
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> [SpotifyTrackRef] {
        struct Response: Decodable {
            struct Tracks: Decodable { let items: [SpotifyAPITrack] }
            let tracks: Tracks
        }
        return try JSONDecoder().decode(Response.self, from: data).tracks.items.compactMap(\.ref)
    }
}
