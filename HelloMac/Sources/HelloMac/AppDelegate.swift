import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindowController: MainWindowController?
    var facetimeTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenuBar()
        mainWindowController = MainWindowController()
        mainWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - Menu Bar
    private func buildMenuBar() {
        let mainMenu = NSMenu()

        // ── HelloMac (App Menu) ──
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "HelloMac")
        appMenuItem.submenu = appMenu

        let aboutItem = NSMenuItem(title: "Σχετικά με το HelloMac", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Έξοδος", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // ── Εργαλεία ──
        let toolsMenuItem = NSMenuItem()
        mainMenu.addItem(toolsMenuItem)
        let toolsMenu = NSMenu(title: "Εργαλεία")
        toolsMenuItem.submenu = toolsMenu

        let contactsItem = NSMenuItem(title: "Επαφές", action: #selector(menuShowContacts), keyEquivalent: "1")
        contactsItem.target = self
        toolsMenu.addItem(contactsItem)

        let dialerItem = NSMenuItem(title: "Πληκτρολόγιο", action: #selector(menuShowDialer), keyEquivalent: "2")
        dialerItem.target = self
        toolsMenu.addItem(dialerItem)

        toolsMenu.addItem(NSMenuItem.separator())

        let addItem = NSMenuItem(title: "Προσθήκη Επαφής", action: #selector(menuAddContact), keyEquivalent: "n")
        addItem.target = self
        toolsMenu.addItem(addItem)

        let removeItem = NSMenuItem(title: "Διαγραφή Επαφής", action: #selector(menuRemoveContact), keyEquivalent: "d")
        removeItem.target = self
        toolsMenu.addItem(removeItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "HelloMac"
        alert.informativeText = "Έκδοση 1.0\n\nΠρογραμματιστής: Konstantinos2106\n\nΓρήγορη κλήση επαφών απευθείας από το Mac!"
        alert.icon = NSImage(systemSymbolName: "phone.fill", accessibilityDescription: nil)
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func menuShowContacts() {
        mainWindowController?.showWindow(nil)
        mainWindowController?.showFavoritesPublic()
    }

    @objc func menuShowDialer() {
        mainWindowController?.showWindow(nil)
        mainWindowController?.showDialerPublic()
    }

    @objc func menuAddContact() {
        mainWindowController?.showWindow(nil)
        mainWindowController?.openAddPublic()
    }

    @objc func menuRemoveContact() {
        mainWindowController?.showWindow(nil)
        mainWindowController?.openRemovePublic()
    }

    // MARK: - FaceTime suppression
    func suppressFaceTime() {
        facetimeTimer?.invalidate()
        facetimeTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] timer in
            for app in NSWorkspace.shared.runningApplications
                where app.bundleIdentifier == "com.apple.FaceTime" {
                app.hide()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self?.facetimeTimer?.invalidate()
                    self?.keepFaceTimeHidden()
                }
            }
        }
    }

    func keepFaceTimeHidden() {
        facetimeTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            for app in NSWorkspace.shared.runningApplications
                where app.bundleIdentifier == "com.apple.FaceTime" {
                app.hide()
            }
        }
    }

    func stopSuppressingFaceTime() {
        facetimeTimer?.invalidate()
        facetimeTimer = nil
    }
}
