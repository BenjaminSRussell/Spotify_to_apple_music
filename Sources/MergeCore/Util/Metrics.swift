import Foundation

/// Metrics collection and monitoring
public actor MetricsCollector {
    private var counters: [String: Int] = [:]
    private var timers: [String: [TimeInterval]] = [:]
    private var gauges: [String: Double] = [:]
    
    public init() {}
    
    // MARK: - Counters
    
    public func incrementCounter(_ name: String, by value: Int = 1) {
        counters[name, default: 0] += value
    }
    
    public func getCounter(_ name: String) -> Int {
        return counters[name] ?? 0
    }
    
    // MARK: - Timers
    
    public func recordTime(_ name: String, duration: TimeInterval) {
        timers[name, default: []].append(duration)
    }
    
    public func getAverageTime(_ name: String) -> TimeInterval? {
        guard let times = timers[name], !times.isEmpty else { return nil }
        return times.reduce(0, +) / Double(times.count)
    }
    
    // MARK: - Gauges
    
    public func setGauge(_ name: String, value: Double) {
        gauges[name] = value
    }
    
    public func getGauge(_ name: String) -> Double? {
        return gauges[name]
    }
    
    // MARK: - Reports
    
    public func getReport() -> MetricsReport {
        var timerStats: [String: TimerStatistics] = [:]
        
        for (name, times) in timers {
            guard !times.isEmpty else { continue }
            let sorted = times.sorted()
            timerStats[name] = TimerStatistics(
                count: times.count,
                average: times.reduce(0, +) / Double(times.count),
                min: sorted.first!,
                max: sorted.last!,
                p50: sorted[sorted.count / 2],
                p95: sorted[Int(Double(sorted.count) * 0.95)],
                p99: sorted[Int(Double(sorted.count) * 0.99)]
            )
        }
        
        return MetricsReport(
            counters: counters,
            timers: timerStats,
            gauges: gauges
        )
    }
    
    public func reset() {
        counters.removeAll()
        timers.removeAll()
        gauges.removeAll()
    }
}

// MARK: - Supporting Types

public struct MetricsReport {
    public let counters: [String: Int]
    public let timers: [String: TimerStatistics]
    public let gauges: [String: Double]
    
    public var summary: String {
        var output = "=== Metrics Report ===\n\n"
        
        if !counters.isEmpty {
            output += "Counters:\n"
            for (name, value) in counters.sorted(by: { $0.key < $1.key }) {
                output += "  \(name): \(value)\n"
            }
            output += "\n"
        }
        
        if !timers.isEmpty {
            output += "Timers:\n"
            for (name, stats) in timers.sorted(by: { $0.key < $1.key }) {
                output += "  \(name):\n"
                output += "    Count: \(stats.count)\n"
                output += "    Avg: \(String(format: "%.3f", stats.average))s\n"
                output += "    Min: \(String(format: "%.3f", stats.min))s\n"
                output += "    Max: \(String(format: "%.3f", stats.max))s\n"
                output += "    P50: \(String(format: "%.3f", stats.p50))s\n"
                output += "    P95: \(String(format: "%.3f", stats.p95))s\n"
            }
            output += "\n"
        }
        
        if !gauges.isEmpty {
            output += "Gauges:\n"
            for (name, value) in gauges.sorted(by: { $0.key < $1.key }) {
                output += "  \(name): \(String(format: "%.2f", value))\n"
            }
        }
        
        return output
    }
}

public struct TimerStatistics {
    public let count: Int
    public let average: TimeInterval
    public let min: TimeInterval
    public let max: TimeInterval
    public let p50: TimeInterval
    public let p95: TimeInterval
    public let p99: TimeInterval
}

/// Global metrics collector
public let globalMetrics = MetricsCollector()

/// Measure execution time of a block
public func measureTime<T>(_ name: String, _ block: () async throws -> T) async rethrows -> T {
    let start = Date()
    defer {
        let duration = Date().timeIntervalSince(start)
        Task {
            await globalMetrics.recordTime(name, duration: duration)
        }
    }
    return try await block()
}
