import Foundation
import GRDB

// MARK: - Sync Run Model

/// Record of a sync run
public struct SyncRun: Codable, Sendable {
    public let id: String
    public let startedAt: Date
    public var completedAt: Date?
    public let direction: MergeDirection
    public var operationsCount: Int?
    public var successCount: Int?
    public var failureCount: Int?
    public var status: SyncStatus
    public var durationSeconds: Double?

    public init(
        id: String = UUID().uuidString,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        direction: MergeDirection,
        operationsCount: Int? = nil,
        successCount: Int? = nil,
        failureCount: Int? = nil,
        status: SyncStatus = .running,
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.direction = direction
        self.operationsCount = operationsCount
        self.successCount = successCount
        self.failureCount = failureCount
        self.status = status
        self.durationSeconds = durationSeconds
    }
}

/// Sync run status
public enum SyncStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
}

// MARK: - GRDB Conformance

extension SyncRun: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "sync_runs" }

    public enum Columns {
        static let id = Column("id")
        static let startedAt = Column("started_at")
        static let completedAt = Column("completed_at")
        static let direction = Column("direction")
        static let operationsCount = Column("operations_count")
        static let successCount = Column("success_count")
        static let failureCount = Column("failure_count")
        static let status = Column("status")
        static let durationSeconds = Column("duration_seconds")
    }

    public init(row: Row) {
        self.id = row[Columns.id]
        self.startedAt = row[Columns.startedAt]
        self.completedAt = row[Columns.completedAt]
        self.direction = MergeDirection(rawValue: row[Columns.direction])!
        self.operationsCount = row[Columns.operationsCount]
        self.successCount = row[Columns.successCount]
        self.failureCount = row[Columns.failureCount]
        self.status = SyncStatus(rawValue: row[Columns.status])!
        self.durationSeconds = row[Columns.durationSeconds]
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.startedAt] = startedAt
        container[Columns.completedAt] = completedAt
        container[Columns.direction] = direction.rawValue
        container[Columns.operationsCount] = operationsCount
        container[Columns.successCount] = successCount
        container[Columns.failureCount] = failureCount
        container[Columns.status] = status.rawValue
        container[Columns.durationSeconds] = durationSeconds
    }
}

// MARK: - Sync Run Store

/// Protocol for sync run persistence
public protocol SyncRunStore: Sendable {
    func save(_ run: SyncRun) async throws
    func fetch(id: String) async throws -> SyncRun?
    func fetchAll() async throws -> [SyncRun]
    func fetchRecent(limit: Int) async throws -> [SyncRun]
}

/// GRDB-based sync run store implementation
public final class SyncRunStoreImpl: SyncRunStore {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue = DatabaseProvider.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    public func save(_ run: SyncRun) async throws {
        try await dbQueue.write { db in
            try run.save(db)
        }
    }

    public func fetch(id: String) async throws -> SyncRun? {
        try await dbQueue.read { db in
            try SyncRun
                .filter(SyncRun.Columns.id == id)
                .fetchOne(db)
        }
    }

    public func fetchAll() async throws -> [SyncRun] {
        try await dbQueue.read { db in
            try SyncRun
                .order(SyncRun.Columns.startedAt.desc)
                .fetchAll(db)
        }
    }

    public func fetchRecent(limit: Int = 10) async throws -> [SyncRun] {
        try await dbQueue.read { db in
            try SyncRun
                .order(SyncRun.Columns.startedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
}
