import SwiftUI
import MergeCore

struct SyncView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var syncState = SyncState()
    
    var body: some View {
        VStack(spacing: 20) {
            if syncState.isSyncing {
                // Sync in progress
                SyncProgressView(syncState: syncState)
            } else if let result = syncState.lastResult {
                // Sync completed
                SyncResultView(result: result)
                    .transition(.opacity)
            } else {
                // Ready to sync
                SyncConfigView(
                    direction: $appState.syncDirection,
                    onSync: {
                        Task {
                            await syncState.performSync(direction: appState.syncDirection, dryRun: false)
                        }
                    },
                    onDryRun: {
                        Task {
                            await syncState.performSync(direction: appState.syncDirection, dryRun: true)
                        }
                    }
                )
            }
        }
        .padding()
        .navigationTitle("Sync")
        .animation(.default, value: syncState.isSyncing)
    }
}

struct SyncConfigView: View {
    @Binding var direction: MergeDirection
    let onSync: () -> Void
    let onDryRun: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Direction selector
            VStack(spacing: 15) {
                Text("Select Sync Direction")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Picker("Direction", selection: $direction) {
                    Text("Spotify → Apple Music").tag(MergeDirection.spotifyToApple)
                    Text("Apple Music → Spotify").tag(MergeDirection.appleToSpotify)
                    Text("Bidirectional").tag(MergeDirection.bidirectional)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            // Action buttons
            HStack(spacing: 20) {
                Button {
                    onDryRun()
                } label: {
                    Label("Dry Run", systemImage: "eye")
                        .frame(width: 150)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button {
                    onSync()
                } label: {
                    Label("Start Sync", systemImage: "arrow.triangle.2.circlepath")
                        .frame(width: 150)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            
            Spacer()
        }
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
    }
}

struct SyncProgressView: View {
    @ObservedObject var syncState: SyncState
    
    var body: some View {
        VStack(spacing: 25) {
            Spacer()
            
            // Progress indicator
            ProgressView(value: syncState.progress) {
                Text(syncState.currentOperation)
                    .font(.headline)
            } currentValueLabel: {
                Text("\(Int(syncState.progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .progressViewStyle(.linear)
            .frame(maxWidth: 400)
            
            // Stats
            HStack(spacing: 40) {
                VStack {
                    Text("\(syncState.successCount)")
                        .font(.title)
                        .foregroundColor(.green)
                    Text("Succeeded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text("\(syncState.failureCount)")
                        .font(.title)
                        .foregroundColor(.red)
                    Text("Failed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text("\(syncState.totalOperations)")
                        .font(.title)
                        .foregroundColor(.blue)
                    Text("Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
    }
}

struct SyncResultView: View {
    let result: SyncResult
    
    var body: some View {
        VStack(spacing: 25) {
            Spacer()
            
            // Success indicator
            Image(systemName: result.failureCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(result.failureCount == 0 ? .green : .orange)
            
            Text(result.failureCount == 0 ? "Sync Complete!" : "Sync Complete with Errors")
                .font(.title)
                .fontWeight(.bold)
            
            // Stats grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                ResultStatCard(
                    title: "Total Operations",
                    value: "\(result.totalOps)",
                    color: .blue
                )
                
                ResultStatCard(
                    title: "Succeeded",
                    value: "\(result.successCount)",
                    color: .green
                )
                
                if result.failureCount > 0 {
                    ResultStatCard(
                        title: "Failed",
                        value: "\(result.failureCount)",
                        color: .red
                    )
                }
                
                ResultStatCard(
                    title: "Success Rate",
                    value: String(format: "%.1f%%", result.successRate * 100),
                    color: .purple
                )
                
                ResultStatCard(
                    title: "Duration",
                    value: String(format: "%.1fs", result.duration),
                    color: .orange
                )
            }
            .frame(maxWidth: 500)
            
            Spacer()
        }
    }
}

struct ResultStatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

@MainActor
class SyncState: ObservableObject {
    @Published var isSyncing = false
    @Published var progress: Double = 0
    @Published var currentOperation = ""
    @Published var successCount = 0
    @Published var failureCount = 0
    @Published var totalOperations = 0
    @Published var lastResult: SyncResult?
    
    private let coordinator = SyncCoordinator()
    
    func performSync(direction: MergeDirection, dryRun: Bool) async {
        isSyncing = true
        lastResult = nil
        progress = 0
        successCount = 0
        failureCount = 0
        currentOperation = dryRun ? "Previewing changes..." : "Syncing..."
        
        do {
            let result = try await coordinator.performSync(
                direction: direction,
                dryRun: dryRun
            )
            
            lastResult = result
            totalOperations = result.totalOps
            successCount = result.successCount
            failureCount = result.failureCount
            progress = 1.0
        } catch {
            currentOperation = "Sync failed: \(error.localizedDescription)"
            failureCount = totalOperations
        }
        
        isSyncing = false
    }
}
