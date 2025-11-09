# Project Architecture

## Overview

This document describes the complete architecture for the Spotify to Apple Music migration application. The project is structured as a **Swift Package** with shared core logic (`MergeCore`) that powers both a macOS application and an optional CLI tool.

## Design Principles

1. **Service-Agnostic Core**: All business logic works with canonical models, not service-specific types
2. **Separation of Concerns**: Clear boundaries between data access, business logic, and UI
3. **Dependency Injection**: Services are injected, making the codebase testable
4. **Async/Await First**: Modern Swift concurrency throughout
5. **Type Safety**: Leverage Swift's type system to prevent errors at compile time

---

## 1. Repository Structure

### Top-Level Layout

```
SpotifyAppleMerge/
├── Package.swift                 # Swift Package definition
├── README.md                     # Project overview
├── docs/                         # Documentation
│   ├── ARCHITECTURE.md           # This file
│   ├── MATCHING_PIPELINE.md      # Detailed matching algorithm
│   ├── EPIC_ADVANCED_MATCHING_ENGINE.md  # PM epic breakdown
│   └── LIBRARIES.md              # Dependencies reference
├── Sources/                      # Swift Package sources
│   ├── MergeCore/                # Core business logic library
│   ├── MergeCLI/                 # Command-line interface
│   └── MergeKitSupport/          # Optional shared helpers for app
├── App/                          # macOS application
│   ├── SpotifyAppleMerge.xcodeproj
│   └── SpotifyAppleMergeApp/
│       ├── AppDelegate.swift
│       ├── ContentView.swift
│       ├── ViewModels/
│       ├── Views/
│       └── Resources/
└── Tests/                        # All tests
    ├── MergeCoreTests/
    │   ├── DomainTests/
    │   ├── MatchingTests/
    │   ├── DiffTests/
    │   └── SyncTests/
    └── IntegrationTests/
        ├── SpotifyIntegrationTests/
        └── AppleMusicIntegrationTests/
```

### Swift Package Targets

**Package.swift** defines:

```swift
let package = Package(
    name: "SpotifyAppleMerge",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MergeCore", targets: ["MergeCore"]),
        .executable(name: "merge-cli", targets: ["MergeCLI"])
    ],
    dependencies: [
        // Service APIs
        .package(url: "https://github.com/Peter-Schorn/SpotifyAPI", from: "2.0.0"),
        .package(url: "https://github.com/rrroyal/MusadoraKit", from: "3.0.0"),

        // Fuzzy matching
        .package(url: "https://github.com/seanoshea/FuzzyMatchingSwift", from: "1.0.0"),
        .package(url: "https://github.com/krisk/fuse-swift", from: "2.0.0"),

        // Database
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0")
    ],
    targets: [
        .target(
            name: "MergeCore",
            dependencies: [
                "SpotifyAPI",
                "MusadoraKit",
                "FuzzyMatchingSwift",
                "Fuse",
                "GRDB"
            ]
        ),
        .executableTarget(
            name: "MergeCLI",
            dependencies: ["MergeCore"]
        ),
        .testTarget(
            name: "MergeCoreTests",
            dependencies: ["MergeCore"]
        )
    ]
)
```

**Key Benefits**:
- **Single source of truth**: Core logic shared between UI and CLI
- **Easy testing**: MergeCore can be tested independently
- **Flexible deployment**: Headless CLI for automation, GUI for end users

---

## 2. MergeCore Architecture

### Module Organization

```
Sources/MergeCore/
├── Domain/                       # Core domain models
│   ├── CanonicalModels.swift     # Service-agnostic track/playlist models
│   ├── ServiceModels.swift       # Service-specific reference types
│   ├── MatchModels.swift         # Matching-related types
│   ├── DiffModels.swift          # Sync operation types
│   └── Config.swift              # User configuration
├── Persistence/                  # Database layer
│   ├── Database.swift            # GRDB setup
│   ├── Migrations.swift          # Schema migrations
│   ├── TrackStore.swift          # Track CRUD
│   ├── PlaylistStore.swift       # Playlist CRUD
│   ├── MappingStore.swift        # ID mapping storage
│   └── SyncRunStore.swift        # Sync history
├── Integrations/                 # Service clients
│   ├── Spotify/
│   │   ├── SpotifyAuthService.swift
│   │   ├── SpotifyLibraryService.swift
│   │   └── SpotifySearchService.swift
│   └── AppleMusic/
│       ├── AppleAuthService.swift
│       ├── AppleLibraryService.swift
│       └── AppleSearchService.swift
├── Matching/                     # Matching engine
│   ├── TextNormalizer.swift      # String normalization
│   ├── StringSimilarity.swift    # Fuzzy matching wrapper
│   ├── StrongMatcher.swift       # ISRC-based matching
│   ├── CandidateGenerator.swift  # Search candidate generation
│   ├── MatchScorer.swift         # Multi-component scoring
│   └── MatchEngine.swift         # Orchestration
├── Diff/                         # Library comparison
│   ├── LibraryDiffEngine.swift   # Compute sync operations
│   └── PlaylistDiffEngine.swift  # Playlist-specific diff
├── Sync/                         # Sync execution
│   ├── MergePolicy.swift         # User-defined sync rules
│   ├── SyncPlanner.swift         # Operation planning
│   ├── SyncExecutor.swift        # Operation execution
│   └── RateLimitHandler.swift    # Rate limiting
└── Util/                         # Shared utilities
    ├── Logging.swift             # Centralized logging
    ├── Errors.swift              # Custom error types
    └── Extensions.swift          # Swift extensions
```

---

## 3. Domain Layer

### 3.1 Canonical Models

The core abstraction is the **canonical model** - a service-agnostic representation of tracks and playlists.

#### CanonicalTrack

```swift
public struct CanonicalTrackID: Hashable, Codable {
    public let value: String  // Hash of normalized metadata
}

public struct CanonicalTrack: Codable {
    public let id: CanonicalTrackID

    // Metadata
    public var title: String
    public var artist: String
    public var album: String?
    public var durationSeconds: Int?
    public var isExplicit: Bool?
    public var isrc: String?

    // Service mappings
    public var spotifyID: String?
    public var appleID: String?

    // Availability tracking
    public var availability: AvailabilityFlags
}

public struct AvailabilityFlags: OptionSet, Codable {
    public let rawValue: Int

    public static let spotify    = AvailabilityFlags(rawValue: 1 << 0)
    public static let appleMusic = AvailabilityFlags(rawValue: 1 << 1)
}
```

**Key Design Decisions**:
- **Canonical ID**: Stable identifier derived from normalized metadata, not service IDs
- **Service IDs**: Optional - tracks may exist on one service but not the other
- **Availability Flags**: Track which services have this track

#### CanonicalPlaylist

```swift
public struct CanonicalPlaylistID: Hashable, Codable {
    public let value: String  // Hash of owner + name
}

public struct CanonicalPlaylist: Codable {
    public let id: CanonicalPlaylistID

    // Metadata
    public var name: String
    public var owner: String?
    public var description: String?

    // Contents
    public var trackIDs: [CanonicalTrackID]  // Ordered

    // Service mappings
    public var sourceSpotifyID: String?
    public var sourceAppleID: String?
}
```

**Playlist Semantics**:
- Tracks are stored in order (playlists are sequences, not sets)
- Playlists are "owned" by one service initially, then mirrored to the other

### 3.2 Service Models

Service-specific types used **before** normalization to canonical models.

```swift
public enum MusicService: String, Codable {
    case spotify
    case appleMusic
}

// Spotify
public struct SpotifyTrackRef {
    public let id: String
    public let name: String
    public let artistNames: [String]
    public let albumName: String?
    public let durationMs: Int?
    public let isExplicit: Bool?
    public let isrc: String?
}

// Apple Music
public struct AppleTrackRef {
    public let id: String
    public let name: String
    public let artistName: String
    public let albumName: String?
    public let durationMs: Int?
    public let isExplicit: Bool?
    public let isrc: String?
}
```

**Conversion Flow**:
```
SpotifyAPI → SpotifyTrackRef → CanonicalTrack
MusicKit   → AppleTrackRef   → CanonicalTrack
```

### 3.3 Match Models

Types used during the matching process.

```swift
public struct NormalizedTrackKey {
    public let titleKey: String
    public let artistKey: String
    public let albumKey: String?
}

public struct MatchScoreComponents {
    public let titleScore: Double       // 0.0-1.0
    public let artistScore: Double      // 0.0-1.0
    public let albumScore: Double       // 0.0-1.0
    public let durationScore: Double    // 0.0-1.0
    public let isrcBonus: Double        // 0.0 or 0.2
}

public struct MatchScore {
    public let candidateID: String
    public let score: Double           // Combined score 0.0-1.0
    public let components: MatchScoreComponents
}

public enum MatchDecision {
    case auto(candidate: MatchScore)
    case ambiguous(candidates: [MatchScore])
    case noMatch
}
```

### 3.4 Diff Models

Describe operations to apply during sync.

```swift
public enum SyncOperation {
    case addTrackToApple(canonicalTrackID: CanonicalTrackID)
    case addTrackToSpotify(canonicalTrackID: CanonicalTrackID)
    case removeTrackFromApple(canonicalTrackID: CanonicalTrackID)
    case removeTrackFromSpotify(canonicalTrackID: CanonicalTrackID)

    case createApplePlaylist(playlist: CanonicalPlaylist)
    case createSpotifyPlaylist(playlist: CanonicalPlaylist)
    case updateApplePlaylistMembers(playlistID: CanonicalPlaylistID, trackIDs: [CanonicalTrackID])
    case updateSpotifyPlaylistMembers(playlistID: CanonicalPlaylistID, trackIDs: [CanonicalTrackID])
}

public struct LibraryDiff {
    public let trackOps: [SyncOperation]
    public let playlistOps: [SyncOperation]

    public var totalOperations: Int {
        trackOps.count + playlistOps.count
    }
}
```

### 3.5 Configuration

```swift
public enum MergeDirection {
    case spotifyToApple      // One-way: Spotify → Apple Music
    case appleToSpotify      // One-way: Apple Music → Spotify
    case bidirectional       // Two-way: sync both directions
}

public struct MergePolicy {
    public let direction: MergeDirection
    public let preferExplicit: Bool
    public let autoResolveThreshold: Double   // Default: 0.85
    public let ambiguousThreshold: Double     // Default: 0.65
}
```

---

## 4. Persistence Layer

Uses **GRDB.swift** for SQLite database access.

### Database Schema

```sql
-- Canonical tracks
CREATE TABLE canonical_tracks (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    album TEXT,
    duration_seconds INTEGER,
    is_explicit BOOLEAN,
    isrc TEXT,
    spotify_id TEXT,
    apple_id TEXT,
    availability INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_tracks_spotify_id ON canonical_tracks(spotify_id);
CREATE INDEX idx_tracks_apple_id ON canonical_tracks(apple_id);
CREATE INDEX idx_tracks_isrc ON canonical_tracks(isrc);

-- Canonical playlists
CREATE TABLE canonical_playlists (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    owner TEXT,
    description TEXT,
    source_spotify_id TEXT,
    source_apple_id TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Playlist membership (ordered)
CREATE TABLE playlist_tracks (
    playlist_id TEXT NOT NULL,
    track_id TEXT NOT NULL,
    position INTEGER NOT NULL,
    FOREIGN KEY (playlist_id) REFERENCES canonical_playlists(id),
    FOREIGN KEY (track_id) REFERENCES canonical_tracks(id),
    PRIMARY KEY (playlist_id, position)
);

-- Manual track mappings (user overrides)
CREATE TABLE manual_mappings (
    id TEXT PRIMARY KEY,
    canonical_track_id TEXT NOT NULL,
    source_service TEXT NOT NULL,
    source_track_id TEXT NOT NULL,
    target_service TEXT NOT NULL,
    target_track_id TEXT NOT NULL,
    confidence_score DOUBLE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(source_service, source_track_id),
    FOREIGN KEY (canonical_track_id) REFERENCES canonical_tracks(id)
);

-- Sync run history
CREATE TABLE sync_runs (
    id TEXT PRIMARY KEY,
    started_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP,
    direction TEXT NOT NULL,
    operations_count INTEGER,
    success_count INTEGER,
    failure_count INTEGER,
    status TEXT NOT NULL  -- 'running', 'completed', 'failed'
);
```

### Database Provider

```swift
public final class DatabaseProvider {
    public static let shared = DatabaseProvider()

    public let dbQueue: DatabaseQueue

    private init() {
        let dbPath = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("SpotifyAppleMerge")
            .appendingPathComponent("db.sqlite")
            .path

        dbQueue = try! DatabaseQueue(path: dbPath)
        try! Migrations.migrate(dbQueue)
    }
}
```

### Store Protocols

```swift
// TrackStore.swift
public protocol TrackStore {
    func save(_ track: CanonicalTrack) async throws
    func saveAll(_ tracks: [CanonicalTrack]) async throws
    func fetch(id: CanonicalTrackID) async throws -> CanonicalTrack?
    func fetchBySpotifyID(_ id: String) async throws -> CanonicalTrack?
    func fetchByAppleID(_ id: String) async throws -> CanonicalTrack?
    func fetchAll() async throws -> [CanonicalTrack]
}

// MappingStore.swift
public protocol MappingStore {
    func getManualMapping(sourceService: MusicService, sourceID: String) async throws -> ManualMapping?
    func saveManualMapping(_ mapping: ManualMapping) async throws
    func deleteManualMapping(id: String) async throws
}
```

---

## 5. Integrations Layer

### 5.1 Spotify Integration

#### SpotifyAuthService.swift

Handles OAuth 2.0 authentication.

```swift
public protocol SpotifyAuthService {
    func authorize() async throws
    func refreshTokenIfNeeded() async throws
    var isAuthorized: Bool { get }
}

public final class SpotifyAuthServiceImpl: SpotifyAuthService {
    private let spotifyAPI: SpotifyAPI<AuthorizationCodeFlowManager>

    public func authorize() async throws {
        // Trigger OAuth flow
        // Save tokens to Keychain
    }

    public func refreshTokenIfNeeded() async throws {
        // Check token expiry
        // Refresh if needed
    }
}
```

#### SpotifyLibraryService.swift

Fetches user's library content.

```swift
public protocol SpotifyLibraryService {
    func fetchSavedTracks() async throws -> [SpotifyTrackRef]
    func fetchPlaylists() async throws -> [SpotifyPlaylistRef]
    func fetchPlaylistTracks(playlistID: String) async throws -> [SpotifyTrackRef]
}

public final class SpotifyLibraryServiceImpl: SpotifyLibraryService {
    private let spotifyAPI: SpotifyAPI<AuthorizationCodeFlowManager>

    public func fetchSavedTracks() async throws -> [SpotifyTrackRef] {
        var allTracks: [SpotifyTrackRef] = []
        var offset = 0
        let limit = 50

        while true {
            let page = try await spotifyAPI.currentUserSavedTracks(
                offset: offset,
                limit: limit
            )

            let tracks = page.items.map { savedTrack in
                SpotifyTrackRef(from: savedTrack.track)
            }

            allTracks.append(contentsOf: tracks)

            if page.next == nil { break }
            offset += limit
        }

        return allTracks
    }
}
```

#### SpotifySearchService.swift

Searches Spotify catalog for candidate tracks.

```swift
public protocol SpotifySearchService {
    func search(query: String, limit: Int) async throws -> [SpotifyTrackRef]
}
```

### 5.2 Apple Music Integration

#### AppleAuthService.swift

Uses MusicKit for authorization.

```swift
public protocol AppleAuthService {
    func requestAuthorization() async throws
    var isAuthorized: Bool { get }
}

public final class AppleAuthServiceImpl: AppleAuthService {
    public func requestAuthorization() async throws {
        let status = await MusicAuthorization.request()

        guard status == .authorized else {
            throw MergeError.authRequired(service: .appleMusic)
        }
    }
}
```

#### AppleLibraryService.swift

Fetches library via MusadoraKit.

```swift
public protocol AppleLibraryService {
    func fetchLibrarySongs() async throws -> [AppleTrackRef]
    func fetchPlaylists() async throws -> [ApplePlaylistRef]
}

public final class AppleLibraryServiceImpl: AppleLibraryService {
    public func fetchLibrarySongs() async throws -> [AppleTrackRef] {
        let songs = try await MLibrary.songs()
        return songs.map { AppleTrackRef(from: $0) }
    }
}
```

---

## 6. Matching Engine

See [MATCHING_PIPELINE.md](./MATCHING_PIPELINE.md) for detailed algorithms.

### Module Overview

```
Matching/
├── TextNormalizer.swift      # Clean/normalize strings
├── StringSimilarity.swift    # Fuzzy string matching wrapper
├── StrongMatcher.swift       # ISRC-based matching
├── CandidateGenerator.swift  # Search for potential matches
├── MatchScorer.swift         # Multi-component scoring
└── MatchEngine.swift         # Orchestrates entire pipeline
```

### MatchEngine Orchestration

```swift
public final class MatchEngine {
    private let mappingStore: MappingStore
    private let strongMatcher: StrongMatcher
    private let candidateGenerator: CandidateGenerator
    private let scorer: MatchScorer
    private let config: MergePolicy

    public func matchSpotifyTrackToApple(
        _ source: CanonicalTrack
    ) async throws -> MatchDecision {
        // Stage 0: Check existing mappings
        if let existing = try await mappingStore.getManualMapping(
            sourceService: .spotify,
            sourceID: source.spotifyID!
        ) {
            return .auto(candidate: MatchScore(from: existing))
        }

        // Stage 1: Strong match (ISRC)
        if let strong = strongMatcher.match(source: source, candidates: appleCatalog) {
            return .auto(candidate: strong)
        }

        // Stage 3: Generate candidates via search
        let candidates = try await candidateGenerator.candidatesForSpotifyTrackOnApple(source)

        guard !candidates.isEmpty else {
            return .noMatch
        }

        // Stage 4: Score all candidates
        let scores = candidates.map { candidate in
            scorer.score(source: source, candidate: candidate)
        }.sorted { $0.score > $1.score }

        // Stage 5: Apply decision thresholds
        return classifyMatch(scores: scores)
    }

    private func classifyMatch(scores: [MatchScore]) -> MatchDecision {
        guard let best = scores.first else { return .noMatch }

        let margin = scores.count > 1 ? best.score - scores[1].score : 1.0

        if best.score >= config.autoResolveThreshold && margin >= 0.10 {
            return .auto(candidate: best)
        }

        if best.score >= config.ambiguousThreshold {
            return .ambiguous(candidates: Array(scores.prefix(3)))
        }

        return .noMatch
    }
}
```

---

## 7. Diff & Sync

### LibraryDiffEngine

Compares canonical snapshots to determine required operations.

```swift
public final class LibraryDiffEngine {
    public func diff(
        canonicalTracks: [CanonicalTrack],
        canonicalPlaylists: [CanonicalPlaylist],
        policy: MergePolicy
    ) -> LibraryDiff {
        var trackOps: [SyncOperation] = []
        var playlistOps: [SyncOperation] = []

        switch policy.direction {
        case .spotifyToApple:
            // Find tracks on Spotify but not Apple
            for track in canonicalTracks where track.availability.contains(.spotify) {
                if !track.availability.contains(.appleMusic) {
                    trackOps.append(.addTrackToApple(canonicalTrackID: track.id))
                }
            }

            // Find Spotify playlists to mirror
            for playlist in canonicalPlaylists where playlist.sourceSpotifyID != nil {
                if playlist.sourceAppleID == nil {
                    playlistOps.append(.createApplePlaylist(playlist: playlist))
                }
            }

        case .appleToSpotify:
            // Reverse logic

        case .bidirectional:
            // Both directions
        }

        return LibraryDiff(trackOps: trackOps, playlistOps: playlistOps)
    }
}
```

### SyncExecutor

Executes sync operations against service APIs.

```swift
public final class SyncExecutor {
    private let spotifyLib: SpotifyLibraryService
    private let appleLib: AppleLibraryService
    private let trackStore: TrackStore
    private let playlistStore: PlaylistStore
    private let rateLimiter: RateLimitHandler

    public func execute(operations: [SyncOperation]) async -> SyncResult {
        var successCount = 0
        var failureCount = 0

        for op in operations {
            do {
                try await executeOperation(op)
                successCount += 1
            } catch {
                Log.error("Operation failed: \(op)", error: error)
                failureCount += 1
            }
        }

        return SyncResult(
            totalOps: operations.count,
            successCount: successCount,
            failureCount: failureCount
        )
    }

    private func executeOperation(_ op: SyncOperation) async throws {
        switch op {
        case .addTrackToApple(let trackID):
            // Look up canonical track
            guard let track = try await trackStore.fetch(id: trackID) else {
                throw MergeError.trackNotFound(trackID)
            }

            // Add to Apple Music library via MusicKit
            // Update track.appleID in database

        case .createApplePlaylist(let playlist):
            // Create playlist via MusicKit
            // Add tracks to playlist
            // Update playlist.sourceAppleID in database

        // ... other cases
        }
    }
}
```

---

## 8. macOS Application

### App Structure

```
App/SpotifyAppleMergeApp/
├── SpotifyAppleMergeApp.swift   # App entry point
├── AppDelegate.swift
├── ContentView.swift             # Main UI container
├── ViewModels/
│   ├── AppCoordinator.swift      # Navigation/state coordinator
│   ├── ConnectionViewModel.swift # Auth management
│   ├── LibraryViewModel.swift    # Library fetching
│   ├── DiffViewModel.swift       # Diff computation
│   └── SyncViewModel.swift       # Sync execution
└── Views/
    ├── ConnectionView.swift      # Auth screens
    ├── LibrarySummaryView.swift  # Display library stats
    ├── DiffSummaryView.swift     # Show planned changes
    ├── PlaylistDetailView.swift  # Playlist comparison
    └── SyncProgressView.swift    # Sync progress/results
```

### App Entry Point

```swift
@main
struct SpotifyAppleMergeApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
```

### ViewModel Example: DiffViewModel

```swift
@MainActor
final class DiffViewModel: ObservableObject {
    @Published var diffSummary: DiffSummary?
    @Published var isLoading = false
    @Published var error: String?

    private let diffEngine: LibraryDiffEngine
    private let trackStore: TrackStore
    private let playlistStore: PlaylistStore
    private let policy: MergePolicy

    init(
        diffEngine: LibraryDiffEngine,
        trackStore: TrackStore,
        playlistStore: PlaylistStore,
        policy: MergePolicy
    ) {
        self.diffEngine = diffEngine
        self.trackStore = trackStore
        self.playlistStore = playlistStore
        self.policy = policy
    }

    func computeDiff() {
        Task {
            isLoading = true
            defer { isLoading = false }

            do {
                let tracks = try await trackStore.fetchAll()
                let playlists = try await playlistStore.fetchAll()

                let diff = diffEngine.diff(
                    canonicalTracks: tracks,
                    canonicalPlaylists: playlists,
                    policy: policy
                )

                diffSummary = DiffSummary(from: diff)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct DiffSummary {
    let tracksToAddToSpotify: Int
    let tracksToAddToApple: Int
    let playlistsToCreate: Int
    let totalOperations: Int
}
```

### View Example: DiffSummaryView

```swift
struct DiffSummaryView: View {
    @ObservedObject var viewModel: DiffViewModel

    var body: some View {
        VStack(spacing: 20) {
            if viewModel.isLoading {
                ProgressView("Computing differences...")
            } else if let summary = viewModel.diffSummary {
                summaryCard(summary)

                Button("Start Sync") {
                    // Navigate to sync view
                }
                .buttonStyle(.borderedProminent)
            } else if let error = viewModel.error {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            }
        }
        .padding()
        .onAppear {
            viewModel.computeDiff()
        }
    }

    private func summaryCard(_ summary: DiffSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync Summary")
                .font(.headline)

            HStack {
                Image(systemName: "music.note.list")
                Text("\(summary.tracksToAddToApple) tracks → Apple Music")
            }

            HStack {
                Image(systemName: "music.note")
                Text("\(summary.tracksToAddToSpotify) tracks → Spotify")
            }

            HStack {
                Image(systemName: "square.stack")
                Text("\(summary.playlistsToCreate) playlists to create")
            }

            Divider()

            Text("Total: \(summary.totalOperations) operations")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}
```

---

## 9. CLI Tool

### Structure

```
Sources/MergeCLI/
└── main.swift              # CLI entry point
```

### Implementation

```swift
import ArgumentParser
import MergeCore

@main
struct MergeCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "merge-cli",
        abstract: "Spotify to Apple Music migration tool",
        version: "1.0.0"
    )

    @Option(name: .long, help: "Direction: spotify-to-apple, apple-to-spotify, bidirectional")
    var direction: String = "spotify-to-apple"

    @Flag(name: .long, help: "Dry run (don't make actual changes)")
    var dryRun: Bool = false

    @Option(name: .long, help: "Auto-resolve threshold (0.0-1.0)")
    var autoThreshold: Double = 0.85

    func run() async throws {
        let mergeDirection: MergeDirection
        switch direction {
        case "spotify-to-apple":
            mergeDirection = .spotifyToApple
        case "apple-to-spotify":
            mergeDirection = .appleToSpotify
        case "bidirectional":
            mergeDirection = .bidirectional
        default:
            throw ValidationError("Invalid direction: \(direction)")
        }

        let policy = MergePolicy(
            direction: mergeDirection,
            preferExplicit: true,
            autoResolveThreshold: autoThreshold,
            ambiguousThreshold: 0.65
        )

        let coordinator = MergeCoordinator(policy: policy)

        print("🎵 Spotify to Apple Music Migration")
        print("Direction: \(direction)")
        print("Dry run: \(dryRun)")
        print()

        if dryRun {
            let report = try await coordinator.performDryRun()
            printReport(report)
        } else {
            let result = try await coordinator.performSync()
            printResult(result)
        }
    }

    private func printReport(_ report: DryRunReport) {
        print("📊 Dry Run Report")
        print("─────────────────")
        print("Tracks to sync: \(report.trackCount)")
        print("Playlists to sync: \(report.playlistCount)")
        print("Total operations: \(report.totalOperations)")
        print()
        print("✅ Ready to sync. Run without --dry-run to proceed.")
    }

    private func printResult(_ result: SyncResult) {
        print("✨ Sync Complete")
        print("─────────────────")
        print("Success: \(result.successCount)")
        print("Failed: \(result.failureCount)")
        print("Total: \(result.totalOps)")
    }
}
```

**Usage Examples**:

```bash
# Dry run
$ merge-cli --dry-run --direction spotify-to-apple

# Actual sync
$ merge-cli --direction spotify-to-apple

# Bidirectional with custom threshold
$ merge-cli --direction bidirectional --auto-threshold 0.90
```

---

## 10. End-to-End Flows

### 10.1 First-Time Import & Diff Flow

**Objective**: Fetch both libraries, normalize to canonical models, and compute differences.

**Steps**:

1. **Authenticate Both Services**
   ```swift
   try await spotifyAuth.authorize()
   try await appleAuth.requestAuthorization()
   ```

2. **Fetch Remote Libraries**
   ```swift
   let spotifyTracks = try await spotifyLib.fetchSavedTracks()
   let spotifyPlaylists = try await spotifyLib.fetchPlaylists()

   let appleTracks = try await appleLib.fetchLibrarySongs()
   let applePlaylists = try await appleLib.fetchPlaylists()
   ```

3. **Normalize to Canonical Models**
   ```swift
   let canonicalTracks = normalize(
       spotify: spotifyTracks,
       apple: appleTracks
   )

   let canonicalPlaylists = normalize(
       spotify: spotifyPlaylists,
       apple: applePlaylists
   )
   ```

4. **Persist Canonical Snapshot**
   ```swift
   try await trackStore.saveAll(canonicalTracks)
   try await playlistStore.saveAll(canonicalPlaylists)
   ```

5. **Run Matching Engine** (optional pre-matching)
   ```swift
   for track in canonicalTracks where track.spotifyID != nil && track.appleID == nil {
       let decision = try await matchEngine.matchSpotifyTrackToApple(track)
       // Handle decision
   }
   ```

6. **Compute Diff**
   ```swift
   let diff = diffEngine.diff(
       canonicalTracks: canonicalTracks,
       canonicalPlaylists: canonicalPlaylists,
       policy: policy
   )
   ```

7. **Display Diff** (UI or CLI)
   ```swift
   // UI: Show DiffSummaryView
   // CLI: Print report
   ```

### 10.2 Sync Execution Flow

**Objective**: Execute planned operations to sync libraries.

**Steps**:

1. **Plan Operations**
   ```swift
   let operations = syncPlanner.plan(from: diff)
   ```

2. **Execute Operations**
   ```swift
   let result = try await syncExecutor.execute(operations: operations)
   ```

   For each operation:
   - **Add Track to Apple**:
     - Look up canonical track from DB
     - Search Apple Music catalog if appleID unknown
     - Add to library via MusicKit
     - Update `track.appleID` in DB

   - **Create Apple Playlist**:
     - Create playlist via MusicKit
     - Add tracks in order
     - Update `playlist.sourceAppleID` in DB

   - Rate limiting is automatically handled by `RateLimitHandler`

3. **Log Sync Run**
   ```swift
   try await syncRunStore.insert(
       startedAt: startTime,
       completedAt: Date(),
       direction: policy.direction,
       operationsCount: operations.count,
       successCount: result.successCount,
       failureCount: result.failureCount,
       status: .completed
   )
   ```

4. **Display Results**
   ```swift
   // UI: Show SyncProgressView with success/failure counts
   // CLI: Print summary
   ```

### 10.3 Ambiguous Match Resolution Flow

**Objective**: Present ambiguous matches to user for manual decision.

**Steps**:

1. **Detect Ambiguous Matches**
   ```swift
   let decision = try await matchEngine.matchSpotifyTrackToApple(track)

   if case .ambiguous(let candidates) = decision {
       // Present to user
   }
   ```

2. **Present UI**
   - Show source track details
   - List 2-3 candidates with scores
   - Options:
     - Select one candidate
     - Skip this track
     - Manually search

3. **User Selects Candidate**
   ```swift
   let manualMapping = ManualMapping(
       canonicalTrackID: track.id,
       sourceService: .spotify,
       sourceTrackID: track.spotifyID!,
       targetService: .appleMusic,
       targetTrackID: selectedCandidate.id,
       confidenceScore: selectedCandidate.score
   )

   try await mappingStore.saveManualMapping(manualMapping)
   ```

4. **Future Syncs**
   - Manual mapping is checked first (Stage 0)
   - User never asked about this track again

---

## 11. Testing Strategy

### Unit Tests

**Location**: `Tests/MergeCoreTests/`

**Coverage**:
- Domain models (serialization, equality)
- Text normalization (edge cases)
- String similarity (known pairs)
- Match scoring (component calculation)
- Decision logic (boundary conditions)
- Diff engine (various library configurations)

**Example**:

```swift
final class TextNormalizerTests: XCTestCase {
    var normalizer: TrackTextNormalizer!

    override func setUp() {
        normalizer = TrackTextNormalizer()
    }

    func testRemovesFeaturing() {
        let input = "Song Name (feat. Someone)"
        let expected = "song name"
        XCTAssertEqual(normalizer.normalizeTitle(input), expected)
    }

    func testRemovesRemastered() {
        let input = "Track - Remastered 2011"
        let expected = "track"
        XCTAssertEqual(normalizer.normalizeTitle(input), expected)
    }
}
```

### Integration Tests

**Location**: `Tests/IntegrationTests/`

**Coverage**:
- End-to-end matching pipeline with mock API responses
- Database migrations and queries
- Service integrations (with test fixtures)

**Example**:

```swift
final class MatchEngineIntegrationTests: XCTestCase {
    var matchEngine: MatchEngine!
    var testDB: DatabaseQueue!

    func testMatchKnownTrack() async throws {
        let spotifyTrack = CanonicalTrack(
            title: "Bohemian Rhapsody",
            artist: "Queen",
            album: "A Night at the Opera",
            isrc: "GBUM71029604"
        )

        let decision = try await matchEngine.matchSpotifyTrackToApple(spotifyTrack)

        guard case .auto(let match) = decision else {
            XCTFail("Expected auto-match")
            return
        }

        XCTAssertGreaterThanOrEqual(match.score, 0.95)
    }
}
```

### Evaluation Corpus Tests

See [EPIC_ADVANCED_MATCHING_ENGINE.md](./EPIC_ADVANCED_MATCHING_ENGINE.md) Epic E4-A8 for details.

**Objective**: Validate matching quality on labeled dataset of 500+ track pairs.

**Metrics**:
- Precision: TP / (TP + FP) ≥ 0.98
- Recall: TP / (TP + FN) ≥ 0.95
- F1 Score: ≥ 0.96

---

## 12. Error Handling

### Error Types

```swift
public enum MergeError: Error, LocalizedError {
    case authRequired(service: MusicService)
    case authFailed(service: MusicService, reason: String)
    case rateLimited(service: MusicService, retryAfter: TimeInterval)
    case networkError(service: MusicService, underlying: Error)
    case trackNotFound(CanonicalTrackID)
    case playlistNotFound(CanonicalPlaylistID)
    case mappingConflict(trackID: CanonicalTrackID)
    case databaseError(underlying: Error)
    case invalidConfiguration(reason: String)

    public var errorDescription: String? {
        switch self {
        case .authRequired(let service):
            return "Authorization required for \(service.rawValue)"
        case .rateLimited(let service, let retryAfter):
            return "Rate limited by \(service.rawValue). Retry after \(retryAfter)s"
        // ... other cases
        }
    }
}
```

### Retry Strategy

```swift
public final class RateLimitHandler {
    private var backoffIntervals: [MusicService: TimeInterval] = [:]

    public func execute<T>(
        service: MusicService,
        operation: () async throws -> T
    ) async throws -> T {
        var attempts = 0
        let maxAttempts = 3

        while attempts < maxAttempts {
            do {
                let result = try await operation()
                backoffIntervals[service] = nil  // Reset on success
                return result
            } catch {
                attempts += 1

                if let rateLimitError = error as? MergeError,
                   case .rateLimited(_, let retryAfter) = rateLimitError {
                    try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                } else {
                    let backoff = TimeInterval(pow(2.0, Double(attempts)))
                    try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                }

                if attempts == maxAttempts {
                    throw error
                }
            }
        }

        fatalError("Unreachable")
    }
}
```

---

## 13. Logging & Observability

### Logging Infrastructure

```swift
public enum Log {
    public static func debug(_ message: String, file: String = #file, line: Int = #line) {
        #if DEBUG
        print("🔍 [\(timestamp())] \(file):\(line) - \(message)")
        #endif
    }

    public static func info(_ message: String) {
        print("ℹ️  [\(timestamp())] \(message)")
    }

    public static func warning(_ message: String) {
        print("⚠️  [\(timestamp())] \(message)")
    }

    public static func error(_ message: String, error: Error? = nil) {
        print("❌ [\(timestamp())] \(message)")
        if let error = error {
            print("   Error: \(error)")
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
```

### Analytics Events

Track key events for quality monitoring:

```swift
public enum AnalyticsEvent {
    case matchAttempted(service: MusicService)
    case matchSucceeded(method: MatchMethod, score: Double)
    case matchAmbiguous(candidateCount: Int)
    case matchFailed
    case userResolvedAmbiguous(acceptedRank: Int)
    case syncStarted(operationCount: Int)
    case syncCompleted(successRate: Double, duration: TimeInterval)
}
```

---

## 14. Future Enhancements

### Phase 2 Features

1. **Incremental Sync**
   - Track library changes since last sync
   - Only process new/modified tracks

2. **Conflict Resolution UI**
   - Handle tracks that exist on both services with different metadata
   - Let user choose which version to keep

3. **Playlist Merge Strategies**
   - Union: combine tracks from both services
   - Intersection: only tracks on both
   - Custom rules

4. **Export/Import**
   - Export canonical library as JSON
   - Import from backup
   - Share mappings between users

### Phase 3 Features

1. **Machine Learning**
   - Train model on user corrections
   - Learn personalized matching preferences

2. **Collaborative Filtering**
   - Anonymous sharing of mappings
   - "Wisdom of the crowd" for ambiguous cases

3. **Advanced Audio Analysis**
   - Tempo, key, energy matching
   - Beyond fingerprinting

4. **Web Service**
   - Cloud-based matching service
   - Pre-computed mappings for popular tracks

---

## 15. Performance Considerations

### Scalability Targets

| Library Size | Target Performance |
|--------------|-------------------|
| 1,000 tracks | < 2 minutes total |
| 10,000 tracks | < 15 minutes total |
| 50,000 tracks | < 60 minutes total |

### Optimization Strategies

1. **Parallel Processing**
   ```swift
   await withTaskGroup(of: MatchDecision.self) { group in
       for track in tracks {
           group.addTask {
               try await matchEngine.matchSpotifyTrackToApple(track)
           }
       }
   }
   ```

2. **Batch API Requests**
   - Fetch tracks in batches of 50
   - Minimize round trips

3. **Caching**
   - In-memory cache for search results
   - Database cache for mappings

4. **Progressive UI Updates**
   - Don't wait for entire library
   - Stream results as they complete

---

## Conclusion

This architecture provides a solid foundation for building a production-quality music library migration tool. Key strengths:

- **Modularity**: Clear separation between core logic, services, and UI
- **Testability**: Domain logic isolated from I/O and UI
- **Flexibility**: Same core powers both GUI and CLI
- **Extensibility**: Easy to add new services (e.g., YouTube Music, Tidal)
- **Type Safety**: Swift's type system prevents many runtime errors

Next steps: Begin implementation starting with Epic E4-A1 (see [EPIC_ADVANCED_MATCHING_ENGINE.md](./EPIC_ADVANCED_MATCHING_ENGINE.md)).
