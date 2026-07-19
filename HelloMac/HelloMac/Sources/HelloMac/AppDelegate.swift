import AppKit
import Carbon

// Διαχειριστής της παγκόσμιας συντόμευσης (Global HotKey)
class HotKeyManager {
    static let shared = HotKeyManager()
    
    func register() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(1234)
        hotKeyID.id = 1
        
        // Ctrl + Option + Cmd + H  (kVK_ANSI_H = 4)
        let modifiers = UInt32(cmdKey | optionKey | controlKey)
        let keyCode = UInt32(4) 
        
        var hotKeyRef: EventHotKeyRef?
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handler: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                if let del = NSApp.delegate as? AppDelegate {
                    del.mainWindowController?.showWindow(nil)
                    del.mainWindowController?.window?.makeKeyAndOrderFront(nil)
                }
            }
            return noErr
        }
        
        // Χρήση της πραγματικής συνάρτησης αντί του macro
        var handlerRef: EventHandlerRef? = nil
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &handlerRef)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindowController: MainWindowController?
    var settingsWindowController: SettingsWindowController?
    var facetimeTimer: Timer?
    
    var progressWindow: NSWindow?
    var progressBar: NSProgressIndicator?
    var progressLabel: NSTextField?
    var downloadObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenuBar()
        
        HotKeyManager.shared.register() // Ενεργοποίηση της παγκόσμιας συντόμευσης
        HistoryStore.shared.purgeExpiredRecords() // Καθαρισμός παλιού ιστορικού βάσει της ρύθμισης αυτόματης διαγραφής
        
        mainWindowController = MainWindowController()
        mainWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        
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
        let isGreek = Locale.preferredLanguages.first?.hasPrefix("el") ?? true

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

        // ── Επεξεργασία (Edit) ──
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: isGreek ? "Επεξεργασία" : "Edit")
        editMenuItem.submenu = editMenu
        
        editMenu.addItem(withTitle: isGreek ? "Αποκοπή" : "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: isGreek ? "Αντιγραφή" : "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: isGreek ? "Επικόλληση" : "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: isGreek ? "Επιλογή όλων" : "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        editMenu.addItem(NSMenuItem.separator())
        
        let dictationItem = NSMenuItem(title: isGreek ? "Έναρξη υπαγόρευσης..." : "Start Dictation...", action: Selector(("startDictation:")), keyEquivalent: "")
        editMenu.addItem(dictationItem)
        
        let emojiItem = NSMenuItem(title: isGreek ? "Emoji και σύμβολα" : "Emoji & Symbols", action: #selector(NSApplication.orderFrontCharacterPalette(_:)), keyEquivalent: "e")
        emojiItem.keyEquivalentModifierMask = [.command, .control]
        editMenu.addItem(emojiItem)

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
        
        let historyItem = NSMenuItem(title: L("history"), action: #selector(menuShowHistory), keyEquivalent: "4")
        historyItem.target = self
        toolsMenu.addItem(historyItem)

        toolsMenu.addItem(NSMenuItem.separator())

        let addItem = NSMenuItem(title: L("add_contact_menu"), action: #selector(menuAddContact), keyEquivalent: "n")
        addItem.target = self
        toolsMenu.addItem(addItem)

        NSApp.mainMenu = mainMenu
    }

    /// Επιστρέφει το παράθυρο πάνω στο οποίο πρέπει να "κολλήσει" ένα sheet
    /// (About, ενημερώσεις κλπ.), ώστε να μην έρχεται πάντα μπροστά το
    /// κεντρικό παράθυρο της εφαρμογής όταν είναι ανοιχτές οι Ρυθμίσεις.
    /// Δεν βασιζόμαστε στο NSApp.keyWindow, γιατί τη στιγμή που πατιέται ένα
    /// στοιχείο του menu bar, το key window μπορεί στιγμιαία να μην είναι
    /// ακόμα σταθεροποιημένο. Αντ' αυτού προτιμάμε πάντα το παράθυρο
    /// Ρυθμίσεων αν είναι ανοιχτό/ορατό, αλλιώς το κεντρικό παράθυρο.
    private func windowForSheet() -> NSWindow? {
        if let settingsWindow = settingsWindowController?.window, settingsWindow.isVisible {
            return settingsWindow
        }
        return mainWindowController?.window
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "HelloMac"
        alert.informativeText = L("about_text")
        if let customIcon = NSImage(named: "AppIcon") { alert.icon = customIcon }
        else { alert.icon = NSApp.applicationIconImage }
        alert.addButton(withTitle: L("ok"))
        alert.addButton(withTitle: L("learn_more"))
        alert.window.appearance = NSAppearance(named: .darkAqua)

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .alertSecondButtonReturn {
                self?.showSettingsToInfo()
            }
        }

        if let appWindow = windowForSheet() {
            alert.beginSheetModal(for: appWindow, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }
    
    @objc func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.resetUpdateStatusUI()
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showSettingsToAppearance() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.resetUpdateStatusUI()
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        
        if let tabVC = settingsWindowController?.window?.contentViewController as? NSTabViewController {
            tabVC.selectedTabViewItemIndex = 1
        }
        
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Ανοίγει τις Ρυθμίσεις κατευθείαν στην καρτέλα «Πληροφορίες» —
    /// χρησιμοποιείται από το κουμπί «Δείτε περισσότερα» στο «Σχετικά».
    func showSettingsToInfo() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.resetUpdateStatusUI()
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)

        if let tabVC = settingsWindowController?.window?.contentViewController as? NSTabViewController {
            tabVC.selectedTabViewItemIndex = 3
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
    
    @objc func menuShowHistory() {
        mainWindowController?.showWindow(nil)
        mainWindowController?.showHistoryPublic()
    }

    @objc func menuAddContact() {
        mainWindowController?.showWindow(nil)
        mainWindowController?.openAddPublic()
    }
    
    // MARK: - Updater
    @objc func menuCheckUpdates() {
        checkForUpdates(userInitiated: true)
    }

    private func checkForUpdates(userInitiated: Bool) {
        checkForUpdates(userInitiated: userInitiated, completion: nil)
    }

    /// Αποτέλεσμα ελέγχου ενημέρωσης, για χρήση από τις Ρυθμίσεις (εμφάνιση inline, όχι popup).
    enum UpdateCheckResult {
        case upToDate
        case updateAvailable(latestVersion: String, downloadURL: URL)
        case error
    }

    /// Ελέγχει για ενημερώσεις. Αν δοθεί completion, ΔΕΝ εμφανίζει alerts μόνος του —
    /// περνάει το αποτέλεσμα πίσω ώστε ο καλών (π.χ. οι Ρυθμίσεις) να το εμφανίσει inline.
    private func checkForUpdates(userInitiated: Bool, completion: ((UpdateCheckResult) -> Void)?) {
        let urlString = "https://api.github.com/repos/Konstantinos2106/HelloMac/releases/latest"
        guard let url = URL(string: urlString) else { return }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if error != nil {
                    if let completion = completion {
                        completion(.error)
                    } else if userInitiated {
                        self.showUpdateAlert(title: L("update_error"), text: L("update_error_text"))
                    }
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    if let completion = completion {
                        completion(.error)
                    } else if userInitiated {
                        self.showUpdateAlert(title: L("update_error"), text: L("update_error_text"))
                    }
                    return
                }

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
                    let finalURL: URL
                    if let dmgUrl = dmgDownloadUrl, let parsed = URL(string: dmgUrl) {
                        finalURL = parsed
                    } else {
                        finalURL = URL(string: "https://github.com/Konstantinos2106/HelloMac/releases/latest")!
                    }

                    if let completion = completion {
                        completion(.updateAvailable(latestVersion: latestVersion, downloadURL: finalURL))
                    } else {
                        self.promptDownloadUpdate(latestVersion: latestVersion, downloadURL: finalURL)
                    }
                } else {
                    if let completion = completion {
                        completion(.upToDate)
                    } else if userInitiated {
                        self.showUpdateAlert(title: L("up_to_date"), text: L("up_to_date_text"))
                    }
                }
            }
        }
        task.resume()
    }

    /// Καλείται από τις Ρυθμίσεις. Δεν εμφανίζει popup: επιστρέφει το αποτέλεσμα inline.
    func checkForUpdatesFromSettings(completion: @escaping (UpdateCheckResult) -> Void) {
        checkForUpdates(userInitiated: true, completion: completion)
    }

    /// Καλείται από τις Ρυθμίσεις όταν ο χρήστης πατήσει «Εγκατάσταση».
    /// Κλείνει πρώτα το παράθυρο Ρυθμίσεων, μετά ανοίγει το μικρό παράθυρο προόδου.
    func beginUpdateFromSettings(downloadURL: URL) {
        settingsWindowController?.close()
        if downloadURL.absoluteString.hasSuffix(".dmg") {
            startAutoUpdate(from: downloadURL)
        } else {
            NSWorkspace.shared.open(downloadURL)
        }
    }

    private func promptDownloadUpdate(latestVersion: String, downloadURL: URL) {
        let alert = NSAlert()
        alert.messageText = L("update_available")
        alert.informativeText = L("update_text", latestVersion)
        alert.addButton(withTitle: L("download"))
        alert.addButton(withTitle: L("cancel_btn"))
        if let icon = NSImage(named: "AppIcon") { alert.icon = icon }

        alert.window.appearance = NSAppearance(named: .darkAqua)

        if let appWindow = windowForSheet() {
            alert.beginSheetModal(for: appWindow) { response in
                if response == .alertFirstButtonReturn {
                    if downloadURL.absoluteString.hasSuffix(".dmg") {
                        self.startAutoUpdate(from: downloadURL)
                    } else {
                        NSWorkspace.shared.open(downloadURL)
                    }
                }
            }
        } else {
            if alert.runModal() == .alertFirstButtonReturn {
                if downloadURL.absoluteString.hasSuffix(".dmg") {
                    startAutoUpdate(from: downloadURL)
                } else {
                    NSWorkspace.shared.open(downloadURL)
                }
            }
        }
    }

    private func showUpdateAlert(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: L("ok"))
        if let icon = NSImage(named: "AppIcon") { alert.icon = icon }

        alert.window.appearance = NSAppearance(named: .darkAqua)

        if let appWindow = windowForSheet() {
            alert.beginSheetModal(for: appWindow, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    private func startAutoUpdate(from url: URL) {
        let winRect = NSRect(x: 0, y: 0, width: 300, height: 120)
        let win = NSWindow(contentRect: winRect, styleMask: [.titled], backing: .buffered, defer: false)
        win.title = "HelloMac Updater"
        if let mainWindow = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.title == "HelloMac" }) {
            let x = mainWindow.frame.midX - win.frame.width / 2
            let y = mainWindow.frame.midY - win.frame.height / 2
            win.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            win.center()
        }
        win.level = .floating
        
        win.appearance = NSAppearance(named: .darkAqua)
        
        let contentView = NSView(frame: winRect)
        
        let label = NSTextField(labelWithString: L("downloading"))
        label.frame = NSRect(x: 20, y: 70, width: 260, height: 20)
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(label)
        self.progressLabel = label
        
        let spinner = NSProgressIndicator(frame: NSRect(x: 135, y: 30, width: 30, height: 30))
        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.controlSize = .regular
        contentView.addSubview(spinner)
        spinner.startAnimation(nil)
        
        win.contentView = contentView
        win.makeKeyAndOrderFront(nil)
        self.progressWindow = win
        
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
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        try? process.run()
        
        NSApp.terminate(nil)
    }

    var facetimeSuppressionCount = 0

    func suppressFaceTime() {
        facetimeTimer?.invalidate()
        facetimeSuppressionCount = 0
        
        facetimeTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            self.facetimeSuppressionCount += 1
            
            if let facetimeApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.FaceTime" }) {
                if facetimeApp.isActive {
                    facetimeApp.hide()
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            
            if self.facetimeSuppressionCount >= 200 {
                self.stopSuppressingFaceTime()
            }
        }
    }

    func stopSuppressingFaceTime() {
        facetimeTimer?.invalidate()
        facetimeTimer = nil
        facetimeSuppressionCount = 0
    }
}