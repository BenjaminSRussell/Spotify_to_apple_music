import Foundation
import GRDB

/// Protocol for manual mapping persistence
public protocol MappingStore: Sendable {
    func getManualMapping(sourceService: MusicService, sourceID: String) async throws -> ManualMapping?
    func saveManualMapping(_ mapping: ManualMapping) async throws
    func deleteManualMapping(id: String) async throws
    func getAllManualMappings() async throws -> [ManualMapping]
}

/// GRDB-based mapping store implementation
public final class MappingStoreImpl: MappingStore {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue = DatabaseProvider.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    public func getManualMapping(sourceService: MusicService, sourceID: String) async throws -> ManualMapping? {
        try await dbQueue.read { db in
            try ManualMapping
                .filter(ManualMapping.Columns.sourceService == sourceService.rawValue)
                .filter(ManualMapping.Columns.sourceTrackID == sourceID)
                .fetchOne(db)
        }
    }

    public func saveManualMapping(_ mapping: ManualMapping) async throws {
        try await dbQueue.write { db in
            try mapping.save(db)
        }
    }

    public func deleteManualMapping(id: String) async throws {
        try await dbQueue.write { db in
            try ManualMapping
                .filter(ManualMapping.Columns.id == id)
                .deleteAll(db)
        }
    }

    public func getAllManualMappings() async throws -> [ManualMapping] {
        try await dbQueue.read { db in
            try ManualMapping.fetchAll(db)
        }
    }
}
