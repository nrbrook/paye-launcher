import AppKit
import PAYELauncherCore
import WebKit

/// A window with a web view that shows the local Basic PAYE Tools pages.
final class BrowserWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate,
    WKUIDelegate, WKDownloadDelegate, NSMenuItemValidation {
    private static var popups: [BrowserWindowController] = []

    let webView: WKWebView
    let isMain: Bool
    private unowned let app: AppDelegate
    private let overlay = NSView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private var titleObservation: NSKeyValueObservation?
    private var openWhenDone: [ObjectIdentifier: URL] = [:]

    private var local: LocalServer { app.server?.local ?? LocalServer(port: ShellSettings.defaultPort) }

    init(configuration: WKWebViewConfiguration, isMain: Bool, app: AppDelegate) {
        self.isMain = isMain
        self.app = app
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 860), configuration: configuration)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = AppInfo.windowTitle
        window.minSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.pageZoom = app.preferences.pageZoom
        window.contentView = makeContent()

        if isMain {
            if !window.setFrameUsingName("MainWindow") { window.center() }
            window.setFrameAutosaveName("MainWindow")
        } else {
            overlay.isHidden = true
            if let main = app.mainWindow?.window {
                window.setFrame(main.frame, display: false)
                window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: main.frame.minX, y: main.frame.maxY)))
            } else {
                window.center()
            }
        }

        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] view, _ in
            let title = view.title ?? ""
            self?.window?.title = title.isEmpty ? AppInfo.windowTitle : title
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    static func closePopups() { popups.forEach { $0.close() } }

    private func makeContent() -> NSView {
        let content = NSView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(webView)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor(srgbRed: 0, green: 0x86 / 255.0, blue: 0x70 / 255.0, alpha: 1).cgColor
        content.addSubview(overlay)

        spinner.style = .spinning
        spinner.appearance = NSAppearance(named: .darkAqua)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = NSTextField(labelWithString: AppInfo.windowTitle)
        titleLabel.textColor = .white
        titleLabel.font = .boldSystemFont(ofSize: 26)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        [titleLabel, spinner, statusLabel].forEach(overlay.addSubview)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.topAnchor.constraint(equalTo: content.topAnchor),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: content.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: spinner.topAnchor, constant: -24),
            spinner.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            statusLabel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 18),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: overlay.widthAnchor, constant: -40),
        ])
        return content
    }

    // MARK: Status overlay

    func showStatus(_ text: String) {
        statusLabel.stringValue = text
        overlay.isHidden = false
        spinner.startAnimation(nil)
    }

    func hideStatus() {
        overlay.isHidden = true
        spinner.stopAnimation(nil)
        window?.makeFirstResponder(webView)
    }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }

    private func openInBrowser(_ url: URL) {
        app.log("Opening in the default browser: \(url.absoluteString)")
        NSWorkspace.shared.open(url)
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isMain else { return true }
        NSApp.terminate(nil)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard !isMain else { return }
        webView.stopLoading()
        Self.popups.removeAll { $0 === self }
    }

    // MARK: WKNavigationDelegate

    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if action.shouldPerformDownload { decisionHandler(.download); return }
        switch local.decision(for: url, isMainFrame: action.targetFrame?.isMainFrame ?? true) {
        case .allow:
            decisionHandler(.allow)
        case .openInBrowser:
            openInBrowser(url)
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        if let http = response.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().contains("attachment") {
            decisionHandler(.download)
            return
        }
        if response.isForMainFrame, response.response.mimeType?.lowercased() == "application/pdf" {
            decisionHandler(.download)
            return
        }
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if isMain { hideStatus() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadError(error)
    }

    private func handleLoadError(_ error: Error) {
        let nsError = error as NSError
        // Cancelled loads and loads that became downloads are not errors.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && [102, 204].contains(nsError.code) { return }
        app.log("Page load error: \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)")
        guard isMain, !app.terminating, let window, app.server?.isRunning == true || app.server?.adopted == true else { return }
        let alert = NSAlert()
        alert.messageText = "The page could not be shown"
        alert.informativeText = nsError.localizedDescription
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Go to Home Page")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.webView.reload() } else { self?.goHome(nil) }
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        app.log("The web content process stopped; reloading")
        webView.reload()
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: WKDownloadDelegate

    func download(
        _ download: WKDownload, decideDestinationUsing response: URLResponse,
        suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void
    ) {
        let downloads = app.paths.downloads
        let isPDF = response.mimeType?.lowercased() == "application/pdf" || suggestedFilename.lowercased().hasSuffix(".pdf")
        if isPDF {
            // Printable forms and reports go to Downloads and open in the PDF viewer.
            let name = suggestedFilename.lowercased().hasSuffix(".pdf") ? suggestedFilename : suggestedFilename + ".pdf"
            let destination = FileNaming.uniqueURL(in: downloads, name: name) { FileManager.default.fileExists(atPath: $0.path) }
            openWhenDone[ObjectIdentifier(download)] = destination
            app.log("Saving PDF to \(destination.path)")
            completionHandler(destination)
            return
        }
        guard let window else { completionHandler(nil); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = FileNaming.sanitised(suggestedFilename)
        panel.directoryURL = downloads
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let url = panel.url else { completionHandler(nil); return }
            try? FileManager.default.removeItem(at: url)  // the panel already asked to replace it
            self?.app.log("Saving a download to \(url.path)")
            completionHandler(url)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let url = openWhenDone.removeValue(forKey: ObjectIdentifier(download)) { NSWorkspace.shared.open(url) }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        openWhenDone.removeValue(forKey: ObjectIdentifier(download))
        app.log("Download failed: \(error.localizedDescription)")
        let alert = NSAlert(error: error)
        alert.messageText = "The download did not complete"
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    // MARK: WKUIDelegate

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = action.request.url, let scheme = url.scheme?.lowercased(),
           scheme.hasPrefix("http") || scheme == "mailto", !local.isLocal(url) {
            openInBrowser(url)
            return nil
        }
        let popup = BrowserWindowController(configuration: configuration, isMain: false, app: app)
        Self.popups.append(popup)
        popup.showWindow(nil)
        return popup.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        if !isMain { window?.close() }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void
    ) {
        guard let window else { completionHandler(); return }
        let alert = NSAlert()
        alert.messageText = AppInfo.windowTitle
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void
    ) {
        guard let window else { completionHandler(false); return }
        let alert = NSAlert()
        alert.messageText = AppInfo.windowTitle
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void
    ) {
        guard let window else { completionHandler(nil); return }
        let alert = NSAlert()
        alert.messageText = AppInfo.windowTitle
        alert.informativeText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    func webView(
        _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void
    ) {
        guard let window else { completionHandler(nil); return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) }
    }

    // MARK: Menu actions

    @objc func printPage(_ sender: Any?) {
        guard let window else { return }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.topMargin = 28
        info.bottomMargin = 28
        info.leftMargin = 28
        info.rightMargin = 28
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    @objc func goHome(_ sender: Any?) { load(local.baseURL) }
    @objc func pageBack(_ sender: Any?) { webView.goBack() }
    @objc func pageForward(_ sender: Any?) { webView.goForward() }
    @objc func pageReload(_ sender: Any?) { webView.reload() }
    @objc func zoomInPage(_ sender: Any?) { setZoom(webView.pageZoom + 0.1) }
    @objc func zoomOutPage(_ sender: Any?) { setZoom(webView.pageZoom - 0.1) }
    @objc func actualSizePage(_ sender: Any?) { setZoom(1.0) }

    private func setZoom(_ value: CGFloat) {
        app.preferences.pageZoom = Double(value)
        let zoom = CGFloat(app.preferences.pageZoom)
        (Self.popups + [app.mainWindow].compactMap { $0 }).forEach { $0.webView.pageZoom = zoom }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(pageBack(_:)): return webView.canGoBack
        case #selector(pageForward(_:)): return webView.canGoForward
        case #selector(printPage(_:)), #selector(pageReload(_:)), #selector(goHome(_:)): return overlay.isHidden
        default: return true
        }
    }
}
