import AppKit
import PAYELauncherCore

/// The app's dialogs, in plain words for non-technical users.
enum Alerts {
    enum InstallChoice { case install, openGovUK, quit }

    static func offerInstall() -> InstallChoice {
        let alert = NSAlert()
        alert.messageText = "Basic PAYE Tools is not installed"
        alert.informativeText = """
        PAYE Launcher opens HMRC's Basic PAYE Tools, which is free from GOV.UK.

        PAYE Launcher can download it from GOV.UK now, check that it is HMRC's signed installer, \
        and install it. You may need to enter your Mac password.
        """
        alert.addButton(withTitle: "Download and Install")
        alert.addButton(withTitle: "Open GOV.UK")
        alert.addButton(withTitle: "Quit")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .install
        case .alertSecondButtonReturn: return .openGovUK
        default: return .quit
        }
    }

    enum InstallFailedChoice { case retry, openGovUK, quit }

    static func installFailed(_ message: String) -> InstallFailedChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Basic PAYE Tools was not installed"
        alert.informativeText = message
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Open GOV.UK")
        alert.addButton(withTitle: "Quit")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .retry
        case .alertSecondButtonReturn: return .openGovUK
        default: return .quit
        }
    }

    static func confirmUnknownPublisher(signer: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Install from this publisher?"
        alert.informativeText = """
        The installer from GOV.UK is signed and notarised for Apple, but by "\(signer)". \
        This is not the publisher that PAYE Launcher knows for Basic PAYE Tools. HMRC may have changed it.

        Install only if you trust this publisher. If you are not sure, click Cancel and install from GOV.UK yourself.
        """
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Install")
        return alert.runModal() == .alertSecondButtonReturn
    }

    static func rosettaMissing(canUseNative: Bool, completion: (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Rosetta is not installed"
        alert.informativeText = """
        HMRC's own server is an Intel program. On this Mac it needs Rosetta 2. \
        To install Rosetta, open Terminal and type: softwareupdate --install-rosetta
        """
        if canUseNative { alert.addButton(withTitle: "Use the Built-in Runtime") }
        alert.addButton(withTitle: "Quit")
        let response = alert.runModal()
        completion(canUseNative && response == .alertFirstButtonReturn)
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
            text += "\n\nYou can try HMRC's own server instead of the built-in runtime. On Apple Silicon it needs Rosetta 2."
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
