import AppKit
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
                SyncResultView(
                    result: result,
                    onResume: { syncState.resume() },
                    onDone: { syncState.lastResult = nil }
                )
                .transition(.opacity)
            } else {
                // Ready to sync
                SyncConfigView(
                    direction: $appState.syncDirection,
                    onSync: {
                        syncState.start(direction: appState.syncDirection, dryRun: false)
                    },
                    onDryRun: {
                        syncState.start(direction: appState.syncDirection, dryRun: true)
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

            // Playlist-level progress (#12)
            VStack(alignment: .leading, spacing: 8) {
                if let name = syncState.playlistName {
                    Text("Playlist \(syncState.playlistIndex) of \(syncState.playlistCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                ProgressView(value: syncState.progress) {
                    Text(syncState.currentOperation)
                        .font(.headline)
                } currentValueLabel: {
                    Text("\(syncState.completedOperations) of \(syncState.totalOperations) operations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .progressViewStyle(.linear)
            }
            .frame(maxWidth: 400)
            .accessibilityElement(children: .combine)
            .accessibilityValue(syncState.currentOperation)

            // Stats
            HStack(spacing: 40) {
                stat("\(syncState.successCount)", "Succeeded", .green)
                stat("\(syncState.failureCount)", "Failed", .red)
                if syncState.skippedCount > 0 {
                    stat("\(syncState.skippedCount)", "Resumed", .secondary)
                }
                stat("\(syncState.totalOperations)", "Total", .blue)
            }

            // Cooperative cancel: in-flight calls finish, the rest can be resumed later.
            Button(role: .cancel) {
                syncState.cancel()
            } label: {
                Label(syncState.isCancelling ? "Cancelling…" : "Cancel Sync", systemImage: "stop.circle")
                    .frame(width: 160)
            }
            .controlSize(.large)
            .disabled(syncState.isCancelling)
            .keyboardShortcut(.cancelAction)
            .accessibilityHint("Stops after in-flight operations finish. You can resume later.")

            Spacer()
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack {
            Text(value)
                .font(.title)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SyncResultView: View {
    let result: SyncResult
    var onResume: () -> Void = {}
    var onDone: () -> Void = {}

    private var title: String {
        if result.cancelled { return "Sync Cancelled" }
        return result.failureCount == 0 ? "Sync Complete!" : "Sync Complete with Errors"
    }

    var body: some View {
        VStack(spacing: 25) {
            Spacer()
            
            // Success indicator
            Image(systemName: result.cancelled ? "pause.circle.fill"
                  : (result.failureCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
                .font(.system(size: 60))
                .foregroundColor(result.cancelled ? .secondary : (result.failureCount == 0 ? .green : .orange))

            Text(title)
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

            HStack(spacing: 20) {
                if result.cancelled || result.failureCount > 0 {
                    Button(action: onResume) {
                        Label("Resume Sync", systemImage: "play.circle")
                            .frame(width: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("Continues from the last checkpoint without repeating finished operations.")
                }
                Button("Done", action: onDone)
                    .controlSize(.large)
            }

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
    @Published var isCancelling = false
    @Published var progress: Double = 0
    @Published var currentOperation = ""
    @Published var successCount = 0
    @Published var failureCount = 0
    @Published var skippedCount = 0
    @Published var completedOperations = 0
    @Published var totalOperations = 0
    @Published var playlistName: String?
    @Published var playlistIndex = 0
    @Published var playlistCount = 0
    @Published var lastResult: SyncResult?

    private let coordinator = SyncCoordinator()
    private var syncTask: Task<Void, Never>?

    func start(direction: MergeDirection, dryRun: Bool) {
        run(dryRun ? "Previewing changes..." : "Syncing...") { coordinator, progress in
            try await coordinator.performSync(direction: direction, dryRun: dryRun, progress: progress)
        }
    }

    /// Resume the last cancelled or failed run from its checkpoints (#12).
    func resume() {
        let runID = lastResult?.runID
        run("Resuming...") { coordinator, progress in
            try await coordinator.resumeSync(runID: runID, progress: progress)
        }
    }

    /// Cooperative cancel: no new API calls start; finished work stays checkpointed.
    func cancel() {
        guard isSyncing, !isCancelling else { return }
        isCancelling = true
        currentOperation = "Cancelling after in-flight operations finish..."
        announce("Cancelling sync")
        syncTask?.cancel()
    }

    private func run(
        _ label: String,
        _ body: @escaping @Sendable (SyncCoordinator, @escaping SyncProgressHandler) async throws -> SyncResult
    ) {
        guard !isSyncing else { return }
        isSyncing = true
        isCancelling = false
        lastResult = nil
        progress = 0
        successCount = 0
        failureCount = 0
        skippedCount = 0
        completedOperations = 0
        playlistName = nil
        currentOperation = label

        let coordinator = self.coordinator
        let handler: SyncProgressHandler = { [weak self] update in
            Task { @MainActor in self?.apply(update) }
        }
        syncTask = Task { [weak self] in
            do {
                let result = try await body(coordinator, handler)
                self?.finish(result)
            } catch {
                self?.fail(error)
            }
        }
    }

    private func apply(_ update: SyncProgress) {
        // Progress hops to the main actor asynchronously; never move backwards.
        guard update.completed >= completedOperations || update.phase == .finished || update.phase == .cancelled else { return }
        completedOperations = update.completed
        totalOperations = update.total
        failureCount = update.failed
        skippedCount = update.skipped
        successCount = max(0, update.completed - update.failed)
        progress = update.fraction
        playlistName = update.playlistName
        playlistIndex = update.playlistIndex
        playlistCount = update.playlistCount
        if !isCancelling {
            currentOperation = update.statusLine
        }
        if let announcement = update.announcement {
            announce(announcement)
        }
    }

    private func finish(_ result: SyncResult) {
        lastResult = result
        totalOperations = result.totalOps
        successCount = result.successCount
        failureCount = result.failureCount
        skippedCount = result.skippedCount
        progress = result.cancelled ? progress : 1.0
        isSyncing = false
        isCancelling = false
        syncTask = nil
    }

    private func fail(_ error: Error) {
        currentOperation = "Sync failed: \(error.localizedDescription)"
        announce(currentOperation)
        failureCount = totalOperations
        isSyncing = false
        isCancelling = false
        syncTask = nil
    }

    /// VoiceOver announcement (macOS 13 compatible).
    private func announce(_ text: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}
