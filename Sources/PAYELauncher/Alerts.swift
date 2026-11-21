import AppKit
import PAYELauncherCore

/// The app's dialogs, in plain words for non-technical users.
enum Alerts {
    static func notInstalled() {
        let alert = NSAlert()
        alert.messageText = "Basic PAYE Tools is not installed"
        alert.informativeText = """
        PAYE Launcher opens the HMRC Basic PAYE Tools that is installed on this Mac. \
        Download and install Basic PAYE Tools from GOV.UK, then open PAYE Launcher again.
        """
        alert.addButton(withTitle: "Open GOV.UK")
        alert.addButton(withTitle: "Quit")
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(BPTInstallation.downloadPage) }
    }

    static func rosettaMissing(canUseNative: Bool, completion: (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Rosetta is not installed"
        alert.informativeText = """
        HMRC's own server is an Intel program. On this Mac it needs Rosetta 2. \
        To install Rosetta, open Terminal and type: softwareupdate --install-rosetta
        """
        if canUseNative { alert.addButton(withTitle: "Use the Apple Silicon Runtime") }
        alert.addButton(withTitle: "Quit")
        completion(canUseNative && alert.runModal() == .alertFirstButtonReturn)
    }

    enum PortBusyChoice { case retry, useRunning, quit }

    static func portBusy(port: Int) -> PortBusyChoice {
        let alert = NSAlert()
        alert.messageText = "Basic PAYE Tools is already running"
        alert.informativeText = """
        Another program uses port \(port). This is usually another copy of Basic PAYE Tools, \
        for example one that you started in Terminal.

        Close it and click Try Again, or use the running copy. If you use the running copy, \
        PAYE Launcher does not stop it or make a backup when you quit.
        """
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Use the Running Copy")
        alert.addButton(withTitle: "Quit")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .retry
        case .alertSecondButtonReturn: return .useRunning
        default: return .quit
        }
    }

    enum StartupChoice { case retry, useHMRCServer, showLog, quit }

    static func startupFailed(_ message: String, offerHMRCServer: Bool) -> StartupChoice {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Basic PAYE Tools could not start"
        var text = message
        if offerHMRCServer {
            text += "\n\nYou can try HMRC's own server instead of the Apple Silicon runtime. It is slower and needs Rosetta 2."
        }
        alert.informativeText = text + "\n\nThe log file has more information."
        alert.addButton(withTitle: "Try Again")
        if offerHMRCServer { alert.addButton(withTitle: "Use HMRC's Server") }
        alert.addButton(withTitle: "Show Log")
        alert.addButton(withTitle: "Quit")
        let response = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let choices: [StartupChoice] = offerHMRCServer ? [.retry, .useHMRCServer, .showLog, .quit] : [.retry, .showLog, .quit]
        return choices.indices.contains(response) ? choices[response] : .quit
    }

    static func confirmQuitWithOutstanding(pct: Bool) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        if pct {
            alert.messageText = "PCT - Are you sure you wish to exit?"
            alert.informativeText = "There is data that has not been submitted. If you close now, this data will be lost."
        } else {
            alert.messageText = "Outstanding submissions"
            alert.informativeText = """
            There is submission data which has not yet been sent to HMRC. To send it, click Cancel and go to \
            the Employer menu. Select 'View outstanding submissions', then 'Send all outstanding submissions', \
            and follow the instructions.
            """
        }
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: pct ? "Close PCT" : "Close BPT-RTI")
        return alert.runModal() == .alertSecondButtonReturn
    }

    static func confirmRestartForRuntime() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Restart Basic PAYE Tools now?"
        alert.informativeText = "The new setting takes effect when Basic PAYE Tools starts again."
        alert.addButton(withTitle: "Restart Now")
        alert.addButton(withTitle: "Later")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
