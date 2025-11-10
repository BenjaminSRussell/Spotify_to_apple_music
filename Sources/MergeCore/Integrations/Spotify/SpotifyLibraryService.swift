import Foundation
// import SpotifyAPI  // Uncomment when implementing

/// Protocol for Spotify library operations
public protocol SpotifyLibraryService: Sendable {
    func fetchSavedTracks() async throws -> [SpotifyTrackRef]
    func fetchPlaylists() async throws -> [SpotifyPlaylistRef]
    func fetchPlaylistTracks(playlistID: String) async throws -> [SpotifyTrackRef]
}

/// Spotify library service implementation using SpotifyAPI
public final class SpotifyLibraryServiceImpl: SpotifyLibraryService {
    // TODO: Inject SpotifyAPI instance
    // private let spotify: SpotifyAPI<AuthorizationCodeFlowManager>

    public init() {
        // TODO: Receive spotify instance from auth service
    }

    public func fetchSavedTracks() async throws -> [SpotifyTrackRef] {
        // TODO: Implement pagination through user's saved tracks
        //
        // var allTracks: [SpotifyTrackRef] = []
        // var offset = 0
        // let limit = 50  // Spotify API max
        //
        // while true {
        //     let page = try await spotify.currentUserSavedTracks(
        //         offset: offset,
        //         limit: limit
        //     )
        //
        //     let tracks = page.items.map { savedTrack in
        //         mapToSpotifyTrackRef(track: savedTrack.track)
        //     }
        //
        //     allTracks.append(contentsOf: tracks)
        //
        //     if page.next == nil { break }
        //     offset += limit
        // }
        //
        // return allTracks

        Log.info("Fetching Spotify saved tracks (not yet implemented)")
        return []
    }

    public func fetchPlaylists() async throws -> [SpotifyPlaylistRef] {
        // TODO: Implement pagination through user's playlists
        //
        // 1. Fetch all playlists:
        //    var allPlaylists: [SpotifyPlaylistRef] = []
        //    var offset = 0
        //
        //    while true {
        //        let page = try await spotify.currentUserPlaylists(offset: offset, limit: 50)
        //
        //        for playlist in page.items {
        //            // Fetch full playlist with tracks
        //            let fullPlaylist = try await spotify.playlist(playlist.uri)
        //
        //            let trackRefs = fullPlaylist.items.tracks.items.compactMap { item in
        //                guard let track = item.item as? Track else { return nil }
        //                return mapToSpotifyTrackRef(track: track)
        //            }
        //
        //            allPlaylists.append(SpotifyPlaylistRef(
        //                id: playlist.id,
        //                name: playlist.name,
        //                owner: playlist.owner?.id,
        //                description: playlist.description,
        //                trackRefs: trackRefs
        //            ))
        //        }
        //
        //        if page.next == nil { break }
        //        offset += 50
        //    }
        //
        // return allPlaylists

        Log.info("Fetching Spotify playlists (not yet implemented)")
        return []
    }

    public func fetchPlaylistTracks(playlistID: String) async throws -> [SpotifyTrackRef] {
        // TODO: Fetch tracks for a specific playlist
        //
        // let playlist = try await spotify.playlist(playlistID)
        // return playlist.items.tracks.items.compactMap { item in
        //     guard let track = item.item as? Track else { return nil }
        //     return mapToSpotifyTrackRef(track: track)
        // }

        Log.info("Fetching tracks for playlist \(playlistID) (not yet implemented)")
        return []
    }

    // MARK: - Private Helpers

    // TODO: Implement mapping from SpotifyAPI Track to SpotifyTrackRef
    // private func mapToSpotifyTrackRef(track: Track) -> SpotifyTrackRef {
    //     return SpotifyTrackRef(
    //         id: track.id ?? "",
    //         name: track.name,
    //         artistNames: track.artists?.map { $0.name } ?? [],
    //         albumName: track.album?.name,
    //         durationMs: track.durationMS,
    //         isExplicit: track.explicit,
    //         isrc: track.externalIDs?.isrc
    //     )
    // }
}

