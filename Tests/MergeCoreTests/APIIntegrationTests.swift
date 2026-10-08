import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import MergeCore

/// Replays recorded API responses keyed by path (+ query); records every request.
private final class RecordedTransport: HTTPTransport, @unchecked Sendable {
    struct Reply { var status = 200; var body: String; var headers: [String: String] = [:] }
    private let lock = NSLock()
    private var routes: [String: [Reply]] = [:]
    private(set) var requests: [URLRequest] = []

    func on(_ key: String, _ replies: Reply...) {
        lock.lock(); routes[key, default: []] += replies; lock.unlock()
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let key = url.path + (url.query.map { "?" + $0 } ?? "")
        lock.lock()
        requests.append(request)
        var queue = routes[key] ?? routes[url.path] ?? []
        let reply = queue.isEmpty ? Reply(status: 404, body: "{\"error\":\"no fixture for \(key)\"}") : queue.removeFirst()
        if !queue.isEmpty || routes[key] != nil { routes[key] = queue }
        lock.unlock()
        return (Data(reply.body.utf8), HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!)
    }

    var lastRequest: URLRequest? { lock.lock(); defer { lock.unlock() }; return requests.last }
    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return requests.count }
}

private func track(_ id: String?, _ name: String, isrc: String? = nil, local: Bool = false) -> String {
    """
    {"id":\(id.map { "\"\($0)\"" } ?? "null"),"name":"\(name)","artists":[{"name":"Artist \(name)"}],
     "album":{"name":"Album"},"duration_ms":200000,"explicit":false,"is_local":\(local),
     "external_ids":\(isrc.map { "{\"isrc\":\"\($0)\"}" } ?? "{}")}
    """
}

/// #6: real OAuth + library import against recorded HTTP fixtures (no live credentials in CI).
final class APIIntegrationTests: XCTestCase {
    private let config = SpotifyOAuthConfig(clientID: "client-123")
    private let fastRetry = RetryPolicy(maxAttempts: 3, baseDelay: 0.001, maxDelay: 0.01, jitterFactor: 0)

    // MARK: PKCE / authorize URL

    func testPKCEChallengeIsS256Base64URL() {
        // Expected value computed independently with Python hashlib + urlsafe_b64encode.
        let pair = PKCEPair(verifier: "dBjftJeZ4CVP-mJ92K1XpYvHyuU7Pe2FvPkKxLD-o4E")
        XCTAssertEqual(pair.challenge, "gFqhbK9Mw8POZMldVVn5I1qQkp-pFBfNYQH2gsUWotE")
        let generated = PKCEPair.generate()
        XCTAssertEqual(generated.verifier.count, 64)
        XCTAssertNotEqual(generated, PKCEPair.generate())
    }

    func testAuthorizationURLCarriesPKCEAndScopes() throws {
        let pkce = PKCEPair(verifier: "v")
        let url = SpotifyOAuthClient(config: config).authorizationURL(state: "st", pkce: pkce)
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.host, "accounts.spotify.com")
        XCTAssertEqual(items["client_id"], "client-123")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["code_challenge"], pkce.challenge)
        XCTAssertEqual(items["state"], "st")
        XCTAssertEqual(items["redirect_uri"], SpotifyOAuthConfig.defaultRedirectURI)
        XCTAssertTrue(items["scope"]?.contains("user-library-read") ?? false)
    }

    func testRedirectParsing() throws {
        XCTAssertEqual(try SpotifyOAuthClient.code(fromRedirect: "http://127.0.0.1:8888/callback?code=abc&state=s1", expectedState: "s1"), "abc")
        XCTAssertThrowsError(try SpotifyOAuthClient.code(fromRedirect: "http://x/cb?code=abc&state=evil", expectedState: "s1")) {
            XCTAssertEqual($0 as? SpotifyOAuthError, .stateMismatch)
        }
        XCTAssertThrowsError(try SpotifyOAuthClient.code(fromRedirect: "http://x/cb?error=access_denied&state=s1", expectedState: "s1")) {
            XCTAssertEqual($0 as? SpotifyOAuthError, .denied("access_denied"))
        }
    }

    // MARK: Token exchange + refresh

    func testAuthorizeExchangesCodeAndStoresTokensInCredentialStore() async throws {
        let transport = RecordedTransport()
        transport.on("/api/token", .init(body: #"{"access_token":"AT1","refresh_token":"RT1","expires_in":3600,"scope":"user-library-read"}"#))
        let store = InMemoryCredentialStore()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let auth = SpotifyAuthServiceImpl(
            credentials: store, config: config, transport: transport,
            prompt: { url in
                let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
                return "http://127.0.0.1:8888/callback?code=CODE42&state=\(state)"
            },
            clock: { now }
        )
        try await auth.authorize()

        let saved = try XCTUnwrap(try store.load(for: .spotify))
        XCTAssertEqual(saved.accessToken, "AT1")
        XCTAssertEqual(saved.refreshToken, "RT1")
        XCTAssertEqual(saved.expiresAt, now.addingTimeInterval(3600))
        let request = try XCTUnwrap(transport.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("code=CODE42"))
        XCTAssertTrue(body.contains("code_verifier="))
        XCTAssertFalse(body.contains("client_secret"), "PKCE: no client secret")
        let authorized = await auth.isAuthorized
        XCTAssertTrue(authorized)
    }

    func testExpiredTokenIsRefreshedAndPersistedKeepingRefreshToken() async throws {
        let transport = RecordedTransport()
        transport.on("/api/token", .init(body: #"{"access_token":"AT2","expires_in":3600}"#))
        let now = Date(timeIntervalSince1970: 2_000_000)
        let store = InMemoryCredentialStore([.spotify: OAuthTokens(accessToken: "OLD", refreshToken: "RT1", expiresAt: now.addingTimeInterval(-10))])
        let auth = SpotifyAuthServiceImpl(credentials: store, config: config, transport: transport, clock: { now })

        let token = try await auth.validAccessToken()
        XCTAssertEqual(token, "AT2")
        XCTAssertEqual(try store.load(for: .spotify)?.refreshToken, "RT1", "Spotify may omit refresh_token on refresh")
        let body = String(data: transport.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("grant_type=refresh_token") && body.contains("refresh_token=RT1"))

        // A fresh token is returned without another network call.
        _ = try await auth.validAccessToken()
        XCTAssertEqual(transport.requestCount, 1)
    }

    func testNoStoredTokensRequiresLogin() async {
        let auth = SpotifyAuthServiceImpl(credentials: InMemoryCredentialStore(), config: config, transport: RecordedTransport())
        do {
            _ = try await auth.validAccessToken()
            XCTFail("expected authRequired")
        } catch MergeError.authRequired(let service) {
            XCTAssertEqual(service, .spotify)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: Spotify library pagination

    func testSpotifySavedTracksFollowNextLinksSkipLocalFilesAndRetry429() async throws {
        let transport = RecordedTransport()
        transport.on("/v1/me/tracks?limit=50",
            .init(status: 429, body: "{}", headers: ["Retry-After": "0"]),
            .init(body: """
                {"items":[{"track":\(track("t1", "One", isrc: "US1"))},{"track":\(track(nil, "Local", local: true))},{"track":null}],
                 "next":"https://api.spotify.com/v1/me/tracks?offset=50&limit=50"}
                """))
        transport.on("/v1/me/tracks?offset=50&limit=50",
            .init(body: #"{"items":[{"track":\#(track("t2", "Two"))}],"next":null}"#))
        let library = SpotifyLibraryServiceImpl(transport: transport, token: { "AT" }, retryPolicy: fastRetry)

        let tracks = try await library.fetchSavedTracks()
        XCTAssertEqual(tracks.map(\.id), ["t1", "t2"])
        XCTAssertEqual(tracks.first?.isrc, "US1")
        XCTAssertEqual(transport.requestCount, 3, "429 retried once, then two pages")
        XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer AT")
    }

    func testSpotifyPlaylistsIncludePagedTracks() async throws {
        let transport = RecordedTransport()
        transport.on("/v1/me/playlists?limit=50", .init(body: """
            {"items":[{"id":"pl1","name":"Road Trip","description":"","owner":{"display_name":"Ben","id":"ben"}}],"next":null}
            """))
        transport.on("/v1/playlists/pl1/tracks?limit=100", .init(body: """
            {"items":[{"track":\(track("t1", "One"))}],"next":"https://api.spotify.com/v1/playlists/pl1/tracks?offset=100&limit=100"}
            """))
        transport.on("/v1/playlists/pl1/tracks?offset=100&limit=100", .init(body: #"{"items":[{"track":\#(track("t3", "Three"))}],"next":null}"#))
        let playlists = try await SpotifyLibraryServiceImpl(transport: transport, token: { "AT" }, retryPolicy: fastRetry).fetchPlaylists()

        XCTAssertEqual(playlists.count, 1)
        XCTAssertEqual(playlists[0].name, "Road Trip")
        XCTAssertEqual(playlists[0].owner, "Ben")
        XCTAssertNil(playlists[0].description)
        XCTAssertEqual(playlists[0].trackRefs.map(\.id), ["t1", "t3"])
    }

    // MARK: Apple Music REST

    func testAppleLibrarySongsFollowRelativeNextAndSendBothTokens() async throws {
        let transport = RecordedTransport()
        func song(_ id: String, _ name: String, catalog: String?) -> String {
            """
            {"id":"\(id)","attributes":{"name":"\(name)","artistName":"Queen","albumName":"Opera",
             "durationInMillis":354947,"contentRating":"explicit"\(catalog.map { ",\"playParams\":{\"catalogId\":\"\($0)\"}" } ?? "")}}
            """
        }
        transport.on("/v1/me/library/songs?limit=100", .init(body: #"{"data":[\#(song("i.1", "A", catalog: "111"))],"next":"/v1/me/library/songs?offset=100"}"#))
        transport.on("/v1/me/library/songs?offset=100", .init(body: #"{"data":[\#(song("i.2", "B", catalog: nil))]}"#))
        let library = AppleLibraryServiceImpl(
            transport: transport, developerToken: { "DEV" }, userToken: { "USER" },
            retryPolicy: fastRetry, credentials: InMemoryCredentialStore(), environment: [:]
        )

        let songs = try await library.fetchLibrarySongs()
        XCTAssertEqual(songs.map(\.id), ["111", "i.2"], "catalog ID preferred, library ID as fallback")
        XCTAssertEqual(songs.first?.isExplicit, true)
        let request = try XCTUnwrap(transport.lastRequest)
        XCTAssertEqual(request.url?.host, "api.music.apple.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer DEV")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Music-User-Token"), "USER")
    }

    func testAppleTokensFromEnvironmentAndCredentialStore() async throws {
        let store = InMemoryCredentialStore()
        try await AppleAuthServiceImpl(credentials: store, environment: ["APPLE_MUSIC_USER_TOKEN": "U1"]).requestAuthorization()
        XCTAssertEqual(try store.load(for: .appleMusic)?.accessToken, "U1")

        let transport = RecordedTransport()
        transport.on("/v1/me/library/playlists?limit=100", .init(body: #"{"data":[{"id":"p.1","attributes":{"name":"Mix","description":{"standard":"desc"}}}]}"#))
        transport.on("/v1/me/library/playlists/p.1/tracks?limit=100", .init(body: #"{"data":[{"id":"i.9","attributes":{"name":"Song","artistName":"X"}}]}"#))
        let library = AppleLibraryServiceImpl(transport: transport, retryPolicy: fastRetry, credentials: store,
                                              environment: ["APPLE_MUSIC_DEVELOPER_TOKEN": "DEV"])
        let playlists = try await library.fetchPlaylists()
        XCTAssertEqual(playlists.first?.description, "desc")
        XCTAssertEqual(playlists.first?.trackRefs.map(\.id), ["i.9"])
        XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "Music-User-Token"), "U1")
    }

    // MARK: Import (CLI path)

    func testImportDryRunWritesNothingAndRealRunPopulatesCanonicalTracks() async throws {
        let transport = RecordedTransport()
        let savedPage = """
            {"items":[{"track":\(track("t1", "One", isrc: "US1"))},{"track":\(track("t2", "Two"))}],"next":null}
            """
        let playlistsPage = #"{"items":[{"id":"pl1","name":"Mix","owner":{"id":"ben"}}],"next":null}"#
        let playlistTracks = #"{"items":[{"track":\#(track("t2", "Two"))}],"next":null}"#
        for _ in 0..<2 {
            transport.on("/v1/me/tracks?limit=50", .init(body: savedPage))
            transport.on("/v1/me/playlists?limit=50", .init(body: playlistsPage))
            transport.on("/v1/playlists/pl1/tracks?limit=100", .init(body: playlistTracks))
        }
        let db = try DatabaseProvider.inMemory()
        let trackStore = TrackStoreImpl(dbQueue: db.dbQueue)
        let playlistStore = PlaylistStoreImpl(dbQueue: db.dbQueue)
        let tokens = InMemoryCredentialStore([.spotify: OAuthTokens(accessToken: "AT", refreshToken: "RT", expiresAt: .distantFuture)])
        let coordinator = ImportCoordinator(
            trackStore: trackStore,
            playlistStore: playlistStore,
            spotifyAuth: SpotifyAuthServiceImpl(credentials: tokens, config: config, transport: transport),
            spotifyLibrary: SpotifyLibraryServiceImpl(transport: transport, token: { "AT" }, retryPolicy: fastRetry),
            appleAuth: AppleAuthServiceImpl(credentials: InMemoryCredentialStore(), environment: [:]),
            appleLibrary: AppleLibraryServiceImpl(credentials: InMemoryCredentialStore(), environment: [:])
        )

        let preview = try await coordinator.importFromSpotify(dryRun: true)
        XCTAssertTrue(preview.dryRun)
        XCTAssertEqual(preview.tracks.count, 2)
        XCTAssertEqual(preview.playlistCount, 1)
        XCTAssertTrue(preview.summary.contains("Dry run"))
        let afterPreview = try await trackStore.fetchAll()
        XCTAssertTrue(afterPreview.isEmpty, "dry run writes nothing")

        try await coordinator.importFromSpotify()
        let stored = try await trackStore.fetchAll()
        XCTAssertEqual(Set(stored.compactMap(\.spotifyID)), ["t1", "t2"])
        let playlists = try await playlistStore.fetchAll()
        XCTAssertEqual(playlists.map(\.name), ["Mix"])
    }
}
