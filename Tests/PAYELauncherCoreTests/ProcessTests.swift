import Foundation
@testable import PAYELauncherCore
import Testing

private func shell(_ script: String, in dir: URL) -> ServerCommand {
    ServerCommand(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], environment: ["PATH": "/usr/bin:/bin"], workingDirectory: dir)
}

@Suite(.serialized)
struct ProcessRunnerTests {
    @Test func returnsExitCodeAndOutput() {
        let dir = TemporaryDirectory()
        let output = OutputCollector()
        let runner = ProcessRunner { output.append($0) }
        #expect(runner.run(shell("echo hello; echo oops >&2; exit 3", in: dir.url), timeout: 10) == 3)
        #expect(waitFor(2) { output.text.contains("hello") && output.text.contains("oops") })
    }

    @Test func usesWorkingDirectoryAndEnvironment() {
        let dir = TemporaryDirectory()
        let output = OutputCollector()
        let runner = ProcessRunner { output.append($0) }
        var cmd = shell("pwd -P; echo \"$MARKER\"", in: dir.url)
        cmd.environment["MARKER"] = "set-by-test"
        #expect(runner.run(cmd, timeout: 10) == 0)
        let realDir = dir.url.resolvingSymlinksInPath().path
        #expect(waitFor(2) { output.text.contains(realDir) && output.text.contains("set-by-test") })
    }

    @Test func stopsCommandsThatTakeTooLong() {
        let dir = TemporaryDirectory()
        let runner = ProcessRunner { _ in }
        let start = Date()
        #expect(runner.run(shell("sleep 30", in: dir.url), timeout: 0.5) == nil)
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test func returnsNilWhenExecutableIsMissing() {
        let dir = TemporaryDirectory()
        let output = OutputCollector()
        let runner = ProcessRunner { output.append($0) }
        let cmd = ServerCommand(executable: URL(fileURLWithPath: "/nonexistent/rti"), arguments: [], environment: [:], workingDirectory: dir.url)
        #expect(runner.run(cmd, timeout: 5) == nil)
        #expect(output.text.contains("Could not start"))
    }

    @Test func stopEscalatesWhenInterruptIsIgnored() throws {
        let dir = TemporaryDirectory()
        let runner = ProcessRunner { _ in }
        let process = try runner.start(shell("trap '' INT; sleep 30", in: dir.url)) { _ in }
        #expect(waitFor(2) { process.isRunning })
        ProcessRunner.stop(pid: process.processIdentifier, interruptWait: 0.3, terminateWait: 3)
        #expect(waitFor(5) { !process.isRunning })
    }
}

@Suite(.serialized)
struct PIDFileTests {
    @Test func writesAndReads() {
        let dir = TemporaryDirectory()
        let file = PIDFile(url: dir.url.appendingPathComponent("sub/server.pid"))
        file.write(1234)
        #expect(file.read() == 1234)
        file.remove()
        #expect(file.read() == nil)
    }

    @Test func stopsOnlyMatchingServer() throws {
        let dir = TemporaryDirectory()
        let runner = ProcessRunner { _ in }
        let process = try runner.start(shell("sleep 30", in: dir.url)) { _ in }
        let file = PIDFile(url: dir.url.appendingPathComponent("server.pid"))

        file.write(process.processIdentifier)
        #expect(!file.stopStaleServer { _ in false })
        #expect(process.isRunning)
        #expect(file.read() == nil)

        file.write(process.processIdentifier)
        #expect(file.stopStaleServer { _ in true })
        #expect(waitFor(5) { !process.isRunning })
    }
}

@Suite(.serialized)
struct BPTServerTests {
    /// A fake rti: records each command, and for runserver serves HTTP with python3.
    static let fakeRTI = """
    #!/bin/sh
    echo "$@" >> "$CALLS"
    case "$1" in
      runserver) exec /usr/bin/python3 -m http.server "$2" --bind 127.0.0.1 ;;
      fail) exit 4 ;;
      *) exit 0 ;;
    esac
    """

    func makeServer(dir: TemporaryDirectory, port: Int) -> (BPTServer, URL) {
        let app = dir.fakeBPT(version: "26.1", rtiScript: Self.fakeRTI)
        let install = BPTInstallation(appURL: app, version: "26.1")
        let calls = dir.url.appendingPathComponent("calls.txt")
        let server = BPTServer(
            install: install,
            local: LocalServer(port: port),
            kind: .hmrc,
            pidFile: PIDFile(url: dir.url.appendingPathComponent("server.pid")),
            runner: ProcessRunner { _ in },
            log: { _ in },
            makeCommand: { args in
                var cmd = Runtime.command(args, kind: .hmrc, install: install, native: nil, baseEnvironment: ["PATH": "/usr/bin:/bin"])
                cmd.environment["CALLS"] = calls.path
                return cmd
            }
        )
        return (server, calls)
    }

    @Test func runsCommands() {
        let dir = TemporaryDirectory()
        let (server, calls) = makeServer(dir: dir, port: freePort())
        #expect(server.runCommand(["startdb"], timeout: 10) == 0)
        #expect(server.runCommand(["fail"], timeout: 10) == 4)
        #expect((try? String(contentsOf: calls, encoding: .utf8)) == "startdb\nfail\n")
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/python3")))
    func startsWaitsAndShutsDownWithBackup() throws {
        let dir = TemporaryDirectory()
        let port = freePort()
        let (server, calls) = makeServer(dir: dir, port: port)
        let unexpected = OutputCollector()
        server.onUnexpectedExit = { _ in unexpected.append(Data("exit".utf8)) }

        try server.startServer()
        #expect(server.waitUntilReady(timeout: 30))
        #expect(PIDFile(url: dir.url.appendingPathComponent("server.pid")).read() != nil)
        server.shutdown()
        #expect(!server.isRunning)
        #expect(!LocalServer(port: port).portInUse())
        let recorded = (try? String(contentsOf: calls, encoding: .utf8)) ?? ""
        #expect(recorded == "runserver \(port)\nautobackup\n")
        #expect(PIDFile(url: dir.url.appendingPathComponent("server.pid")).read() == nil)
        usleep(200_000)
        #expect(unexpected.text.isEmpty)
    }

    @Test func reportsUnexpectedExit() throws {
        let dir = TemporaryDirectory()
        let app = dir.fakeBPT(version: "26.1", rtiScript: "#!/bin/sh\nexit 9\n")
        let install = BPTInstallation(appURL: app, version: "26.1")
        let server = BPTServer(
            install: install, local: LocalServer(port: freePort()), kind: .hmrc, pidFile: nil,
            runner: ProcessRunner { _ in }, log: { _ in },
            makeCommand: { Runtime.command($0, kind: .hmrc, install: install, native: nil, baseEnvironment: [:]) }
        )
        let codes = OutputCollector()
        server.onUnexpectedExit = { codes.append(Data("\($0)".utf8)) }
        try server.startServer()
        #expect(!server.waitUntilReady(timeout: 5))
        #expect(waitFor(5) { codes.text == "9" })
    }

    @Test func adoptedServerIsNotStopped() {
        let dir = TemporaryDirectory()
        let (server, calls) = makeServer(dir: dir, port: freePort())
        server.adopted = true
        server.shutdown()
        #expect(!FileManager.default.fileExists(atPath: calls.path))
    }
}
