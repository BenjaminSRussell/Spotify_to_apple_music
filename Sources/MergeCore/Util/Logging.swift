import Foundation

/// Centralized logging utility
public enum Log {
    public static func debug(_ message: String, file: String = #file, line: Int = #line) {
        #if DEBUG
        print("🔍 [\(timestamp())] \(file):\(line) - \(message)")
        #endif
    }

    public static func info(_ message: String) {
        print("ℹ️  [\(timestamp())] \(message)")
    }

    public static func warning(_ message: String) {
        print("⚠️  [\(timestamp())] \(message)")
    }

    public static func error(_ message: String, error: Error? = nil) {
        print("❌ [\(timestamp())] \(message)")
        if let error = error {
            print("   Error: \(error)")
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
