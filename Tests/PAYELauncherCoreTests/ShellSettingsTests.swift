import Foundation
@testable import PAYELauncherCore
import Testing

struct ShellSettingsTests {
    @Test func readsPortFromGeneralSection() {
        #expect(ShellSettings.port(fromINI: "[General]\nmode=assistive\nport=47000\n") == 47000)
    }

    @Test func acceptsAnyKeyThatContainsPort() {
        #expect(ShellSettings.port(fromINI: "[Network]\nserverPort = 46800") == 46800)
    }

    @Test func ignoresCommentsAndBadValues() {
        let text = """
        ; port=40000
        # port=40001
        port=abc
        port=80
        port=70000
        port=46900
        """
        #expect(ShellSettings.port(fromINI: text) == 46900)
    }

    @Test func returnsNilWhenThereIsNoPort() {
        #expect(ShellSettings.port(fromINI: "[General]\nmode=assistive\n") == nil)
        #expect(ShellSettings.port(fromINI: "") == nil)
    }

    @Test func usesDefaultWhenFileIsMissing() {
        let missing = URL(fileURLWithPath: "/nonexistent/bptshell-settings.ini")
        #expect(ShellSettings.port(at: missing) == ShellSettings.defaultPort)
    }

    @Test func readsFile() {
        let dir = TemporaryDirectory()
        let file = dir.write("[General]\nport=46750\n", to: "bptshell-settings.ini")
        #expect(ShellSettings.port(at: file) == 46750)
    }
}
