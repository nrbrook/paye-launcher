import Foundation
@testable import PAYELauncherCore
import Testing

struct RuntimeTests {
    let install = BPTInstallation(appURL: URL(fileURLWithPath: "/Applications/Basic PAYE Tools.app"), version: "26.1")
    let native = NativeRuntime(root: URL(fileURLWithPath: "/App/Contents/Resources/runtime"))

    @Test func nativeOnlyOnAppleSiliconWithRuntime() {
        #expect(Runtime.effective(preferred: .native, isAppleSilicon: true, native: native) == .native)
        #expect(Runtime.effective(preferred: .native, isAppleSilicon: false, native: native) == .hmrc)
        #expect(Runtime.effective(preferred: .native, isAppleSilicon: true, native: nil) == .hmrc)
        #expect(Runtime.effective(preferred: .hmrc, isAppleSilicon: true, native: native) == .hmrc)
    }

    @Test func nativeCommand() {
        let env = ["PATH": "/usr/bin", "PYTHONPATH": "/evil", "PYTHONHOME": "/evil", "DYLD_INSERT_LIBRARIES": "x"]
        let cmd = Runtime.command(["runserver", "46729"], kind: .native, install: install, native: native, baseEnvironment: env)
        #expect(cmd.executable == native.python)
        #expect(cmd.arguments == ["-S", "-E", "-B", "-u", native.bootScript.path, "runserver", "46729"])
        #expect(cmd.environment["BPT_RTI_APP"] == install.rtiApp.path)
        #expect(cmd.environment["PYTHONUNBUFFERED"] == "1")
        #expect(cmd.environment["PYTHONPATH"] == nil)
        #expect(cmd.environment["PYTHONHOME"] == nil)
        #expect(cmd.environment["DYLD_INSERT_LIBRARIES"] == nil)
        #expect(cmd.environment["PATH"] == "/usr/bin")
        #expect(cmd.workingDirectory == install.serverDirectory)
    }

    @Test func hmrcCommand() {
        let cmd = Runtime.command(["startdb"], kind: .hmrc, install: install, native: native, baseEnvironment: [:])
        #expect(cmd.executable == install.rtiExecutable)
        #expect(cmd.arguments == ["startdb"])
        #expect(cmd.environment["BPT_RTI_APP"] == nil)
        #expect(cmd.workingDirectory == install.serverDirectory)
    }

    @Test func nativeKindWithoutRuntimeFallsBackToHMRC() {
        let cmd = Runtime.command(["startdb"], kind: .native, install: install, native: nil, baseEnvironment: [:])
        #expect(cmd.executable == install.rtiExecutable)
    }

    @Test func findsBundledRuntime() {
        let dir = TemporaryDirectory()
        #expect(NativeRuntime.bundled(inResources: dir.url) == nil)
        dir.write("#!/bin/sh\n", to: "runtime/python/bin/python2.7", executable: true)
        #expect(NativeRuntime.bundled(inResources: dir.url) == nil)
        dir.write("# boot\n", to: "runtime/bpt_native_boot.py")
        #expect(NativeRuntime.bundled(inResources: dir.url)?.root.lastPathComponent == "runtime")
        #expect(NativeRuntime.bundled(inResources: nil) == nil)
    }
}
