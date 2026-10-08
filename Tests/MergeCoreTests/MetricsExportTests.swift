import XCTest
import GRDB
@testable import MergeCore

final class MetricsExportTests: XCTestCase {
    private var db: DatabaseProvider!
    private var dir: URL!

    override func setUpWithError() throws {
        db = try DatabaseProvider.inMemory()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("metrics-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func outcome(_ run: String?, _ decision: String, _ score: Double?) -> MatchOutcome {
        MatchOutcome(runID: run, sourceService: .spotify, targetService: .appleMusic, sourceTrackID: UUID().uuidString,
                     decision: decision, method: score == nil ? nil : "fuzzy", topScore: score,
                     candidateCount: score == nil ? 0 : 1)
    }

    func testEmptyDatabaseExportsHeaderOnly() throws {
        let runs = dir.appendingPathComponent("report.csv")
        let hist = MetricsExporter.histogramURL(for: runs)
        XCTAssertEqual(hist.lastPathComponent, "report.histogram.csv")

        try MetricsExporter(dbQueue: db.dbQueue).writeCSV(runsURL: runs, histogramURL: hist)

        XCTAssertEqual(try String(contentsOf: runs, encoding: .utf8), MetricsExporter.runHeader.joined(separator: ",") + "\n")
        XCTAssertEqual(try String(contentsOf: hist, encoding: .utf8), MetricsExporter.histogramHeader.joined(separator: ",") + "\n")
    }

    func testPerRunCountsAndHistogram() async throws {
        let runs = SyncRunStoreImpl(dbQueue: db.dbQueue)
        var run = SyncRun(id: "run-1", startedAt: Date(timeIntervalSince1970: 1_700_000_000), direction: .spotifyToApple,
                          operationsCount: 3)
        run.status = .completed
        run.successCount = 3
        run.failureCount = 0
        run.durationSeconds = 1.5
        try await runs.save(run)

        let store = MatchOutcomeStoreImpl(dbQueue: db.dbQueue)
        try await store.record([
            outcome("run-1", "auto", 0.95), outcome("run-1", "auto", 0.91),
            outcome("run-1", "ambiguous", 0.72), outcome("run-1", "no_match", nil),
            outcome("dry-1", "auto", 0.88),   // dry run: outcomes but no saved sync_runs row
            outcome(nil, "ambiguous", 0.65),  // matched outside any run
        ])

        let exporter = MetricsExporter(dbQueue: db.dbQueue, bucketCount: 10)
        let metrics = try exporter.runMetrics()
        XCTAssertEqual(metrics.count, 3)
        let r1 = try XCTUnwrap(metrics.first { $0.runID == "run-1" })
        XCTAssertEqual(r1.status, "completed")
        XCTAssertEqual(r1.operations, 3)
        XCTAssertEqual(r1.matches, 4)
        XCTAssertEqual(r1.autoMatches, 2)
        XCTAssertEqual(r1.ambiguous, 1)
        XCTAssertEqual(r1.noMatch, 1)
        XCTAssertEqual(r1.autoRate ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(r1.meanTopScore ?? -1, (0.95 + 0.91 + 0.72) / 3, accuracy: 1e-9)
        XCTAssertEqual(metrics.first { $0.runID == "dry-1" }?.status, "dry_run")
        XCTAssertEqual(metrics.first { $0.runID == MetricsExporter.unassignedRunID }?.status, "unassigned")

        let hist = try exporter.histogram()
        let r1Auto = hist.filter { $0.runID == "run-1" && $0.decision == "auto" }
        XCTAssertEqual(r1Auto.count, 10, "every bucket is emitted")
        XCTAssertEqual(r1Auto.first { $0.lower == 0.9 }?.count, 2)
        XCTAssertEqual(r1Auto.reduce(0) { $0 + $1.count }, 2)
        XCTAssertEqual(hist.first { $0.runID == "run-1" && $0.decision == "ambiguous" && $0.lower == 0.7 }?.count, 1)
        XCTAssertNil(hist.first { $0.decision == "no_match" }, "unscored outcomes are not bucketed")

        let runsURL = dir.appendingPathComponent("r.csv")
        try exporter.writeCSV(runsURL: runsURL, histogramURL: MetricsExporter.histogramURL(for: runsURL))
        let lines = try String(contentsOf: runsURL, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines.contains { $0.hasPrefix("run-1,2023-11-14T22:13:20Z,,spotifyToApple,completed,3,3,0,1.5,4,2,1,1,0.5,") })
    }

    func testScoreOfOneLandsInTopBucket() async throws {
        try await MatchOutcomeStoreImpl(dbQueue: db.dbQueue).record([outcome("r", "auto", 1.0), outcome("r", "auto", 0.0)])
        let hist = try MetricsExporter(dbQueue: db.dbQueue, bucketCount: 4).histogram()
        XCTAssertEqual(hist.map(\.count), [1, 0, 0, 1])
    }

    func testDiffRecordsOutcomes() async throws {
        let store = MatchOutcomeStoreImpl(dbQueue: db.dbQueue)
        let engine = MatchEngine(trackStore: TrackStoreImpl(dbQueue: db.dbQueue), mappingStore: MappingStoreImpl(dbQueue: db.dbQueue))
        let diff = DiffComputer(matchEngine: engine, outcomeStore: store)
        let track = CanonicalTrack(id: CanonicalTrackID(value: "t"), title: "Song", artist: "Band", spotifyID: "sp", availability: .spotify)
        _ = try await diff.computeTrackDiff(sourceTracks: [track], targetService: .appleMusic, runID: "run-x")
        let saved = try await store.fetchAll()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.runID, "run-x")
        XCTAssertEqual(saved.first?.decision, "no_match")
        XCTAssertEqual(saved.first?.sourceService, .spotify)
    }

    func testCSVEscaping() {
        XCTAssertEqual(MetricsExporter.escape("plain"), "plain")
        XCTAssertEqual(MetricsExporter.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(MetricsExporter.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
    }
}
