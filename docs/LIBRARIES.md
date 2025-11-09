# Libraries & Dependencies

This document outlines all the libraries and frameworks used in the Spotify to Apple Music migration app, with specific focus on the matching engine components.

## Core Service APIs

### Spotify Integration

**[SpotifyAPI](https://github.com/Peter-Schorn/SpotifyAPI)** - Full Swift client for Spotify Web API
- **Purpose**: Fetch user library, playlists, track metadata (including ISRC), run search queries
- **Key Features**:
  - Uses Combine for async operations
  - Integrates with SwiftUI
  - Complete coverage of Spotify Web API endpoints
- **Usage**:
  - Fetch user library + playlists
  - Fetch track metadata, including ISRC where available
  - Run search queries for candidate track generation

### Apple Music Integration

**[MusicKit for Swift](https://developer.apple.com/documentation/musickit/)** - Official Apple framework for Apple Music
- **Purpose**: Core framework for Apple Music integration
- **Key Features**:
  - Official Apple framework
  - Full access to Apple Music catalog and user library
  - Native iOS integration

**[MusadoraKit](https://github.com/rryam/MusadoraKit)** - High-level Swift wrapper around MusicKit
- **Purpose**: Simplify MusicKit operations with better ergonomics and documentation
- **Key Features**:
  - Wrapper around MusicKit with cleaner API
  - Better documentation and examples
  - Helper methods for common operations
- **Usage**:
  - Fetch library songs & playlists
  - Search Apple Music catalog for candidate tracks
  - Simplified playlist/library management

## String Similarity & Fuzzy Matching

### Primary Libraries

**[FuzzyMatchingSwift](https://github.com/seanoshea/FuzzyMatchingSwift)** - Levenshtein-based fuzzy matching
- **Purpose**: Primary string similarity scoring for track/artist names
- **Key Features**:
  - Levenshtein distance algorithm
  - Configurable thresholds
  - Returns normalized similarity scores (0-1)
- **Usage**:
  - Score normalized title/artist pairs
  - Calculate similarity between cleaned metadata strings

**[Fuzzywuzzy_swift](https://github.com/xrdrsp/Fuzzywuzzy_swift)** - Port of Python's fuzzywuzzy
- **Purpose**: Token sort/ratio style fuzzy matching
- **Key Features**:
  - Token-based matching (handles word order variations)
  - Partial ratio matching
  - Multiple scoring algorithms
- **Usage**:
  - Alternative/complementary to FuzzyMatchingSwift
  - Useful for titles with different word ordering

**[Fuse-swift](https://github.com/krisk/fuse-swift)** - Lightweight fuzzy search library
- **Purpose**: Fuzzy searching within candidate sets
- **Key Features**:
  - Optimized for searching lists of candidates
  - Pattern-based scoring
  - Fast performance on moderate-sized datasets
- **Usage**:
  - Find candidate tracks by text within a search result set
  - Pre-filter candidates before heavy scoring

### Recommended Combination

For best results, use this combination:
1. **Fuse** - Find candidate tracks by fuzzy text search within a set
2. **FuzzyMatchingSwift** - Score normalized title/artist pairs for final matching

## Audio Fingerprinting (Optional - Advanced)

**[Chromaprint](https://acoustid.org/chromaprint)** - Audio fingerprint library
- **Purpose**: Generate acoustic fingerprints for audio files
- **Key Features**:
  - Industry-standard fingerprinting
  - Works with AcoustID service
  - Can identify tracks from audio data

**[ChromaSwift](https://github.com/kissygalleryteam/ChromaSwift)** - Swift wrapper for Chromaprint
- **Purpose**: Swift bindings for Chromaprint
- **Key Features**:
  - Native Swift interface
  - Integrates Chromaprint into Swift projects
- **Usage** (for v2+):
  - Generate fingerprints for local audio files
  - Look up AcoustID for identification
  - Map to MusicBrainz metadata
  - Feed into matching pipeline as fallback

**Note**: Audio fingerprinting is considered overkill for v1 but valuable for:
- Users with local file libraries
- Cases with severely mismatched or missing metadata
- Ultimate fallback when text-based matching fails

## Swift Package Manager Dependencies

All libraries should be added via Swift Package Manager (SPM) to `Package.swift`:

```swift
dependencies: [
    // Spotify
    .package(url: "https://github.com/Peter-Schorn/SpotifyAPI.git", from: "2.0.0"),

    // Apple Music
    .package(url: "https://github.com/rryam/MusadoraKit.git", from: "1.0.0"),

    // Fuzzy Matching
    .package(url: "https://github.com/seanoshea/FuzzyMatchingSwift.git", from: "1.0.0"),
    .package(url: "https://github.com/krisk/fuse-swift.git", from: "1.0.0"),

    // Optional: Audio Fingerprinting (v2+)
    // .package(url: "https://github.com/kissygalleryteam/ChromaSwift.git", from: "1.0.0"),
]
```

## Version Compatibility

- **Minimum iOS Version**: iOS 15.0+ (required for MusicKit)
- **Swift Version**: Swift 5.5+ (for async/await support)
- **Xcode Version**: Xcode 13.0+

## References

- [Spotify Web API Documentation](https://developer.spotify.com/documentation/web-api/)
- [Apple MusicKit Documentation](https://developer.apple.com/documentation/musickit/)
- [AcoustID Service](https://acoustid.org/)
- [MusicBrainz Database](https://musicbrainz.org/)
