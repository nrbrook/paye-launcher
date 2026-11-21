import Foundation

/// Writes the launcher log, together with the server output, to
/// `~/HMRC/payetools-rti/logs/launcher-<date>.log`.
public final class Logger: @unchecked Sendable {
    public let url: URL
    private let queue = DispatchQueue(label: "paye-launcher.log")
    private let handle: FileHandle?
    private let stamp: DateFormatter

    public init(directory: URL, keepDays: Int = 60, now: Date = Date()) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = DateFormatter()
        name.locale = Locale(identifier: "en_US_POSIX")
        name.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        url = directory.appendingPathComponent("launcher-\(name.string(from: now)).log")
        fm.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()
        stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        Self.removeOldLogs(in: directory, olderThan: now.addingTimeInterval(-Double(keepDays) * 86_400))
    }

    public func write(_ message: String) {
        let line = "[\(stamp.string(from: Date()))] [launcher] \(message)\n"
        queue.async { self.handle?.write(Data(line.utf8)) }
    }

    public func raw(_ data: Data) {
        queue.async { self.handle?.write(data) }
    }

    /// Waits until all queued writes are done.
    public func flush() {
        queue.sync { try? handle?.synchronize() }
    }

    static func removeOldLogs(in directory: URL, olderThan cutoff: Date) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for item in items where item.lastPathComponent.hasPrefix("launcher-") && item.pathExtension == "log" {
            if let date = try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date < cutoff {
                try? fm.removeItem(at: item)
            }
        }
    }
}
