import Foundation

/// Protocol for manual mapping persistence
public protocol MappingStore: Sendable {
    func getManualMapping(sourceService: MusicService, sourceID: String) async throws -> ManualMapping?
    func saveManualMapping(_ mapping: ManualMapping) async throws
    func deleteManualMapping(id: String) async throws
    func getAllManualMappings() async throws -> [ManualMapping]
}

/// Default implementation (stub)
public final class MappingStoreImpl: MappingStore {
    public init() {}

    public func getManualMapping(sourceService: MusicService, sourceID: String) async throws -> ManualMapping? {
        // TODO: Implement database fetch
        return nil
    }

    public func saveManualMapping(_ mapping: ManualMapping) async throws {
        // TODO: Implement database save
    }

    public func deleteManualMapping(id: String) async throws {
        // TODO: Implement database delete
    }

    public func getAllManualMappings() async throws -> [ManualMapping] {
        // TODO: Implement fetch all
        return []
    }
}
