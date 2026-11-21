import Darwin
import Foundation

/// Runs the Basic PAYE Tools server with the same steps as HMRC's own app:
/// `startdb`, `updatecheck`, `runserver <port>`, and `autobackup` at quit.
///
/// All methods block, so call them from a background queue.
public final class BPTServer: @unchecked Sendable {
    public let install: BPTInstallation
    public let local: LocalServer
    public let kind: RuntimeKind
    /// True when we use a server that this app did not start.
    public var adopted = false
    public var onUnexpectedExit: (@Sendable (Int32) -> Void)?

    private let makeCommand: @Sendable ([String]) -> ServerCommand
    private let runner: ProcessRunner
    private let log: @Sendable (String) -> Void
    private let pidFile: PIDFile?
    private let lock = NSLock()
    private var process: Process?
    private var stopping = false

    public init(
        install: BPTInstallation,
        local: LocalServer,
        kind: RuntimeKind,
        pidFile: PIDFile?,
        runner: ProcessRunner,
        log: @escaping @Sendable (String) -> Void,
        makeCommand: @escaping @Sendable ([String]) -> ServerCommand
    ) {
        self.install = install
        self.local = local
        self.kind = kind
        self.pidFile = pidFile
        self.runner = runner
        self.log = log
        self.makeCommand = makeCommand
    }

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return process?.isRunning ?? false
    }

    /// Runs one management command, for example `startdb`.
    @discardableResult
    public func runCommand(_ arguments: [String], timeout: TimeInterval) -> Int32? {
        log("Running (\(kind.rawValue)): rti \(arguments.joined(separator: " "))")
        let status = runner.run(makeCommand(arguments), timeout: timeout)
        log("rti \(arguments.joined(separator: " ")) finished with exit code \(status.map(String.init) ?? "none")")
        return status
    }

    /// Starts `runserver` and returns at once.
    public func startServer() throws {
        lock.lock(); stopping = false; lock.unlock()
        log("Running (\(kind.rawValue)): rti runserver \(local.port)")
        let process = try runner.start(makeCommand(["runserver", "\(local.port)"])) { [weak self] status in
            guard let self else { return }
            self.pidFile?.remove()
            self.log("Web server finished with exit code \(status)")
            self.lock.lock(); let stopping = self.stopping; self.lock.unlock()
            if !stopping { self.onUnexpectedExit?(status) }
        }
        pidFile?.write(process.processIdentifier)
        lock.lock(); self.process = process; lock.unlock()
    }

    /// Waits until the server answers, the process stops, or the time ends.
    public func waitUntilReady(timeout: TimeInterval, poll: TimeInterval = 0.25) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !adopted && !isRunning { return false }
            if local.get("/", timeout: 2) != nil { return true }
            Thread.sleep(forTimeInterval: poll)
        }
        return false
    }

    /// Stops the web server, then makes the automatic backup (as HMRC's app does at exit).
    public func shutdown(backup: Bool = true) {
        guard !adopted else { return }
        lock.lock(); stopping = true; let process = self.process; lock.unlock()
        if let process, process.isRunning {
            log("Stopping the web server")
            ProcessRunner.stop(pid: process.processIdentifier)
            process.waitUntilExit()
        }
        pidFile?.remove()
        if backup { runCommand(["autobackup"], timeout: 300) }
    }
}
