import Foundation
#if canImport(MusicKit)
import MusicKit
#endif

public protocol AppleAuthService: Sendable {
    func requestAuthorization() async throws
    var isAuthorized: Bool { get async }
}

/// Apple Music authorization (#6).
///
/// - On macOS, `requestAuthorization()` asks for MusicKit access (`MusicAuthorization.request()`),
///   which lets `AppleLibraryServiceImpl` read the library natively.
/// - For the REST path (CI, Linux, or no MusicKit entitlement), a Music User Token from
///   `APPLE_MUSIC_USER_TOKEN` is stored in the Keychain via `CredentialStore`.
public final class AppleAuthServiceImpl: AppleAuthService {
    private let credentials: CredentialStore
    private let environment: [String: String]

    public init(
        credentials: CredentialStore = CredentialStores.platformDefault(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.credentials = credentials
        self.environment = environment
    }

    public func requestAuthorization() async throws {
        if let userToken = environment["APPLE_MUSIC_USER_TOKEN"], !userToken.isEmpty {
            try credentials.save(OAuthTokens(accessToken: userToken), for: .appleMusic)
            Log.info("Stored Apple Music user token from APPLE_MUSIC_USER_TOKEN")
            return
        }
        #if canImport(MusicKit)
        let status = await MusicAuthorization.request()
        guard status == .authorized else {
            throw MergeError.authFailed(service: .appleMusic, reason: "MusicKit authorization status: \(status)")
        }
        Log.info("Apple Music access granted (MusicKit)")
        #else
        throw MergeError.authRequired(service: .appleMusic)
        #endif
    }

    public var isAuthorized: Bool {
        get async {
            if (try? credentials.load(for: .appleMusic)) != nil { return true }
            #if canImport(MusicKit)
            return MusicAuthorization.currentStatus == .authorized
            #else
            return false
            #endif
        }
    }
}
