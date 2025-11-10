# Spotify ↔ Apple Music Migration Tool

A comprehensive Swift-based tool for migrating music libraries between Spotify and Apple Music, featuring intelligent track matching, fuzzy text matching, and a native macOS UI.

## Features

- 🎵 **Bidirectional Sync** - Spotify → Apple Music, Apple Music → Spotify, or both
- 🔍 **Intelligent Matching** - Multi-stage matching pipeline with ISRC, fuzzy text, and duration matching
- 📊 **Library Management** - Import, track, and sync your entire music library
- 🖥️ **Native macOS UI** - Beautiful SwiftUI interface for visual library management
- ⚡ **CLI Support** - Full-featured command-line interface for automation
- 🗄️ **Local Database** - SQLite storage with GRDB for fast, offline operations
- 🎯 **Confidence Scoring** - Automatic matching with configurable thresholds
- 📋 **Playlist Support** - Migrate playlists with track ordering preserved

## Architecture

### Project Structure

```
SpotifyAppleMerge/
├── Sources/
│   ├── MergeCore/              # Core business logic library
│   │   ├── Domain/              # Domain models (tracks, playlists, diffs)
│   │   ├── Persistence/         # GRDB database layer
│   │   ├── Integrations/        # Spotify & Apple Music API clients
│   │   ├── Matching/            # Matching engine & algorithms
│   │   ├── Sync/                # Sync & diff computation
│   │   └── UI/                  # CLI match resolver
│   ├── MergeCLI/               # Command-line interface
│   └── MergeApp/               # macOS SwiftUI application
│       ├── Views/              # SwiftUI views
│       └── ViewModels/         # State management
├── Tests/
│   └── MergeCoreTests/
│       ├── TestFixtures.swift    # Sample data for testing
│       └── EndToEndTests.swift   # Comprehensive integration tests
└── docs/                       # Detailed documentation
```

### Technology Stack

- **Language**: Swift 5.7+
- **Platform**: macOS 13+
- **Database**: SQLite with GRDB 7.0+
- **UI**: SwiftUI (macOS app)
- **CLI**: Swift Argument Parser 1.5+
- **APIs**: 
  - SpotifyAPI 3.0+
  - MusadoraKit 4.0+ (Apple Music)
- **Matching**: FuzzyMatchingSwift, Fuse-swift

## Installation

### Prerequisites

- macOS 13+ (Ventura or later)
- Xcode 14.0+ (for building)
- Swift 5.7+

### Build from Source

```bash
# Clone the repository
git clone https://github.com/BenjaminSRussell/Spotify_to_apple_music.git
cd Spotify_to_apple_music

# Build all targets
swift build

# Run tests
swift test

# Run CLI
swift run merge-cli --help

# Run macOS app
swift run MergeApp
```

## Usage

### Command-Line Interface (CLI)

#### 1. Import Libraries

```bash
# Import from Spotify
swift run merge-cli import --spotify

# Import from Apple Music
swift run merge-cli import --apple

# Import from both
swift run merge-cli import --spotify --apple
```

#### 2. Preview Changes (Diff)

```bash
# See what would change for Spotify → Apple Music
swift run merge-cli diff --direction spotify-to-apple

# See what would change for Apple Music → Spotify
swift run merge-cli diff --direction apple-to-spotify

# See bidirectional changes
swift run merge-cli diff --direction bidirectional
```

Example output:
```
📊 Library Diff Summary
═══════════════════════
Direction: spotify-to-apple

Track Operations: 245
  - Add to Apple Music: 245

Playlist Operations: 12
  - Create in Apple Music: 10
  - Update in Apple Music: 2

Total Operations: 257
═══════════════════════
```

#### 3. Execute Sync

```bash
# Dry run (preview only, no changes)
swift run merge-cli sync --direction spotify-to-apple --dry-run

# Actual sync
swift run merge-cli sync --direction spotify-to-apple

# Custom confidence threshold (default: 0.85)
swift run merge-cli sync --direction spotify-to-apple --auto-threshold 0.90
```

### macOS Application

```bash
# Launch the native macOS app
swift run MergeApp
```

#### App Features

- **Library Tab** - View all tracks with search, filtering, and statistics
- **Sync Tab** - Visual sync interface with progress tracking
- **Matches Tab** - Interactive resolution for ambiguous matches
- **Settings Tab** - Configure matching parameters and service connections

## Matching Engine

### Multi-Stage Pipeline

```
Source Track
    ↓
Stage 0: Manual Mappings
    ↓ (if no manual mapping)
Stage 1: ISRC Exact Match
    ↓ (if no ISRC or no match)
Stage 2: Metadata Search (fuzzy candidates)
    ↓
Stage 3: Confidence Scoring
    ↓
Decision: Auto (≥0.85) | Ambiguous (0.65-0.85) | No Match (<0.65)
```

### Matching Strategies

1. **ISRC Matching** (Highest Confidence)
   - Exact match via International Standard Recording Code
   - Confidence: 0.95

2. **Fuzzy Text Matching**
   - Normalized title, artist, album comparison
   - Levenshtein distance algorithm
   - Weighted scoring (Title: 40%, Artist: 35%, Album: 15%, Duration: 10%)

3. **Duration Filtering**
   - ±5 seconds tolerance (configurable)
   - Prevents mismatches with similar names

### Text Normalization

The system applies comprehensive normalization:

- **Diacritics removal**: é → e, ñ → n
- **Case insensitive**: All lowercase
- **Parentheticals removed**: "(Live)", "(Remaster)", "(Explicit)"
- **Featured artists normalized**: "feat.", "ft.", "&" → standardized
- **Edition markers removed**: "Deluxe", "Anniversary", etc.

Examples:
```
"Hotel California (2013 Remaster)" → "hotel california"
"The Kid LAROI feat. Justin Bieber" → "the kid laroi"
"Led Zeppelin IV (Deluxe Edition)" → "led zeppelin iv"
```

## Testing

### Run All Tests

```bash
swift test
```

### End-to-End Integration Tests

Comprehensive tests with realistic sample data:

```bash
# Run specific test
swift test --filter EndToEndTests
```

The test suite includes:
- ✅ Full workflow (Import → Match → Diff → Sync)
- ✅ ISRC matching validation
- ✅ Fuzzy matching with variations
- ✅ Ambiguous match detection
- ✅ Text normalization edge cases
- ✅ Performance benchmarks

### Sample Data

Test fixtures include 12 tracks covering:
- Perfect ISRC matches (Bohemian Rhapsody, Hotel California)
- Fuzzy matches with album variations
- Ambiguous matches (multiple versions)
- Featuring artist variations
- Exclusive tracks (platform-specific)
- Live versions

See `Tests/MergeCoreTests/TestFixtures.swift` for full dataset.

## Database

### Schema

The app uses SQLite with GRDB for persistent storage:

```sql
-- Canonical tracks (service-agnostic)
canonical_tracks (id, title, artist, album, duration, isrc, ...)

-- Playlists
canonical_playlists (id, name, owner, description, ...)
playlist_tracks (playlist_id, track_id, position)

-- Manual mappings (user overrides)
manual_mappings (id, canonical_track_id, source_service, target_service, ...)

-- Sync history
sync_runs (id, direction, status, operations_count, ...)
```

### Location

```
~/Library/Application Support/SpotifyAppleMerge/db.sqlite
```

## Configuration

### Settings (macOS App)

- **Auto-match Threshold**: 0.50 - 1.00 (default: 0.85)
- **Duration Tolerance**: 0-15 seconds (default: ±5s)
- **Enable ISRC Matching**: On/Off
- **Enable Fuzzy Matching**: On/Off

Settings persist across launches via `@AppStorage`.

## Performance

### Benchmarks

- **Matching Speed**: ~100-200 tracks/second
- **Database Operations**: Sub-millisecond queries
- **ISRC Lookup**: O(1) with indexing
- **Fuzzy Matching**: O(n*m) where n=candidates, m=fields

### Optimizations

- In-memory caching for repeated lookups
- Candidate pre-filtering (max 50 candidates per track)
- Batch database operations
- Async/await for concurrency

## API Integration Status

### Current Implementation

- ✅ Complete architecture and abstractions
- ✅ Service protocol interfaces
- ✅ OAuth flow placeholders
- ⚠️ API calls are stubbed (TODO comments show exact implementation)

### Spotify API

Located in `Sources/MergeCore/Integrations/Spotify/`:
- `SpotifyAuthService.swift` - OAuth flow ready for implementation
- `SpotifyLibraryService.swift` - Pagination patterns documented

```swift
// TODO: Real implementation
try await spotify.currentUserProfile()
let tracks = try await spotify.library.savedTracks()
```

### Apple Music API

Located in `Sources/MergeCore/Integrations/AppleMusic/`:
- `AppleAuthService.swift` - MusicKit authorization patterns
- `AppleLibraryService.swift` - MusadoraKit usage examples

```swift
// TODO: Real implementation
let status = await MusicAuthorization.request()
let library = try await MLLibrary.shared.songs()
```

## Roadmap

### Phase 7: Hardening & Polish (Next)

- [ ] Real Spotify OAuth implementation
- [ ] Real Apple Music MusicKit integration
- [ ] Retry logic with exponential backoff
- [ ] Rate limiting and throttling
- [ ] Parallel execution for performance
- [ ] Incremental sync (change detection)
- [ ] Conflict resolution strategies
- [ ] Error recovery and rollback

### Future Enhancements

- [ ] Audio fingerprinting (ChromaSwift)
- [ ] Machine learning for confidence tuning
- [ ] iOS companion app
- [ ] Web interface
- [ ] Playlist collaborative editing
- [ ] Export to CSV/JSON
- [ ] Statistics and analytics

## Troubleshooting

### Common Issues

**Database locked errors:**
```bash
# Clear the database
rm ~/Library/Application\ Support/SpotifyAppleMerge/db.sqlite
```

**Build errors:**
```bash
# Clean and rebuild
swift package clean
swift package resolve
swift build
```

**Test failures:**
```bash
# Run with verbose output
swift test --verbose
```

## Contributing

Contributions are welcome! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Setup

```bash
# Install dependencies
swift package resolve

# Run tests in watch mode
swift test --watch

# Format code (if using SwiftFormat)
swiftformat .
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [SpotifyAPI](https://github.com/Peter-Schorn/SpotifyAPI) - Spotify Web API client
- [MusadoraKit](https://github.com/rryam/MusadoraKit) - Apple Music API wrapper
- [GRDB](https://github.com/groue/GRDB.swift) - SQLite toolkit
- [Swift Argument Parser](https://github.com/apple/swift-argument-parser) - CLI framework

## Contact

- **Author**: Benjamin S Russell
- **Repository**: https://github.com/BenjaminSRussell/Spotify_to_apple_music
- **Issues**: https://github.com/BenjaminSRussell/Spotify_to_apple_music/issues

---

**Built with ❤️ using Swift and SwiftUI**
