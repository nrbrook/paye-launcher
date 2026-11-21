import Foundation

/// File locations used by Basic PAYE Tools and by PAYE Launcher.
public struct Paths: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// The Basic PAYE Tools data folder (database, backups, settings, logs).
    public var userData: URL { home.appendingPathComponent("HMRC/payetools-rti", isDirectory: true) }
    public var logs: URL { userData.appendingPathComponent("logs", isDirectory: true) }
    /// The settings file of the HMRC user interface; we read the port from it.
    public var shellSettings: URL { userData.appendingPathComponent("bptshell-settings.ini") }
    /// PAYE Launcher's own state.
    public var support: URL {
        home.appendingPathComponent("Library/Application Support/PAYE Launcher", isDirectory: true)
    }
    public var pidFile: URL { support.appendingPathComponent("server.pid") }
    public var downloads: URL { home.appendingPathComponent("Downloads", isDirectory: true) }
}
