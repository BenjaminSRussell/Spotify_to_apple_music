import Foundation
import GRDB

/// Database provider singleton
public final class DatabaseProvider: @unchecked Sendable {
    public static let shared = DatabaseProvider()

    public let dbQueue: DatabaseQueue

    private init() {
        // Get application support directory
        let fileManager = FileManager.default
        let appSupportURL = try! fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let dbDirectory = appSupportURL.appendingPathComponent("SpotifyAppleMerge", isDirectory: true)
        try! fileManager.createDirectory(at: dbDirectory, withIntermediateDirectories: true)

        let dbPath = dbDirectory.appendingPathComponent("db.sqlite").path

        Log.info("Database path: \(dbPath)")

        self.dbQueue = try! DatabaseQueue(path: dbPath)

        // Run migrations
        try! Migrations.migrate(dbQueue)

        Log.info("Database initialized and migrated")
    }

    /// Initialize with custom path (for testing)
    public init(path: String) throws {
        self.dbQueue = try DatabaseQueue(path: path)
        try Migrations.migrate(dbQueue)
    }

    /// Initialize with in-memory database (for testing)
    public static func inMemory() throws -> DatabaseProvider {
        let provider = try DatabaseProvider(path: ":memory:")
        return provider
    }
}
