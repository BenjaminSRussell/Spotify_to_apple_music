import Foundation
import GRDB

/// Database provider singleton
public final class DatabaseProvider: @unchecked Sendable {
    public static let shared: DatabaseProvider = {
        do {
            return try DatabaseProvider.createDefault()
        } catch {
            // Launch-time failure: surface a clear message instead of an opaque try! trap (#13).
            fatalError("Failed to open SpotifyAppleMerge database: \(error)")
        }
    }()

    public let dbQueue: DatabaseQueue

    /// Throwing factory for the default app-support path (recoverable from AppState).
    public static func createDefault() throws -> DatabaseProvider {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbDirectory = appSupportURL.appendingPathComponent("SpotifyAppleMerge", isDirectory: true)
        try fileManager.createDirectory(at: dbDirectory, withIntermediateDirectories: true)
        let dbPath = dbDirectory.appendingPathComponent("db.sqlite").path
        Log.info("Database path: \(dbPath)")
        return try DatabaseProvider(path: dbPath)
    }

    /// Initialize with custom path (for testing)
    public init(path: String) throws {
        self.dbQueue = try DatabaseQueue(path: path)
        try Migrations.migrate(dbQueue)
        Log.info("Database initialized and migrated")
    }

    /// Initialize with in-memory database (for testing)
    public static func inMemory() throws -> DatabaseProvider {
        try DatabaseProvider(path: ":memory:")
    }
}
