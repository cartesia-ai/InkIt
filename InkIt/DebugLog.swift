import Foundation
import os

/// Debug sink that writes to BOTH unified logging and a flat file under
/// `~/Library/Logs/InkIt-debug.log`. The file is the reliable channel under
/// ad-hoc signing + hardened runtime, where NSLog to unified logging is
/// occasionally suppressed. Use this for any developer-facing trace.
enum DebugLog {
    private static let logger = Logger(subsystem: "com.aiqiliu.InkIt", category: "trace")
    private static let queue = DispatchQueue(label: "com.aiqiliu.InkIt.debuglog")
    private static let url: URL = {
        let logs = (try? FileManager.default.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("Logs", isDirectory: true)) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("InkIt-debug.log")
    }()

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        write(message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        write(message)
    }

    private static func write(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        queue.async {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    handle.seekToEndOfFile()
                    handle.write(data)
                    return
                }
            }
            try? data.write(to: url, options: [.atomic])
        }
    }
}
