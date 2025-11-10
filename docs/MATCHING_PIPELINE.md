# Advanced Matching Pipeline Specification

## Overview

The matching engine is a multi-stage pipeline that identifies corresponding tracks between Spotify and Apple Music catalogs. It combines deterministic ID-based matching with fuzzy string similarity and optional audio fingerprinting to achieve high accuracy while minimizing false positives.

## Architecture Philosophy

Think of the matching engine as a **confidence cascade**:
- Each stage narrows the candidate set
- Each stage increases confidence in the match
- Earlier stages are cheaper (faster, deterministic)
- Later stages are more expensive (fuzzy algorithms, search queries)
- Users only see ambiguous cases requiring manual decision

## Pipeline Stages

### Stage 0: Previously-Known Mappings

**Purpose**: Instant retrieval for tracks already matched in previous syncs.

**Process**:
1. Check local database for existing mapping
2. Query: `SELECT target_id FROM track_mappings WHERE source_id = ? AND canonical_id = ?`
3. If found, return immediately with confidence = 1.0

**Data Structure**:
```swift
struct TrackMapping {
    let canonicalId: String      // Stable ID across both services
    let spotifyId: String?
    let appleMusicId: String?
    let matchedAt: Date
    let matchMethod: MatchMethod  // .isrc, .fuzzy, .manual, etc.
    let confidence: Double
}
```

**Performance**: O(1) database lookup, <1ms per track

**Exit Condition**: Mapping exists → return match, skip all other stages

---

### Stage 1: Strong ID-Based Matches (Deterministic)

**Purpose**: Find perfect matches using standardized identifiers.

#### 1.1: ISRC Matching

**ISRC** (International Standard Recording Code) is a unique identifier for recordings.

**Algorithm**:
```swift
func matchByISRC(source: Track, candidates: [Track]) -> Match? {
    guard let sourceISRC = source.isrc else { return nil }

    for candidate in candidates {
        guard let candidateISRC = candidate.isrc else { continue }

        // Exact ISRC match + duration tolerance
        if sourceISRC == candidateISRC &&
           abs(source.durationSeconds - candidate.durationSeconds) <= 2.0 {
            return Match(
                candidate: candidate,
                score: 1.0,
                method: .isrc,
                components: MatchScoreComponents(
                    isrcMatch: true,
                    titleScore: 1.0,
                    artistScore: 1.0,
                    albumScore: 1.0,
                    durationScore: 1.0
                )
            )
        }
    }

    return nil
}
```

**Confidence**: 1.0 (perfect match)

**False Positive Rate**: ~0.001% (ISRCs are globally unique)

**Availability**:
- Spotify: Available via `external_ids.isrc` field
- Apple Music: Available in track metadata

#### 1.2: Exact Metadata Matching

When ISRC is unavailable, fall back to exact metadata comparison.

**Algorithm**:
```swift
func matchByExactMetadata(source: Track, candidates: [Track]) -> Match? {
    for candidate in candidates {
        let artistMatch = source.artistName.lowercased() == candidate.artistName.lowercased()
        let titleMatch = source.trackName.lowercased() == candidate.trackName.lowercased()
        let albumMatch = source.albumName.lowercased() == candidate.albumName.lowercased()
        let durationMatch = abs(source.durationSeconds - candidate.durationSeconds) <= 2.0

        if artistMatch && titleMatch && albumMatch && durationMatch {
            return Match(
                candidate: candidate,
                score: 0.95,  // Slightly lower than ISRC
                method: .exactMetadata,
                components: MatchScoreComponents(
                    isrcMatch: false,
                    titleScore: 1.0,
                    artistScore: 1.0,
                    albumScore: 1.0,
                    durationScore: 1.0
                )
            )
        }
    }

    return nil
}
```

**Confidence**: 0.95

**Note**: Requires all metadata fields to match exactly (case-insensitive)

**Auto-Accept**: Both ISRC and exact metadata matches are auto-accepted without user prompt.

---

### Stage 2: Text Normalization & Canonical Strings

**Purpose**: Clean and standardize text before fuzzy matching to improve accuracy.

#### 2.1: Normalization Rules

**Operations** (applied in order):
1. **Unicode Normalization**: NFKD (Compatibility Decomposition)
2. **Lowercase**: Convert all characters to lowercase
3. **Strip Punctuation**: Remove `.`, `,`, `!`, `?`, `:`, `;`, `'`, `"`
4. **Remove Noise Patterns**:
   - `(feat. X)`, `(featuring X)`, `(ft. X)`, `(with X)`
   - `- Remastered YYYY`, `- Remaster YYYY`, `(Remastered)`
   - `- Live`, `(Live)`, `- Live at ...`, `(Live at ...)`
   - `(Explicit)`, `(Explicit Version)`
   - `- Single Version`, `- Album Version`
   - `- Radio Edit`, `(Radio Edit)`
5. **Whitespace Normalization**: Replace multiple spaces with single space, trim

#### 2.2: Implementation

```swift
struct TrackTextNormalizer {
    static func normalize(_ text: String) -> String {
        var normalized = text

        // Unicode normalization
        normalized = normalized.precomposedStringWithCompatibilityMapping

        // Lowercase
        normalized = normalized.lowercased()

        // Remove noise patterns (regex)
        let patterns = [
            #"\(feat\.?\s+[^)]+\)"#,
            #"\(featuring\s+[^)]+\)"#,
            #"\(ft\.?\s+[^)]+\)"#,
            #"\(with\s+[^)]+\)"#,
            #"-\s*remaster(ed)?\s*\d{4}"#,
            #"\(remaster(ed)?\)"#,
            #"-\s*live(\s+at\s+[^-]+)?"#,
            #"\(live(\s+at\s+[^)]+)?\)"#,
            #"\(explicit(\s+version)?\)"#,
            #"-\s*(single|album)\s+version"#,
            #"-\s*radio\s+edit"#,
            #"\(radio\s+edit\)"#
        ]

        for pattern in patterns {
            normalized = normalized.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        // Strip punctuation
        let punctuation = CharacterSet.punctuationCharacters
        normalized = normalized.components(separatedBy: punctuation).joined()

        // Normalize whitespace
        normalized = normalized.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        return normalized
    }
}
```

#### 2.3: Canonical Track Key

```swift
struct NormalizedTrackKey: Hashable {
    let artistKey: String   // Normalized primary artist
    let titleKey: String    // Normalized track title
    let albumKey: String?   // Normalized album title (optional)

    init(from track: Track) {
        self.artistKey = TrackTextNormalizer.normalize(track.artistName)
        self.titleKey = TrackTextNormalizer.normalize(track.trackName)
        self.albumKey = track.albumName.map { TrackTextNormalizer.normalize($0) }
    }
}
```

**Why This Matters**:
- Eliminates false negatives from minor variations
- Examples:
  - "Bohemian Rhapsody - Remastered 2011" → "bohemian rhapsody"
  - "Let It Be (feat. John Doe)" → "let it be"
  - "Song Title (Live at Madison Square Garden)" → "song title"

---

### Stage 3: Candidate Generation via Search

**Purpose**: Query the target service's catalog to find a small set of potential matches.

#### 3.1: Search Query Construction

For each source track, construct search queries:

**Primary Query** (preferred):
```swift
let query = "\(normalizedArtist) \(normalizedTitle)"
// Example: "beatles let it be"
```

**Fallback Query** (if primary returns <3 results):
```swift
let query = normalizedTitle
// Example: "let it be"
```

**Album-Specific Query** (optional third attempt):
```swift
let query = "\(normalizedArtist) \(normalizedTitle) \(normalizedAlbum)"
// Example: "beatles let it be let it be"
```

#### 3.2: Service-Specific Search

**Spotify Search** (using SpotifyAPI):
```swift
func searchSpotify(query: String, limit: Int = 10) async throws -> [Track] {
    let searchResults = try await spotifyAPI.search(
        query: query,
        categories: [.track],
        limit: limit
    )

    return searchResults.tracks?.items ?? []
}
```

**Apple Music Search** (using MusadoraKit):
```swift
func searchAppleMusic(query: String, limit: Int = 10) async throws -> [Track] {
    let searchResults = try await MusicCatalogSearchRequest(
        term: query,
        types: [Song.self]
    )
    .response()

    return Array(searchResults.songs.prefix(limit))
}
```

#### 3.3: Candidate Pool

- **Target Size**: 5-10 candidates per track
- **Strategy**: Prefer recall over precision at this stage
- **Optimization**: Cache search results for common queries

**Output**: Array of candidate tracks for fuzzy scoring

---

### Stage 4: Fuzzy Scoring Per Candidate

**Purpose**: Calculate a multi-component similarity score for each candidate.

#### 4.1: Match Score Data Structure

```swift
struct MatchScore {
    let candidateId: String
    let candidate: Track
    let score: Double              // Combined score: 0.0 to 1.0
    let components: MatchScoreComponents
    let method: MatchMethod

    var isAutoMatch: Bool {
        score >= 0.85
    }

    var isAmbiguous: Bool {
        score >= 0.65 && score < 0.85
    }
}

struct MatchScoreComponents {
    let titleScore: Double       // 0.0 to 1.0
    let artistScore: Double      // 0.0 to 1.0
    let albumScore: Double       // 0.0 to 1.0
    let durationScore: Double    // 0.0 to 1.0
    let isrcBonus: Double        // 0.0 or 0.2

    // For debugging/transparency
    var breakdown: String {
        """
        Title: \(String(format: "%.2f", titleScore))
        Artist: \(String(format: "%.2f", artistScore))
        Album: \(String(format: "%.2f", albumScore))
        Duration: \(String(format: "%.2f", durationScore))
        ISRC Bonus: \(String(format: "%.2f", isrcBonus))
        """
    }
}
```

#### 4.2: Component Scoring Algorithms

**Title Score**:
```swift
func calculateTitleScore(source: String, candidate: String) -> Double {
    // Use FuzzyMatchingSwift or similar
    let similarity = FuzzyMatching.similarity(
        source: TrackTextNormalizer.normalize(source),
        target: TrackTextNormalizer.normalize(candidate)
    )

    // Normalize to 0.0-1.0 range
    return min(max(similarity, 0.0), 1.0)
}
```

**Artist Score**:
```swift
func calculateArtistScore(source: Track, candidate: Track) -> Double {
    let sourceArtists = source.allArtists.map { TrackTextNormalizer.normalize($0) }
    let candidateArtists = candidate.allArtists.map { TrackTextNormalizer.normalize($0) }

    // Primary artist match (most important)
    let primaryScore = FuzzyMatching.similarity(
        source: sourceArtists.first ?? "",
        target: candidateArtists.first ?? ""
    )

    // Bonus for any overlapping collaborators
    let overlap = Set(sourceArtists).intersection(Set(candidateArtists))
    let overlapBonus = min(Double(overlap.count) * 0.1, 0.2)

    return min(primaryScore + overlapBonus, 1.0)
}
```

**Album Score**:
```swift
func calculateAlbumScore(source: String?, candidate: String?) -> Double {
    guard let sourceAlbum = source, let candidateAlbum = candidate else {
        return 0.5  // Neutral score if album info missing
    }

    return FuzzyMatching.similarity(
        source: TrackTextNormalizer.normalize(sourceAlbum),
        target: TrackTextNormalizer.normalize(candidateAlbum)
    )
}
```

**Duration Score**:
```swift
func calculateDurationScore(sourceDuration: Double, candidateDuration: Double) -> Double {
    let delta = abs(sourceDuration - candidateDuration)

    switch delta {
    case 0...1:
        return 1.0
    case 1...5:
        // Linear interpolation from 1.0 to 0.5
        return 1.0 - (delta - 1.0) * 0.125
    case 5...10:
        // Linear interpolation from 0.5 to 0.0
        return 0.5 - (delta - 5.0) * 0.1
    default:
        return 0.0
    }
}
```

**ISRC Bonus**:
```swift
func calculateISRCBonus(source: Track, candidate: Track) -> Double {
    guard let sourceISRC = source.isrc,
          let candidateISRC = candidate.isrc else {
        return 0.0
    }

    return sourceISRC == candidateISRC ? 0.2 : 0.0
}
```

#### 4.3: Combined Score

```swift
func calculateCombinedScore(components: MatchScoreComponents) -> Double {
    let baseScore =
        0.40 * components.titleScore +
        0.30 * components.artistScore +
        0.15 * components.albumScore +
        0.15 * components.durationScore

    let finalScore = min(baseScore + components.isrcBonus, 1.0)

    return finalScore
}
```

**Weights Explanation**:
- **Title (40%)**: Most distinctive identifier for users
- **Artist (30%)**: Critical for disambiguation, but titles vary more
- **Album (15%)**: Helpful but less critical (many singles, compilations)
- **Duration (15%)**: Good tie-breaker, but can vary (edits, fades)
- **ISRC Bonus (+20%)**: Strong signal when available

#### 4.4: Scoring All Candidates

```swift
func scoreAllCandidates(source: Track, candidates: [Track]) -> [MatchScore] {
    let scores = candidates.map { candidate in
        let components = MatchScoreComponents(
            titleScore: calculateTitleScore(source: source.trackName, candidate: candidate.trackName),
            artistScore: calculateArtistScore(source: source, candidate: candidate),
            albumScore: calculateAlbumScore(source: source.albumName, candidate: candidate.albumName),
            durationScore: calculateDurationScore(
                sourceDuration: source.durationSeconds,
                candidateDuration: candidate.durationSeconds
            ),
            isrcBonus: calculateISRCBonus(source: source, candidate: candidate)
        )

        let combinedScore = calculateCombinedScore(components: components)

        return MatchScore(
            candidateId: candidate.id,
            candidate: candidate,
            score: combinedScore,
            components: components,
            method: .fuzzy
        )
    }

    // Sort by score descending
    return scores.sorted { $0.score > $1.score }
}
```

---

### Stage 5: Decision Logic (Auto vs Ambiguous vs No-Match)

**Purpose**: Classify matches into actionable categories based on confidence and margin.

#### 5.1: Decision Thresholds

```swift
struct MatchThresholds {
    // Auto-accept thresholds
    static let autoMatchMinScore: Double = 0.85
    static let autoMatchMinMargin: Double = 0.10

    // Ambiguous range
    static let ambiguousMinScore: Double = 0.65

    // Below this = no match
    static let noMatchThreshold: Double = 0.65
}
```

#### 5.2: Decision Algorithm

```swift
enum MatchDecision {
    case autoMatch(MatchScore)
    case ambiguous([MatchScore])  // Top candidates for user review
    case noMatch
}

func classifyMatch(sortedScores: [MatchScore]) -> MatchDecision {
    guard let best = sortedScores.first else {
        return .noMatch
    }

    let secondBest = sortedScores.count > 1 ? sortedScores[1] : nil
    let margin = secondBest.map { best.score - $0.score } ?? 1.0

    // Auto-match criteria
    if best.score >= MatchThresholds.autoMatchMinScore &&
       margin >= MatchThresholds.autoMatchMinMargin {
        return .autoMatch(best)
    }

    // Ambiguous criteria
    if best.score >= MatchThresholds.ambiguousMinScore {
        let topCandidates = sortedScores.prefix(3).filter {
            $0.score >= MatchThresholds.ambiguousMinScore
        }
        return .ambiguous(Array(topCandidates))
    }

    // No match
    return .noMatch
}
```

#### 5.3: Decision Matrix

| Best Score | Margin (vs 2nd) | Decision    | Rationale                              |
|------------|-----------------|-------------|----------------------------------------|
| ≥ 0.85     | ≥ 0.10          | Auto-match  | Clear winner, high confidence          |
| ≥ 0.85     | < 0.10          | Ambiguous   | High scores but close competitors      |
| 0.65-0.84  | Any             | Ambiguous   | Medium confidence, user should verify  |
| < 0.65     | Any             | No match    | Low confidence, likely doesn't exist   |

#### 5.4: User Interaction for Ambiguous Matches

For ambiguous matches, present to user:
- Source track (Spotify or Apple Music)
- Top 2-3 candidates with scores
- Option to:
  - ✅ Select one candidate (store as manual match)
  - ⏭️ Skip this track (no mapping)
  - 🔍 Search manually (open search interface)

---

### Stage 6: Optional Audio Fingerprint Fallback

**Purpose**: Handle edge cases with severely mismatched metadata using acoustic analysis.

**When to Use**:
- Stage 5 returned `noMatch`
- User has local audio files
- Willing to wait for fingerprint processing (~1-2s per track)

#### 6.1: Fingerprint Generation

```swift
import ChromaSwift

func generateFingerprint(audioFileURL: URL) async throws -> Fingerprint {
    let fingerprint = try await ChromaSwift.fingerprint(url: audioFileURL)
    return fingerprint
}
```

#### 6.2: AcoustID Lookup

```swift
struct AcoustIDClient {
    func lookup(fingerprint: Fingerprint, duration: Int) async throws -> [AcoustIDResult] {
        let apiKey = Configuration.acoustIDKey
        let endpoint = "https://api.acoustid.org/v2/lookup"

        let parameters = [
            "client": apiKey,
            "fingerprint": fingerprint.encoded,
            "duration": String(duration),
            "meta": "recordings+releasegroups+compress"
        ]

        // HTTP POST request
        let results = try await performRequest(endpoint: endpoint, parameters: parameters)
        return results
    }
}

struct AcoustIDResult {
    let acoustID: String
    let score: Double
    let recordings: [MusicBrainzRecording]
}

struct MusicBrainzRecording {
    let mbid: String
    let title: String
    let artists: [MusicBrainzArtist]
    let duration: Int?
    let isrcs: [String]
}
```

#### 6.3: Integration with Main Pipeline

```swift
func matchWithFingerprintFallback(
    source: Track,
    audioFileURL: URL?
) async throws -> MatchDecision {
    // Try standard pipeline first
    let candidates = try await generateCandidates(for: source)
    let scores = scoreAllCandidates(source: source, candidates: candidates)
    let decision = classifyMatch(sortedScores: scores)

    // If no match and audio file available, try fingerprinting
    if case .noMatch = decision, let audioURL = audioFileURL {
        let fingerprint = try await generateFingerprint(audioFileURL: audioURL)
        let acoustIDResults = try await acoustIDClient.lookup(
            fingerprint: fingerprint,
            duration: Int(source.durationSeconds)
        )

        // Extract ISRCs from AcoustID results
        let isrcs = acoustIDResults.flatMap { $0.recordings.flatMap { $0.isrcs } }

        // Re-search using discovered ISRCs
        for isrc in isrcs {
            if let match = try await searchByISRC(isrc: isrc) {
                return .autoMatch(match)
            }
        }
    }

    return decision
}
```

#### 6.4: Performance Considerations

- **Fingerprinting Time**: ~1-2 seconds per track
- **Network Latency**: ~200-500ms per AcoustID query
- **Recommended Strategy**:
  - Only use for "no match" cases
  - Process in background, batch queries
  - Cache AcoustID results locally

---

## Performance Metrics & Optimization

### Expected Performance

| Stage                     | Time per Track | Success Rate |
|---------------------------|----------------|--------------|
| Stage 0: Known Mappings   | <1ms           | Varies       |
| Stage 1: ISRC Match       | ~50ms          | ~60-70%      |
| Stage 1: Exact Metadata   | ~50ms          | ~10-15%      |
| Stage 3-5: Fuzzy Pipeline | ~500-1000ms    | ~15-20%      |
| Stage 6: Fingerprint      | ~2-3s          | ~5-10%       |

### Cumulative Match Rate (Target)

- **Auto-matched**: ≥ 85% of tracks
- **Ambiguous** (user review): ~10-12%
- **No match**: ~3-5%

### Optimization Strategies

1. **Batch Processing**: Process tracks in parallel (10-20 concurrent)
2. **Caching**:
   - Cache search results for common queries
   - Cache ISRC lookups
   - Persist all matches to database immediately
3. **Progressive Display**: Show results as they complete, don't wait for entire library
4. **Smart Ordering**: Process high-confidence tracks first (those with ISRCs)

---

## Tuning & Calibration

### Adjustable Parameters

| Parameter                  | Default | Range      | Impact                          |
|----------------------------|---------|------------|---------------------------------|
| `autoMatchMinScore`        | 0.85    | 0.80-0.90  | Higher = fewer auto, more manual|
| `autoMatchMinMargin`       | 0.10    | 0.05-0.20  | Higher = require clearer winner |
| `ambiguousMinScore`        | 0.65    | 0.60-0.75  | Lower = more no-matches         |
| Title weight               | 0.40    | 0.30-0.50  | Emphasize title vs other fields |
| Artist weight              | 0.30    | 0.20-0.40  | Emphasize artist matching       |
| Duration tolerance (exact) | 2s      | 1-5s       | Stricter = fewer false positives|

### Evaluation Metrics

```swift
struct MatchingQualityMetrics {
    let totalTracks: Int
    let autoMatched: Int
    let ambiguous: Int
    let noMatch: Int

    // Ground truth comparison (when available)
    let truePositives: Int
    let falsePositives: Int
    let falseNegatives: Int

    var precision: Double {
        Double(truePositives) / Double(truePositives + falsePositives)
    }

    var recall: Double {
        Double(truePositives) / Double(truePositives + falseNegatives)
    }

    var f1Score: Double {
        2 * (precision * recall) / (precision + recall)
    }
}
```

### Target Metrics

- **Precision**: ≥ 98% (very few false auto-matches)
- **Recall**: ≥ 95% (find most matches)
- **F1 Score**: ≥ 0.96

---

## Error Handling

### Network Failures

```swift
enum MatchingError: Error {
    case networkTimeout
    case serviceUnavailable(service: String)
    case rateLimitExceeded
    case invalidResponse
    case authenticationFailed
}
```

**Retry Strategy**:
- Exponential backoff: 1s, 2s, 4s
- Max 3 retries per request
- Circuit breaker: pause service queries after 5 consecutive failures

### Data Quality Issues

```swift
enum DataQualityIssue: Error {
    case missingISRC
    case missingMetadata(field: String)
    case invalidDuration
    case emptySearchResults
}
```

**Handling**:
- Log warnings for analytics
- Fall back to next pipeline stage
- Never crash, always degrade gracefully

---

## Testing Strategy

See [EPIC_ADVANCED_MATCHING_ENGINE.md](EPIC_ADVANCED_MATCHING_ENGINE.md) for detailed testing acceptance criteria.

### Unit Tests

- Text normalization with edge cases
- Fuzzy scoring algorithms
- Decision logic boundary conditions

### Integration Tests

- End-to-end pipeline with mock API responses
- Known test corpus (500+ tracks with ground truth)

### Performance Tests

- Batch processing of 10,000 tracks
- Memory usage profiling
- Concurrent request handling

---

## Future Enhancements

1. **Machine Learning**:
   - Train ML model on user corrections
   - Learn personalized thresholds

2. **Collaborative Filtering**:
   - Share anonymized mappings between users
   - "Wisdom of the crowd" for ambiguous cases

3. **Acoustic Analysis**:
   - Tempo, key, energy matching
   - Audio similarity beyond fingerprinting

4. **Cross-Service Features**:
   - Handle region-specific availability
   - Map to alternative versions (live, acoustic, etc.)
