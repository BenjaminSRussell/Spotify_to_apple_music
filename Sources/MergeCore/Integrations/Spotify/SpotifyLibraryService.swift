import Foundation

/// Protocol for Spotify library operations
public protocol SpotifyLibraryService: Sendable {
    func fetchSavedTracks() async throws -> [SpotifyTrackRef]
    func fetchPlaylists() async throws -> [SpotifyPlaylistRef]
    func fetchPlaylistTracks(playlistID: String) async throws -> [SpotifyTrackRef]
}

/// Spotify Web API library reader with `next`-link pagination and 429 backoff (#6).
public final class SpotifyLibraryServiceImpl: SpotifyLibraryService {
    private let transport: HTTPTransport
    private let token: TokenProvider
    private let baseURL: URL
    private let retryPolicy: RetryPolicy

    public init(
        transport: HTTPTransport = URLSessionTransport(),
        token: TokenProvider? = nil,
        baseURL: URL = URL(string: "https://api.spotify.com/v1")!,
        retryPolicy: RetryPolicy = RetryPolicy(maxAttempts: 5, baseDelay: 1.0)
    ) {
        self.transport = transport
        // Default: tokens from the Keychain, refreshed on demand.
        let auth = SpotifyAuthServiceImpl(transport: transport)
        self.token = token ?? { try await auth.validAccessToken() }
        self.baseURL = baseURL
        self.retryPolicy = retryPolicy
    }

    public func fetchSavedTracks() async throws -> [SpotifyTrackRef] {
        struct Item: Decodable { let track: SpotifyAPITrack? }
        let items: [Item] = try await paginate(url("me/tracks", limit: 50))
        return items.compactMap { $0.track?.ref }
    }

    public func fetchPlaylists() async throws -> [SpotifyPlaylistRef] {
        struct Playlist: Decodable {
            struct Owner: Decodable { let display_name: String?; let id: String? }
            let id: String
            let name: String
            let description: String?
            let owner: Owner?
        }
        let playlists: [Playlist] = try await paginate(url("me/playlists", limit: 50))
        var result: [SpotifyPlaylistRef] = []
        for playlist in playlists {
            let tracks = try await fetchPlaylistTracks(playlistID: playlist.id)
            result.append(SpotifyPlaylistRef(
                id: playlist.id,
                name: playlist.name,
                owner: playlist.owner?.display_name ?? playlist.owner?.id,
                description: playlist.description.flatMap { $0.isEmpty ? nil : $0 },
                trackRefs: tracks
            ))
        }
        return result
    }

    public func fetchPlaylistTracks(playlistID: String) async throws -> [SpotifyTrackRef] {
        struct Item: Decodable { let track: SpotifyAPITrack? }
        let items: [Item] = try await paginate(url("playlists/\(playlistID)/tracks", limit: 100))
        return items.compactMap { $0.track?.ref }
    }

    // MARK: - Paging

    private func url(_ path: String, limit: Int) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        return components.url!
    }

    private func paginate<Item: Decodable>(_ first: URL) async throws -> [Item] {
        var items: [Item] = []
        var next: URL? = first
        while let url = next {
            let transport = self.transport
            let token = self.token
            let data = try await retryPolicy.execute(
                operation: { try await transport.getJSON(url, headers: ["Authorization": "Bearer \(try await token())"]) },
                shouldRetry: { RetryPolicy.isRetryableError($0) }
            )
            let page = try JSONDecoder().decode(SpotifyPage<Item>.self, from: data)
            items += page.items
            next = page.next.flatMap(URL.init(string:))
        }
        return items
    }
}

/// Paging object (`items` + absolute `next` URL).
struct SpotifyPage<Item: Decodable>: Decodable {
    let items: [Item]
    let next: String?
}

/// Track object as returned by the Spotify Web API.
struct SpotifyAPITrack: Decodable {
    struct Artist: Decodable { let name: String }
    struct Album: Decodable { let name: String? }
    let id: String?
    let name: String
    let artists: [Artist]
    let album: Album?
    let duration_ms: Int?
    let explicit: Bool?
    let external_ids: [String: String]?
    let is_local: Bool?

    /// Local files and removed tracks have no ID and can't be migrated.
    var ref: SpotifyTrackRef? {
        guard let id, is_local != true else { return nil }
        return SpotifyTrackRef(
            id: id,
            name: name,
            artistNames: artists.map(\.name),
            albumName: album?.name,
            durationMs: duration_ms,
            isExplicit: explicit,
            isrc: external_ids?["isrc"]
        )
    }
}
