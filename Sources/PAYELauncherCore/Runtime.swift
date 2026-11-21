import Darwin
import Foundation

/// Which program runs the HMRC server code.
public enum RuntimeKind: String, Sendable, CaseIterable {
    /// The built-in native Python runtime, which loads the installed HMRC code.
    case native
    /// HMRC's own `rti` executable (Intel; on Apple Silicon it needs Rosetta 2).
    case hmrc
}

/// The native Python runtime that ships inside PAYE Launcher (universal: arm64 and x86_64).
public struct NativeRuntime: Equatable, Sendable {
    public let root: URL
    /// The CPU architectures of the runtime's Python executable.
    public let architectures: Set<String>

    public init(root: URL, architectures: Set<String>? = nil) {
        self.root = root
        self.architectures = architectures ?? MachO.architectures(of: root.appendingPathComponent("python/bin/python2.7"))
    }

    public var python: URL { root.appendingPathComponent("python/bin/python2.7") }
    public var bootScript: URL { root.appendingPathComponent("bpt_native_boot.py") }

    public func supports(_ architecture: String) -> Bool { architectures.contains(architecture) }

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
    public static var isAppleSilicon: Bool { sysctlFlag("hw.optional.arm64") }

    /// True when this process runs in Rosetta (for example "Open using Rosetta").
    public static var isTranslated: Bool { sysctlFlag("sysctl.proc_translated") }

    /// The native architecture of this Mac: "arm64" or "x86_64".
    public static var machineArchitecture: String { isAppleSilicon ? "arm64" : "x86_64" }

    public static func rosettaInstalled(fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")
    }

    private static func sysctlFlag(_ name: String) -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 && value == 1
    }

    /// The runtime to use for a preference on this Mac. The built-in runtime is
    /// used when the user wants it and it contains this Mac's architecture.
    public static func effective(preferred: RuntimeKind, machineArchitecture: String, native: NativeRuntime?) -> RuntimeKind {
        guard preferred == .native, let native, native.supports(machineArchitecture) else { return .hmrc }
        return .native
    }

    /// Builds the command that runs `rti <arguments>` with the chosen runtime.
    ///
    /// If this app runs in Rosetta on Apple Silicon, `forceArm64` makes the
    /// universal runtime start as arm64 (a translated process would start it as x86_64).
    public static func command(
        _ arguments: [String],
        kind: RuntimeKind,
        install: BPTInstallation,
        native: NativeRuntime?,
        baseEnvironment: [String: String],
        forceArm64: Bool = false
    ) -> ServerCommand {
        var env = baseEnvironment.filter { !$0.key.hasPrefix("PYTHON") && !$0.key.hasPrefix("DYLD_") }
        env["PYTHONUNBUFFERED"] = "1"
        guard kind == .native, let native else {
            return ServerCommand(
                executable: install.rtiExecutable,
                arguments: arguments,
                environment: env,
                workingDirectory: install.serverDirectory
            )
        }
        env["BPT_RTI_APP"] = install.rtiApp.path
        // -S: no site.py, -E: ignore PYTHON* variables, -B: no .pyc files, -u: unbuffered output.
        let pythonArguments = ["-S", "-E", "-B", "-u", native.bootScript.path] + arguments
        if forceArm64 {
            return ServerCommand(
                executable: URL(fileURLWithPath: "/usr/bin/arch"),
                arguments: ["-arm64", native.python.path] + pythonArguments,
                environment: env,
                workingDirectory: install.serverDirectory
            )
        }
        return ServerCommand(
            executable: native.python,
            arguments: pythonArguments,
            environment: env,
            workingDirectory: install.serverDirectory
        )
    }
}
