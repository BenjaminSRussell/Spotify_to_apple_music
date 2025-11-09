# Epic 4: Advanced Matching Engine

**Epic Owner**: Engineering Team
**Priority**: P0 (Critical Path)
**Estimated Duration**: 6-8 weeks
**Dependencies**: Epic 1 (Core Infrastructure), Epic 2 (API Integration)

## Epic Overview

Build a sophisticated, multi-stage track matching engine that identifies corresponding tracks between Spotify and Apple Music catalogs with ≥95% accuracy. The engine combines deterministic ID-based matching (ISRC), fuzzy string similarity, and optional audio fingerprinting to minimize false positives while maximizing match coverage.

## Success Metrics

- **Match Rate**: ≥ 95% of tracks that exist on both services are correctly matched
- **False Match Rate**: ≤ 2% (wrong auto-matches)
- **Auto-Match Rate**: ≥ 85% (no user intervention required)
- **Performance**: < 1 second average per track (excluding fingerprinting)
- **User Satisfaction**: ≥ 90% approval on manual match UI

## Technical Foundation

See [MATCHING_PIPELINE.md](./MATCHING_PIPELINE.md) for detailed technical specifications.

See [LIBRARIES.md](./LIBRARIES.md) for dependency information.

---

## Stories & Tasks

### E4-A1: Integrate Fuzzy String Matching Library

**Story**: As a developer, I need fuzzy string matching capabilities integrated into the project so I can compare track metadata with tolerance for variations.

**Business Value**: Foundation for all fuzzy matching logic; enables 15-20% of matches that would otherwise require manual intervention.

**Acceptance Criteria**:
- [ ] FuzzyMatchingSwift and Fuse-swift added as SPM dependencies
- [ ] Wrapper module `StringSimilarity` created with documented API
- [ ] Unit tests demonstrate:
  - Same title variants (e.g., "Song" vs "song") score > 0.9
  - Clearly different titles score < 0.5
  - Edge cases handled (empty strings, special characters, Unicode)
- [ ] All wrapper functions return normalized values ∈ [0,1]
- [ ] Performance benchmark: < 1ms per comparison

#### Tasks

**E4-A1.1**: Add SPM Dependencies
```swift
// Add to Package.swift:
dependencies: [
    .package(url: "https://github.com/seanoshea/FuzzyMatchingSwift.git", from: "1.0.0"),
    .package(url: "https://github.com/krisk/fuse-swift.git", from: "1.0.0"),
]
```
- Update Package.swift
- Resolve dependencies
- Verify builds successfully

**E4-A1.2**: Create `StringSimilarity` Module
- Create `Sources/StringSimilarity/StringSimilarity.swift`
- Implement wrapper functions:
  ```swift
  public func similarity(_ a: String, _ b: String) -> Double
  public func fuzzySearch(_ query: String, in candidates: [String]) -> [(String, Double)]
  ```
- Add inline documentation for each public API

**E4-A1.3**: Write Unit Tests
- Create `Tests/StringSimilarityTests/StringSimilarityTests.swift`
- Test cases:
  - Identical strings → 1.0
  - Single character difference → ~0.9
  - Completely different → ~0.0
  - Empty string handling
  - Unicode normalization (e.g., "café" vs "cafe")
  - Very long strings (performance)

**E4-A1.4**: Performance Benchmark
- Create benchmark suite
- Measure time for 1,000 comparisons
- Optimize if needed (e.g., caching, pre-normalization)

**Story Points**: 5
**Estimated Duration**: 3-4 days

---

### E4-A2: Implement String Normalization Pipeline

**Story**: As a developer, I need a robust text normalization utility so track metadata can be cleaned and standardized before comparison.

**Business Value**: Significantly improves fuzzy matching accuracy by eliminating noise like "(feat. X)", "- Remastered", etc. Critical for reducing false negatives.

**Acceptance Criteria**:
- [ ] `TrackTextNormalizer` class created with static normalization function
- [ ] All specified noise patterns removed correctly (see test cases)
- [ ] Unicode normalization (NFKD) applied
- [ ] Normalization is deterministic (same input → same output)
- [ ] Performance: < 0.5ms per string
- [ ] Unit tests pass for all real-world edge cases

#### Tasks

**E4-A2.1**: Implement `TrackTextNormalizer`
- Create `Sources/MatchingEngine/TrackTextNormalizer.swift`
- Implement:
  ```swift
  struct TrackTextNormalizer {
      static func normalize(_ text: String) -> String
  }
  ```
- Apply transformations:
  1. Unicode NFKD normalization
  2. Lowercase conversion
  3. Regex pattern removal (see spec)
  4. Punctuation stripping
  5. Whitespace normalization

**E4-A2.2**: Define Noise Patterns
- Create regex patterns for:
  - `(feat. X)`, `(featuring X)`, `(ft. X)`, `(with X)`
  - `- Remastered YYYY`, `(Remastered)`
  - `- Live`, `(Live at ...)`, etc.
  - `(Explicit)`, `(Explicit Version)`
  - `- Single/Album Version`, `- Radio Edit`
- Store patterns in static configuration

**E4-A2.3**: Write Comprehensive Tests
- Test cases (input → expected output):
  - `"Song Name (feat. Someone)"` → `"song name"`
  - `"Track - Remastered 2011"` → `"track"`
  - `"Song (Live at Wembley)"` → `"song"`
  - `"Title (Explicit Version)"` → `"title"`
  - `"Let It Be - The Beatles"` → `"let it be the beatles"`
  - Unicode: `"Café Müncher"` → `"cafe muncher"`

**E4-A2.4**: Create `NormalizedTrackKey` Struct
- Implement:
  ```swift
  struct NormalizedTrackKey: Hashable {
      let artistKey: String
      let titleKey: String
      let albumKey: String?
  }
  ```
- Add initializer from `Track` model

**Story Points**: 5
**Estimated Duration**: 3-4 days

---

### E4-A3: Strong ID-Based Match Module

**Story**: As a developer, I need a deterministic matching module using ISRC and exact metadata so I can auto-match tracks with 100% confidence.

**Business Value**: Handles 60-70% of matches with perfect accuracy, zero user intervention required. Foundational for high-quality UX.

**Acceptance Criteria**:
- [ ] ISRC fields extracted from both Spotify and Apple Music APIs
- [ ] `StrongMatcher` module created with ISRC + duration matching
- [ ] On test set with known ISRCs: ≥ 99% match rate
- [ ] Zero false positives in negative test set (different tracks with different ISRCs)
- [ ] Exact metadata fallback implemented for non-ISRC tracks
- [ ] All matches tagged with `MatchMethod` enum for analytics

#### Tasks

**E4-A3.1**: Extract ISRC from API Responses
- Spotify: Parse `external_ids.isrc` from track objects
- Apple Music: Parse ISRC from MusicKit `Song` metadata
- Handle missing ISRC gracefully (return `nil`)

**E4-A3.2**: Implement `StrongMatcher`
- Create `Sources/MatchingEngine/StrongMatcher.swift`
- Implement:
  ```swift
  struct StrongMatcher {
      func matchByISRC(source: Track, candidates: [Track]) -> Match?
      func matchByExactMetadata(source: Track, candidates: [Track]) -> Match?
  }
  ```
- ISRC matching logic:
  - Compare ISRCs (case-insensitive, just in case)
  - Verify duration within 2 seconds
  - Return score = 1.0
- Exact metadata logic:
  - Compare artist, title, album (normalized)
  - Verify duration within 2 seconds
  - Return score = 0.95

**E4-A3.3**: Define Match Models
```swift
struct Match {
    let candidate: Track
    let score: Double
    let method: MatchMethod
    let components: MatchScoreComponents
}

enum MatchMethod {
    case isrc
    case exactMetadata
    case fuzzy
    case manual
    case fingerprint
}
```

**E4-A3.4**: Create Test Corpus
- Collect 100 known Spotify ↔ Apple Music track pairs with ISRCs
- Create negative test set (different tracks)
- Write integration tests
- Verify ≥ 99% accuracy

**E4-A3.5**: Add Analytics Logging
- Log match method for each successful match
- Track ISRC availability rate (what % of tracks have ISRCs)
- Log edge cases (ISRC mismatch, duration mismatch)

**Story Points**: 8
**Estimated Duration**: 5-6 days

---

### E4-A4: Candidate Generator via Service Search

**Story**: As a developer, I need to query each service's catalog to find candidate matches so I have a manageable set of tracks to score.

**Business Value**: Reduces fuzzy matching search space from millions to 5-10 candidates per track, making the process fast and scalable.

**Acceptance Criteria**:
- [ ] `CandidateGenerator` module created
- [ ] Search implementations for both Spotify and Apple Music
- [ ] Query construction optimized (primary, fallback strategies)
- [ ] On test queries, correct track appears in candidates ≥ 95% of the time
- [ ] Network errors handled gracefully (return empty list, log error)
- [ ] Rate limiting respected (use exponential backoff)
- [ ] Search results cached for common queries

#### Tasks

**E4-A4.1**: Implement `CandidateGenerator`
- Create `Sources/MatchingEngine/CandidateGenerator.swift`
- Implement:
  ```swift
  struct CandidateGenerator {
      func candidatesForSpotifyTrack(onApple track: Track) async throws -> [Track]
      func candidatesForAppleTrack(onSpotify track: Track) async throws -> [Track]
  }
  ```

**E4-A4.2**: Implement Search Query Construction
- Primary query: `"{artist} {title}"`
- Fallback query: `"{title}"`
- Album-specific query: `"{artist} {title} {album}"`
- Use normalized strings from `TrackTextNormalizer`

**E4-A4.3**: Integrate Spotify Search API
- Use `SpotifyAPI.search(query:, categories: [.track], limit: 10)`
- Parse response into `Track` models
- Handle pagination if needed

**E4-A4.4**: Integrate Apple Music Search API
- Use `MusicCatalogSearchRequest` via MusadoraKit
- Parse `Song` results into `Track` models
- Limit to top 10 results

**E4-A4.5**: Implement Caching Layer
- Use in-memory cache (NSCache or similar)
- Key: normalized query string
- Value: array of candidate tracks
- TTL: 24 hours

**E4-A4.6**: Error Handling & Retry Logic
- Catch network errors (timeout, unavailable)
- Implement exponential backoff (1s, 2s, 4s)
- Max 3 retries per query
- Log failures for monitoring

**E4-A4.7**: Create Validation Test Set
- Build test set of 100 known tracks
- Run search queries
- Measure recall: % of queries where correct track is in results
- Target: ≥ 95% recall

**Story Points**: 8
**Estimated Duration**: 5-6 days

---

### E4-A5: Composite Scoring Engine

**Story**: As a developer, I need a multi-component scoring system so I can calculate match confidence for each candidate based on title, artist, album, duration, and ISRC.

**Business Value**: The heart of the matching engine; determines which tracks auto-match vs require user review. Direct impact on UX and accuracy.

**Acceptance Criteria**:
- [ ] `MatchScorer` module created with component scoring functions
- [ ] `MatchScore` and `MatchScoreComponents` data models defined
- [ ] On labeled test set: correct matches rank #1 with score ≥ 0.85 in ≥ 90% of cases
- [ ] Obviously wrong candidates score < 0.6
- [ ] Score components logged for debugging/transparency
- [ ] Weights are configurable (title: 0.4, artist: 0.3, album: 0.15, duration: 0.15)
- [ ] Performance: score 10 candidates in < 10ms

#### Tasks

**E4-A5.1**: Define Data Models
```swift
struct MatchScore {
    let candidateId: String
    let candidate: Track
    let score: Double
    let components: MatchScoreComponents
    let method: MatchMethod
}

struct MatchScoreComponents {
    let titleScore: Double
    let artistScore: Double
    let albumScore: Double
    let durationScore: Double
    let isrcBonus: Double
}
```

**E4-A5.2**: Implement Component Scoring Functions
- `calculateTitleScore(source:, candidate:) -> Double`
  - Use FuzzyMatchingSwift on normalized titles
- `calculateArtistScore(source:, candidate:) -> Double`
  - Primary artist match + collaboration overlap bonus
- `calculateAlbumScore(source:, candidate:) -> Double`
  - Fuzzy match on normalized album names
  - Return 0.5 if album info missing
- `calculateDurationScore(source:, candidate:) -> Double`
  - Implement tiered scoring (see spec)
- `calculateISRCBonus(source:, candidate:) -> Double`
  - Return 0.2 if ISRCs match, else 0.0

**E4-A5.3**: Implement Combined Score Calculation
```swift
func calculateCombinedScore(components: MatchScoreComponents) -> Double {
    let baseScore =
        0.40 * components.titleScore +
        0.30 * components.artistScore +
        0.15 * components.albumScore +
        0.15 * components.durationScore

    return min(baseScore + components.isrcBonus, 1.0)
}
```

**E4-A5.4**: Implement Batch Scoring
```swift
func scoreAllCandidates(source: Track, candidates: [Track]) -> [MatchScore] {
    // Calculate scores for all candidates
    // Sort by score descending
    // Return sorted array
}
```

**E4-A5.5**: Create Labeled Test Corpus
- Build dataset of 500 known track pairs with ground truth
- Include:
  - Easy cases (identical metadata)
  - Medium cases (minor variations)
  - Hard cases (live versions, remasters, different artists)
  - Negative cases (wrong matches)

**E4-A5.6**: Validate Scoring Quality
- Run scorer on test corpus
- Measure:
  - % where correct match ranks #1
  - % where correct match is in top 3
  - Average score of correct matches
  - Average score of wrong matches
- Tune weights if needed

**E4-A5.7**: Add Logging & Debugging
- Log score components for each match
- Create debug mode that outputs detailed breakdown
- Add telemetry for score distribution analysis

**Story Points**: 13
**Estimated Duration**: 8-10 days

---

### E4-A6: Decision Logic (Auto-Match vs Ambiguous vs No-Match)

**Story**: As a developer, I need threshold-based decision logic so the system can automatically classify matches as confident, ambiguous, or no-match.

**Business Value**: Automates the majority of matches while surfacing only uncertain cases to users. Balances automation with safety.

**Acceptance Criteria**:
- [ ] Decision thresholds implemented and configurable
- [ ] `MatchDecision` enum defined with three states
- [ ] On test data: majority of obvious matches → auto (≥ 85%)
- [ ] Very few wrong auto decisions (< 2% false positive rate)
- [ ] Ambiguous and no-match cases correctly classified
- [ ] Thresholds stored in config file (tunable without code changes)

#### Tasks

**E4-A6.1**: Define `MatchDecision` Enum
```swift
enum MatchDecision {
    case autoMatch(MatchScore)
    case ambiguous([MatchScore])  // Top 2-3 candidates
    case noMatch
}
```

**E4-A6.2**: Define Threshold Configuration
```swift
struct MatchThresholds {
    static let autoMatchMinScore: Double = 0.85
    static let autoMatchMinMargin: Double = 0.10
    static let ambiguousMinScore: Double = 0.65
}
```
- Store in configuration file (JSON or plist)
- Load at runtime

**E4-A6.3**: Implement Decision Algorithm
```swift
func classifyMatch(sortedScores: [MatchScore]) -> MatchDecision {
    guard let best = sortedScores.first else {
        return .noMatch
    }

    let margin = sortedScores.count > 1 ? best.score - sortedScores[1].score : 1.0

    if best.score >= MatchThresholds.autoMatchMinScore &&
       margin >= MatchThresholds.autoMatchMinMargin {
        return .autoMatch(best)
    }

    if best.score >= MatchThresholds.ambiguousMinScore {
        let topCandidates = sortedScores.prefix(3).filter {
            $0.score >= MatchThresholds.ambiguousMinScore
        }
        return .ambiguous(Array(topCandidates))
    }

    return .noMatch
}
```

**E4-A6.4**: Create Decision Matrix Visualization
- Document decision boundaries
- Create test cases for each boundary:
  - Auto: score=0.86, margin=0.12 → auto
  - Ambiguous: score=0.87, margin=0.05 → ambiguous
  - Ambiguous: score=0.70, margin=0.15 → ambiguous
  - No match: score=0.60, margin=0.20 → no match

**E4-A6.5**: Validate Decision Quality
- Run on test corpus
- Measure:
  - Auto-match rate
  - Ambiguous rate
  - No-match rate
  - False positive rate (wrong auto-matches)
  - False negative rate (missed matches)
- Target metrics:
  - False positive rate < 2%
  - Auto-match rate ≥ 85%

**E4-A6.6**: Implement Threshold Tuning UI (Optional)
- Admin/debug interface to adjust thresholds
- Show impact on test corpus in real-time
- Allow A/B testing different configurations

**Story Points**: 8
**Estimated Duration**: 5-6 days

---

### E4-A7: Ambiguity Handling + Manual Overrides

**Story**: As a user, I need to review and resolve ambiguous matches so I can ensure my library is correctly migrated.

**Technical Story**: As a developer, I need to store and respect manual match decisions so users don't get asked twice for the same track.

**Business Value**: Critical for user trust and data quality. Ensures users have control over their library migration.

**Acceptance Criteria**:
- [ ] Database table `ManualTrackMapping` created
- [ ] UI elements to display ambiguous candidates with scores
- [ ] User can select one candidate, skip, or search manually
- [ ] Manual decisions persisted to database
- [ ] Future syncs respect manual decisions (bypass matching pipeline)
- [ ] User can view and edit manual decisions in settings
- [ ] Analytics tracked (what % of users override vs accept suggestions)

#### Tasks

**E4-A7.1**: Design Database Schema
```sql
CREATE TABLE ManualTrackMapping (
    id UUID PRIMARY KEY,
    source_track_id VARCHAR NOT NULL,
    source_service VARCHAR NOT NULL,  -- 'spotify' or 'apple_music'
    target_track_id VARCHAR NOT NULL,
    target_service VARCHAR NOT NULL,
    user_id UUID NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    confidence_score DOUBLE,  -- Original score before manual override
    UNIQUE(source_track_id, user_id)
);

CREATE INDEX idx_manual_mapping_user ON ManualTrackMapping(user_id);
CREATE INDEX idx_manual_mapping_source ON ManualTrackMapping(source_track_id);
```

**E4-A7.2**: Implement Data Access Layer
```swift
struct ManualMappingRepository {
    func saveManualMapping(_ mapping: ManualTrackMapping) async throws
    func getManualMapping(sourceTrackId: String, userId: String) async throws -> ManualTrackMapping?
    func getAllManualMappings(userId: String) async throws -> [ManualTrackMapping]
    func deleteManualMapping(id: UUID) async throws
}
```

**E4-A7.3**: Update Matching Pipeline to Check Manual Mappings
- At Stage 0, check for manual mappings before other stages
- If found, return immediately with `MatchMethod.manual`

**E4-A7.4**: Design Ambiguous Match UI
- Components:
  - Source track display (artwork, title, artist, album)
  - List of 2-3 candidate tracks with:
    - Artwork thumbnail
    - Title, artist, album
    - Match score (as percentage)
    - Score component breakdown (expandable)
  - Actions:
    - ✅ "Select this match" button per candidate
    - ⏭️ "Skip this track" button
    - 🔍 "Search manually" button

**E4-A7.5**: Implement UI Logic
- Display ambiguous matches in queue
- On user selection:
  - Save to `ManualTrackMapping`
  - Mark as resolved
  - Move to next ambiguous track
- On skip:
  - Mark as no-match
  - Move to next
- On manual search:
  - Open search interface
  - Allow free-form search
  - Save selected result as manual mapping

**E4-A7.6**: Create Manual Mapping Management UI
- Settings screen to view all manual mappings
- Filter by service (Spotify → Apple or vice versa)
- Option to delete mapping (re-run matching)
- Export manual mappings (JSON backup)

**E4-A7.7**: Add Analytics
- Track events:
  - Ambiguous match presented
  - User selected suggestion #1 vs #2 vs #3
  - User skipped
  - User searched manually
- Aggregate metrics:
  - Average score of accepted suggestions
  - % of ambiguous cases where user picks top suggestion
  - Common patterns in skipped tracks

**Story Points**: 13
**Estimated Duration**: 8-10 days

---

### E4-A8: Evaluation Harness for Mapping Quality

**Story**: As a developer, I need an automated evaluation system so I can measure matching pipeline quality and track improvements over time.

**Business Value**: Ensures quality doesn't regress. Provides data-driven basis for tuning thresholds and improving algorithms.

**Acceptance Criteria**:
- [ ] Labeled ground truth corpus of ≥ 500 track pairs created
- [ ] Automated test script that runs entire pipeline on corpus
- [ ] Metrics calculated: match rate, false match rate, ambiguous rate, precision, recall, F1
- [ ] Baseline goals met:
  - ≥ 95% correct match rate
  - ≤ 2% false match rate
  - Remaining are ambiguous or no-match (geo-locked, etc.)
- [ ] Report generated with per-category breakdown
- [ ] CI/CD integration (run on every PR)

#### Tasks

**E4-A8.1**: Build Ground Truth Corpus
- Collect tracks from multiple sources:
  - Popular tracks (Billboard, Spotify Top 50)
  - Niche genres (indie, classical, international)
  - Edge cases (live versions, remasters, compilations)
  - Regional tracks (different availability)
- For each track, manually verify:
  - Spotify ID
  - Apple Music ID (or mark as unavailable)
  - Metadata (title, artist, album, ISRC)
- Store in JSON format:
  ```json
  {
    "tracks": [
      {
        "spotify_id": "...",
        "apple_music_id": "...",
        "isrc": "...",
        "title": "...",
        "artist": "...",
        "album": "...",
        "notes": "Remastered version on Apple"
      }
    ]
  }
  ```

**E4-A8.2**: Implement Evaluation Script
```swift
struct MatchingEvaluator {
    func evaluate(corpus: [GroundTruthTrack]) async throws -> EvaluationReport
}

struct EvaluationReport {
    let totalTracks: Int
    let autoMatched: Int
    let ambiguous: Int
    let noMatch: Int

    let truePositives: Int
    let falsePositives: Int
    let falseNegatives: Int

    var precision: Double
    var recall: Double
    var f1Score: Double

    var categoryBreakdown: [String: CategoryMetrics]
}
```

**E4-A8.3**: Define Quality Metrics
- **Match Rate**: (TP + TN) / Total
- **False Match Rate**: FP / (TP + FP)
- **Precision**: TP / (TP + FP)
- **Recall**: TP / (TP + FN)
- **F1 Score**: 2 * (Precision * Recall) / (Precision + Recall)

**E4-A8.4**: Implement Category Breakdown
- Group tracks by:
  - Genre (pop, rock, classical, etc.)
  - Popularity (mainstream vs niche)
  - Metadata quality (has ISRC vs no ISRC)
  - Edge case type (live, remaster, cover, etc.)
- Calculate metrics per category
- Identify weak spots

**E4-A8.5**: Create Reporting Dashboard
- Generate HTML or markdown report
- Include:
  - Overall metrics summary
  - Category breakdowns
  - List of false positives (for manual review)
  - List of false negatives (missed matches)
  - Score distribution histogram
- Example output:
  ```
  Matching Pipeline Evaluation Report
  ====================================
  Total Tracks: 500
  Auto-Matched: 470 (94.0%)
  Ambiguous: 20 (4.0%)
  No Match: 10 (2.0%)

  Quality Metrics:
  - Precision: 98.0%
  - Recall: 96.5%
  - F1 Score: 97.2%

  Category Breakdown:
  - Pop (200 tracks): 98% match rate
  - Rock (150 tracks): 95% match rate
  - Classical (100 tracks): 88% match rate ⚠️
  - International (50 tracks): 90% match rate
  ```

**E4-A8.6**: Integrate into CI/CD
- Add evaluation as GitHub Actions workflow
- Run on every PR to `main`
- Post summary as PR comment
- Fail if metrics drop below thresholds:
  - F1 score < 0.95
  - False match rate > 3%

**E4-A8.7**: Create Continuous Monitoring
- Run evaluation weekly on production data (anonymized)
- Track metrics over time
- Alert if significant degradation detected

**Story Points**: 13
**Estimated Duration**: 8-10 days

---

### E4-A9 (Optional): Audio Fingerprint Fallback

**Story**: As a user with local audio files, I want the system to use acoustic analysis to identify tracks when metadata is insufficient.

**Business Value**: Handles edge cases (5-10% of library) where metadata-based matching fails. Particularly valuable for users migrating local file collections.

**Acceptance Criteria**:
- [ ] ChromaSwift integrated as SPM dependency
- [ ] Fingerprint generation works for common audio formats (MP3, FLAC, M4A, WAV)
- [ ] AcoustID lookup implemented with API key management
- [ ] Fingerprint results feed into standard matching pipeline
- [ ] On test set of local files: ≥ 80% correct identification
- [ ] Only used as last resort (after Stage 5 returns no-match)
- [ ] Performance acceptable (< 3 seconds per track)
- [ ] User consent obtained (privacy: fingerprints sent to third-party service)

#### Tasks

**E4-A9.1**: Add ChromaSwift Dependency
```swift
dependencies: [
    .package(url: "https://github.com/kissygalleryteam/ChromaSwift.git", from: "1.0.0"),
]
```

**E4-A9.2**: Implement Fingerprint Generation
```swift
struct AudioFingerprinter {
    func fingerprint(audioFileURL: URL) async throws -> Fingerprint
}
```
- Support formats: MP3, FLAC, M4A, WAV
- Handle errors (unsupported format, corrupted file)
- Return base64-encoded fingerprint

**E4-A9.3**: Implement AcoustID Client
```swift
struct AcoustIDClient {
    let apiKey: String

    func lookup(fingerprint: Fingerprint, duration: Int) async throws -> [AcoustIDResult]
}

struct AcoustIDResult {
    let acoustID: String
    let score: Double
    let recordings: [MusicBrainzRecording]
}
```
- Make HTTP POST to `https://api.acoustid.org/v2/lookup`
- Parse JSON response
- Extract MusicBrainz recordings

**E4-A9.4**: Map MusicBrainz Metadata to Tracks
```swift
struct MusicBrainzMapper {
    func mapToTrack(_ recording: MusicBrainzRecording) -> Track
}
```
- Extract:
  - ISRCs
  - Artist name(s)
  - Title
  - Album (if available)
  - Duration
- Feed into matching pipeline as high-confidence search query

**E4-A9.5**: Integrate with Main Pipeline
```swift
func matchWithFingerprintFallback(
    source: Track,
    audioFileURL: URL?
) async throws -> MatchDecision {
    // Stage 0-5: Standard pipeline
    let decision = try await runStandardPipeline(source: source)

    // If no match and audio file available, try fingerprinting
    if case .noMatch = decision, let audioURL = audioFileURL {
        // Generate fingerprint
        // Lookup AcoustID
        // Extract ISRCs/metadata
        // Re-run search with discovered data
        // Return best match
    }

    return decision
}
```

**E4-A9.6**: Add Privacy & Consent UI
- Privacy notice:
  - "Audio fingerprints will be sent to AcoustID (third-party service)"
  - Link to AcoustID privacy policy
- User consent checkbox
- Option to skip fingerprinting for specific tracks

**E4-A9.7**: Create Test Corpus
- Collect 100 local audio files (MP3/FLAC)
- Include:
  - Clean files with good metadata
  - Files with missing/wrong metadata
  - Obscure tracks
  - Regional/niche tracks
- Manually verify ground truth
- Run fingerprinting and measure accuracy

**E4-A9.8**: Optimize Performance
- Batch fingerprint generation (parallel processing)
- Cache fingerprints (store in DB)
- Batch AcoustID requests (up to 10 per request)
- Show progress UI (fingerprinting can take time)

**E4-A9.9**: Add API Key Management
- Store AcoustID API key securely (Keychain)
- Rate limit handling (AcoustID free tier limits)
- Fallback: prompt user to get their own API key

**Story Points**: 21
**Estimated Duration**: 2 weeks

---

## Epic Summary

### Total Effort Estimate

| Story | Story Points | Duration      | Priority |
|-------|-------------|---------------|----------|
| E4-A1 | 5           | 3-4 days      | P0       |
| E4-A2 | 5           | 3-4 days      | P0       |
| E4-A3 | 8           | 5-6 days      | P0       |
| E4-A4 | 8           | 5-6 days      | P0       |
| E4-A5 | 13          | 8-10 days     | P0       |
| E4-A6 | 8           | 5-6 days      | P0       |
| E4-A7 | 13          | 8-10 days     | P0       |
| E4-A8 | 13          | 8-10 days     | P0       |
| E4-A9 | 21          | 2 weeks       | P2 (opt) |
| **Total (core)** | **73** | **6-7 weeks** | |
| **Total (with opt)** | **94** | **8-9 weeks** | |

### Recommended Phasing

**Phase 1 (MVP)**: Stories E4-A1 through E4-A6
- Duration: 4-5 weeks
- Deliverable: Working matching engine with auto-match capability
- Match rate: ~85-90%

**Phase 2 (Production)**: Add E4-A7 and E4-A8
- Duration: +2-3 weeks
- Deliverable: User-facing ambiguity resolution + quality assurance
- Match rate: ~95%+

**Phase 3 (Advanced)**: Add E4-A9 if needed
- Duration: +2 weeks
- Deliverable: Audio fingerprinting for edge cases
- Match rate: ~98%+

### Dependencies

- **Requires**: Epic 1 (Core Infrastructure - database, models)
- **Requires**: Epic 2 (API Integration - Spotify/Apple Music clients)
- **Blocks**: Epic 5 (Sync Engine - uses matching results)
- **Blocks**: Epic 6 (UI - displays match quality and ambiguous cases)

### Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Fuzzy matching accuracy lower than expected | High | Medium | Build evaluation harness early (E4-A8), iterate on scoring |
| ISRC availability lower than 60% | Medium | Low | Strengthen fuzzy matching, add fingerprinting |
| API rate limits hit during candidate generation | Medium | Medium | Implement caching, batch requests, exponential backoff |
| User dissatisfaction with ambiguous match UI | High | Medium | User testing, iterate on UI, provide escape hatches |
| Performance issues with large libraries (10k+ tracks) | Medium | Medium | Parallelize, optimize queries, add progress indicators |

### Success Criteria Review

At epic completion, we must achieve:
- [x] ≥ 95% match rate on test corpus
- [x] ≤ 2% false match rate
- [x] ≥ 85% auto-match (no user intervention)
- [x] < 1s average per track (excluding fingerprinting)
- [x] User ambiguity resolution UI tested and approved

---

## Related Documentation

- [MATCHING_PIPELINE.md](./MATCHING_PIPELINE.md) - Detailed technical specification
- [LIBRARIES.md](./LIBRARIES.md) - Dependency information and usage
- [Architecture Decision Records](./ADR/) - Key architectural decisions

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2025-11-09 | PM Team | Initial epic definition with detailed breakdown |
