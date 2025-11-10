import Foundation

/// Retry policy with exponential backoff for API requests
public actor RetryPolicy {
    private let maxAttempts: Int
    private let baseDelay: TimeInterval
    private let maxDelay: TimeInterval
    private let jitterFactor: Double
    
    public init(
        maxAttempts: Int = 4,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 32.0,
        jitterFactor: Double = 0.1
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitterFactor = jitterFactor
    }
    
    // MARK: - Retry Logic
    
    /// Execute operation with exponential backoff retry
    public func execute<T>(
        operation: @Sendable () async throws -> T,
        shouldRetry: ((Error) -> Bool)? = nil
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<maxAttempts {
            do {
                let result = try await operation()
                
                if attempt > 0 {
                    Log.info("Operation succeeded after \(attempt + 1) attempts")
                }
                
                return result
            } catch {
                lastError = error
                
                // Check if we should retry this error
                if let shouldRetry = shouldRetry, !shouldRetry(error) {
                    Log.debug("Error is not retryable: \(error)")
                    throw error
                }
                
                // Don't sleep after last attempt
                if attempt < maxAttempts - 1 {
                    let delay = calculateDelay(attempt: attempt)
                    Log.debug("Attempt \(attempt + 1) failed, retrying in \(String(format: "%.2f", delay))s...")
                    
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        // All attempts failed
        Log.error("All \(maxAttempts) attempts failed")
        throw lastError ?? RetryError.maxAttemptsExceeded
    }
    
    // MARK: - Delay Calculation
    
    /// Calculate delay with exponential backoff and jitter
    private func calculateDelay(attempt: Int) -> TimeInterval {
        // Exponential backoff: base * 2^attempt
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt))
        
        // Cap at max delay
        let cappedDelay = min(exponentialDelay, maxDelay)
        
        // Add jitter to prevent thundering herd
        let jitter = cappedDelay * jitterFactor * (Double.random(in: -1...1))
        
        return max(0, cappedDelay + jitter)
    }
    
    // MARK: - Convenience Methods
    
    /// Check if error is retryable (network/rate limit errors)
    public static func isRetryableError(_ error: Error) -> Bool {
        // Network errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost,
                 .notConnectedToInternet, .cannotFindHost:
                return true
            default:
                return false
            }
        }
        
        // HTTP status codes
        if let httpError = error as? HTTPError {
            switch httpError.statusCode {
            case 408, 429, 500, 502, 503, 504: // Timeout, rate limit, server errors
                return true
            default:
                return false
            }
        }
        
        // Custom retryable errors
        if error is RetryableError {
            return true
        }
        
        return false
    }
}

// MARK: - Errors

public enum RetryError: Error {
    case maxAttemptsExceeded
    case operationCancelled
}

public protocol RetryableError: Error {}

public struct HTTPError: Error {
    public let statusCode: Int
    public let message: String?
    
    public init(statusCode: Int, message: String? = nil) {
        self.statusCode = statusCode
        self.message = message
    }
}
