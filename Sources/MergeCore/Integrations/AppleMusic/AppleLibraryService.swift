import Foundation
#if canImport(MusicKit)
import MusicKit
#endif

public protocol AppleLibraryService: Sendable {
    func fetchLibrarySongs() async throws -> [AppleTrackRef]
    func fetchPlaylists() async throws -> [ApplePlaylistRef]
}

/// Apple Music library reader (#6).
///
/// Uses the Apple Music REST API (`/v1/me/library/...`, paginated by `next`) when a developer
/// token and a Music User Token are available. Otherwise, on macOS 14+, it falls back to
/// MusicKit's `MusicLibraryRequest` after `MusicAuthorization` is granted.
public final class AppleLibraryServiceImpl: AppleLibraryService {
    private let transport: HTTPTransport
    private let developerToken: TokenProvider?
    private let userToken: TokenProvider?
    private let baseURL: URL
    private let retryPolicy: RetryPolicy

    public init(
        transport: HTTPTransport = URLSessionTransport(),
        developerToken: TokenProvider? = nil,
        userToken: TokenProvider? = nil,
        baseURL: URL = URL(string: "https://api.music.apple.com")!,
        retryPolicy: RetryPolicy = RetryPolicy(maxAttempts: 5, baseDelay: 1.0),
        credentials: CredentialStore = CredentialStores.platformDefault(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.retryPolicy = retryPolicy
        if let developerToken {
            self.developerToken = developerToken
        } else if let token = environment["APPLE_MUSIC_DEVELOPER_TOKEN"], !token.isEmpty {
            self.developerToken = { token }
        } else {
            self.developerToken = nil
        }
        if let userToken {
            self.userToken = userToken
        } else if let stored = (try? credentials.load(for: .appleMusic))?.accessToken {
            self.userToken = { stored }
        } else {
            self.userToken = nil
        }
    }

    private var usesREST: Bool { developerToken != nil && userToken != nil }

    public func fetchLibrarySongs() async throws -> [AppleTrackRef] {
        if usesREST {
            let songs: [AppleAPISong] = try await paginate("/v1/me/library/songs?limit=100")
            return songs.map(\.ref)
        }
        #if canImport(MusicKit)
        if #available(macOS 14.0, iOS 16.0, *) {
            return try await MusicKitLibrary.songs()
        }
        #endif
        throw MergeError.authRequired(service: .appleMusic)
    }

    public func fetchPlaylists() async throws -> [ApplePlaylistRef] {
        if usesREST {
            struct Playlist: Decodable {
                struct Attributes: Decodable {
                    struct Description: Decodable { let standard: String? }
                    let name: String
                    let description: Description?
                }
                let id: String
                let attributes: Attributes
            }
            var result: [ApplePlaylistRef] = []
            for playlist in try await paginate("/v1/me/library/playlists?limit=100") as [Playlist] {
                let tracks: [AppleAPISong] = try await paginate("/v1/me/library/playlists/\(playlist.id)/tracks?limit=100")
                result.append(ApplePlaylistRef(
                    id: playlist.id,
                    name: playlist.attributes.name,
                    description: playlist.attributes.description?.standard,
                    trackRefs: tracks.map(\.ref)
                ))
            }
            return result
        }
        #if canImport(MusicKit)
        if #available(macOS 14.0, iOS 16.0, *) {
            return try await MusicKitLibrary.playlists()
        }
        #endif
        throw MergeError.authRequired(service: .appleMusic)
    }

    /// Follows Apple's relative `next` links ("/v1/me/library/songs?offset=100").
    private func paginate<Item: Decodable>(_ firstPath: String) async throws -> [Item] {
        guard let developerToken, let userToken else { throw MergeError.authRequired(service: .appleMusic) }
        var items: [Item] = []
        var nextPath: String? = firstPath
        while let path = nextPath, let url = URL(string: path, relativeTo: baseURL)?.absoluteURL {
            let transport = self.transport
            let data = try await retryPolicy.execute(
                operation: {
                    try await transport.getJSON(url, headers: [
                        "Authorization": "Bearer \(try await developerToken())",
                        "Music-User-Token": try await userToken()
                    ])
                },
                shouldRetry: { RetryPolicy.isRetryableError($0) }
            )
            let page = try JSONDecoder().decode(ApplePage<Item>.self, from: data)
            items += page.data
            nextPath = page.next
        }
        return items
    }
}

struct ApplePage<Item: Decodable>: Decodable {
    let data: [Item]
    let next: String?
}

/// Library song resource from the Apple Music API.
struct AppleAPISong: Decodable {
    struct Attributes: Decodable {
        struct PlayParams: Decodable { let catalogId: String? }
        let name: String
        let artistName: String
        let albumName: String?
        let durationInMillis: Int?
        let contentRating: String?
        let isrc: String?
        let playParams: PlayParams?
    }
    let id: String
    let attributes: Attributes

    var ref: AppleTrackRef {
        AppleTrackRef(
            // Prefer the catalog ID so the same song matches across libraries.
            id: attributes.playParams?.catalogId ?? id,
            name: attributes.name,
            artistName: attributes.artistName,
            albumName: attributes.albumName,
            durationMs: attributes.durationInMillis,
            isExplicit: attributes.contentRating.map { $0 == "explicit" },
            isrc: attributes.isrc
        )
    }
}

#if canImport(MusicKit)
/// Native MusicKit library access (macOS 14+), used when no REST tokens are configured.
@available(macOS 14.0, iOS 16.0, *)
enum MusicKitLibrary {
    static func songs() async throws -> [AppleTrackRef] {
        guard MusicAuthorization.currentStatus == .authorized else { throw MergeError.authRequired(service: .appleMusic) }
        var request = MusicLibraryRequest<Song>()
        request.limit = 100
        var batch: MusicItemCollection<Song>? = try await request.response().items
        var result: [AppleTrackRef] = []
        while let current = batch {
            result += current.map(ref(for:))
            batch = current.hasNextBatch ? try await current.nextBatch() : nil
        }
        return result
    }

    static func playlists() async throws -> [ApplePlaylistRef] {
        guard MusicAuthorization.currentStatus == .authorized else { throw MergeError.authRequired(service: .appleMusic) }
        let request = MusicLibraryRequest<Playlist>()
        var result: [ApplePlaylistRef] = []
        for playlist in try await request.response().items {
            let detailed = try await playlist.with([.tracks])
            let tracks = (detailed.tracks ?? []).map { track in
                AppleTrackRef(
                    id: track.id.rawValue,
                    name: track.title,
                    artistName: track.artistName,
                    albumName: track.albumTitle,
                    durationMs: track.duration.map { Int($0 * 1000) },
                    isExplicit: track.contentRating.map { $0 == .explicit },
                    isrc: track.isrc
                )
            }
            result.append(ApplePlaylistRef(
                id: playlist.id.rawValue,
                name: playlist.name,
                description: playlist.standardDescription,
                trackRefs: tracks
            ))
        }
        return result
    }

    private static func ref(for song: Song) -> AppleTrackRef {
        AppleTrackRef(
            id: song.id.rawValue,
            name: song.title,
            artistName: song.artistName,
            albumName: song.albumTitle,
            durationMs: song.duration.map { Int($0 * 1000) },
            isExplicit: song.contentRating.map { $0 == .explicit },
            isrc: song.isrc
        )
    }
}
#endif
