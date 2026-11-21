import Foundation

/// Finds, downloads and checks Basic PAYE Tools from GOV.UK.
public enum BPTDownload {
    public static let pageURL = URL(string: "https://www.gov.uk/basic-paye-tools")!

    /// Apple Team IDs that sign HMRC's macOS package and app. In November 2026
    /// this is the Developer ID of VE3 Global Ltd, which builds Basic PAYE Tools
    /// for HMRC. If HMRC changes it, the user is asked before installing.
    public static let knownTeamIDs: Set<String> = ["6DYLJ52V9Y"]

    /// The macOS download link on the GOV.UK page. If there is more than one,
    /// the newest version.
    public static func downloadURL(fromPage html: String, base: URL = pageURL) -> URL? {
        let pattern = #"(?:https://www\.gov\.uk)?/government/uploads/uploaded/hmrc/payetools-rti-([0-9.]+)-osx\.zip"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range).compactMap { match -> (String, String)? in
            guard let whole = Range(match.range, in: html), let version = Range(match.range(at: 1), in: html) else { return nil }
            return (String(html[whole]), String(html[version]))
        }
        guard let best = matches.max(by: { BPTInstallation.compareVersions($0.1, $1.1) == .orderedAscending }) else { return nil }
        return URL(string: best.0, relativeTo: base)?.absoluteURL
    }
}

/// The result of `pkgutil --check-signature`.
public struct PackageSignature: Equatable, Sendable {
    public var signedForDistribution = false
    public var notarized = false
    public var signer: String?
    public var teamID: String?

    public init(signedForDistribution: Bool = false, notarized: Bool = false, signer: String? = nil, teamID: String? = nil) {
        self.signedForDistribution = signedForDistribution
        self.notarized = notarized
        self.signer = signer
        self.teamID = teamID
    }

    public static func parse(pkgutilOutput text: String) -> PackageSignature {
        var result = PackageSignature()
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Status:") {
                result.signedForDistribution = line.contains("signed by a developer certificate issued by Apple for distribution")
            } else if line.hasPrefix("Notarization:") {
                result.notarized = line.contains("trusted by the Apple notary service")
            } else if result.signer == nil, line.hasPrefix("1. ") {
                let signer = String(line.dropFirst(3))
                result.signer = signer
                result.teamID = teamIdentifier(inCertificateName: signer)
            }
        }
        return result
    }

    /// "Developer ID Installer: Name (TEAMID)" -> "TEAMID"
    public static func teamIdentifier(inCertificateName name: String) -> String? {
        guard name.hasSuffix(")"), let open = name.lastIndex(of: "(") else { return nil }
        let id = name[name.index(after: open)..<name.index(before: name.endIndex)]
        return id.count == 10 && id.allSatisfy { $0.isLetter || $0.isNumber } ? String(id) : nil
    }

    /// Signed with a Developer ID for distribution and notarised by Apple.
    public var isTrusted: Bool { signedForDistribution && notarized && teamID != nil }
    public var isKnownPublisher: Bool { teamID.map(BPTDownload.knownTeamIDs.contains) ?? false }
}

/// The Team ID in `codesign -dv` output ("TeamIdentifier=6DYLJ52V9Y").
public func codesignTeamID(fromOutput text: String) -> String? {
    for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("TeamIdentifier=") {
        let value = line.dropFirst("TeamIdentifier=".count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty || value == "not set" ? nil : value
    }
    return nil
}

public enum BPTInstallError: Error, Equatable, Sendable {
    case noDownloadLink
    case network(String)
    case badDownload(String)
    case untrustedPackage
    case unknownPublisher(signer: String, package: URL)
    case installFailed(String)

    /// A message for the user, in plain words.
    public var message: String {
        switch self {
        case .noDownloadLink:
            return "The download link for Basic PAYE Tools was not found on GOV.UK. Install it from GOV.UK yourself."
        case .network(let detail):
            return "Basic PAYE Tools could not be downloaded from GOV.UK. Check the internet connection and try again.\n\n\(detail)"
        case .badDownload(let detail):
            return "The downloaded file is not a usable Basic PAYE Tools installer.\n\n\(detail)"
        case .untrustedPackage:
            return "The downloaded installer is not signed and notarised for Apple. PAYE Launcher did not install it."
        case .unknownPublisher(let signer, _):
            return "The installer is signed by \"\(signer)\", which is not the publisher that PAYE Launcher knows for Basic PAYE Tools."
        case .installFailed(let detail):
            return "Basic PAYE Tools could not be installed.\n\n\(detail)"
        }
    }
}

/// Downloads Basic PAYE Tools from GOV.UK, checks it, and installs it.
/// All methods block, so call them from a background queue.
public final class BPTInstallJob: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public enum Step: Equatable, Sendable {
        case findingDownload
        case downloading(fraction: Double?)
        case checking
        case installing
    }

    public let workDirectory: URL
    private let progress: @Sendable (Step) -> Void
    private let log: @Sendable (String) -> Void
    private let session: URLSession
    private var downloadDone = DispatchSemaphore(value: 0)
    private var downloadResult: Result<URL, BPTInstallError> = .failure(.network("Not started"))

    public init(
        workDirectory: URL,
        progress: @escaping @Sendable (Step) -> Void = { _ in },
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.workDirectory = workDirectory
        self.progress = progress
        self.log = log
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        session = URLSession(configuration: config)
        super.init()
    }

    deinit { session.invalidateAndCancel() }

    // MARK: Steps

    /// Finds the download, downloads it, unpacks it and checks the signature.
    /// Returns the installer package.
    public func prepare(page: URL = BPTDownload.pageURL) -> Result<URL, BPTInstallError> {
        try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        progress(.findingDownload)
        let html: String
        switch fetchText(page) {
        case .success(let text): html = text
        case .failure(let error): return .failure(error)
        }
        guard let zipURL = BPTDownload.downloadURL(fromPage: html, base: page) else { return .failure(.noDownloadLink) }
        log("Downloading \(zipURL.absoluteString)")
        progress(.downloading(fraction: nil))
        let zip: URL
        switch download(zipURL) {
        case .success(let file): zip = file
        case .failure(let error): return .failure(error)
        }
        progress(.checking)
        return unpackAndCheck(zip: zip)
    }

    /// Unpacks the zip and checks the installer package in it.
    public func unpackAndCheck(zip: URL) -> Result<URL, BPTInstallError> {
        try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let unpacked = workDirectory.appendingPathComponent("unpacked", isDirectory: true)
        try? FileManager.default.removeItem(at: unpacked)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]).status == 0 else {
            return .failure(.badDownload("The zip file could not be opened."))
        }
        let packages = (FileManager.default.enumerator(at: unpacked, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "pkg" && !$0.path.contains("__MACOSX") }
        guard let package = packages.first else { return .failure(.badDownload("There is no installer package in the zip file.")) }
        let check = run("/usr/sbin/pkgutil", ["--check-signature", package.path])
        let signature = PackageSignature.parse(pkgutilOutput: check.output)
        log("Installer signature: \(signature.signer ?? "none"), notarised: \(signature.notarized)")
        guard check.status == 0, signature.isTrusted else { return .failure(.untrustedPackage) }
        guard signature.isKnownPublisher else {
            return .failure(.unknownPublisher(signer: signature.signer ?? "unknown", package: package))
        }
        return .success(package)
    }

    /// Installs without Apple's Installer: copies the signed app out of the
    /// package. Used when Rosetta is not installed, because HMRC's package asks
    /// the Installer for an Intel Mac. Returns the installed app.
    public func installDirectly(package: URL, allowedTeamIDs: Set<String>, destinations: [URL]) -> Result<URL, BPTInstallError> {
        progress(.installing)
        let expanded = workDirectory.appendingPathComponent("expanded", isDirectory: true)
        try? FileManager.default.removeItem(at: expanded)
        guard run("/usr/sbin/pkgutil", ["--expand-full", package.path, expanded.path]).status == 0 else {
            return .failure(.installFailed("The installer package could not be opened."))
        }
        guard let app = Self.findApp(named: "Basic PAYE Tools.app", in: expanded) else {
            return .failure(.installFailed("The installer package does not contain Basic PAYE Tools."))
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]).status == 0 else {
            return .failure(.installFailed("The signature of Basic PAYE Tools in the package is not valid."))
        }
        let team = codesignTeamID(fromOutput: run("/usr/bin/codesign", ["-dv", app.path]).output)
        guard let team, allowedTeamIDs.contains(team) else {
            return .failure(.installFailed("Basic PAYE Tools in the package is signed by an unexpected publisher."))
        }

        let fm = FileManager.default
        var lastError = "No folder to install to."
        for folder in destinations {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            guard fm.isWritableFile(atPath: folder.path) else { lastError = "\(folder.path) is not writable."; continue }
            let target = folder.appendingPathComponent("Basic PAYE Tools.app", isDirectory: true)
            if fm.fileExists(atPath: target.path) {
                // An unusable copy (PAYE Launcher found no usable one). Move it to the Trash, which can be undone.
                try? fm.trashItem(at: target, resultingItemURL: nil)
            }
            let copy = run("/usr/bin/ditto", [app.path, target.path])
            if copy.status == 0 {
                log("Installed Basic PAYE Tools to \(target.path)")
                return .success(target)
            }
            lastError = copy.output
        }
        return .failure(.installFailed(lastError))
    }

    /// Removes the downloaded and unpacked files.
    public func cleanUp() { try? FileManager.default.removeItem(at: workDirectory) }

    static func findApp(named name: String, in folder: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == name {
                return url
            }
            if url.pathExtension == "app" { enumerator?.skipDescendants() }
        }
        return nil
    }

    // MARK: Network

    private func fetchText(_ url: URL) -> Result<String, BPTInstallError> {
        let done = DispatchSemaphore(value: 0)
        let box = TextBox()
        session.dataTask(with: url) { data, response, error in
            if let error {
                box.result = .failure(.network(error.localizedDescription))
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                box.result = .failure(.network("GOV.UK answered with status \(http.statusCode)."))
            } else {
                box.result = .success(String(data: data ?? Data(), encoding: .utf8) ?? "")
            }
            done.signal()
        }.resume()
        done.wait()
        return box.result
    }

    private func download(_ url: URL) -> Result<URL, BPTInstallError> {
        downloadDone = DispatchSemaphore(value: 0)
        let delegateSession = URLSession(configuration: session.configuration, delegate: self, delegateQueue: nil)
        delegateSession.downloadTask(with: url).resume()
        downloadDone.wait()
        delegateSession.finishTasksAndInvalidate()
        return downloadResult
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : nil
        progress(.downloading(fraction: fraction))
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            downloadResult = .failure(.network("GOV.UK answered with status \(http.statusCode)."))
            return
        }
        // The file at `location` is removed when this method returns, so move it now.
        let name = downloadTask.originalRequest?.url?.lastPathComponent ?? "payetools.zip"
        let target = workDirectory.appendingPathComponent(FileNaming.sanitised(name))
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.moveItem(at: location, to: target)
            downloadResult = .success(target)
        } catch {
            downloadResult = .failure(.network(error.localizedDescription))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { downloadResult = .failure(.network(error.localizedDescription)) }
        downloadDone.signal()
    }

    // MARK: Tools

    private func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let collector = TextCollector()
        let runner = ProcessRunner { collector.append($0) }
        let command = ServerCommand(executable: URL(fileURLWithPath: tool), arguments: arguments,
                                    environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"], workingDirectory: URL(fileURLWithPath: "/"))
        let status = runner.run(command, timeout: 600) ?? -1
        return (status, collector.text)
    }
}

private final class TextBox: @unchecked Sendable {
    var result: Result<String, BPTInstallError> = .failure(.network("No answer"))
}

private final class TextCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock(); data.append(chunk); lock.unlock()
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
