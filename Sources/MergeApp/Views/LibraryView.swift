import SwiftUI
import MergeCore

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedService: ServiceFilter = .all
    
    var body: some View {
        VStack(spacing: 0) {
            // Stats header
            StatsHeaderView(stats: appState.libraryStats)
                .padding()
            
            Divider()
            
            // Library content
            VStack {
                // Toolbar
                HStack {
                    // Search
                    TextField("Search tracks...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                    
                    Spacer()
                    
                    // Filter
                    Picker("Service", selection: $selectedService) {
                        ForEach(ServiceFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                    
                    // Import buttons
                    Button {
                        Task { await appState.importFromSpotify() }
                    } label: {
                        Label("Import Spotify", systemImage: "square.and.arrow.down")
                    }
                    .disabled(appState.isLoading)
                    
                    Button {
                        Task { await appState.importFromAppleMusic() }
                    } label: {
                        Label("Import Apple", systemImage: "square.and.arrow.down")
                    }
                    .disabled(appState.isLoading)
                }
                .padding()
                
                // Track list
                if appState.isLoading {
                    ProgressView("Loading library...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TrackListView(
                        tracks: filteredTracks,
                        searchText: searchText
                    )
                }
            }
        }
        .navigationTitle("Library")
    }
    
    var filteredTracks: [CanonicalTrack] {
        appState.tracks.filter { track in
            switch selectedService {
            case .all:
                return true
            case .spotify:
                return track.availability.contains(.spotify)
            case .appleMusic:
                return track.availability.contains(.appleMusic)
            case .both:
                return track.availability.contains(.spotify) && track.availability.contains(.appleMusic)
            }
        }
    }
}

struct StatsHeaderView: View {
    let stats: LibraryStats
    
    var body: some View {
        HStack(spacing: 40) {
            StatCard(
                title: "Total Tracks",
                value: "\(stats.totalTracks)",
                icon: "music.note",
                color: .blue
            )
            
            StatCard(
                title: "Spotify",
                value: "\(stats.spotifyTracks)",
                icon: "s.circle.fill",
                color: .green
            )
            
            StatCard(
                title: "Apple Music",
                value: "\(stats.appleTracks)",
                icon: "a.circle.fill",
                color: .pink
            )
            
            StatCard(
                title: "Playlists",
                value: "\(stats.totalPlaylists)",
                icon: "music.note.list",
                color: .purple
            )
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct TrackListView: View {
    let tracks: [CanonicalTrack]
    let searchText: String
    
    var filteredTracks: [CanonicalTrack] {
        if searchText.isEmpty {
            return tracks
        }
        return tracks.filter { track in
            track.title.localizedCaseInsensitiveContains(searchText) ||
            track.artist.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        Table(filteredTracks) {
            TableColumn("Title") { track in
                VStack(alignment: .leading) {
                    Text(track.title)
                        .font(.body)
                    Text(track.artist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            TableColumn("Album") { track in
                Text(track.album ?? "—")
                    .foregroundColor(.secondary)
            }
            
            TableColumn("Duration") { track in
                if let duration = track.durationSeconds {
                    Text(formatDuration(duration))
                        .foregroundColor(.secondary)
                } else {
                    Text("—")
                        .foregroundColor(.secondary)
                }
            }
            .width(80)
            
            TableColumn("Services") { track in
                HStack(spacing: 4) {
                    if track.availability.contains(.spotify) {
                        Image(systemName: "s.circle.fill")
                            .foregroundColor(.green)
                    }
                    if track.availability.contains(.appleMusic) {
                        Image(systemName: "a.circle.fill")
                            .foregroundColor(.pink)
                    }
                }
            }
            .width(80)
        }
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

enum ServiceFilter: String, CaseIterable, Identifiable {
    case all
    case spotify
    case appleMusic
    case both
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .all: return "All"
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .both: return "Both"
        }
    }
}
