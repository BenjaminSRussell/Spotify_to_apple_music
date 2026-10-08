import Foundation
import GRDB

/// Per-run match quality and sync counts (#9)
public struct RunMetrics: Equatable, Sendable {
    public var runID: String
    public var startedAt: Date?
    public var completedAt: Date?
    public var direction: String?
    public var status: String
    public var operations: Int?
    public var successes: Int?
    public var failures: Int?
    public var durationSeconds: Double?
    public var matches: Int
    public var autoMatches: Int
    public var ambiguous: Int
    public var noMatch: Int
    public var meanTopScore: Double?

    public var autoRate: Double? { matches > 0 ? Double(autoMatches) / Double(matches) : nil }
}

/// One confidence-histogram bucket for a run and decision
public struct HistogramBucket: Equatable, Sendable {
    public var runID: String
    public var decision: String
    public var lower: Double
    public var upper: Double
    public var count: Int
}

/// Builds analytics tables from `sync_runs` + `match_outcomes` and writes them as CSV.
public struct MetricsExporter: Sendable {
    public static let runHeader = [
        "run_id", "started_at", "completed_at", "direction", "status", "operations", "successes", "failures",
        "duration_seconds", "matches", "auto", "ambiguous", "no_match", "auto_rate", "mean_top_score",
    ]
    public static let histogramHeader = ["run_id", "decision", "bucket_lower", "bucket_upper", "count"]

    private let dbQueue: DatabaseQueue
    public let bucketCount: Int

    public init(dbQueue: DatabaseQueue, bucketCount: Int = 10) {
        self.dbQueue = dbQueue
        self.bucketCount = max(1, bucketCount)
    }

    /// Outcomes without a run (matching outside a sync) are grouped under this ID
    public static let unassignedRunID = "(none)"

    public func runMetrics() throws -> [RunMetrics] {
        try dbQueue.read { db in
            let runs = try SyncRun.fetchAll(db)
            let outcomes = try MatchOutcome.fetchAll(db)
            var byRun: [String: [MatchOutcome]] = [:]
            for o in outcomes { byRun[o.runID ?? Self.unassignedRunID, default: []].append(o) }

            var rows: [RunMetrics] = runs.map { run in
                Self.metrics(runID: run.id, run: run, outcomes: byRun.removeValue(forKey: run.id) ?? [])
            }
            // Outcomes whose run was never saved (dry runs) or that have no run
            for (id, list) in byRun {
                rows.append(Self.metrics(runID: id, run: nil, outcomes: list))
            }
            return rows.sorted {
                ($0.startedAt ?? .distantFuture, $0.runID) < ($1.startedAt ?? .distantFuture, $1.runID)
            }
        }
    }

    private static func metrics(runID: String, run: SyncRun?, outcomes: [MatchOutcome]) -> RunMetrics {
        let scores = outcomes.compactMap(\.topScore)
        return RunMetrics(
            runID: runID,
            startedAt: run?.startedAt ?? outcomes.map(\.recordedAt).min(),
            completedAt: run?.completedAt,
            direction: run?.direction.rawValue,
            status: run?.status.rawValue ?? (runID == unassignedRunID ? "unassigned" : "dry_run"),
            operations: run?.operationsCount,
            successes: run?.successCount,
            failures: run?.failureCount,
            durationSeconds: run?.durationSeconds,
            matches: outcomes.count,
            autoMatches: outcomes.filter { $0.decision == "auto" }.count,
            ambiguous: outcomes.filter { $0.decision == "ambiguous" }.count,
            noMatch: outcomes.filter { $0.decision == "no_match" }.count,
            meanTopScore: scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
        )
    }

    /// `bucketCount` equal-width buckets over [0, 1] per run and decision (scored outcomes only).
    /// Every bucket is emitted (zeros included) so histograms line up across runs.
    public func histogram() throws -> [HistogramBucket] {
        let outcomes = try dbQueue.read { db in try MatchOutcome.fetchAll(db) }
        var counts: [String: [String: [Int]]] = [:]
        for o in outcomes {
            guard let score = o.topScore else { continue }
            let run = o.runID ?? Self.unassignedRunID
            let i = min(bucketCount - 1, max(0, Int(score * Double(bucketCount))))
            var perDecision = counts[run, default: [:]]
            var buckets = perDecision[o.decision, default: Array(repeating: 0, count: bucketCount)]
            buckets[i] += 1
            perDecision[o.decision] = buckets
            counts[run] = perDecision
        }
        var rows: [HistogramBucket] = []
        for run in counts.keys.sorted() {
            for decision in counts[run]!.keys.sorted() {
                for (i, c) in counts[run]![decision]!.enumerated() {
                    rows.append(HistogramBucket(runID: run, decision: decision,
                                                lower: Double(i) / Double(bucketCount),
                                                upper: Double(i + 1) / Double(bucketCount), count: c))
                }
            }
        }
        return rows
    }

    // MARK: - CSV

    /// Writes `runsURL` and `histogramURL`. An empty database produces header-only files.
    public func writeCSV(runsURL: URL, histogramURL: URL) throws {
        let iso = ISO8601DateFormatter()
        let fmt: (Double?) -> String = { $0.map { String(format: "%.6g", $0) } ?? "" }
        let runLines: [[String]] = try runMetrics().map { r in
            let started: String = r.startedAt.map { iso.string(from: $0) } ?? ""
            let completed: String = r.completedAt.map { iso.string(from: $0) } ?? ""
            let ops: String = r.operations.map { String($0) } ?? ""
            let ok: String = r.successes.map { String($0) } ?? ""
            let failed: String = r.failures.map { String($0) } ?? ""
            var row: [String] = [r.runID, started, completed, r.direction ?? "", r.status, ops, ok, failed]
            row.append(fmt(r.durationSeconds))
            row.append(contentsOf: [String(r.matches), String(r.autoMatches), String(r.ambiguous), String(r.noMatch)])
            row.append(fmt(r.autoRate))
            row.append(fmt(r.meanTopScore))
            return row
        }
        let histLines = try histogram().map { h in
            [h.runID, h.decision, fmt(h.lower), fmt(h.upper), String(h.count)]
        }
        try Self.csv(header: Self.runHeader, rows: runLines).write(to: runsURL, atomically: true, encoding: .utf8)
        try Self.csv(header: Self.histogramHeader, rows: histLines).write(to: histogramURL, atomically: true, encoding: .utf8)
    }

    /// Histogram path next to the runs file: `report.csv` -> `report.histogram.csv`
    public static func histogramURL(for runsURL: URL) -> URL {
        runsURL.deletingPathExtension().appendingPathExtension("histogram").appendingPathExtension("csv")
    }

    static func csv(header: [String], rows: [[String]]) -> String {
        ([header] + rows).map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
