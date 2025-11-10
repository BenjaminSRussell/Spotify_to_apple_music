import SwiftUI
import MergeCore

@main
struct MergeApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
