import SwiftUI
import MergeCore

struct SettingsView: View {
    @AppStorage("autoMatchThreshold") private var autoMatchThreshold = 0.85
    @AppStorage("durationTolerance") private var durationTolerance = 5.0
    @AppStorage("enableISRCMatching") private var enableISRCMatching = true
    @AppStorage("enableFuzzyMatching") private var enableFuzzyMatching = true
    
    var body: some View {
        Form {
            Section("Matching Settings") {
                VStack(alignment: .leading) {
                    Text("Auto-match Threshold")
                        .font(.headline)
                    HStack {
                        Slider(value: $autoMatchThreshold, in: 0.5...1.0, step: 0.05)
                        Text(String(format: "%.0f%%", autoMatchThreshold * 100))
                            .frame(width: 50, alignment: .trailing)
                            .monospacedDigit()
                    }
                    Text("Tracks with confidence above this threshold will be automatically matched")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading) {
                    Text("Duration Tolerance")
                        .font(.headline)
                    HStack {
                        Slider(value: $durationTolerance, in: 0...15, step: 1)
                        Text(String(format: "±%.0fs", durationTolerance))
                            .frame(width: 50, alignment: .trailing)
                            .monospacedDigit()
                    }
                    Text("Maximum duration difference allowed for track matching")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                
                Toggle("Enable ISRC Matching", isOn: $enableISRCMatching)
                Text("Use ISRC codes for high-confidence exact matching")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Toggle("Enable Fuzzy Matching", isOn: $enableFuzzyMatching)
                Text("Use fuzzy string matching for tracks without ISRC")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("Services") {
                ServiceStatusRow(
                    service: "Spotify",
                    isConnected: false,
                    icon: "s.circle.fill",
                    color: .green
                ) {
                    // TODO: Implement Spotify auth
                }
                
                ServiceStatusRow(
                    service: "Apple Music",
                    isConnected: false,
                    icon: "a.circle.fill",
                    color: .pink
                ) {
                    // TODO: Implement Apple Music auth
                }
            }
            
            Section("Database") {
                HStack {
                    Text("Database Location")
                    Spacer()
                    Text("~/Library/Application Support/SpotifyAppleMerge")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button("Clear Database") {
                    // TODO: Implement database clear
                }
                .foregroundColor(.red)
            }
            
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("0.1.0")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Build")
                    Spacer()
                    Text("Phase 6 - macOS UI")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 500)
    }
}

struct ServiceStatusRow: View {
    let service: String
    let isConnected: Bool
    let icon: String
    let color: Color
    let onConnect: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title2)
            
            VStack(alignment: .leading) {
                Text(service)
                    .font(.headline)
                Text(isConnected ? "Connected" : "Not connected")
                    .font(.caption)
                    .foregroundColor(isConnected ? .green : .secondary)
            }
            
            Spacer()
            
            Button(isConnected ? "Disconnect" : "Connect") {
                onConnect()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}
