# Spotify to Apple Music Migration App

A sophisticated macOS application that enables seamless migration of music libraries between Spotify and Apple Music services. Built with Swift as a reusable package (with both GUI and CLI interfaces), the app features an advanced matching engine that identifies corresponding tracks across platforms with ≥95% accuracy.

## Project Overview

This application solves the common problem of switching music streaming services by automatically matching and transferring:
- Individual tracks and albums
- Curated playlists
- Saved/liked songs
- User library organization

### Key Features

- **Advanced Matching Engine**: Multi-stage pipeline combining ISRC-based matching, fuzzy string similarity, and optional audio fingerprinting
- **High Accuracy**: ≥95% automatic match rate with <2% false positives
- **Smart Ambiguity Resolution**: User-friendly interface for reviewing uncertain matches
- **Bi-directional Sync**: Transfer from Spotify → Apple Music or Apple Music → Spotify
- **Privacy-First**: All processing happens locally; no data sent to third parties (except optional AcoustID for fingerprinting)
- **Performance Optimized**: <1 second average per track matching

## Architecture

The project is structured as a **Swift Package** with shared core logic (`MergeCore`) that powers both a macOS application and an optional CLI tool.

The application is built around a sophisticated **6-stage matching pipeline**:

0. **Previously-Known Mappings** - Instant retrieval for already-matched tracks
1. **Strong ID-Based Matches** - ISRC + exact metadata matching (60-70% of tracks)
2. **Text Normalization** - Clean and standardize metadata before comparison
3. **Candidate Generation** - Query target service catalog for potential matches
4. **Fuzzy Scoring** - Multi-component similarity scoring (title, artist, album, duration)
5. **Decision Logic** - Classify as auto-match, ambiguous, or no-match
6. **Audio Fingerprint Fallback** (Optional) - Acoustic analysis for edge cases

**See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for complete architectural details, module organization, data flows, and implementation patterns.**

## Documentation

### Technical Specifications
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Complete system architecture, module organization, data models, and implementation patterns
- **[MATCHING_PIPELINE.md](docs/MATCHING_PIPELINE.md)** - Detailed technical specification of the 6-stage matching algorithm
- **[LIBRARIES.md](docs/LIBRARIES.md)** - Dependencies, libraries, and framework references
- **[EPIC_ADVANCED_MATCHING_ENGINE.md](docs/EPIC_ADVANCED_MATCHING_ENGINE.md)** - Detailed PM epic with stories, tasks, and acceptance criteria

## Technology Stack

### Core Frameworks
- **Swift 5.5+** - Primary language with async/await support
- **SwiftUI** - Modern declarative UI framework
- **Combine** - Reactive programming for async operations

### Service Integration
- **[SpotifyAPI](https://github.com/Peter-Schorn/SpotifyAPI)** - Full Swift client for Spotify Web API
- **[MusicKit for Swift](https://developer.apple.com/documentation/musickit/)** - Official Apple Music framework
- **[MusadoraKit](https://github.com/rryam/MusadoraKit)** - High-level wrapper for MusicKit

### Matching Engine
- **[FuzzyMatchingSwift](https://github.com/seanoshea/FuzzyMatchingSwift)** - Levenshtein-based string similarity
- **[Fuse-swift](https://github.com/krisk/fuse-swift)** - Fuzzy search library
- **[ChromaSwift](https://github.com/kissygalleryteam/ChromaSwift)** (Optional) - Audio fingerprinting via Chromaprint

See [docs/LIBRARIES.md](docs/LIBRARIES.md) for detailed dependency information.

## Requirements

- **macOS**: 13.0+ (Ventura)
- **Xcode**: 14.0+
- **Swift**: 5.7+

### Additional Dependencies
- **GRDB.swift**: SQLite database toolkit
- **SpotifyAPI**: Spotify Web API client
- **MusadoraKit**: Apple Music API wrapper

## Development Status

This project is currently in the **specification and planning phase**. See [docs/EPIC_ADVANCED_MATCHING_ENGINE.md](docs/EPIC_ADVANCED_MATCHING_ENGINE.md) for the detailed development roadmap.

### Planned Development Phases

**Phase 1 (MVP)**: Core matching engine - 4-5 weeks
- Basic matching with auto-match capability
- Target: ~85-90% match rate

**Phase 2 (Production)**: User-facing features - 2-3 weeks
- Ambiguity resolution UI
- Quality assurance and evaluation harness
- Target: ~95%+ match rate

**Phase 3 (Advanced)**: Edge case handling - 2 weeks
- Audio fingerprinting for difficult cases
- Target: ~98%+ match rate

## Project Structure

```
SpotifyAppleMerge/
├── Package.swift                   # Swift Package definition
├── README.md                       # This file
├── docs/                           # Documentation
│   ├── ARCHITECTURE.md             # System architecture
│   ├── MATCHING_PIPELINE.md        # Matching algorithm spec
│   ├── EPIC_ADVANCED_MATCHING_ENGINE.md  # PM epic breakdown
│   └── LIBRARIES.md                # Dependencies reference
├── Sources/                        # Swift Package sources
│   ├── MergeCore/                  # Core business logic library
│   │   ├── Domain/                 # Domain models
│   │   ├── Persistence/            # Database layer (GRDB)
│   │   ├── Integrations/           # Spotify & Apple Music clients
│   │   ├── Matching/               # Matching engine
│   │   ├── Diff/                   # Library comparison
│   │   ├── Sync/                   # Sync execution
│   │   └── Util/                   # Shared utilities
│   ├── MergeCLI/                   # Command-line interface
│   └── MergeKitSupport/            # Shared helpers for app (optional)
├── App/                            # macOS application
│   ├── SpotifyAppleMerge.xcodeproj
│   └── SpotifyAppleMergeApp/
│       ├── ViewModels/
│       ├── Views/
│       └── Resources/
└── Tests/                          # All tests
    ├── MergeCoreTests/
    │   ├── DomainTests/
    │   ├── MatchingTests/
    │   ├── DiffTests/
    │   └── SyncTests/
    └── IntegrationTests/
```

**Key Design**: MergeCore is a reusable library that powers both the macOS app (GUI) and CLI tool (headless), ensuring consistent behavior across interfaces.

## Success Metrics

- **Match Rate**: ≥ 95% of tracks that exist on both services
- **False Match Rate**: ≤ 2% (wrong auto-matches)
- **Auto-Match Rate**: ≥ 85% (no user intervention)
- **Performance**: < 1 second average per track
- **User Satisfaction**: ≥ 90% approval rating

## Contributing

This is currently a specification project. Once implementation begins, contribution guidelines will be added.

## License

TBD

## Contact

For questions or suggestions, please open an issue on GitHub.
