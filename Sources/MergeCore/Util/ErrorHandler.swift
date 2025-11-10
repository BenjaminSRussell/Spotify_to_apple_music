import Foundation

/// Centralized error handling and recovery
public actor ErrorHandler {
    private var errorCounts: [String: Int] = [:]
    private var lastErrors: [Date: Error] = [:]
    private let maxErrorHistory = 100
    
    public init() {}
    
    // MARK: - Error Classification
    
    public enum ErrorSeverity {
        case fatal      // Unrecoverable, must stop
        case critical   // Requires user attention
        case warning    // Degraded functionality
        case info       // Logged but handled
    }
    
    public func classify(_ error: Error) -> ErrorSeverity {
        switch error {
        // Fatal errors
        case is CancellationError:
            return .fatal
            
        // Critical errors
        case MergeError.authFailed, MergeError.authRequired:
            return .critical
        case MergeError.databaseError:
            return .critical
        case MergeError.invalidConfiguration:
            return .critical
            
        // Warnings
        case MergeError.rateLimited:
            return .warning
        case MergeError.networkError:
            return .warning
        case MergeError.trackNotFound, MergeError.playlistNotFound:
            return .warning
            
        // Info
        default:
            return .info
        }
    }
    
    // MARK: - Error Recording
    
    public func record(_ error: Error, context: String? = nil) {
        let errorKey = String(describing: type(of: error))
        errorCounts[errorKey, default: 0] += 1
        lastErrors[Date()] = error
        
        // Trim history if needed
        if lastErrors.count > maxErrorHistory {
            let sortedKeys = lastErrors.keys.sorted()
            for key in sortedKeys.prefix(lastErrors.count - maxErrorHistory) {
                lastErrors.removeValue(forKey: key)
            }
        }
        
        let severity = classify(error)
        let contextInfo = context.map { " [\($0)]" } ?? ""
        
        switch severity {
        case .fatal:
            Log.error("FATAL\(contextInfo): \(error.localizedDescription)", error: error)
        case .critical:
            Log.error("CRITICAL\(contextInfo): \(error.localizedDescription)", error: error)
        case .warning:
            Log.warning("WARNING\(contextInfo): \(error.localizedDescription)")
        case .info:
            Log.info("INFO\(contextInfo): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Error Recovery
    
    /// Determine if operation should be retried based on error
    public func shouldRetry(_ error: Error, attempt: Int, maxAttempts: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        
        switch error {
        // Always retry network issues
        case is URLError:
            return true
            
        // Retry rate limits
        case MergeError.rateLimited:
            return true
            
        // Retry network errors
        case MergeError.networkError:
            return true
            
        // Don't retry auth issues
        case MergeError.authRequired, MergeError.authFailed:
            return false
            
        // Don't retry database errors
        case MergeError.databaseError:
            return false
            
        // Don't retry not found errors
        case MergeError.trackNotFound, MergeError.playlistNotFound:
            return false
            
        default:
            // Default: retry if it's an HTTP 5xx error
            if let httpError = error as? HTTPError {
                return httpError.statusCode >= 500
            }
            return false
        }
    }
    
    // MARK: - Error Statistics
    
    public func getErrorStatistics() -> ErrorStatistics {
        let totalErrors = errorCounts.values.reduce(0, +)
        let errorTypes = errorCounts.count
        let recentErrors = lastErrors.filter { $0.key.timeIntervalSinceNow > -3600 } // Last hour
        
        return ErrorStatistics(
            totalErrors: totalErrors,
            errorTypes: errorTypes,
            recentErrors: recentErrors.count,
            topErrors: Array(errorCounts.sorted { $0.value > $1.value }.prefix(5))
        )
    }
    
    public func reset() {
        errorCounts.removeAll()
        lastErrors.removeAll()
    }
}

// MARK: - Supporting Types

public struct ErrorStatistics {
    public let totalErrors: Int
    public let errorTypes: Int
    public let recentErrors: Int
    public let topErrors: [(String, Int)]
    
    public var summary: String {
        """
        Error Statistics:
        - Total errors: \(totalErrors)
        - Error types: \(errorTypes)
        - Recent (1h): \(recentErrors)
        
        Top Errors:
        \(topErrors.map { "  - \($0.0): \($0.1)" }.joined(separator: "\n"))
        """
    }
}

/// Global error handler instance
public let globalErrorHandler = ErrorHandler()
