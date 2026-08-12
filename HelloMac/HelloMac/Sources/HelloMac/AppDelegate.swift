import AppKit
import Carbon
import UniformTypeIdentifiers

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

        var handlerRef: EventHandlerRef? = nil
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &handlerRef)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindowController: MainWindowController?
    var appearanceObservation: NSKeyValueObservation?
    private static let baseWindowSize = NSSize(width: 335, height: 680)
    var naturalWindowSize: NSSize {
        get {
            guard let saved = UserDefaults.standard.string(forKey: "a11yNaturalWindowSize") else {
                return AppDelegate.baseWindowSize
            }
            let size = NSSizeFromString(saved)
            guard size.width > 0, size.height > 0 else { return AppDelegate.baseWindowSize }
            return size
        }
        set {
            UserDefaults.standard.set(NSStringFromSize(newValue), forKey: "a11yNaturalWindowSize")
        }
    }
    var settingsWindowController: SettingsWindowController?
    var isApplyingUIScale = false
    var facetimeTimer: Timer?
    var historyPurgeTimer: Timer?
    
    var progressWindow: NSWindow?
    var progressBar: NSProgressIndicator?
    var progressLabel: NSTextField?
    var downloadObservation: NSKeyValueObservation?
    var updateActivityScheduler: NSBackgroundActivityScheduler?
    var privacyModeMenuItem: NSMenuItem?
    var menuBarController: MenuBarController?
    private var syncContactsMenuItem: NSMenuItem?
    private var syncContactsSeparatorItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "showMenuBarIcon": true,
            "contactGroupsEnabled": true,
            "enableSpeedDial": true
        ])
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.addObserver(self, selector: #selector(updateSyncContactsMenuVisibility), name: .contactsSyncSettingsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showContactsPermissionLostPrompt), name: .contactsSyncShouldShowPermissionLostPrompt, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showInitialRemindersPermissionPrompt), name: .remindersShouldShowInitialPermissionPrompt, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showRemindersPermissionLostPrompt), name: .remindersShouldShowPermissionLostPrompt, object: nil)

        buildMenuBar()
        
        HotKeyManager.shared.register()
        HistoryStore.shared.purgeExpiredRecords()
        startHistoryPurgeTimer()

        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        
        menuBarController = MenuBarController()
        mainWindowController = MainWindowController()
        mainWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(self, selector: #selector(mainWindowWillClose), name: NSWindow.willCloseNotification, object: mainWindowController?.window)
        resetWindowToDefaultSizeOnLaunch()
        NotificationCenter.default.addObserver(self, selector: #selector(accessibilitySettingsChanged), name: .accessibilitySettingsDidChange, object: nil)
        
        checkForUpdates(userInitiated: false)

        appearanceObservation = NSApp.observe(\.effectiveAppearance) { _, _ in
            if AccessibilityManager.shared.colorAdjustmentTheme == .auto {
                NotificationCenter.default.post(name: .accessibilitySettingsDidChange, object: nil)
            }
        }
        
        setupSmartAutoUpdater()

        ContactsSyncManager.shared.resumeAutoSyncIfNeeded()
        ReminderManager.shared.resumeIfNeeded()

        announceContactsSyncFeatureIfNeeded()
    }  
    
    @objc private func accessibilitySettingsChanged() {
        applyUIScale()
    }

    private func resetWindowToDefaultSizeOnLaunch() {
        naturalWindowSize = AppDelegate.baseWindowSize
        applyUIScale()
    }

    private func applyUIScale() {
        guard let window = mainWindowController?.window else { return }
        let scale = AccessibilityManager.shared.uiScaleFactor
        let natural = naturalWindowSize

        let newWidth = (natural.width * scale).rounded()
        let newHeight = (natural.height * scale).rounded()

        var frame = window.frame

        let newSize = NSSize(width: newWidth, height: newHeight)
        guard abs(frame.size.width - newSize.width) > 0.5 || abs(frame.size.height - newSize.height) > 0.5 else {
            window.minSize = NSSize(width: 300 * scale, height: 550 * scale)
            return
        }

        let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
        frame.size = NSSize(width: newWidth, height: newHeight)
        frame.origin = NSPoint(x: topLeft.x, y: topLeft.y - newHeight)

        window.minSize = NSSize(width: 300 * scale, height: 550 * scale)

        isApplyingUIScale = true
        window.setFrame(frame, display: true, animate: false)
        isApplyingUIScale = false
    }

    @objc private func mainWindowWillClose() {
        settingsWindowController?.close()
        settingsWindowController = nil
    }  

    @objc private func updateSyncContactsMenuVisibility() {
        let enabled = ContactsSyncManager.shared.isFeatureEnabled
        syncContactsMenuItem?.isHidden = !enabled
        syncContactsSeparatorItem?.isHidden = !enabled
    }

    private func announceContactsSyncFeatureIfNeeded() {
        guard !ContactsSyncManager.shared.hasShownFeatureAnnouncement else { return }
        
        let status = ContactsSyncManager.shared.authorizationStatus
        guard status == .notDetermined else {
            ContactsSyncManager.shared.hasShownFeatureAnnouncement = true
            return
        }

        ContactsSyncManager.shared.hasShownFeatureAnnouncement = true

        let panelWidth: CGFloat = 290 
        let panelHeight: CGFloat = 190
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        AccessibilityManager.shared.applyPreferredAppearance(to: panel)

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: L("contacts_sync_announce_title"))
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.drawsBackground = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(titleLabel)

        let textLabel = NSTextField(wrappingLabelWithString: L("contacts_sync_announce_text"))
        textLabel.font = NSFont.systemFont(ofSize: 12)
        textLabel.textColor = .labelColor
        textLabel.alignment = .center
        textLabel.isEditable = false
        textLabel.isSelectable = false
        textLabel.drawsBackground = false
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(textLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -16),
            
            textLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            textLabel.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 16),
            textLabel.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -16),
            textLabel.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -16)
        ])
        
        panel.contentView = visualEffect

        if let mainWindow = mainWindowController?.window {
            let x = mainWindow.frame.midX - (panelWidth / 2)
            let y = mainWindow.frame.minY + 80 
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }
        
        AccessibilityManager.shared.applyToViewTree(visualEffect)

        panel.makeKeyAndOrderFront(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ContactsSyncManager.shared.requestAccess { [weak self] granted in
                DispatchQueue.main.async {
                    panel.close()
                    if granted {
                        ContactsSyncManager.shared.isFeatureEnabled = true
                        self?.syncWithSystemContacts()
                    } else {
                        ContactsSyncManager.shared.isFeatureEnabled = false
                    }
                }
            }
        }
    }

    private func startHistoryPurgeTimer() {
        historyPurgeTimer?.invalidate()
        historyPurgeTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            HistoryStore.shared.purgeExpiredRecords()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        settingsWindowController?.close()
        settingsWindowController = nil
        return false 
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindowController?.showWindow(nil) }
        return true
    }

    // MARK: - Menu Bar
    private func buildMenuBar() {
        let mainMenu = NSMenu()
        
        // ── Μενού HelloMac ──
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
        
        let updateItem = NSMenuItem(title: L("check_updates"), action: #selector(menuCheckUpdates), keyEquivalent: "u")
        updateItem.keyEquivalentModifierMask = [.command, .option]
        updateItem.target = self
        appMenu.addItem(updateItem)
        
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: L("exit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // ── Αρχείο (File) ──
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: L("file_menu"))
        fileMenuItem.submenu = fileMenu
        
        let importItem = NSMenuItem(title: L("import_contacts"), action: #selector(importContacts), keyEquivalent: "i")
        importItem.target = self
        fileMenu.addItem(importItem)
        
        let exportItem = NSMenuItem(title: L("export_contacts"), action: #selector(exportContacts), keyEquivalent: "e")
        exportItem.keyEquivalentModifierMask = [.command, .shift]
        exportItem.target = self
        fileMenu.addItem(exportItem)
        
        let syncSeparator = NSMenuItem.separator()
        fileMenu.addItem(syncSeparator)

        let syncContactsItem = NSMenuItem(title: L("sync_with_contacts_app"), action: #selector(syncWithSystemContacts), keyEquivalent: "r")
        syncContactsItem.keyEquivalentModifierMask = [.command, .shift]
        syncContactsItem.target = self
        fileMenu.addItem(syncContactsItem)
        self.syncContactsMenuItem = syncContactsItem
        self.syncContactsSeparatorItem = syncSeparator
        updateSyncContactsMenuVisibility()

        fileMenu.addItem(NSMenuItem.separator())
        
        let importBackupItem = NSMenuItem(title: L("import_backup"), action: #selector(importBackup), keyEquivalent: "i")
        importBackupItem.keyEquivalentModifierMask = [.command, .option] // Option + Command + I
        importBackupItem.target = self
        fileMenu.addItem(importBackupItem)
        
        let exportBackupItem = NSMenuItem(title: L("export_backup"), action: #selector(exportBackup), keyEquivalent: "e")
        exportBackupItem.keyEquivalentModifierMask = [.command, .option] // Option + Command + E
        exportBackupItem.target = self
        fileMenu.addItem(exportBackupItem)
        
        fileMenu.addItem(NSMenuItem.separator())
        
        let helpItem = NSMenuItem(title: L("help_menu"), action: #selector(showBackupHelp), keyEquivalent: "?")
        helpItem.keyEquivalentModifierMask = [.command]
        helpItem.target = self
        fileMenu.addItem(helpItem)

        // ── Επεξεργασία (Edit) ──
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: L("edit_menu"))
        editMenuItem.submenu = editMenu
        
        editMenu.addItem(withTitle: L("cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("select_all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        editMenu.addItem(NSMenuItem.separator())
        
        let dictationItem = NSMenuItem(title: L("start_dictation"), action: Selector(("startDictation:")), keyEquivalent: "")
        editMenu.addItem(dictationItem)
        
        let emojiItem = NSMenuItem(title: L("emoji_and_symbols"), action: #selector(NSApplication.orderFrontCharacterPalette(_:)), keyEquivalent: "e")
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

        toolsMenu.addItem(NSMenuItem.separator())

        let privacyItem = NSMenuItem(title: L("privacy_mode_menu"), action: #selector(togglePrivacyMode), keyEquivalent: "p")
        privacyItem.keyEquivalentModifierMask = [.command, .shift]
        privacyItem.target = self
        privacyItem.state = PrivacyMode.shared.isEnabled ? .on : .off
        toolsMenu.addItem(privacyItem)
        privacyModeMenuItem = privacyItem

        NSApp.mainMenu = mainMenu

        NotificationCenter.default.addObserver(self, selector: #selector(privacyModeDidChangeSyncMenu), name: .privacyModeDidChange, object: nil)
    }

    // MARK: - Privacy Mode
    @objc func togglePrivacyMode() {
        if PrivacyMode.shared.isEnabled {
            let alert = NSAlert()
            AccessibilityManager.shared.applyAccessibility(to: alert)
            alert.messageText = L("privacy_mode_disable_title")
            alert.informativeText = L("privacy_mode_disable_text")
            alert.addButton(withTitle: L("privacy_mode_disable_btn"))
            alert.addButton(withTitle: L("cancel_btn"))
            alert.buttons[0].hasDestructiveAction = true
            alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance

            let handle: (NSApplication.ModalResponse) -> Void = { response in
                guard response == .alertFirstButtonReturn else { return }
                PrivacyMode.shared.isEnabled = false
            }

            if let appWindow = windowForSheet() {
                alert.beginSheetModal(for: appWindow, completionHandler: handle)
            } else {
                handle(alert.runModal())
            }
        } else {
            let alert = NSAlert()
            AccessibilityManager.shared.applyAccessibility(to: alert)
            alert.messageText = L("privacy_mode_enable_title")
            alert.informativeText = L("privacy_mode_enable_text")
            alert.addButton(withTitle: L("privacy_mode_enable_btn"))
            alert.addButton(withTitle: L("cancel_btn"))
            alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance

            let handle: (NSApplication.ModalResponse) -> Void = { response in
                guard response == .alertFirstButtonReturn else { return }
                PrivacyMode.shared.isEnabled = true
            }

            if let appWindow = windowForSheet() {
                alert.beginSheetModal(for: appWindow, completionHandler: handle)
            } else {
                handle(alert.runModal())
            }
        }
    }

    @objc private func privacyModeDidChangeSyncMenu() {
        privacyModeMenuItem?.state = PrivacyMode.shared.isEnabled ? .on : .off
    }

    private func windowForSheet() -> NSWindow? {
        let window: NSWindow?
        if let settingsWindow = settingsWindowController?.window, settingsWindow.isVisible {
            window = settingsWindow
        } else {
            window = mainWindowController?.window
        }

        if let window = window {
            if !(window.isKeyWindow && window.isVisible && NSApp.isActive) {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }

        return window
    }

    @objc func showAbout() {
        let alert = NSAlert()
        AccessibilityManager.shared.applyAccessibility(to: alert)
        alert.messageText = "HelloMac"
        alert.informativeText = L("about_text")
        if let customIcon = NSImage(named: "AppIcon") { alert.icon = customIcon }
        else { alert.icon = NSApp.applicationIconImage }
        alert.addButton(withTitle: L("ok"))
        alert.addButton(withTitle: L("learn_more"))
        alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance

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
            let appearanceTitle = L("tab_appearance")
            if let appearanceIndex = tabVC.tabViewItems.firstIndex(where: { $0.label == appearanceTitle }) {
                tabVC.selectedTabViewItemIndex = appearanceIndex
            }
        }
        
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettingsToInfo() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.resetUpdateStatusUI()
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        settingsWindowController?.showInfoCategory()

        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettingsToGroups() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.resetUpdateStatusUI()
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        settingsWindowController?.showGroupsCategory()

        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettingsToSpeedDial() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.resetUpdateStatusUI()
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        settingsWindowController?.showSpeedDialCategory()

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

    enum UpdateCheckResult {
        case upToDate
        case updateAvailable(latestVersion: String, downloadURL: URL)
        case error
    }

    private func checkForUpdates(userInitiated: Bool, completion: ((UpdateCheckResult) -> Void)?) {
        let urlString = "https://api.github.com/repos/Konstantinos2106/HelloMac/releases/latest"
        guard let url = URL(string: urlString) else {
            completion?(.error)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
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

    func checkForUpdatesFromSettings(completion: @escaping (UpdateCheckResult) -> Void) {
        checkForUpdates(userInitiated: true, completion: completion)
    }

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
        AccessibilityManager.shared.applyAccessibility(to: alert)
        alert.messageText = L("update_available")
        alert.informativeText = L("update_text", latestVersion)
        alert.addButton(withTitle: L("download"))
        alert.addButton(withTitle: L("cancel_btn"))
        if let icon = NSImage(named: "AppIcon") { alert.icon = icon }

        alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance

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
        AccessibilityManager.shared.applyAccessibility(to: alert)
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: L("ok"))
        if let icon = NSImage(named: "AppIcon") { alert.icon = icon }

        alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance

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
        self.progressBar = spinner
        
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

        # Mount the update image; abort without touching the installed app
        # if this fails, so a bad/corrupted download can never leave the
        # user with no app at all.
        if ! hdiutil attach "\(dmgPath)" -nobrowse -mountpoint /Volumes/HelloMacUpdate; then
            open "/Applications/HelloMac.app"
            rm "$0"
            exit 1
        fi

        # Make sure the new app bundle is actually present before removing
        # the old one.
        if [ ! -d "/Volumes/HelloMacUpdate/HelloMac.app" ]; then
            hdiutil detach /Volumes/HelloMacUpdate -force
            open "/Applications/HelloMac.app"
            rm "$0"
            exit 1
        fi

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
    
    // MARK: - Import / Export Contacts
    @objc func exportContacts() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "HelloMac_Contacts.json"
        
        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .OK, let url = savePanel.url {
                let contacts = ContactStore.shared.contacts
                if let data = try? JSONEncoder().encode(contacts) {
                    try? data.write(to: url)
                    self?.showUpdateAlert(title: L("export_success_title"), text: L("export_success_text"))
                }
            }
        }
        
        if let appWindow = windowForSheet() {
            savePanel.beginSheetModal(for: appWindow, completionHandler: handleResponse)
        } else {
            handleResponse(savePanel.runModal())
        }
    }
    
    @objc func importContacts() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        
        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .OK, let url = openPanel.url {
                if let data = try? Data(contentsOf: url),
                   let imported = try? JSONDecoder().decode([Contact].self, from: data) {
                    
                    var current = ContactStore.shared.contacts
                    var addedCount = 0
                    
                    // Αποφυγή διπλότυπων
                    for newContact in imported {
                        if !current.contains(where: { $0.id == newContact.id || $0.phone.sanitizedForCall == newContact.phone.sanitizedForCall }) {
                            current.append(newContact)
                            addedCount += 1
                        }
                    }
                    
                    ContactStore.shared.contacts = current
                    NotificationCenter.default.post(name: .contactsDidChange, object: nil) 
                    self?.showUpdateAlert(title: L("import_success_title"), text: String(format: L("import_success_text"), addedCount))
                } else {
                    self?.showUpdateAlert(title: L("import_error_title"), text: L("import_error_text"))
                }
            }
        }
        
        if let appWindow = windowForSheet() {
            openPanel.beginSheetModal(for: appWindow, completionHandler: handleResponse)
        } else {
            handleResponse(openPanel.runModal())
        }
    }

    @objc private func showContactsPermissionLostPrompt() {
        let alert = NSAlert()
        AccessibilityManager.shared.applyAccessibility(to: alert)
        alert.alertStyle = .warning
        alert.messageText = L("contacts_sync_permission_lost_title")
        alert.informativeText = L("contacts_sync_permission_lost_text")
        alert.addButton(withTitle: L("contacts_sync_open_settings_btn"))
        alert.addButton(withTitle: L("cancel_btn"))
        if let icon = NSImage(named: "AppIcon") { alert.icon = icon }
        alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance

        let handle: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                ContactsSyncManager.shared.openSystemPrivacySettings()
            }
        }

        if let appWindow = windowForSheet() {
            alert.beginSheetModal(for: appWindow, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    @objc private func showInitialRemindersPermissionPrompt() {
        let alert = NSAlert()
        AccessibilityManager.shared.applyAccessibility(to: alert)
        alert.messageText = L("reminders_initial_prompt_title")
        alert.informativeText = L("reminders_initial_prompt_text")
        alert.addButton(withTitle: L("contacts_sync_allow_btn"))
        alert.addButton(withTitle: L("cancel_btn"))
        if let icon = NSImage(named: "AppIcon") { alert.icon = icon }
        alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance

        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            ReminderManager.shared.requestAuthorization()
        }

        if let appWindow = windowForSheet() {
            alert.beginSheetModal(for: appWindow, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    @objc private func showRemindersPermissionLostPrompt() {
        let alert = NSAlert()
        AccessibilityManager.shared.applyAccessibility(to: alert)
        alert.alertStyle = .warning
        alert.messageText = L("reminders_permission_lost_title")
        alert.informativeText = L("reminders_permission_lost_text")
        alert.addButton(withTitle: L("contacts_sync_open_settings_btn"))
        alert.addButton(withTitle: L("cancel_btn"))
        if let icon = NSImage(named: "AppIcon") { alert.icon = icon }
        alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance

        let handle: (NSApplication.ModalResponse) -> Void = { response in
            if response == .alertFirstButtonReturn {
                ReminderManager.shared.openSystemNotificationSettings()
            }
        }

        if let appWindow = windowForSheet() {
            alert.beginSheetModal(for: appWindow, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    @objc func syncWithSystemContacts() {
        syncWithSystemContactsAsync(completion: nil)
    }

    func syncWithSystemContactsAsync(completion: (() -> Void)?) {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            completion?()
            return
        }

        let status = ContactsSyncManager.shared.authorizationStatus

        switch status {
        case .denied, .restricted:
            ContactsSyncManager.shared.isFeatureEnabled = false
            let alert = NSAlert()
            AccessibilityManager.shared.applyAccessibility(to: alert)
            alert.messageText = L("contacts_sync_denied_title")
            alert.informativeText = L("contacts_sync_denied_text")
            alert.addButton(withTitle: L("contacts_sync_open_settings_btn"))
            alert.addButton(withTitle: L("cancel_btn"))

            let handle: (NSApplication.ModalResponse) -> Void = { response in
                if response == .alertFirstButtonReturn {
                    ContactsSyncManager.shared.openSystemPrivacySettings()
                }
            }

            if let appWindow = windowForSheet() {
                alert.beginSheetModal(for: appWindow) { response in
                    handle(response)
                    completion?()
                }
            } else {
                handle(alert.runModal())
                completion?()
            }

        case .notDetermined:
            ContactsSyncManager.shared.requestAccess { [weak self] granted in
                guard granted else {
                    ContactsSyncManager.shared.isFeatureEnabled = false
                    completion?()
                    return
                }
                ContactsSyncManager.shared.isFeatureEnabled = true
                self?.performContactsSync(completion: completion)
            }

        case .authorized:
            ContactsSyncManager.shared.isFeatureEnabled = true
            performContactsSync(completion: completion)

        @unknown default:
            performContactsSync(completion: completion)
        }
    }

    private func performContactsSync(completion: (() -> Void)? = nil) {
        ContactsSyncManager.shared.syncNow { [weak self] result in
            self?.updateSyncContactsMenuVisibility()
            switch result {
            case .success(let syncResult):
                let text = String(format: L("contacts_sync_success_text"), syncResult.added, syncResult.updated)
                completion?()
                self?.mainWindowController?.showToast(message: text)
            case .failure:
                completion?()
                self?.mainWindowController?.showToast(message: L("contacts_sync_error_text"))
            }
        }
    }
    
    // MARK: - Import / Export Full Backup (with Photos)
    @objc func exportBackup() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        let savePanel = NSSavePanel()
        savePanel.prompt = L("save_btn") 
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        savePanel.nameFieldStringValue = "HelloMac_Backup_\(dateFormatter.string(from: Date()))"
        
        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .OK, let backupURL = savePanel.url {
                let fm = FileManager.default
                
                do {
                    try fm.createDirectory(at: backupURL, withIntermediateDirectories: true)
                    
                    // 1. Εξαγωγή JSON
                    let contacts = ContactStore.shared.contacts
                    if let data = try? JSONEncoder().encode(contacts) {
                        let jsonURL = backupURL.appendingPathComponent("contacts.json")
                        try data.write(to: jsonURL)
                    }
                    
                    // 2. Εξαγωγή Φωτογραφιών
                    let imagesSourceURL = ContactImageStore.directoryURL
                    let imagesDestURL = backupURL.appendingPathComponent("Images")
                    
                    if fm.fileExists(atPath: imagesSourceURL.path) {
                        try fm.copyItem(at: imagesSourceURL, to: imagesDestURL)
                    } else {
                        try fm.createDirectory(at: imagesDestURL, withIntermediateDirectories: true)
                    }
                    
                    self?.showUpdateAlert(title: L("export_success_title"), text: L("export_success_text"))
                } catch {
                    self?.showUpdateAlert(title: L("import_error_title"), text: error.localizedDescription)
                }
            }
        }
        
        if let appWindow = windowForSheet() {
            savePanel.beginSheetModal(for: appWindow, completionHandler: handleResponse)
        } else {
            handleResponse(savePanel.runModal())
        }
    }
    
    @objc func importBackup() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.prompt = L("select_folder")
        
        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .OK, let url = openPanel.url {
                let jsonURL = url.appendingPathComponent("contacts.json")
                let fm = FileManager.default
                
                if fm.fileExists(atPath: jsonURL.path),
                   let data = try? Data(contentsOf: jsonURL),
                   let imported = try? JSONDecoder().decode([Contact].self, from: data) {
                    
                    // 1. Εισαγωγή Επαφών
                    var current = ContactStore.shared.contacts
                    var addedCount = 0
                    
                    for newContact in imported {
                        if !current.contains(where: { $0.id == newContact.id || $0.phone.sanitizedForCall == newContact.phone.sanitizedForCall }) {
                            current.append(newContact)
                            addedCount += 1
                        }
                    }
                    ContactStore.shared.contacts = current
                    
                    // 2. Εισαγωγή Φωτογραφιών
                    let imagesSourceURL = url.appendingPathComponent("Images")
                    let imagesDestURL = ContactImageStore.directoryURL
                    
                    if fm.fileExists(atPath: imagesSourceURL.path) {
                        if let imageFiles = try? fm.contentsOfDirectory(atPath: imagesSourceURL.path) {
                            for file in imageFiles {
                                let srcURL = imagesSourceURL.appendingPathComponent(file)
                                let dstURL = imagesDestURL.appendingPathComponent(file)
                                if !fm.fileExists(atPath: dstURL.path) {
                                    try? fm.copyItem(at: srcURL, to: dstURL)
                                }
                            }
                        }
                    }
                    
                    NotificationCenter.default.post(name: .contactsDidChange, object: nil)
                    self?.showUpdateAlert(title: L("import_success_title"), text: String(format: L("import_success_text"), addedCount))
                } else {
                    self?.showUpdateAlert(title: L("import_error_title"), text: L("import_error_text"))
                }
            }
        }
        
        if let appWindow = windowForSheet() {
            openPanel.beginSheetModal(for: appWindow, completionHandler: handleResponse)
        } else {
            handleResponse(openPanel.runModal())
        }
    }
    
    // MARK: - Backup Help Alert
    @objc func showBackupHelp() {
        let alert = NSAlert()
        AccessibilityManager.shared.applyAccessibility(to: alert)
        alert.messageText = L("backup_help_title")
        alert.informativeText = L("backup_help_text")
        alert.addButton(withTitle: L("ok"))
        alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance
        
        if let appWindow = windowForSheet() {
            alert.beginSheetModal(for: appWindow, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }
    
    // MARK: - System Service ("Κλήση με το HelloMac")

    private static let minPhoneDigits = 7

    private func looksLikePhoneNumber(_ text: String) -> Bool {
        let digitCount = text.filter { $0.isNumber }.count
        guard digitCount >= AppDelegate.minPhoneDigits else { return false }
        let allowedExtras = CharacterSet(charactersIn: "+()-. \n\t")
        let disallowed = text.unicodeScalars.contains { scalar in
            !CharacterSet.decimalDigits.contains(scalar) && !allowedExtras.contains(scalar)
        }
        return !disallowed
    }

    @objc func callWithHelloMac(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pboard.string(forType: .string), looksLikePhoneNumber(text) else {
            error.pointee = L("contacts_sync_error_text") as NSString
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        mainWindowController?.showWindow(nil)
        mainWindowController?.makeCall(to: text)
    }

    // MARK: - Smart Auto Updater
    func setupSmartAutoUpdater() {
        let activity = NSBackgroundActivityScheduler(identifier: "com.hellomac.backgroundUpdateCheck")
        
        activity.repeats = true
        activity.interval = 24 * 60 * 60 
        activity.tolerance = 2 * 60 * 60 
        activity.qualityOfService = .background
        
        activity.schedule { [weak self] (completion: @escaping NSBackgroundActivityScheduler.CompletionHandler) in
            self?.performSilentUpdateCheck()
            completion(.finished)
        }
        
        self.updateActivityScheduler = activity
    }
    
    func performSilentUpdateCheck() {
        checkForUpdates(userInitiated: false)
    }
}