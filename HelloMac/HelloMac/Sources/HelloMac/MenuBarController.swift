import AppKit

class MenuBarController: NSObject, NSSearchFieldDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    var menu: NSMenu!
    var searchField: NSSearchField!
    var searchMenuItem: NSMenuItem!

    var keypadMenuItem: NSMenuItem!
    var isMenuOpen: Bool = false
    var dialerMenuItem: NSMenuItem!
    var dialerView: MenuBarDialerView!
    var speedDialMenuItem: NSMenuItem!
    
    private var isRefreshingMenuItems = false
    
    override init() {
        super.init()
        setupStatusItem()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshStatusItem), name: NSNotification.Name("UpdateUIVisibility"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(contactsChanged), name: .contactsDidChange, object: nil)
    }
    
    @objc func refreshStatusItem() {
        setupStatusItem()
    }
    
    func setupStatusItem() {
        let show = UserDefaults.standard.bool(forKey: "showMenuBarIcon")
        
        if show {
            if statusItem == nil {
                statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = statusItem?.button {
                    if let customMenuIcon = NSImage(named: "menubar_icon.png") {
                        customMenuIcon.isTemplate = true 
                        customMenuIcon.size = NSSize(width: 24, height: 24)
                        button.image = customMenuIcon
                    } else {
                        button.image = NSImage(systemSymbolName: "phone.fill", accessibilityDescription: "HelloMac")
                   }  
                }
                
                menu = NSMenu()
                menu.delegate = self
                searchMenuItem = NSMenuItem()
                let headerView = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 32))
                headerView.autoresizingMask = [.width]
                searchField = NSSearchField()
                searchField.delegate = self
                searchField.placeholderString = L("search_placeholder")
                searchField.translatesAutoresizingMaskIntoConstraints = false
                headerView.addSubview(searchField)
                NSLayoutConstraint.activate([
                    searchField.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
                    searchField.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
                    searchField.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
                    searchField.heightAnchor.constraint(equalToConstant: 22)
                ])
                
                searchMenuItem.view = headerView

                dialerView = MenuBarDialerView(frame: NSRect(x: 0, y: 0, width: 240, height: 330))
                dialerView.autoresizingMask = [.width]
                dialerView.onCall = { [weak self] phone in
                    self?.makeCall(phone: phone, name: nil, contactID: nil)
                    self?.menu.cancelTracking()
                }
                dialerMenuItem = NSMenuItem()
                dialerMenuItem.view = dialerView

                keypadMenuItem = NSMenuItem(title: L("keypad"), action: nil, keyEquivalent: "")
                keypadMenuItem.image = NSImage(systemSymbolName: "circle.grid.3x3.fill", accessibilityDescription: nil)
                let submenu = NSMenu()
                submenu.addItem(dialerMenuItem)
                keypadMenuItem.submenu = submenu

                speedDialMenuItem = NSMenuItem(title: L("tab_speed_dial"), action: nil, keyEquivalent: "")
                speedDialMenuItem.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
                speedDialMenuItem.submenu = NSMenu()
                
                statusItem?.menu = menu
                buildInitialMenu()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
            menu = nil
            searchMenuItem = nil
            keypadMenuItem = nil
            dialerMenuItem = nil
            dialerView = nil
            speedDialMenuItem = nil
            searchField = nil
        }
    }
    
    private func buildInitialMenu() {
        menu.removeAllItems()
        menu.addItem(searchMenuItem)
        menu.addItem(keypadMenuItem)
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        searchField.stringValue = ""
        dialerView.updatePlusButtonVisibility()
        refreshMenuItems(searchText: "")
        DispatchQueue.main.async { [weak self] in
            self?.dialerView.focusInput()
        }
    }
       
    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.button?.needsDisplay = true
        }
    }
    
    private func rebuildSpeedDialSubmenu() {
        let sdMenu = NSMenu()
        
        var hasEntries = false
        for i in 1...9 {
            let savedValue = UserDefaults.standard.string(forKey: "SpeedDial_\(i)") ?? ""
            guard !savedValue.isEmpty else { continue }
            
            let display: String
            let phone: String
            if let contact = ContactStore.shared.contacts.first(where: { $0.phone.sanitizedForCall == savedValue.sanitizedForCall }) {
                display = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(contact.fullName) : contact.fullName
                phone = contact.phone
            } else {
                display = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(savedValue) : savedValue
                phone = savedValue
            }
            
            let item = NSMenuItem(title: "\(i)  \(display)", action: #selector(speedDialEntryTapped(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = phone
            item.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
            sdMenu.addItem(item)
            hasEntries = true
        }
        
        if !hasEntries {
            let emptyItem = NSMenuItem(title: L("speed_dial_empty"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            sdMenu.addItem(emptyItem)
        }
        
        sdMenu.addItem(NSMenuItem.separator())
        let manageItem = NSMenuItem(title: L("speed_dial_manage_menu_item"), action: #selector(speedDialManageTapped), keyEquivalent: "")
        manageItem.target = self
        manageItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        sdMenu.addItem(manageItem)
        
        speedDialMenuItem.submenu = sdMenu
    }
    
    @objc private func speedDialEntryTapped(_ sender: NSMenuItem) {
        guard let phone = sender.representedObject as? String else { return }
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        makeCall(phone: phone, name: nil, contactID: nil)
        menu.cancelTracking()
    }
    
    @objc private func speedDialManageTapped() {
        menu.cancelTracking()
        NSApp.activate(ignoringOtherApps: true)
        (NSApp.delegate as? AppDelegate)?.showSettingsToSpeedDial()
    }
    
    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSSearchField {
            refreshMenuItems(searchText: field.stringValue)
        }
    }
    
    func controlTextDidBeginEditing(_ obj: Notification) {
        if let field = obj.object as? NSSearchField, field == searchField {
            DispatchQueue.main.async {
                if let editor = field.currentEditor() as? NSTextView {
                    editor.insertionPointColor = .labelColor
                }
            }
        }
    }
    
    private func getClipboardPhone() -> String? {
        guard let pasteString = NSPasteboard.general.string(forType: .string) else { return nil }
        if pasteString.count > 30 { return nil } 
        
        let sanitized = pasteString.sanitizedForCall
        if sanitized.count >= 4 && sanitized.count <= 20 {
            let allowedChars = CharacterSet(charactersIn: "+0123456789 ()-.")
            let isMostlyPhone = pasteString.unicodeScalars.allSatisfy { allowedChars.contains($0) }
            
            if isMostlyPhone {
                return sanitized
            }
        }
        return nil
    }

    func refreshMenuItems(searchText: String) {
        guard !isRefreshingMenuItems else { return }
        isRefreshingMenuItems = true
        defer { isRefreshingMenuItems = false }

        if menu.items.isEmpty {
            menu.addItem(searchMenuItem)
            menu.addItem(keypadMenuItem)
        }
        while menu.items.count > 2 {
            menu.removeItem(at: 2)
        }
        
        if UserDefaults.standard.bool(forKey: "enableSpeedDial") {
            rebuildSpeedDialSubmenu()
            menu.addItem(speedDialMenuItem)
        }
        
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        menu.addItem(NSMenuItem.separator())
        
        if query.isEmpty, let clipboardPhone = getClipboardPhone() {
            let title = L("menubar_call_copied", clipboardPhone)
            let clipboardItem = NSMenuItem(title: title, action: #selector(callHistory(_:)), keyEquivalent: "c")
            clipboardItem.representedObject = clipboardPhone
            clipboardItem.target = self
            clipboardItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
            menu.addItem(clipboardItem)
            menu.addItem(NSMenuItem.separator())
        }
        
        if PrivacyMode.shared.isEnabled && !query.isEmpty {
            menu.addItem(makeWrappingTextItem(L("privacy_mode_search_disabled")))
            addFooterItems()
            menu.update()
            return
        }
        
        var contactsToShow: [Contact] = []
        if query.isEmpty {
            contactsToShow = ContactStore.shared.favorites.sortedByFavoriteOrder()
            let titleItem = NSMenuItem(title: L("favorites"), action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)
        } else {
            contactsToShow = ContactStore.shared.contacts.filter {
                $0.fullName.lowercased().contains(query) || $0.phone.contains(query)
            }
        }
        
        if contactsToShow.isEmpty {
            let emptyText = query.isEmpty ? L("no_favorites") : L("no_search_results")
            menu.addItem(makeWrappingTextItem(emptyText))
        } else {
            let maxDirectContacts = 8
            let directContacts = contactsToShow.prefix(maxDirectContacts)
            let overflowContacts = contactsToShow.dropFirst(maxDirectContacts)
            
            for contact in directContacts {
                let name = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(contact.fullName) : contact.fullName
                let item = NSMenuItem(title: name, action: #selector(callContact(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = contact
                item.image = NSImage(systemSymbolName: "phone.fill", accessibilityDescription: nil)
                menu.addItem(item)
            }
            
            if !overflowContacts.isEmpty {
                let allOverflow = Array(overflowContacts)
                let moreTitle = query.isEmpty ? L("menubar_more_favorites") : L("menubar_more_results")
                
                let entries: [(title: String, symbol: String, action: () -> Void)] = allOverflow.map { contact in
                    let name = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(contact.fullName) : contact.fullName
                    return (title: name, symbol: "phone.fill", action: { [weak self] in
                        if PrivacyMode.shared.isEnabled { PrivacyMode.shared.showBlockedAlert(); return }
                        self?.makeCall(phone: contact.phone, name: contact.fullName, contactID: contact.id)
                    })
                }
                
                let moreItem = makeMoreItem(title: moreTitle, entries: entries)
                menu.addItem(moreItem)
            }
        }
        
        if query.isEmpty {
            let recent = HistoryStore.shared.records
            if !recent.isEmpty {
                menu.addItem(NSMenuItem.separator())
                let historyTitle = NSMenuItem(title: L("recent_calls"), action: nil, keyEquivalent: "")
                historyTitle.isEnabled = false
                menu.addItem(historyTitle)
                
                let topRecent = recent.prefix(4)
                for record in topRecent {
                    let displayName = record.contactName ?? record.phone
                    let name = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(displayName) : displayName
                    let item = NSMenuItem(title: name, action: #selector(callHistory(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = record.phone
                    item.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
                    menu.addItem(item)
                }
                
                if recent.count > 4 {
                    let moreTitle = L("menubar_more_history")
                    let overflowRecords = Array(recent.dropFirst(4))
                    
                    let entries: [(title: String, symbol: String, action: () -> Void)] = overflowRecords.map { record in
                        let displayName = record.contactName ?? record.phone
                        let name = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(displayName) : displayName
                        return (title: name, symbol: "clock", action: { [weak self] in
                            if PrivacyMode.shared.isEnabled { PrivacyMode.shared.showBlockedAlert(); return }
                            self?.makeCall(phone: record.phone, name: nil, contactID: nil)
                        })
                    }
                    
                    let moreItem = makeMoreItem(title: moreTitle, entries: entries)
                    menu.addItem(moreItem)
                }
            }
        }
        
        addFooterItems()
        menu.update()
    }
   
    private func addFooterItems() {
        menu.addItem(NSMenuItem.separator())
        
        let privacyItem = NSMenuItem(title: L("privacy_mode_menu"), action: #selector(togglePrivacy), keyEquivalent: "P")
        privacyItem.keyEquivalentModifierMask = [.command, .shift]
        privacyItem.target = self
        privacyItem.state = PrivacyMode.shared.isEnabled ? .on : .off
        menu.addItem(privacyItem)
        
        let openAppItem = NSMenuItem(title: L("open_hellomac"), action: #selector(openApp), keyEquivalent: "H")
        openAppItem.keyEquivalentModifierMask = [.control, .option, .command]
        openAppItem.target = self
        menu.addItem(openAppItem)
        
        let quitItem = NSMenuItem(title: L("exit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }
    
    private func isGreek() -> Bool {
        return Locale.preferredLanguages.first?.hasPrefix("el") ?? true
    }
    
    // MARK: - Βοηθητικά για Μεγάλες Λίστες (Scrollable Submenus)
    
    private let scrollThreshold = 8
    private let scrollRowHeight: CGFloat = 22
    private let scrollMaxVisibleRows: CGFloat = 8
    
    private final class ScrollableMenuRow: NSView {
        var onClick: (() -> Void)?
        private let horizontalInset: CGFloat = 14
        private let iconTextSpacing: CGFloat = 6
        private let iconView = NSImageView()
        private let label = NSTextField(labelWithString: "")
        private var isHighlighted = false {
            didSet { updateAppearance() }
        }
        
        init(title: String, symbolName: String, width: CGFloat, height: CGFloat) {
            super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
            
            wantsLayer = true
            layer?.cornerRadius = 4
            
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            img?.isTemplate = true 
            iconView.image = img
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.contentTintColor = .labelColor
            iconView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iconView)
            
            label.stringValue = title
            label.font = NSFont.menuFont(ofSize: 13)
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            
            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 16),
                iconView.heightAnchor.constraint(equalToConstant: 16),
                
                label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: iconTextSpacing),
                label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -horizontalInset),
                label.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
        
        required init?(coder: NSCoder) { fatalError() }
        
        private func updateAppearance() {
            if isHighlighted {
                layer?.backgroundColor = NSColor.controlAccentColor.cgColor
                label.textColor = .white
                iconView.contentTintColor = .white
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
                label.textColor = .labelColor
                iconView.contentTintColor = .labelColor
            }
        }
        
        private var trackingArea: NSTrackingArea?
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingArea { removeTrackingArea(existing) }
            let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
            addTrackingArea(area)
            trackingArea = area
        }
        
        override func mouseEntered(with event: NSEvent) { isHighlighted = true }
        override func mouseExited(with event: NSEvent) { isHighlighted = false }
        
        override func mouseDown(with event: NSEvent) {
        }
        
        override func mouseUp(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            if bounds.contains(point) {
                onClick?()
            }
        }
    }
    
    private func makeMoreItem(title: String, entries: [(title: String, symbol: String, action: () -> Void)]) -> NSMenuItem {
        let moreItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        
        if entries.count > scrollThreshold {
            let width: CGFloat = 240
            let visibleRows = min(CGFloat(entries.count), scrollMaxVisibleRows)
            let contentHeight = CGFloat(entries.count) * scrollRowHeight
            let visibleHeight = visibleRows * scrollRowHeight
            
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: visibleHeight))
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            
            let containerView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: contentHeight))
            for (index, entry) in entries.enumerated() {
                let rowY = contentHeight - CGFloat(index + 1) * scrollRowHeight
                let row = ScrollableMenuRow(title: entry.title, symbolName: entry.symbol, width: width, height: scrollRowHeight)
                row.frame.origin.y = rowY
                row.onClick = { [weak self] in
                    entry.action()
                    self?.menu.cancelTracking()
                }
                containerView.addSubview(row)
            }
            
            scrollView.documentView = containerView
            scrollView.heightAnchor.constraint(equalToConstant: visibleHeight).isActive = true
            scrollView.widthAnchor.constraint(equalToConstant: width).isActive = true
            
            let wrapperItem = NSMenuItem()
            wrapperItem.view = scrollView
            submenu.addItem(wrapperItem)
        } else {
            for entry in entries {
                let item = NSMenuItem(title: entry.title, action: #selector(scrollableEntryTapped(_:)), keyEquivalent: "")
                item.target = self
                item.image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)
                item.representedObject = entry.action
                submenu.addItem(item)
            }
        }
        
        moreItem.submenu = submenu
        return moreItem
    }
    
    private func makeWrappingTextItem(_ text: String) -> NSMenuItem {
        let width: CGFloat = 240
        let horizontalPadding: CGFloat = 16
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.menuFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        
        let container = NSView(frame: .zero)
        container.autoresizingMask = [.width]
        container.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalPadding),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalPadding),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        
        let usableWidth = width - horizontalPadding * 2
        let fittingHeight = label.sizeThatFits(NSSize(width: usableWidth, height: .greatestFiniteMagnitude)).height
        container.frame = NSRect(x: 0, y: 0, width: width, height: fittingHeight + 16)
        
        let item = NSMenuItem()
        item.view = container
        return item
    }
    
    @objc private func scrollableEntryTapped(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }
    
    @objc func callContact(_ sender: NSMenuItem) {
        if PrivacyMode.shared.isEnabled { PrivacyMode.shared.showBlockedAlert(); return }
        guard let contact = sender.representedObject as? Contact else { return }
        makeCall(phone: contact.phone, name: contact.fullName, contactID: contact.id)
    }
    
    @objc func callHistory(_ sender: NSMenuItem) {
        if PrivacyMode.shared.isEnabled { PrivacyMode.shared.showBlockedAlert(); return }
        guard let phone = sender.representedObject as? String else { return }
        makeCall(phone: phone, name: nil, contactID: nil)
    }
    
    private func makeCall(phone: String, name: String?, contactID: UUID?) {
        guard !phone.sanitizedForCall.isEmpty else { return }
        let urlString = "tel:\(phone.sanitizedForCall)"
        guard let url = URL(string: urlString) else { return }
        
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.suppressFaceTime()
        }
        NSWorkspace.shared.open(url)
        HistoryStore.shared.addRecord(phone: phone, name: name, contactID: contactID)
    }
    
    @objc func togglePrivacy() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.togglePrivacyMode()
        }
    }
    
    @objc func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        if let del = NSApp.delegate as? AppDelegate {
            del.mainWindowController?.showWindow(nil)
            del.mainWindowController?.window?.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc func contactsChanged() {
        if isMenuOpen, statusItem?.menu != nil {
            refreshMenuItems(searchText: searchField.stringValue)
        }
    }
}

class MenuBarDialerView: NSView {
    var onCall: ((String) -> Void)?
    var displayField: NSTextField!
    private var plusButton: MenuBarDialerKey?
    
    override var acceptsFirstResponder: Bool { return true }
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    func focusInput() {
        attemptFocus(retriesLeft: 5)
    }

    private func attemptFocus(retriesLeft: Int) {
        guard let win = self.window else {
            if retriesLeft > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                    self?.attemptFocus(retriesLeft: retriesLeft - 1)
                }
            }
            return
        }
        if !win.isKeyWindow {
            win.makeKey()
        }
        let success = win.makeFirstResponder(self)
        if !success && retriesLeft > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.attemptFocus(retriesLeft: retriesLeft - 1)
            }
        }
    }

    func updatePlusButtonVisibility() {
        plusButton?.isHidden = UserDefaults.standard.bool(forKey: "hideMenuBarPlusButton")
    }
    
    private func setupUI() {
        displayField = NSTextField()
        displayField.isEditable = false
        displayField.isSelectable = false
        displayField.isBezeled = false
        displayField.drawsBackground = false
        displayField.textColor = .labelColor 
        displayField.focusRingType = .none
        displayField.font = NSFont.systemFont(ofSize: 22, weight: .light)
        displayField.alignment = .center
        
        let placeholderStr = L("menubar_number_placeholder")
        displayField.placeholderAttributedString = NSAttributedString(
            string: placeholderStr,
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.systemFont(ofSize: 22, weight: .light)
            ]
        )
        
        displayField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(displayField)
        
        let deleteBtn = MenuBarDialerActionBtn(symbol: "delete.left", color: .labelColor)
        deleteBtn.onTap = { [weak self] in
            guard let self = self, !self.displayField.stringValue.isEmpty else { return }
            self.displayField.stringValue = String(self.displayField.stringValue.dropLast())
        }
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(deleteBtn)
        
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "+", "0", ""]
        let gridStack = NSStackView()
        gridStack.orientation = .vertical
        gridStack.spacing = 8
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gridStack)
        
        for row in 0..<4 {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.spacing = 16
            rowStack.distribution = .fillEqually
            for col in 0..<3 {
                let digit = keys[row * 3 + col]
                if digit.isEmpty {
                    let dummy = NSView()
                    dummy.widthAnchor.constraint(equalToConstant: 42).isActive = true
                    dummy.heightAnchor.constraint(equalToConstant: 42).isActive = true
                    rowStack.addArrangedSubview(dummy)
                } else if digit == "+" {
                    let wrapper = NSView()
                    wrapper.translatesAutoresizingMaskIntoConstraints = false
                    wrapper.widthAnchor.constraint(equalToConstant: 42).isActive = true
                    wrapper.heightAnchor.constraint(equalToConstant: 42).isActive = true
                    
                    let btn = MenuBarDialerKey(digit: digit)
                    btn.translatesAutoresizingMaskIntoConstraints = false
                    btn.onTap = { [weak self] d in
                        if let firstChar = d.first {
                            DialerSound.playMenuBarKeypadSoundIfEnabled(digit: firstChar)
                        }
                        if (self?.displayField.stringValue.count ?? 0) < 20 {
                            self?.displayField.stringValue += d
                        }
                    }
                    wrapper.addSubview(btn)
                    NSLayoutConstraint.activate([
                        btn.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                        btn.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
                        btn.widthAnchor.constraint(equalTo: wrapper.widthAnchor),
                        btn.heightAnchor.constraint(equalTo: wrapper.heightAnchor)
                    ])
                    self.plusButton = btn
                    rowStack.addArrangedSubview(wrapper)
                } else {
                    let btn = MenuBarDialerKey(digit: digit)
                    btn.onTap = { [weak self] d in
                        if let firstChar = d.first {
                            DialerSound.playMenuBarKeypadSoundIfEnabled(digit: firstChar)
                        }
                        if (self?.displayField.stringValue.count ?? 0) < 20 {
                            self?.displayField.stringValue += d
                        }
                    }
                    rowStack.addArrangedSubview(btn)
                }
            }
            gridStack.addArrangedSubview(rowStack)
        }
        
        let callBtn = MenuBarDialerActionBtn(symbol: "phone.fill", color: NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1), isPrimary: true)
        callBtn.onTap = { [weak self] in
            self?.executeCall()
        }
        callBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(callBtn)
        
        NSLayoutConstraint.activate([
            displayField.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            displayField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            displayField.trailingAnchor.constraint(equalTo: deleteBtn.leadingAnchor, constant: -8),
            displayField.heightAnchor.constraint(equalToConstant: 30),
            
            deleteBtn.centerYAnchor.constraint(equalTo: displayField.centerYAnchor),
            deleteBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            deleteBtn.widthAnchor.constraint(equalToConstant: 28),
            deleteBtn.heightAnchor.constraint(equalToConstant: 28),
            
            gridStack.topAnchor.constraint(equalTo: displayField.bottomAnchor, constant: 16),
            gridStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            
            callBtn.topAnchor.constraint(equalTo: gridStack.bottomAnchor, constant: 16),
            callBtn.centerXAnchor.constraint(equalTo: centerXAnchor),
            callBtn.widthAnchor.constraint(equalToConstant: 48),
            callBtn.heightAnchor.constraint(equalToConstant: 48)
        ])
    }
    
    private func executeCall() {
        let number = displayField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !number.isEmpty else { return }

        if UserDefaults.standard.bool(forKey: "enableSpeedDial"), number.count == 1 {
            if let num = Int(number), num >= 1, num <= 9 {
                if let target = UserDefaults.standard.string(forKey: "SpeedDial_\(num)"), !target.isEmpty {
                    guard !target.sanitizedForCall.isEmpty else {
                        onCall?(number)
                        return
                    }

                    if PrivacyMode.shared.isEnabled {
                        PrivacyMode.shared.showBlockedAlert()
                        return
                    }

                    onCall?(target)
                    displayField.stringValue = ""
                    return
                }
            }
        }
        onCall?(number)
    }
    
    // MARK: - Διαχείριση Πληκτρολογίου & Επικόλλησης (Paste)
    
    @objc func paste(_ sender: Any?) {
        if let pasteString = NSPasteboard.general.string(forType: .string) {
            let allowed = CharacterSet(charactersIn: "+0123456789")
            let sanitized = String(pasteString.unicodeScalars.filter { allowed.contains($0) })
            let currentCount = displayField.stringValue.count
            let allowedCount = max(0, 20 - currentCount)
            displayField.stringValue += String(sanitized.prefix(allowedCount))
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if let chars = event.characters {
            if chars == "\r" || chars == "\u{3}" {
                executeCall()
                return
            }
            
            let allowed = CharacterSet(charactersIn: "+0123456789")
            for scalar in chars.unicodeScalars {
                if allowed.contains(scalar) {
                    if displayField.stringValue.count < 20 { // Όριο 20 χαρακτήρες
                        DialerSound.playMenuBarKeypadSoundIfEnabled(digit: Character(scalar))
                        displayField.stringValue += String(scalar)
                    }
                }
            }
        }
        
        if event.keyCode == 51 || event.keyCode == 117 {
            if !displayField.stringValue.isEmpty {
                displayField.stringValue = String(displayField.stringValue.dropLast())
            }
        }
    }
}

class MenuBarDialerKey: NSButton {
    var digit: String = ""
    var onTap: ((String) -> Void)?
    
    init(digit: String) {
        super.init(frame: .zero)
        self.digit = digit
        self.title = digit
        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center
        self.attributedTitle = NSAttributedString(
            string: digit,
            attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 20, weight: .regular), .paragraphStyle: pStyle]
        )
        
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor
        self.layer?.cornerRadius = 21
        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: 42),
            self.heightAnchor.constraint(equalToConstant: 42)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private var trackingArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }
    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = NSColor(white: 0.32, alpha: 1).cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self.superview ?? self)
        layer?.backgroundColor = NSColor(white: 0.14, alpha: 1).cgColor
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let isInside = bounds.contains(point)
        
        layer?.backgroundColor = isInside ? NSColor(white: 0.32, alpha: 1).cgColor : NSColor(white: 0.22, alpha: 1).cgColor
        
        if isInside {
            let action = self.onTap
            let tappedDigit = self.digit
            DispatchQueue.main.async {
                action?(tappedDigit)
            }
        }
    }
}

class MenuBarDialerActionBtn: NSButton {
    var onTap: (() -> Void)?
    private var baseColor: NSColor
    private var isPrimary: Bool
    private let iconView = NSImageView()
    
    init(symbol: String, color: NSColor, isPrimary: Bool = false, pointSize: CGFloat? = nil, weight: NSFont.Weight? = nil) {
        self.baseColor = color
        self.isPrimary = isPrimary
        super.init(frame: .zero)
        
        self.title = ""
        self.isBordered = false
        self.bezelStyle = .regularSquare
        self.wantsLayer = true
        self.layer?.cornerRadius = isPrimary ? 24 : 14
        if isPrimary { 
            self.layer?.backgroundColor = color.cgColor 
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let size = pointSize ?? (isPrimary ? 20 : 16)
        let w = weight ?? .medium
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: w)
        
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        img?.isTemplate = true
        iconView.image = img
        iconView.contentTintColor = isPrimary ? .white : color
        self.addSubview(iconView)
        
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private var trackingArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }
    
    override func mouseEntered(with event: NSEvent) { 
        if isPrimary { 
            layer?.backgroundColor = baseColor.blended(withFraction: 0.2, of: .white)?.cgColor 
        } else { 
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor 
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        if isPrimary { 
            layer?.backgroundColor = baseColor.cgColor 
        } else { 
            layer?.backgroundColor = NSColor.clear.cgColor 
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self.superview ?? self)
        if isPrimary { 
            layer?.backgroundColor = baseColor.blended(withFraction: 0.2, of: .black)?.cgColor 
        } else { 
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.2).cgColor 
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let isInside = bounds.contains(point)
        
        if isInside {
            mouseEntered(with: event)
            let action = self.onTap
            DispatchQueue.main.async {
                action?()
            }
        } else {
            mouseExited(with: event)
        }
    }
    
    override func updateLayer() {
        super.updateLayer()
        if !isPrimary {
            iconView.contentTintColor = baseColor
        } else {
            iconView.contentTintColor = .white
            layer?.backgroundColor = baseColor.cgColor
        }
    }
}