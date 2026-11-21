import Darwin
import Foundation

/// Which program runs the HMRC server code.
public enum RuntimeKind: String, Sendable, CaseIterable {
    /// The bundled native Apple Silicon Python, which loads the installed HMRC code.
    case native
    /// HMRC's own `rti` executable (Intel; on Apple Silicon it needs Rosetta 2).
    case hmrc
}

/// The native Python runtime that ships inside PAYE Launcher.
public struct NativeRuntime: Equatable, Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public var python: URL { root.appendingPathComponent("python/bin/python2.7") }
    public var bootScript: URL { root.appendingPathComponent("bpt_native_boot.py") }

    /// The runtime in `resources/runtime`, if it is complete.
    public static func bundled(inResources resources: URL?, fileManager: FileManager = .default) -> NativeRuntime? {
        guard let resources else { return nil }
        let runtime = NativeRuntime(root: resources.appendingPathComponent("runtime", isDirectory: true))
        guard fileManager.isExecutableFile(atPath: runtime.python.path),
              fileManager.fileExists(atPath: runtime.bootScript.path) else { return nil }
        return runtime
    }
}

/// A command to run, with everything that `Process` needs.
public struct ServerCommand: Equatable, Sendable {
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: URL
}

public enum Runtime {
    /// True on Apple Silicon, also when this process runs in Rosetta.
    public static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    public static func rosettaInstalled(fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")
    }

    /// The runtime to use for a preference on this machine.
    ///
    /// The native runtime is for Apple Silicon only. On an Intel Mac, HMRC's
    /// own server is already native.
    public static func effective(preferred: RuntimeKind, isAppleSilicon: Bool, native: NativeRuntime?) -> RuntimeKind {
        guard preferred == .native, isAppleSilicon, native != nil else { return .hmrc }
        return .native
    }

    /// Builds the command that runs `rti <arguments>` with the chosen runtime.
    public static func command(
        _ arguments: [String],
        kind: RuntimeKind,
        install: BPTInstallation,
        native: NativeRuntime?,
        baseEnvironment: [String: String]
    ) -> ServerCommand {
        var env = baseEnvironment.filter { !$0.key.hasPrefix("PYTHON") && !$0.key.hasPrefix("DYLD_") }
        env["PYTHONUNBUFFERED"] = "1"
        switch kind {
        case .native where native != nil:
            env["BPT_RTI_APP"] = install.rtiApp.path
            return ServerCommand(
                executable: native!.python,
                // -S: no site.py, -E: ignore PYTHON* variables, -B: no .pyc files, -u: unbuffered output.
                arguments: ["-S", "-E", "-B", "-u", native!.bootScript.path] + arguments,
                environment: env,
                workingDirectory: install.serverDirectory
            )
        default:
            return ServerCommand(
                executable: install.rtiExecutable,
                arguments: arguments,
                environment: env,
                workingDirectory: install.serverDirectory
            )
        }
    }
}
