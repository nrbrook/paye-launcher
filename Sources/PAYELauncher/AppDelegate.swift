import AppKit
import PAYELauncherCore
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let paths = Paths()
    let preferences = Preferences()
    lazy var logger = Logger(directory: paths.logs)
    private(set) var server: BPTServer?
    private(set) var mainWindow: BrowserWindowController?
    private(set) var terminating = false
    private var signalSources: [DispatchSourceSignal] = []
    private let printBridge = PrintBridge()
    private var runtimeMenuItem: NSMenuItem?
    private var installJob: BPTInstallJob?
    private var installTimer: Timer?

    var nativeRuntime: NativeRuntime? { NativeRuntime.bundled(inResources: Bundle.main.resourceURL) }
    var canUseNative: Bool { nativeRuntime?.supports(Runtime.machineArchitecture) ?? false }

    func log(_ message: String) { logger.write(message) }

    // MARK: Web view configuration

    func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15 PAYELauncher/\(AppInfo.version)"
        let controller = WKUserContentController()
        controller.add(WeakScriptHandler(printBridge), name: "bptPrint")
        // window.print() in the page opens the macOS print panel.
        let script = "window.print = function () { window.webkit.messageHandlers.bptPrint.postMessage(null); };"
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController = controller
        return config
    }

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("\(AppInfo.name) \(AppInfo.version) starting on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        runtimeMenuItem = MainMenu.install(delegate: self, showRuntimeOption: canUseNative)
        updateRuntimeMenuItem()
        installSignalHandlers()
        let window = BrowserWindowController(configuration: makeConfiguration(), isMain: true, app: self)
        mainWindow = window
        window.showStatus("Starting…")
        window.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        boot()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func findInstallation() -> BPTInstallation? {
        let candidates = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: BPTInstallation.bundleIdentifier)
            + BPTInstallation.defaultCandidates(home: paths.home)
        return BPTInstallation.newest(among: candidates)
    }

    private func boot() {
        guard let install = findInstallation() else {
            log("Basic PAYE Tools is not installed")
            offerInstall()
            return
        }
        let kind = Runtime.effective(preferred: preferences.runtime, machineArchitecture: Runtime.machineArchitecture, native: nativeRuntime)
        let forceArm64 = kind == .native && Runtime.isAppleSilicon && Runtime.isTranslated
        log("Using \(install.appURL.path) version \(install.version), runtime \(kind.rawValue) on \(Runtime.machineArchitecture)")

        if kind == .hmrc, Runtime.isAppleSilicon, !Runtime.rosettaInstalled() {
            Alerts.rosettaMissing(canUseNative: canUseNative) { [weak self] useNative in
                guard let self else { return }
                if useNative { self.preferences.runtime = .native; self.updateRuntimeMenuItem(); self.boot() } else { NSApp.terminate(nil) }
            }
            return
        }

        let local = LocalServer(port: ShellSettings.port(at: paths.shellSettings))
        let logger = self.logger
        let native = nativeRuntime
        let environment = ProcessInfo.processInfo.environment
        let server = BPTServer(
            install: install,
            local: local,
            kind: kind,
            pidFile: PIDFile(url: paths.pidFile),
            runner: ProcessRunner { logger.raw($0) },
            log: { logger.write($0) },
            makeCommand: {
                Runtime.command($0, kind: kind, install: install, native: native, baseEnvironment: environment, forceArm64: forceArm64)
            }
        )
        server.onUnexpectedExit = { code in
            DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.serverStopped(code) }
        }
        self.server = server

        let pidFile = PIDFile(url: paths.pidFile)
        DispatchQueue.global(qos: .userInitiated).async {
            if pidFile.stopStaleServer(isServer: { $0.hasSuffix("/rti") || $0.hasSuffix("/python2.7") }) {
                logger.write("Stopped a server that an earlier run left open")
            }
            let busy = local.portInUse()
            DispatchQueue.main.async { busy ? self.portBusy(server) : self.prepareAndStart() }
        }
    }

    // MARK: Install Basic PAYE Tools

    private func offerInstall() {
        switch Alerts.offerInstall() {
        case .install:
            startInstall()
        case .openGovUK:
            NSWorkspace.shared.open(BPTDownload.pageURL)
            waitForInstallation(message: "Install Basic PAYE Tools from GOV.UK.\nPAYE Launcher continues when it is installed.")
        case .quit:
            NSApp.terminate(nil)
        }
    }

    private func startInstall() {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("PAYE Launcher install \(UUID().uuidString)", isDirectory: true)
        let logger = self.logger
        let job = BPTInstallJob(
            workDirectory: work,
            progress: { step in DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.showInstallStep(step) } },
            log: { logger.write($0) }
        )
        installJob = job
        DispatchQueue.global(qos: .userInitiated).async {
            let result = job.prepare()
            DispatchQueue.main.async { self.continueInstall(job: job, prepared: result) }
        }
    }

    private func continueInstall(job: BPTInstallJob, prepared: Result<URL, BPTInstallError>) {
        switch prepared {
        case .success(let package):
            install(package: package, job: job, allowedTeamIDs: BPTDownload.knownTeamIDs)
        case .failure(.unknownPublisher(let signer, let package)):
            log("Unknown installer publisher: \(signer)")
            if Alerts.confirmUnknownPublisher(signer: signer),
               let team = PackageSignature.teamIdentifier(inCertificateName: signer) {
                install(package: package, job: job, allowedTeamIDs: [team])
            } else {
                job.cleanUp()
                installFailed(.untrustedPackage)
            }
        case .failure(let error):
            job.cleanUp()
            installFailed(error)
        }
    }

    private func install(package: URL, job: BPTInstallJob, allowedTeamIDs: Set<String>) {
        // HMRC's package asks Apple's Installer for an Intel Mac. Without Rosetta,
        // copy the signed app out of the package instead; the built-in runtime runs it.
        guard Runtime.isAppleSilicon, !Runtime.rosettaInstalled(), canUseNative else {
            log("Opening the installer: \(package.path)")
            NSWorkspace.shared.open(package)
            waitForInstallation(
                message: "Follow the steps in the Installer window.\nPAYE Launcher continues when Basic PAYE Tools is installed.",
                cleanUp: job
            )
            return
        }
        let destinations = [URL(fileURLWithPath: "/Applications"), paths.home.appendingPathComponent("Applications")]
        DispatchQueue.global(qos: .userInitiated).async {
            let result = job.installDirectly(package: package, allowedTeamIDs: allowedTeamIDs, destinations: destinations)
            job.cleanUp()
            DispatchQueue.main.async {
                switch result {
                case .success: self.boot()
                case .failure(let error): self.installFailed(error)
                }
            }
        }
    }

    fileprivate func showInstallStep(_ step: BPTInstallJob.Step) {
        switch step {
        case .findingDownload: mainWindow?.showStatus("Finding Basic PAYE Tools on GOV.UK…")
        case .downloading(let fraction?): mainWindow?.showStatus("Downloading Basic PAYE Tools from GOV.UK… \(Int(fraction * 100))%")
        case .downloading(nil): mainWindow?.showStatus("Downloading Basic PAYE Tools from GOV.UK…")
        case .checking: mainWindow?.showStatus("Checking the download…")
        case .installing: mainWindow?.showStatus("Installing Basic PAYE Tools…")
        }
    }

    /// Checks every 2 seconds whether Basic PAYE Tools is installed, then starts it.
    private func waitForInstallation(message: String, cleanUp job: BPTInstallJob? = nil) {
        mainWindow?.showStatus(message)
        installTimer?.invalidate()
        installTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, self.findInstallation() != nil else { return }
            timer.invalidate()
            self.installTimer = nil
            self.log("Basic PAYE Tools is now installed")
            job?.cleanUp()
            self.installJob = nil
            self.boot()
        }
    }

    private func installFailed(_ error: BPTInstallError) {
        log("Install failed: \(error)")
        installJob = nil
        switch Alerts.installFailed(error.message) {
        case .retry: startInstall()
        case .openGovUK:
            NSWorkspace.shared.open(BPTDownload.pageURL)
            waitForInstallation(message: "Install Basic PAYE Tools from GOV.UK.\nPAYE Launcher continues when it is installed.")
        case .quit: NSApp.terminate(nil)
        }
    }

    // MARK: Server start-up

    private func portBusy(_ server: BPTServer) {
        log("Port \(server.local.port) is already in use")
        switch Alerts.portBusy(port: server.local.port) {
        case .retry: boot()
        case .useRunning:
            server.adopted = true
            waitAndLoad()
        case .quit: NSApp.terminate(nil)
        }
    }

    private func prepareAndStart() {
        guard let server else { return }
        mainWindow?.showStatus("Updating the database…")
        DispatchQueue.global(qos: .userInitiated).async {
            let status = server.runCommand(["startdb"], timeout: 1800)
            guard status == 0 else {
                DispatchQueue.main.async { self.startupFailed("The database could not be prepared.") }
                return
            }
            DispatchQueue.main.async { self.mainWindow?.showStatus("Checking for updates…") }
            server.runCommand(["updatecheck"], timeout: 30)
            DispatchQueue.main.async { self.mainWindow?.showStatus("Starting…") }
            do {
                try server.startServer()
            } catch {
                DispatchQueue.main.async { self.startupFailed("The web server could not start: \(error.localizedDescription)") }
                return
            }
            DispatchQueue.main.async { self.waitAndLoad() }
        }
    }

    private func waitAndLoad() {
        guard let server else { return }
        mainWindow?.showStatus("Waiting for response from web server…")
        DispatchQueue.global(qos: .userInitiated).async {
            let ready = server.waitUntilReady(timeout: 180)
            DispatchQueue.main.async {
                if ready {
                    self.log("Web server is ready at \(server.local.baseURL.absoluteString)")
                    self.mainWindow?.load(server.local.baseURL)
                } else if server.isRunning || server.adopted {
                    self.startupFailed("The web server did not respond.")
                }
                // If the process stopped, serverStopped(_:) shows the message.
            }
        }
    }

    private func startupFailed(_ message: String) {
        log("Start-up failed: \(message)")
        let offerFallback = server?.kind == .native
        switch Alerts.startupFailed(message, offerHMRCServer: offerFallback) {
        case .retry: restartServer()
        case .useHMRCServer:
            preferences.runtime = .hmrc
            updateRuntimeMenuItem()
            restartServer()
        case .showLog:
            showLogs(nil)
            startupFailed(message)
        case .quit: NSApp.terminate(nil)
        }
    }

    func serverStopped(_ code: Int32) {
        guard !terminating else { return }
        log("The web server stopped unexpectedly (exit code \(code))")
        mainWindow?.showStatus("Basic PAYE Tools stopped.")
        startupFailed("The Basic PAYE Tools server stopped with exit code \(code).")
    }

    /// Stops the current server (if any) and starts again with the current preferences.
    private func restartServer() {
        let old = server
        server = nil
        mainWindow?.showStatus("Restarting…")
        DispatchQueue.global(qos: .userInitiated).async {
            old?.shutdown(backup: false)
            DispatchQueue.main.async { self.boot() }
        }
    }

    // MARK: Quit

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateLater }
        guard let server, server.isRunning, !server.adopted else {
            log("Quitting")
            logger.flush()
            return .terminateNow
        }
        if server.local.hasOutstanding("system/hasOutstandingSubmissions") {
            guard Alerts.confirmQuitWithOutstanding(pct: false) else { return .terminateCancel }
        } else if server.local.hasOutstanding("system/hasOutstandingSubmissionsPct") {
            guard Alerts.confirmQuitWithOutstanding(pct: true) else { return .terminateCancel }
        }
        terminating = true
        log("Quitting: stopping the server and making the automatic backup")
        BrowserWindowController.closePopups()
        mainWindow?.showStatus("Closing and making a backup…")
        let logger = self.logger
        DispatchQueue.global(qos: .userInitiated).async {
            server.shutdown()
            logger.write("Shut-down complete")
            logger.flush()
            DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGHUP, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.log("Received signal \(sig)")
                NSApp.terminate(nil)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: Menu actions

    @objc func toggleNativeRuntime(_ sender: Any?) {
        preferences.runtime = preferences.runtime == .native ? .hmrc : .native
        updateRuntimeMenuItem()
        log("Runtime preference changed to \(preferences.runtime.rawValue)")
        if Alerts.confirmRestartForRuntime() { restartServer() }
    }

    private func updateRuntimeMenuItem() {
        runtimeMenuItem?.state = preferences.runtime == .native ? .on : .off
    }

    @objc func showDataFolder(_ sender: Any?) { NSWorkspace.shared.open(paths.userData) }
    @objc func showLogs(_ sender: Any?) { NSWorkspace.shared.activateFileViewerSelecting([logger.url]) }
    @objc func openUserGuide(_ sender: Any?) { NSWorkspace.shared.open(AppInfo.userGuideURL) }
    @objc func openServiceIssues(_ sender: Any?) { NSWorkspace.shared.open(AppInfo.serviceIssuesURL) }
    @objc func openProjectPage(_ sender: Any?) { NSWorkspace.shared.open(AppInfo.projectURL) }
    @objc func reportProblem(_ sender: Any?) { NSWorkspace.shared.open(AppInfo.issuesURL) }

    @objc func showAbout(_ sender: Any?) {
        var text = "Runs the Basic PAYE Tools that you installed from GOV.UK in its own window.\n"
        text += "Not made by, connected with or endorsed by HMRC.\n"
        if let server {
            text += "\nBasic PAYE Tools \(server.install.version)\n\(server.install.appURL.path)\n"
            text += server.kind == .native ? "Runtime: built-in (\(Runtime.machineArchitecture))\n" : "Runtime: HMRC server\n"
        }
        text += "\nYour data: \(paths.userData.path)\n\nFree software under the GNU GPL version 3."
        let credits = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
        ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// `window.print()` in a page opens the macOS print panel.
final class PrintBridge: NSObject, WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        (message.webView?.window?.windowController as? BrowserWindowController)?.printPage(nil)
    }
}

/// Prevents a retain cycle between the content controller and its handler.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
