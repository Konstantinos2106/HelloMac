import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindowController: MainWindowController?
    var settingsWindowController: SettingsWindowController?
    var facetimeTimer: Timer?
    
    // Μεταβλητές για την αυτόματη λήψη
    var progressWindow: NSWindow?
    var progressBar: NSProgressIndicator?
    var progressLabel: NSTextField?
    var downloadObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenuBar()
        mainWindowController = MainWindowController()
        mainWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Αυτόματος έλεγχος στο παρασκήνιο (χωρίς να ενοχλεί)
        checkForUpdates(userInitiated: false)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false 
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindowController?.showWindow(nil) }
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

        let aboutItem = NSMenuItem(title: L("about_menu"), action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        
        let settingsItem = NSMenuItem(title: L("settings_menu"), action: #selector(showSettings), keyEquivalent: ",")
     settingsItem.target = self
     appMenu.addItem(settingsItem)
     appMenu.addItem(NSMenuItem.separator())
        
        let updateItem = NSMenuItem(title: L("check_updates"), action: #selector(menuCheckUpdates), keyEquivalent: "")
        updateItem.target = self
        appMenu.addItem(updateItem)
        
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: L("exit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // ── Εργαλεία ──
        let toolsMenuItem = NSMenuItem()
        mainMenu.addItem(toolsMenuItem)
        let toolsMenu = NSMenu(title: L("tools"))
        toolsMenuItem.submenu = toolsMenu

        let contactsItem = NSMenuItem(title: L("contacts"), action: #selector(menuShowContacts), keyEquivalent: "1")
        contactsItem.target = self
        toolsMenu.addItem(contactsItem)

        let dialerItem = NSMenuItem(title: L("keypad"), action: #selector(menuShowDialer), keyEquivalent: "2")
        dialerItem.target = self
        toolsMenu.addItem(dialerItem)

        let favoritesItem = NSMenuItem(title: L("show_favorites_menu"), action: #selector(menuShowFavorites), keyEquivalent: "3")
        favoritesItem.target = self
        toolsMenu.addItem(favoritesItem)

        toolsMenu.addItem(NSMenuItem.separator())

        let addItem = NSMenuItem(title: L("add_contact_menu"), action: #selector(menuAddContact), keyEquivalent: "n")
        addItem.target = self
        toolsMenu.addItem(addItem)

        let removeItem = NSMenuItem(title: L("remove_contact_menu"), action: #selector(menuRemoveContact), keyEquivalent: "d")
        removeItem.target = self
        toolsMenu.addItem(removeItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "HelloMac"
        alert.informativeText = L("about_text")
        if let customIcon = NSImage(named: "AppIcon") { alert.icon = customIcon }
        else { alert.icon = NSApp.applicationIconImage }
        alert.addButton(withTitle: L("ok"))
        alert.runModal()
    }
    
    @objc func showSettings() {
     if settingsWindowController == nil {
         settingsWindowController = SettingsWindowController()
     }
     settingsWindowController?.showWindow(nil)
     settingsWindowController?.window?.makeKeyAndOrderFront(nil)
     NSApp.activate(ignoringOtherApps: true)
 }
 @objc func showSettingsToAppearance() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        
        // Μαγεία: Βρίσκουμε το TabViewController και το πάμε στην 2η καρτέλα (Εμφάνιση = index 1)
        if let tabVC = settingsWindowController?.window?.contentViewController as? NSTabViewController {
            tabVC.selectedTabViewItemIndex = 1
        }
        
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func menuShowContacts() {
        mainWindowController?.showWindow(nil)
        mainWindowController?.showContactsPublic()
    }

    @objc func menuShowDialer() {
        mainWindowController?.showWindow(nil)
        mainWindowController?.showDialerPublic()
    }

    @objc func menuShowFavorites() {
        mainWindowController?.showWindow(nil)
        mainWindowController?.showFavoritesPublic()
    }

    @objc func menuAddContact() {
        mainWindowController?.showWindow(nil)
        mainWindowController?.openAddPublic()
    }

    @objc func menuRemoveContact() {
        mainWindowController?.showWindow(nil)
        mainWindowController?.openRemovePublic()
    }
    
    // MARK: - Updater (Αυτόματη Ενημέρωση)
    @objc func menuCheckUpdates() {
        checkForUpdates(userInitiated: true)
    }

    private func checkForUpdates(userInitiated: Bool) {
        let urlString = "https://api.github.com/repos/Konstantinos2106/HelloMac/releases/latest"
        guard let url = URL(string: urlString) else { return }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if error != nil {
                    if userInitiated { self.showUpdateAlert(title: L("update_error"), text: L("update_error_text")) }
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    if userInitiated { self.showUpdateAlert(title: L("update_error"), text: L("update_error_text")) }
                    return
                }

                // Εντοπισμός του DMG αρχείου από το API
                var dmgDownloadUrl: String? = nil
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                           let dlUrl = asset["browser_download_url"] as? String {
                            dmgDownloadUrl = dlUrl
                            break
                        }
                    }
                }

                let latestVersion = tagName.replacingOccurrences(of: "v", with: "")
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

                if latestVersion.compare(currentVersion, options: .numeric) == .orderedDescending {
                    if let dmgUrl = dmgDownloadUrl, let url = URL(string: dmgUrl) {
                        self.promptDownloadUpdate(latestVersion: latestVersion, downloadURL: url)
                    } else {
                        // Fallback αν δεν βρει DMG, πάει στη σελίδα
                        self.promptDownloadUpdate(latestVersion: latestVersion, downloadURL: URL(string: "https://github.com/Konstantinos2106/HelloMac/releases/latest")!)
                    }
                } else {
                    if userInitiated { self.showUpdateAlert(title: L("up_to_date"), text: L("up_to_date_text")) }
                }
            }
        }
        task.resume()
    }

    private func promptDownloadUpdate(latestVersion: String, downloadURL: URL) {
        let alert = NSAlert()
        alert.messageText = L("update_available")
        alert.informativeText = L("update_text", latestVersion)
        alert.addButton(withTitle: L("download")) // "Εγκατάσταση & Επανεκκίνηση"
        alert.addButton(withTitle: L("cancel_btn"))
        if let icon = NSImage(named: "AppIcon") { alert.icon = icon }

        if alert.runModal() == .alertFirstButtonReturn {
            if downloadURL.absoluteString.hasSuffix(".dmg") {
                startAutoUpdate(from: downloadURL)
            } else {
                NSWorkspace.shared.open(downloadURL)
            }
        }
    }

    private func showUpdateAlert(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: L("ok"))
        if let icon = NSImage(named: "AppIcon") { alert.icon = icon }
        alert.runModal()
    }

    // MARK: - Η Μαγεία της Αυτόματης Εγκατάστασης (Με Κυκλάκι Φόρτωσης)
    private func startAutoUpdate(from url: URL) {
        // 1. Δημιουργία παραθύρου προόδου
        let winRect = NSRect(x: 0, y: 0, width: 300, height: 120)
        let win = NSWindow(contentRect: winRect, styleMask: [.titled], backing: .buffered, defer: false)
        win.title = "HelloMac Updater"
        win.center()
        win.level = .floating
        
        let contentView = NSView(frame: winRect)
        
        let label = NSTextField(labelWithString: L("downloading"))
        label.frame = NSRect(x: 20, y: 70, width: 260, height: 20)
        label.alignment = .center // Κεντράρισμα κειμένου
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(label)
        self.progressLabel = label
        
        // 2. Το "Κυκλάκι" Φόρτωσης αντί για μπάρα
        // Τοποθετούμε το spinner στο κέντρο (x: 135 γιατί το πλάτος του παραθύρου είναι 300)
        let spinner = NSProgressIndicator(frame: NSRect(x: 135, y: 30, width: 30, height: 30))
        spinner.style = .spinning // Αυτό το κάνει κυκλάκι
        spinner.isIndeterminate = true
        spinner.controlSize = .regular
        contentView.addSubview(spinner)
        spinner.startAnimation(nil) // Ξεκινάει αμέσως
        
        win.contentView = contentView
        win.makeKeyAndOrderFront(nil)
        self.progressWindow = win
        
        // 3. Έναρξη λήψης του DMG
        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempLocalUrl, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if error != nil || tempLocalUrl == nil {
                    self.progressWindow?.close()
                    self.showUpdateAlert(title: L("download_error"), text: L("download_error_text"))
                    return
                }
                
                let fm = FileManager.default
                let destURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("HelloMac_Update.dmg")
                try? fm.removeItem(at: destURL)
                
                do {
                    try fm.moveItem(at: tempLocalUrl!, to: destURL)
                    self.executeInstallScript(dmgPath: destURL.path)
                } catch {
                    self.progressWindow?.close()
                    self.showUpdateAlert(title: L("download_error"), text: L("download_error_text"))
                }
            }
        }
        task.resume()
    }
    
    private func executeInstallScript(dmgPath: String) {
        progressLabel?.stringValue = L("installing")
        progressBar?.isIndeterminate = true
        progressBar?.startAnimation(nil)
        
        // Το script που θα τρέξει αφού κλείσει η εφαρμογή μας
        let scriptContent = """
        #!/bin/bash
        sleep 2
        hdiutil attach "\(dmgPath)" -nobrowse -mountpoint /Volumes/HelloMacUpdate
        rm -rf "/Applications/HelloMac.app"
        cp -R "/Volumes/HelloMacUpdate/HelloMac.app" "/Applications/"
        hdiutil detach /Volumes/HelloMacUpdate -force
        open "/Applications/HelloMac.app"
        rm "$0"
        """
        
        let scriptPath = NSTemporaryDirectory() + "hellomac_updater.sh"
        try? scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        
        // Εκτέλεση του script στο παρασκήνιο (ανεξάρτητα από εμάς)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        try? process.run()
        
        // Τερματισμός της τρέχουσας εφαρμογής για να μπορέσει το script να την αντικαταστήσει!
        NSApp.terminate(nil)
    }

    // MARK: - Έξυπνος Αλγόριθμος Κλήσης & Απόκρυψης FaceTime
    var facetimeSuppressionCount = 0

    func suppressFaceTime() {
        // Καθαρίζουμε τυχόν προηγούμενο χρονόμετρο
        facetimeTimer?.invalidate()
        facetimeSuppressionCount = 0
        
        // Ξεκινάμε τον έλεγχο κάθε 0.3 δευτερόλεπτα
        facetimeTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            self.facetimeSuppressionCount += 1
            
            // Βρίσκουμε αν το FaceTime τρέχει αυτή τη στιγμή
            if let facetimeApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.FaceTime" }) {
                
                // Αν το FaceTime προσπαθήσει να έρθει στο προσκήνιο (το μαύρο παράθυρο)
                if facetimeApp.isActive {
                    // 1. Το κρύβουμε αστραπιαία
                    facetimeApp.hide()
                    // 2. Επαναφέρουμε την εφαρμογή μας στο προσκήνιο για να μην καταλάβει τίποτα ο χρήστης
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            
            // Ο έλεγχος σταματάει αυτόματα μετά από 1 λεπτό
            if self.facetimeSuppressionCount >= 200 {
                self.stopSuppressingFaceTime()
            }
        }
    }

    func stopSuppressingFaceTime() {
        facetimeTimer?.invalidate()
        facetimeTimer = nil
        facetimeSuppressionCount = 0
    }}