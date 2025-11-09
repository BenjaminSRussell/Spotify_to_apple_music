import Foundation
import GRDB

/// Database provider singleton
public final class DatabaseProvider: @unchecked Sendable {
    public static let shared = DatabaseProvider()

    public let dbQueue: DatabaseQueue

    private init() {
        // TODO: Configure database path
        // For now, use in-memory database for testing
        self.dbQueue = try! DatabaseQueue()

        // TODO: Run migrations
        // try! Migrations.migrate(dbQueue)
    }

    /// Initialize with custom path (for testing)
    public init(path: String) throws {
        self.dbQueue = try DatabaseQueue(path: path)
        // TODO: Run migrations
    }
}
