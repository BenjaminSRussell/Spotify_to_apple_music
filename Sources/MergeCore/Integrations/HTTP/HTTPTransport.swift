import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal HTTP seam so API clients can be tested with recorded fixtures (no live creds in CI).
public protocol HTTPTransport: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        // Callback API works on both Darwin and swift-corelibs-foundation.
        return try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let http = response as? HTTPURLResponse {
                    continuation.resume(returning: (data ?? Data(), http))
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }.resume()
        }
    }
}

/// Supplies a bearer token (e.g. from `CredentialStore`); never logged.
public typealias TokenProvider = @Sendable () async throws -> String

extension HTTPTransport {
    /// GET + status handling shared by the API clients. 429/5xx become `HTTPError`
    /// (with `Retry-After`) so `RetryPolicy` can back off.
    func getJSON(_ url: URL, headers: [String: String]) async throws -> Data {
        let (data, response) = try await get(url, headers: headers)
        guard (200..<300).contains(response.statusCode) else {
            let retryAfter = (response.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            throw HTTPError(statusCode: response.statusCode, message: String(data: data.prefix(200), encoding: .utf8), retryAfter: retryAfter)
        }
        return data
    }
}

enum SearchQuery {
    /// "Title Artist" with bracketed suffixes ("(Remastered 2011)", "[Live]") removed.
    static func plain(title: String, artist: String) -> String {
        let cleaned = title.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        return "\(cleaned) \(artist)".trimmingCharacters(in: .whitespaces)
    }
}
