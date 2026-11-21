import Foundation

/// An installed copy of HMRC Basic PAYE Tools.
public struct BPTInstallation: Equatable, Sendable {
    public static let bundleIdentifier = "uk.gov.hmrc.bptrti"
    public static let downloadPage = URL(string: "https://www.gov.uk/basic-paye-tools")!

    public let appURL: URL
    public let version: String

    public init(appURL: URL, version: String) {
        self.appURL = appURL
        self.version = version
    }

    /// The HMRC server bundle inside the app.
    public var rtiApp: URL { appURL.appendingPathComponent("Contents/Helpers/rti.app", isDirectory: true) }
    public var serverDirectory: URL { rtiApp.appendingPathComponent("Contents/MacOS", isDirectory: true) }
    public var rtiExecutable: URL { serverDirectory.appendingPathComponent("rti") }
    public var resources: URL { rtiApp.appendingPathComponent("Contents/Resources", isDirectory: true) }
    public var manageScript: URL { resources.appendingPathComponent("manage.py") }

    /// Usual install locations, used together with the Launch Services results.
    public static func defaultCandidates(home: URL) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications/Basic PAYE Tools.app"),
            home.appendingPathComponent("Applications/Basic PAYE Tools.app"),
        ]
    }

    /// Returns the newest usable installation among `candidates`.
    ///
    /// A candidate is usable when its server executable exists. Copies in the
    /// Trash are ignored. `versionOf` reads the app's `CFBundleVersion`.
    public static func newest(
        among candidates: [URL],
        fileManager: FileManager = .default,
        versionOf: (URL) -> String? = { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String }
    ) -> BPTInstallation? {
        var seen = Set<String>()
        var found: [BPTInstallation] = []
        for candidate in candidates {
            let url = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard seen.insert(url.path).inserted, !url.path.contains("/.Trash/") else { continue }
            let install = BPTInstallation(appURL: url, version: versionOf(url) ?? "0")
            if fileManager.isExecutableFile(atPath: install.rtiExecutable.path) {
                found.append(install)
            }
        }
        return found.max { compareVersions($0.version, $1.version) == .orderedAscending }
    }

    /// Compares dotted version strings numerically ("26.1.10" > "26.1.9").
    public static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: .numeric)
    }
}
