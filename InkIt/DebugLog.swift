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

    static func boundedBlock(title: String, text: String, limit: Int = 12_000) -> String {
        let data = Data(text.utf8)
        let truncated = text.count > limit
        let body = truncated ? String(text.prefix(limit)) : text
        return """
        \(title) bytes=\(data.count) hash=\(stableHash(data)) truncated=\(truncated)
        \(body)
        """
    }

    static func infoBlock(title: String, text: String, limit: Int = 12_000) {
        info(boundedBlock(title: title, text: text, limit: limit))
    }

    static func redacted(_ text: String, secrets: [String]) -> String {
        var redacted = text
        for secret in secrets where !secret.isEmpty {
            redacted = redacted.replacingOccurrences(of: secret, with: "<redacted>")
        }
        return redacted
    }

    static func prettyJSONString(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
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

    private static func stableHash(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
