import Darwin
import Foundation

/// Runs server commands and long-running server processes.
public final class ProcessRunner: @unchecked Sendable {
    public typealias Output = @Sendable (Data) -> Void

    private let output: Output

    public init(output: @escaping Output) {
        self.output = output
    }

    private func makeProcess(_ command: ServerCommand) -> Process {
        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.environment = command.environment
        process.currentDirectoryURL = command.workingDirectory
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let output = self.output
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                output(data)
            }
        }
        return process
    }

    /// Runs a command to the end. Returns the exit status, or nil if it did not
    /// start or did not finish within `timeout` (it is then stopped).
    public func run(_ command: ServerCommand, timeout: TimeInterval) -> Int32? {
        let process = makeProcess(command)
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do {
            try process.run()
        } catch {
            output(Data("Could not start \(command.executable.path): \(error.localizedDescription)\n".utf8))
            return nil
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 5) == .timedOut { kill(process.processIdentifier, SIGKILL) }
            return nil
        }
        return process.terminationStatus
    }

    /// Starts a command and returns at once.
    public func start(_ command: ServerCommand, onExit: @escaping @Sendable (Int32) -> Void) throws -> Process {
        let process = makeProcess(command)
        process.terminationHandler = { onExit($0.terminationStatus) }
        try process.run()
        return process
    }

    /// Stops a process: SIGINT, then SIGTERM, then SIGKILL.
    public static func stop(pid: pid_t, interruptWait: TimeInterval = 3, terminateWait: TimeInterval = 10) {
        for (signal, wait) in [(SIGINT, interruptWait), (SIGTERM, terminateWait), (SIGKILL, 2.0)] {
            guard isAlive(pid) else { return }
            kill(pid, signal)
            let deadline = Date().addingTimeInterval(wait)
            while isAlive(pid) && Date() < deadline { usleep(50_000) }
        }
    }

    public static func isAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

    public static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }
}

/// Remembers the server process, so that the next start can stop a server
/// that a crashed run left behind.
public struct PIDFile: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func write(_ pid: pid_t) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "\(pid)".write(to: url, atomically: true, encoding: .utf8)
    }

    public func read() -> pid_t? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func remove() { try? FileManager.default.removeItem(at: url) }

    /// Stops the recorded process if it is still a Basic PAYE Tools server.
    /// `isServer` receives the executable path of the process.
    @discardableResult
    public func stopStaleServer(isServer: (String) -> Bool) -> Bool {
        defer { remove() }
        guard let pid = read(), let path = ProcessRunner.executablePath(of: pid), isServer(path) else { return false }
        ProcessRunner.stop(pid: pid)
        return true
    }
}
