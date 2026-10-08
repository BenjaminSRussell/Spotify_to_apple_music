import SwiftUI
import MergeCore

struct MatchResolverView: View {
    @StateObject private var matchState = MatchState()
    // List selection is by row ID (AmbiguousMatch is Identifiable by UUID)
    @State private var selectedMatchID: AmbiguousMatch.ID?
    private var selectedMatch: AmbiguousMatch? {
        matchState.ambiguousMatches.first { $0.id == selectedMatchID }
    }
    @State private var showCheckmark = false

    var body: some View {
        NavigationSplitView {
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
                    List(matchState.ambiguousMatches, selection: $selectedMatchID) { match in
                        AmbiguousMatchRow(match: match)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(match.pending.accessibilityLabel)
                    }
                }
            }
        } detail: {
            // Match details and resolution
            if let match = selectedMatch {
                MatchDetailView(match: match, onSkip: {
                    Task {
                        await matchState.skip(match)
                        selectedMatchID = matchState.ambiguousMatches.first?.id
                    }
                }, onReject: { candidate in
                    Task { await matchState.reject(candidate, in: match) }
                }) { candidate in
                    Task {
                        // Show checkmark animation
                        withAnimation {
                            showCheckmark = true
                        }

                        // Resolve the match
                        await matchState.resolveMatch(match, with: candidate)

                        // Keep checkmark visible for a brief moment
                        try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds

                        // Auto-advance to the next match or clear selection
                        withAnimation {
                            showCheckmark = false
                            if !matchState.ambiguousMatches.isEmpty {
                                selectedMatchID = matchState.ambiguousMatches.first?.id
                            } else {
                                selectedMatchID = nil
                            }
                        }
                    }
                }
                .overlay(alignment: .center) {
                    if showCheckmark {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                            .transition(.scale.combined(with: .opacity))
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
            Text("\(match.candidates.count) \(match.candidates.count == 1 ? "candidate" : "candidates")")
                .font(.caption2)
                .foregroundColor(.orange)
        }
        .padding(.vertical, 4)
    }
}

struct MatchDetailView: View {
    let match: AmbiguousMatch
    var onSkip: () -> Void = {}
    var onReject: (ResolutionCandidate) -> Void = { _ in }
    let onSelect: (ResolutionCandidate) -> Void
    
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
                        ForEach(Array(match.candidates.enumerated()), id: \.element.id) { index, candidate in
                            CandidateCard(
                                candidate: candidate,
                                rank: index + 1,
                                onReject: { onReject(candidate) }
                            ) {
                                onSelect(candidate)
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            // Skip: never match or add this track on the target service (saved).
            Button(action: onSkip) {
                Text("Skip This Track")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Future syncs won't match or add this track.")
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
    let candidate: ResolutionCandidate
    let rank: Int
    var onReject: () -> Void = {}
    let onSelect: () -> Void

    private var score: MatchScore { candidate.score }
    
    var body: some View {
        HStack {
            // Rank
            Text("#\(rank)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 8) {
                if let track = candidate.track {
                    TrackCard(track: track)
                }
                // Confidence
                HStack {
                    Text("Confidence: \(Int(score.score * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ProgressView(value: score.score)
                        .frame(width: 100)
                }
                
                // Score breakdown
                HStack(spacing: 15) {
                    ScoreBadge(label: "Title", score: score.components.titleScore)
                    ScoreBadge(label: "Artist", score: score.components.artistScore)
                    ScoreBadge(label: "Album", score: score.components.albumScore)
                    ScoreBadge(label: "Duration", score: score.components.durationScore)
                }
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                Button {
                    onSelect()
                } label: {
                    Text("Select")
                        .frame(width: 80)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Select \(candidate.track?.title ?? "candidate \(rank)")")

                Button(role: .destructive) {
                    onReject()
                } label: {
                    Text("Not This")
                        .frame(width: 80)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Never offer \(candidate.track?.title ?? "candidate \(rank)") for this track")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(candidate.accessibilityLabel)
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
    @Published var errorMessage: String?

    /// Shared with the CLI `resolve` command (#7, #10); decisions persist in GRDB.
    private let service = MatchResolutionService()
    var direction: MergeDirection = .spotifyToApple

    func loadAmbiguousMatches() async {
        isLoading = true
        defer { isLoading = false }
        do {
            ambiguousMatches = try await service.pendingResolutions(direction: direction).map(AmbiguousMatch.init)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resolveMatch(_ match: AmbiguousMatch, with candidate: ResolutionCandidate) async {
        await perform(removing: match) {
            try await $0.choose(candidateID: candidate.id, for: match.sourceTrack,
                                targetService: match.pending.targetService, score: candidate.score.score)
        }
    }

    func skip(_ match: AmbiguousMatch) async {
        await perform(removing: match) { try await $0.skip(match.sourceTrack, targetService: match.pending.targetService) }
    }

    func reject(_ candidate: ResolutionCandidate, in match: AmbiguousMatch) async {
        do {
            try await service.reject(candidateID: candidate.id, for: match.sourceTrack, targetService: match.pending.targetService)
            guard let index = ambiguousMatches.firstIndex(where: { $0.id == match.id }) else { return }
            let remaining = match.candidates.filter { $0.id != candidate.id }
            if remaining.isEmpty {
                ambiguousMatches.remove(at: index)
            } else {
                ambiguousMatches[index] = AmbiguousMatch(PendingResolution(
                    source: match.sourceTrack, targetService: match.pending.targetService, candidates: remaining))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(removing match: AmbiguousMatch, _ action: (MatchResolutionService) async throws -> Void) async {
        do {
            try await action(service)
            ambiguousMatches.removeAll { $0.id == match.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AmbiguousMatch: Identifiable {
    let pending: PendingResolution

    init(_ pending: PendingResolution) {
        self.pending = pending
    }

    var id: String { pending.id }
    var sourceTrack: CanonicalTrack { pending.source }
    var candidates: [ResolutionCandidate] { pending.candidates }
}
