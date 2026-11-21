import Darwin
import Foundation

/// The local Basic PAYE Tools web server and the rules for links to it.
public struct LocalServer: Equatable, Sendable {
    public let port: Int

    public init(port: Int) { self.port = port }

    public var baseURL: URL { URL(string: "http://127.0.0.1:\(port)/")! }

    /// True for pages of this server.
    public func isLocal(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), ["127.0.0.1", "localhost"].contains(host) else { return false }
        return (url.port ?? 80) == port
    }

    public enum Decision: Equatable, Sendable {
        case allow
        case openInBrowser
    }

    /// What to do with a navigation in the web view.
    ///
    /// Pages of the local server stay in the app. Links to GOV.UK and other
    /// sites open in the default browser. Content in a sub-frame stays in the page.
    public func decision(for url: URL, isMainFrame: Bool) -> Decision {
        let scheme = url.scheme?.lowercased() ?? ""
        if isLocal(url) || ["about", "blob", "data", "javascript"].contains(scheme) { return .allow }
        if !isMainFrame, scheme.hasPrefix("http") { return .allow }
        return .openInBrowser
    }

    /// True when something accepts TCP connections on this port.
    public func portInUse() -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    /// Synchronous GET. Returns (status, body) or nil. Do not call on the main thread.
    public func get(_ path: String, timeout: TimeInterval) -> (status: Int, body: String)? {
        guard let url = URL(string: path, relativeTo: baseURL) else { return nil }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]  // never send local traffic through a proxy
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let done = DispatchSemaphore(value: 0)
        let box = ResultBox()
        session.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse {
                box.value = (http.statusCode, String(data: data ?? Data(), encoding: .utf8) ?? "")
            }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + timeout + 1)
        return box.value
    }

    /// True if the HMRC endpoint (for example `system/hasOutstandingSubmissions`)
    /// reports data that is not sent yet.
    public func hasOutstanding(_ endpoint: String) -> Bool {
        guard let response = get(endpoint, timeout: 3), response.status == 200 else { return false }
        return Self.isOutstanding(body: response.body)
    }

    /// Reads the body of an outstanding-submissions endpoint ("0" means none).
    public static func isOutstanding(body: String) -> Bool {
        let value = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !value.isEmpty && value != "0" && value != "false"
    }
}

private final class ResultBox: @unchecked Sendable {
    var value: (status: Int, body: String)?
}
