import Foundation
@testable import PAYELauncherCore
import Testing

struct FileNamingTests {
    @Test func returnsNameWhenFree() {
        let url = FileNaming.uniqueURL(in: URL(fileURLWithPath: "/d"), name: "P60.pdf") { _ in false }
        #expect(url.path == "/d/P60.pdf")
    }

    @Test func addsNumberWhenTaken() {
        let taken: Set<String> = ["/d/P60.pdf", "/d/P60 2.pdf"]
        let url = FileNaming.uniqueURL(in: URL(fileURLWithPath: "/d"), name: "P60.pdf") { taken.contains($0.path) }
        #expect(url.path == "/d/P60 3.pdf")
    }

    @Test func handlesNameWithoutExtension() {
        let url = FileNaming.uniqueURL(in: URL(fileURLWithPath: "/d"), name: "backup") { $0.path == "/d/backup" }
        #expect(url.path == "/d/backup 2")
    }

    @Test func sanitisesNames() {
        #expect(FileNaming.sanitised("../../etc/passwd") == "-..-etc-passwd")
        #expect(FileNaming.sanitised("a/b:c.pdf") == "a-b-c.pdf")
        #expect(FileNaming.sanitised("...") == "download")
        #expect(FileNaming.sanitised("") == "download")
    }
}

struct PreferencesTests {
    func makeDefaults() -> UserDefaults {
        let suite = "paye-launcher-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func nativeIsTheDefaultRuntime() {
        #expect(Preferences(defaults: makeDefaults()).runtime == .native)
    }

    @Test func storesRuntime() {
        let prefs = Preferences(defaults: makeDefaults())
        prefs.runtime = .hmrc
        #expect(prefs.runtime == .hmrc)
    }

    @Test func clampsZoom() {
        let prefs = Preferences(defaults: makeDefaults())
        #expect(prefs.pageZoom == 1.0)
        prefs.pageZoom = 9
        #expect(prefs.pageZoom == 3.0)
        prefs.pageZoom = 0.1
        #expect(prefs.pageZoom == 0.5)
        prefs.pageZoom = 1.2345
        #expect(prefs.pageZoom == 1.2)
    }
}

struct LoggerTests {
    @Test func writesLinesAndRawOutput() throws {
        let dir = TemporaryDirectory()
        let logger = Logger(directory: dir.url)
        logger.write("hello")
        logger.raw(Data("server output\n".utf8))
        logger.flush()
        let text = try String(contentsOf: logger.url, encoding: .utf8)
        #expect(text.contains("[launcher] hello"))
        #expect(text.contains("server output"))
        #expect(logger.url.lastPathComponent.hasPrefix("launcher-"))
    }

    @Test func removesOnlyOldLauncherLogs() throws {
        let dir = TemporaryDirectory()
        let old = dir.write("x", to: "launcher-2020-01-01_00-00-00.log")
        let other = dir.write("x", to: "bptshell-2020-01-01.log")
        let past = Date(timeIntervalSinceNow: -100 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: other.path)
        _ = Logger(directory: dir.url, keepDays: 60)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }
}

struct PathsTests {
    @Test func locations() {
        let paths = Paths(home: URL(fileURLWithPath: "/Users/test"))
        #expect(paths.userData.path == "/Users/test/HMRC/payetools-rti")
        #expect(paths.shellSettings.path == "/Users/test/HMRC/payetools-rti/bptshell-settings.ini")
        #expect(paths.logs.path == "/Users/test/HMRC/payetools-rti/logs")
        #expect(paths.pidFile.path == "/Users/test/Library/Application Support/PAYE Launcher/server.pid")
    }
}
