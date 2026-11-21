import AppKit

enum MainMenu {
    /// Builds the menu bar. Returns the "Use Built-in Runtime" item, if shown.
    @discardableResult
    static func install(delegate: AppDelegate, showRuntimeOption: Bool) -> NSMenuItem? {
        let main = NSMenu()
        let name = AppInfo.name
        var runtimeItem: NSMenuItem?

        func add(
            _ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
            _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil
        ) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            menu.addItem(item)
            return item
        }

        let appMenu = NSMenu()
        _ = add(appMenu, "About \(name)", #selector(AppDelegate.showAbout(_:)), target: delegate)
        appMenu.addItem(.separator())
        if showRuntimeOption {
            runtimeItem = add(appMenu, "Use Built-in Runtime", #selector(AppDelegate.toggleNativeRuntime(_:)), target: delegate)
            appMenu.addItem(.separator())
        }
        _ = add(appMenu, "Show Data Folder", #selector(AppDelegate.showDataFolder(_:)), target: delegate)
        _ = add(appMenu, "Show Log File", #selector(AppDelegate.showLogs(_:)), target: delegate)
        appMenu.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu()
        NSApp.servicesMenu = services.submenu
        appMenu.addItem(services)
        appMenu.addItem(.separator())
        _ = add(appMenu, "Hide \(name)", #selector(NSApplication.hide(_:)), "h")
        _ = add(appMenu, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        _ = add(appMenu, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        appMenu.addItem(.separator())
        _ = add(appMenu, "Quit \(name)", #selector(NSApplication.terminate(_:)), "q")
        main.addItem(withTitle: name, action: nil, keyEquivalent: "").submenu = appMenu

        let fileMenu = NSMenu(title: "File")
        _ = add(fileMenu, "Close Window", #selector(NSWindow.performClose(_:)), "w")
        fileMenu.addItem(.separator())
        _ = add(fileMenu, "Print…", #selector(BrowserWindowController.printPage(_:)), "p")
        main.addItem(withTitle: "File", action: nil, keyEquivalent: "").submenu = fileMenu

        let editMenu = NSMenu(title: "Edit")
        _ = add(editMenu, "Undo", Selector(("undo:")), "z")
        _ = add(editMenu, "Redo", Selector(("redo:")), "z", [.command, .shift])
        editMenu.addItem(.separator())
        _ = add(editMenu, "Cut", #selector(NSText.cut(_:)), "x")
        _ = add(editMenu, "Copy", #selector(NSText.copy(_:)), "c")
        _ = add(editMenu, "Paste", #selector(NSText.paste(_:)), "v")
        _ = add(editMenu, "Select All", #selector(NSText.selectAll(_:)), "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = editMenu

        let viewMenu = NSMenu(title: "View")
        _ = add(viewMenu, "Back", #selector(BrowserWindowController.pageBack(_:)), "[")
        _ = add(viewMenu, "Forward", #selector(BrowserWindowController.pageForward(_:)), "]")
        _ = add(viewMenu, "Home Page", #selector(BrowserWindowController.goHome(_:)), "h", [.command, .shift])
        _ = add(viewMenu, "Reload Page", #selector(BrowserWindowController.pageReload(_:)), "r")
        viewMenu.addItem(.separator())
        _ = add(viewMenu, "Actual Size", #selector(BrowserWindowController.actualSizePage(_:)), "0")
        _ = add(viewMenu, "Zoom In", #selector(BrowserWindowController.zoomInPage(_:)), "+")
        _ = add(viewMenu, "Zoom Out", #selector(BrowserWindowController.zoomOutPage(_:)), "-")
        viewMenu.addItem(.separator())
        _ = add(viewMenu, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        main.addItem(withTitle: "View", action: nil, keyEquivalent: "").submenu = viewMenu

        let windowMenu = NSMenu(title: "Window")
        _ = add(windowMenu, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        _ = add(windowMenu, "Zoom", #selector(NSWindow.performZoom(_:)))
        windowMenu.addItem(.separator())
        _ = add(windowMenu, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: "Help")
        _ = add(helpMenu, "Basic PAYE Tools User Guide (GOV.UK)", #selector(AppDelegate.openUserGuide(_:)), target: delegate)
        _ = add(helpMenu, "Service Availability and Issues (GOV.UK)", #selector(AppDelegate.openServiceIssues(_:)), target: delegate)
        helpMenu.addItem(.separator())
        _ = add(helpMenu, "PAYE Launcher Website", #selector(AppDelegate.openProjectPage(_:)), target: delegate)
        _ = add(helpMenu, "Report a Problem with PAYE Launcher", #selector(AppDelegate.reportProblem(_:)), target: delegate)
        main.addItem(withTitle: "Help", action: nil, keyEquivalent: "").submenu = helpMenu
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = main
        return runtimeItem
    }
}
