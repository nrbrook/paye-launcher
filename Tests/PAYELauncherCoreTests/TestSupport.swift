import Foundation
@testable import PAYELauncherCore

/// A temporary folder that is removed when the value goes away.
final class TemporaryDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paye-launcher-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func write(_ text: String, to relativePath: String, executable: Bool = false) -> URL {
        let file = url.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: file, atomically: true, encoding: .utf8)
        if executable { chmod(file.path, 0o755) }
        return file
    }

    /// Makes a fake "Basic PAYE Tools.app" with an executable rti.
    func fakeBPT(named name: String = "Basic PAYE Tools.app", version: String?, rtiScript: String = "#!/bin/sh\nexit 0\n") -> URL {
        let app = url.appendingPathComponent(name, isDirectory: true)
        write(rtiScript, to: "\(name)/Contents/Helpers/rti.app/Contents/MacOS/rti", executable: true)
        write("print('manage')\n", to: "\(name)/Contents/Helpers/rti.app/Contents/Resources/manage.py")
        if let version {
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
            <key>CFBundleIdentifier</key><string>uk.gov.hmrc.bptrti</string>
            <key>CFBundleVersion</key><string>\(version)</string>
            </dict></plist>
            """
            write(plist, to: "\(name)/Contents/Info.plist")
        }
        return app
    }
}

/// Collects process output from background threads.
final class OutputCollector: @unchecked Sendable {
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

/// A free TCP port on 127.0.0.1.
func freePort() -> Int {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(fd) }
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = 0
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    _ = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    var bound = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &bound) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
    }
    return Int(UInt16(bigEndian: bound.sin_port))
}

/// Waits until `condition` is true or the time ends.
func waitFor(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        usleep(50_000)
    }
    return condition()
}
