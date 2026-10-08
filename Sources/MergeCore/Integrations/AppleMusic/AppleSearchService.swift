import Foundation

/// Protocol for Apple Music search operations
public protocol AppleSearchService: Sendable {
    func search(query: String, limit: Int) async throws -> [AppleTrackRef]
}

/// Apple Music API catalog search (`GET /v1/catalog/{storefront}/search?types=songs`) (#7).
public final class AppleSearchServiceImpl: AppleSearchService {
    private let transport: HTTPTransport
    private let developerToken: TokenProvider?
    private let storefront: String
    private let baseURL: URL

    /// - Parameters:
    ///   - developerToken: Apple Music developer token (JWT). Without one, search returns no results.
    ///   - storefront: Catalog storefront, e.g. "us".
    public init(
        transport: HTTPTransport = URLSessionTransport(),
        developerToken: TokenProvider? = nil,
        storefront: String = "us",
        baseURL: URL = URL(string: "https://api.music.apple.com/v1")!
    ) {
        self.transport = transport
        self.developerToken = developerToken
        self.storefront = storefront
        self.baseURL = baseURL
    }

    public func search(query: String, limit: Int = 10) async throws -> [AppleTrackRef] {
        guard let developerToken else {
            Log.debug("Apple Music search skipped: no developer token configured")
            return []
        }
        let path = baseURL.appendingPathComponent("catalog").appendingPathComponent(storefront).appendingPathComponent("search")
        var components = URLComponents(url: path, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "types", value: "songs"),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 25)))
        ]
        let data = try await transport.getJSON(components.url!, headers: ["Authorization": "Bearer \(try await developerToken())"])
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> [AppleTrackRef] {
        struct Response: Decodable {
            struct Results: Decodable { let songs: Songs? }
            struct Songs: Decodable { let data: [Song] }
            struct Song: Decodable {
                struct Attributes: Decodable {
                    let name: String
                    let artistName: String
                    let albumName: String?
                    let durationInMillis: Int?
                    let contentRating: String?
                    let isrc: String?
                }
                let id: String
                let attributes: Attributes
            }
            let results: Results
        }
        return (try JSONDecoder().decode(Response.self, from: data).results.songs?.data ?? []).map {
            AppleTrackRef(
                id: $0.id,
                name: $0.attributes.name,
                artistName: $0.attributes.artistName,
                albumName: $0.attributes.albumName,
                durationMs: $0.attributes.durationInMillis,
                isExplicit: $0.attributes.contentRating == "explicit",
                isrc: $0.attributes.isrc
            )
        }
    }
}
