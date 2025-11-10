import SwiftUI
import MergeCore

struct MatchResolverView: View {
    @StateObject private var matchState = MatchState()
    @State private var selectedMatch: AmbiguousMatch?
    
    var body: some View {
        HSplitView {
            // List of ambiguous matches
            VStack(alignment: .leading) {
                Text("Ambiguous Matches")
                    .font(.headline)
                    .padding(.horizontal)
                
                if matchState.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if matchState.ambiguousMatches.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 50))
                            .foregroundColor(.green)
                        Text("All matches resolved!")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List(matchState.ambiguousMatches, selection: $selectedMatch) { match in
                        AmbiguousMatchRow(match: match)
                    }
                }
            }
            .frame(minWidth: 300)
            
            // Match details and resolution
            if let match = selectedMatch {
                MatchDetailView(match: match) { candidate in
                    Task {
                        await matchState.resolveMatch(match, with: candidate)
                        selectedMatch = nil
                    }
                }
            } else {
                Text("Select a match to resolve")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Match Resolution")
        .task {
            await matchState.loadAmbiguousMatches()
        }
    }
}

struct AmbiguousMatchRow: View {
    let match: AmbiguousMatch
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(match.sourceTrack.title)
                .font(.body)
            Text(match.sourceTrack.artist)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(match.candidates.count) candidates")
                .font(.caption2)
                .foregroundColor(.orange)
        }
        .padding(.vertical, 4)
    }
}

struct MatchDetailView: View {
    let match: AmbiguousMatch
    let onSelect: (MatchScore) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Source track
            VStack(alignment: .leading, spacing: 8) {
                Text("Source Track")
                    .font(.headline)
                
                TrackCard(track: match.sourceTrack)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            
            Divider()
            
            // Candidates
            VStack(alignment: .leading, spacing: 12) {
                Text("Possible Matches")
                    .font(.headline)
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(match.candidates.enumerated()), id: \.offset) { index, candidate in
                            CandidateCard(candidate: candidate, rank: index + 1) {
                                onSelect(candidate)
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            // Skip button
            Button {
                // Skip this match for now
            } label: {
                Text("Skip")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct TrackCard: View {
    let track: CanonicalTrack
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.title)
                .font(.title3)
                .fontWeight(.semibold)
            Text(track.artist)
                .foregroundColor(.secondary)
            if let album = track.album {
                Text(album)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct CandidateCard: View {
    let candidate: MatchScore
    let rank: Int
    let onSelect: () -> Void
    
    var body: some View {
        HStack {
            // Rank
            Text("#\(rank)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 8) {
                // Confidence
                HStack {
                    Text("Confidence: \(Int(candidate.score * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ProgressView(value: candidate.score)
                        .frame(width: 100)
                }
                
                // Score breakdown
                HStack(spacing: 15) {
                    ScoreBadge(label: "Title", score: candidate.components.titleScore)
                    ScoreBadge(label: "Artist", score: candidate.components.artistScore)
                    ScoreBadge(label: "Album", score: candidate.components.albumScore)
                    ScoreBadge(label: "Duration", score: candidate.components.durationScore)
                }
            }
            
            Spacer()
            
            // Select button
            Button {
                onSelect()
            } label: {
                Text("Select")
                    .frame(width: 80)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

struct ScoreBadge: View {
    let label: String
    let score: Double
    
    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(String(format: "%.0f%%", score * 100))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(scoreColor)
        }
    }
    
    var scoreColor: Color {
        if score >= 0.9 { return .green }
        if score >= 0.7 { return .orange }
        return .red
    }
}

// MARK: - State Management

@MainActor
class MatchState: ObservableObject {
    @Published var ambiguousMatches: [AmbiguousMatch] = []
    @Published var isLoading = false
    
    func loadAmbiguousMatches() async {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: Load actual ambiguous matches from matching engine
        // For now, empty state
        ambiguousMatches = []
    }
    
    func resolveMatch(_ match: AmbiguousMatch, with candidate: MatchScore) async {
        // TODO: Save manual mapping
        ambiguousMatches.removeAll { $0.id == match.id }
    }
}

struct AmbiguousMatch: Identifiable {
    let id = UUID()
    let sourceTrack: CanonicalTrack
    let candidates: [MatchScore]
}
