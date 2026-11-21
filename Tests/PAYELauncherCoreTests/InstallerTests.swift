import Foundation
@testable import PAYELauncherCore
import Testing

struct MachOTests {
    func bytes(_ values: [UInt32], bigEndian: Bool) -> Data {
        var data = Data()
        for value in values {
            var word = bigEndian ? value.bigEndian : value.littleEndian
            data.append(Data(bytes: &word, count: 4))
        }
        return data
    }

    @Test func readsThinBinaries() {
        #expect(MachO.architectures(header: bytes([0xFEED_FACF, 0x0100_000C, 0, 0], bigEndian: false)) == ["arm64"])
        #expect(MachO.architectures(header: bytes([0xFEED_FACF, 0x0100_0007, 3, 0], bigEndian: false)) == ["x86_64"])
    }

    @Test func readsUniversalBinaries() {
        // fat_header (magic, count) and two fat_arch entries of 5 words each.
        let fat = bytes([0xCAFE_BABE, 2, 0x0100_0007, 3, 0x4000, 0x1000, 14, 0x0100_000C, 0, 0x8000, 0x1000, 14], bigEndian: true)
        #expect(MachO.architectures(header: fat) == ["x86_64", "arm64"])
    }

    @Test func rejectsOtherFiles() {
        #expect(MachO.architectures(header: Data("#!/bin/sh\nexit 0\n".utf8)).isEmpty)
        #expect(MachO.architectures(header: Data()).isEmpty)
        #expect(MachO.architectures(of: URL(fileURLWithPath: "/nonexistent")).isEmpty)
    }

    @Test func readsARealBinary() {
        #expect(!MachO.architectures(of: URL(fileURLWithPath: "/bin/ls")).isEmpty)
    }
}

struct BPTDownloadTests {
    @Test func findsTheMacOSLink() {
        let html = """
        <a href="/government/uploads/uploaded/hmrc/payetools-rti-26.1.26134.173934-win.zip">Windows</a>
        <a href="/government/uploads/uploaded/hmrc/payetools-rti-26.1.26134.173934-osx.zip">Mac</a>
        <a href="/government/uploads/uploaded/hmrc/payetools-rti-26.1.26134.173934-linux.zip">Linux</a>
        """
        #expect(BPTDownload.downloadURL(fromPage: html)?.absoluteString
            == "https://www.gov.uk/government/uploads/uploaded/hmrc/payetools-rti-26.1.26134.173934-osx.zip")
    }

    @Test func picksTheNewestVersion() {
        let html = """
        <a href="https://www.gov.uk/government/uploads/uploaded/hmrc/payetools-rti-25.2.25200.1-osx.zip">old</a>
        <a href="/government/uploads/uploaded/hmrc/payetools-rti-26.1.26134.173934-osx.zip">new</a>
        """
        #expect(BPTDownload.downloadURL(fromPage: html)?.lastPathComponent == "payetools-rti-26.1.26134.173934-osx.zip")
    }

    @Test func noLink() {
        #expect(BPTDownload.downloadURL(fromPage: "<html>No downloads today</html>") == nil)
        #expect(BPTDownload.downloadURL(fromPage: "https://evil.example/payetools-rti-1.0-osx.zip") == nil)
    }
}

struct PackageSignatureTests {
    static let signedOutput = """
    Package "payetools-rti-26.1.26134.173934-osx.pkg":
       Status: signed by a developer certificate issued by Apple for distribution
       Notarization: trusted by the Apple notary service
       Signed with a trusted timestamp on: 2026-05-14 17:46:07 +0000
       Certificate Chain:
        1. Developer ID Installer: VE3 Global Ltd (6DYLJ52V9Y)
           Expires: 2031-02-11 19:47:48 +0000
        2. Developer ID Certification Authority
        3. Apple Root CA
    """

    @Test func readsASignedNotarisedPackage() {
        let signature = PackageSignature.parse(pkgutilOutput: Self.signedOutput)
        #expect(signature.signedForDistribution)
        #expect(signature.notarized)
        #expect(signature.signer == "Developer ID Installer: VE3 Global Ltd (6DYLJ52V9Y)")
        #expect(signature.teamID == "6DYLJ52V9Y")
        #expect(signature.isTrusted)
        #expect(signature.isKnownPublisher)
    }

    @Test func unknownPublisherIsTrustedButNotKnown() {
        let text = Self.signedOutput.replacingOccurrences(of: "VE3 Global Ltd (6DYLJ52V9Y)", with: "Someone Else (ABCDE12345)")
        let signature = PackageSignature.parse(pkgutilOutput: text)
        #expect(signature.isTrusted)
        #expect(!signature.isKnownPublisher)
        #expect(signature.teamID == "ABCDE12345")
    }

    @Test func notNotarisedIsNotTrusted() {
        let text = Self.signedOutput.replacingOccurrences(of: "   Notarization: trusted by the Apple notary service\n", with: "")
        #expect(!PackageSignature.parse(pkgutilOutput: text).isTrusted)
    }

    @Test func unsignedIsNotTrusted() {
        let signature = PackageSignature.parse(pkgutilOutput: "Package \"x.pkg\":\n   Status: no signature\n")
        #expect(!signature.isTrusted)
        #expect(signature.teamID == nil)
    }

    @Test func teamIDFromCertificateName() {
        #expect(PackageSignature.teamIdentifier(inCertificateName: "Developer ID Application: A (B) Ltd (6DYLJ52V9Y)") == "6DYLJ52V9Y")
        #expect(PackageSignature.teamIdentifier(inCertificateName: "Apple Root CA") == nil)
        #expect(PackageSignature.teamIdentifier(inCertificateName: "Name (short)") == nil)
    }

    @Test func teamIDFromCodesign() {
        #expect(codesignTeamID(fromOutput: "Identifier=uk.gov.hmrc.bptrti\nTeamIdentifier=6DYLJ52V9Y\n") == "6DYLJ52V9Y")
        #expect(codesignTeamID(fromOutput: "TeamIdentifier=not set\n") == nil)
        #expect(codesignTeamID(fromOutput: "Identifier=x\n") == nil)
    }
}

@Suite(.serialized)
struct BPTInstallJobTests {
    @Test func findsAppInExpandedPackage() {
        let dir = TemporaryDirectory()
        dir.write("x", to: "uk.gov.hmrc.bptrti.pkg/Payload/Basic PAYE Tools.app/Contents/Info.plist")
        dir.write("x", to: "uk.gov.hmrc.bptrti.pkg/Payload/Basic PAYE Tools.app/Contents/Helpers/Other.app/x")
        #expect(BPTInstallJob.findApp(named: "Basic PAYE Tools.app", in: dir.url)?.lastPathComponent == "Basic PAYE Tools.app")
        #expect(BPTInstallJob.findApp(named: "Missing.app", in: dir.url) == nil)
    }

    @Test func refusesAnUnsignedPackage() throws {
        let dir = TemporaryDirectory()
        dir.write("hello", to: "root/Applications/Fake.app/Contents/Info.plist")
        let pkg = dir.url.appendingPathComponent("zipped/fake.pkg")
        try FileManager.default.createDirectory(at: pkg.deletingLastPathComponent(), withIntermediateDirectories: true)
        let build = Process()
        build.executableURL = URL(fileURLWithPath: "/usr/bin/pkgbuild")
        build.arguments = ["--quiet", "--root", dir.url.appendingPathComponent("root").path, "--identifier", "test.fake", "--version", "1", pkg.path]
        try build.run()
        build.waitUntilExit()
        #expect(build.terminationStatus == 0)
        let zip = dir.url.appendingPathComponent("fake.zip")
        let compress = Process()
        compress.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        compress.arguments = ["-c", "-k", pkg.deletingLastPathComponent().path, zip.path]
        try compress.run()
        compress.waitUntilExit()

        let job = BPTInstallJob(workDirectory: dir.url.appendingPathComponent("work"))
        let result = job.unpackAndCheck(zip: zip)
        #expect(result == .failure(.untrustedPackage), "\(result)")
    }

    @Test func refusesAZipWithoutPackage() {
        let dir = TemporaryDirectory()
        let zip = dir.write("not a zip", to: "bad.zip")
        let job = BPTInstallJob(workDirectory: dir.url.appendingPathComponent("work"))
        guard case .failure(.badDownload) = job.unpackAndCheck(zip: zip) else {
            Issue.record("expected badDownload")
            return
        }
    }

    /// Downloads the real installer from GOV.UK (about 200 MB), checks it, and
    /// copies Basic PAYE Tools into a temporary folder. Run with PAYE_LAUNCHER_NETWORK_TESTS=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PAYE_LAUNCHER_NETWORK_TESTS"] == "1"))
    func downloadsChecksAndInstallsFromGovUK() throws {
        let dir = TemporaryDirectory()
        let steps = OutputCollector()
        let job = BPTInstallJob(workDirectory: dir.url.appendingPathComponent("work")) { step in
            if case .checking = step { steps.append(Data("checking ".utf8)) }
        }
        let package = try job.prepare().get()
        #expect(package.pathExtension == "pkg")
        #expect(steps.text.contains("checking"))
        let app = try job.installDirectly(package: package, allowedTeamIDs: BPTDownload.knownTeamIDs,
                                          destinations: [dir.url.appendingPathComponent("Applications")]).get()
        let found = BPTInstallation.newest(among: [app])
        #expect(found != nil)
        #expect(MachO.architectures(of: found!.rtiExecutable).contains("x86_64"))
        job.cleanUp()
    }
}
