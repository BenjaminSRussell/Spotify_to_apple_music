import Foundation

/// Token bucket rate limiter for API request throttling
public actor RateLimiter {
    private let maxTokens: Int
    private let refillRate: TimeInterval  // Seconds per token
    private var tokens: Double
    private var lastRefill: Date
    
    public init(requestsPerSecond: Double) {
        self.maxTokens = Int(requestsPerSecond * 10) // Buffer for burst
        self.refillRate = 1.0 / requestsPerSecond
        self.tokens = Double(maxTokens)
        self.lastRefill = Date()
    }
    
    // MARK: - Rate Limiting
    
    /// Acquire permission to make a request (awaits if needed)
    public func acquire(cost: Int = 1) async {
        await refillTokens()
        
        while tokens < Double(cost) {
            // Wait until we have enough tokens
            let timeNeeded = TimeInterval(Double(cost) - tokens) * refillRate
            Log.debug("Rate limit: waiting \(String(format: "%.2f", timeNeeded))s for \(cost) token(s)")
            
            try? await Task.sleep(nanoseconds: UInt64(timeNeeded * 1_000_000_000))
            await refillTokens()
        }
        
        tokens -= Double(cost)
    }
    
    /// Try to acquire immediately, returns false if not available
    public func tryAcquire(cost: Int = 1) async -> Bool {
        await refillTokens()
        
        if tokens >= Double(cost) {
            tokens -= Double(cost)
            return true
        }
        
        return false
    }
    
    /// Get current token availability
    public func availableTokens() async -> Int {
        await refillTokens()
        return Int(tokens)
    }
    
    // MARK: - Token Refill
    
    private func refillTokens() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefill)
        
        if elapsed > 0 {
            let tokensToAdd = elapsed / refillRate
            tokens = min(Double(maxTokens), tokens + tokensToAdd)
            lastRefill = now
        }
    }
    
    // MARK: - Batch Operations
    
    /// Execute batch operations with rate limiting
    public func executeBatch<T>(
        items: [T],
        operation: @Sendable (T) async throws -> Void
    ) async throws {
        for item in items {
            await acquire()
            try await operation(item)
        }
    }
    
    /// Execute batch with parallel execution (respecting rate limit)
    public func executeBatchParallel<T>(
        items: [T],
        maxConcurrency: Int = 5,
        operation: @Sendable (T) async throws -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = items.makeIterator()
            var activeTasks = 0
            
            // Start initial tasks
            while activeTasks < maxConcurrency, let item = iterator.next() {
                group.addTask {
                    await self.acquire()
                    try await operation(item)
                }
                activeTasks += 1
            }
            
            // Continue processing remaining items
            while let item = iterator.next() {
                try await group.next() // Wait for a task to complete
                
                group.addTask {
                    await self.acquire()
                    try await operation(item)
                }
            }
            
            // Wait for remaining tasks
            try await group.waitForAll()
        }
    }
}

// MARK: - Service-Specific Rate Limiters

/// Pre-configured rate limiters for music services
public enum ServiceRateLimiter {
    /// Spotify API rate limit: ~180 requests/minute (conservative: 2 req/sec)
    public static let spotify = RateLimiter(requestsPerSecond: 2.0)
    
    /// Apple Music API rate limit: ~20 requests/second (conservative: 10 req/sec)
    public static let appleMusic = RateLimiter(requestsPerSecond: 10.0)
}
