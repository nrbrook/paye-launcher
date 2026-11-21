import Foundation
@testable import PAYELauncherCore
import Testing

struct BPTInstallationTests {
    @Test func comparesVersionsNumerically() {
        #expect(BPTInstallation.compareVersions("26.1.10", "26.1.9") == .orderedDescending)
        #expect(BPTInstallation.compareVersions("25.2.1", "26.1.0") == .orderedAscending)
        #expect(BPTInstallation.compareVersions("26.1.26134.173934", "26.1.26134.173934") == .orderedSame)
    }

    @Test func picksTheNewestUsableCopy() {
        let dir = TemporaryDirectory()
        let old = dir.fakeBPT(named: "Old.app", version: "25.2.25100.1")
        let new = dir.fakeBPT(named: "New.app", version: "26.1.26134.173934")
        let found = BPTInstallation.newest(among: [old, new])
        #expect(found?.appURL.lastPathComponent == "New.app")
        #expect(found?.version == "26.1.26134.173934")
    }

    @Test func ignoresCopiesWithoutServerAndInTrash() {
        let dir = TemporaryDirectory()
        let noServer = dir.url.appendingPathComponent("Empty.app")
        try? FileManager.default.createDirectory(at: noServer, withIntermediateDirectories: true)
        let trashed = dir.fakeBPT(named: ".Trash/Basic PAYE Tools.app", version: "99.0")
        #expect(BPTInstallation.newest(among: [noServer, trashed]) == nil)
    }

    @Test func removesDuplicates() {
        let dir = TemporaryDirectory()
        let app = dir.fakeBPT(version: "26.1")
        var calls = 0
        let found = BPTInstallation.newest(among: [app, app, app]) { _ in calls += 1; return "26.1" }
        #expect(found != nil)
        #expect(calls == 1)
    }

    @Test func pathsInsideTheApp() {
        let install = BPTInstallation(appURL: URL(fileURLWithPath: "/Applications/Basic PAYE Tools.app"), version: "26.1")
        #expect(install.rtiExecutable.path == "/Applications/Basic PAYE Tools.app/Contents/Helpers/rti.app/Contents/MacOS/rti")
        #expect(install.manageScript.path == "/Applications/Basic PAYE Tools.app/Contents/Helpers/rti.app/Contents/Resources/manage.py")
    }
}
