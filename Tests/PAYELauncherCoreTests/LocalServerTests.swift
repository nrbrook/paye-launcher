import Foundation
@testable import PAYELauncherCore
import Testing

struct LocalServerTests {
    let server = LocalServer(port: 46729)

    @Test func recognisesLocalPages() {
        #expect(server.isLocal(URL(string: "http://127.0.0.1:46729/pages/home/")!))
        #expect(server.isLocal(URL(string: "http://localhost:46729/")!))
        #expect(!server.isLocal(URL(string: "http://127.0.0.1:8080/")!))
        #expect(!server.isLocal(URL(string: "https://www.gov.uk/")!))
        #expect(!server.isLocal(URL(string: "http://127.0.0.1/")!))
    }

    @Test func navigationDecisions() {
        #expect(server.decision(for: URL(string: "http://127.0.0.1:46729/bptrti/")!, isMainFrame: true) == .allow)
        #expect(server.decision(for: URL(string: "https://www.gov.uk/")!, isMainFrame: true) == .openInBrowser)
        #expect(server.decision(for: URL(string: "mailto:someone@example.com")!, isMainFrame: true) == .openInBrowser)
        #expect(server.decision(for: URL(string: "https://example.com/frame")!, isMainFrame: false) == .allow)
        #expect(server.decision(for: URL(string: "about:blank")!, isMainFrame: true) == .allow)
        #expect(server.decision(for: URL(string: "data:text/plain,hi")!, isMainFrame: true) == .allow)
    }

    @Test func readsOutstandingSubmissionBodies() {
        #expect(!LocalServer.isOutstanding(body: "0"))
        #expect(!LocalServer.isOutstanding(body: " 0\n"))
        #expect(!LocalServer.isOutstanding(body: ""))
        #expect(!LocalServer.isOutstanding(body: "False"))
        #expect(LocalServer.isOutstanding(body: "1"))
        #expect(LocalServer.isOutstanding(body: "3"))
        #expect(LocalServer.isOutstanding(body: "true"))
    }

    @Test func detectsPortInUse() {
        let port = freePort()
        let local = LocalServer(port: port)
        #expect(!local.portInUse())

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        #expect(bound == 0)
        #expect(listen(fd, 1) == 0)
        #expect(local.portInUse())
    }

    @Test func getReturnsNilWhenNothingListens() {
        #expect(LocalServer(port: freePort()).get("/", timeout: 1) == nil)
    }
}
