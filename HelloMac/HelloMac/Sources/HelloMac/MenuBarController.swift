import AppKit

class MenuBarController: NSObject, NSSearchFieldDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    var menu: NSMenu!
    var searchField: NSSearchField!
    var searchMenuItem: NSMenuItem!
    var dialerHeaderMenuItem: NSMenuItem!
    
    var isDialerActive: Bool = false
    var dialerMenuItem: NSMenuItem!
    var dialerView: MenuBarDialerView!
    
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
                
                let keypadBtn = MenuBarDialerActionBtn(symbol: "circle.grid.3x3.fill", color: .labelColor, pointSize: 13, weight: .regular)
                keypadBtn.onTap = { [weak self] in
                    self?.toggleDialer()
                }
                keypadBtn.translatesAutoresizingMaskIntoConstraints = false
                headerView.addSubview(keypadBtn)
                
                NSLayoutConstraint.activate([
                    searchField.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
                    searchField.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
                    searchField.heightAnchor.constraint(equalToConstant: 22),
                    
                    keypadBtn.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
                    keypadBtn.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
                    keypadBtn.widthAnchor.constraint(equalToConstant: 24),
                    keypadBtn.heightAnchor.constraint(equalToConstant: 24),
                    
                    searchField.trailingAnchor.constraint(equalTo: keypadBtn.leadingAnchor, constant: -8)
                ])
                
                searchMenuItem.view = headerView

                dialerHeaderMenuItem = NSMenuItem()
                let dialerHeaderView = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 32))
                dialerHeaderView.autoresizingMask = [.width]
                
                let dialerTitleLabel = NSTextField(labelWithString: L("dialer_title"))
                dialerTitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
                dialerTitleLabel.textColor = .labelColor
                dialerTitleLabel.alignment = .center
                dialerTitleLabel.translatesAutoresizingMaskIntoConstraints = false
                dialerHeaderView.addSubview(dialerTitleLabel)
                
                let backBtn = MenuBarDialerActionBtn(symbol: "xmark.circle.fill", color: .labelColor, pointSize: 18, weight: .medium)
                backBtn.onTap = { [weak self] in
                    self?.toggleDialer()
                }
                backBtn.translatesAutoresizingMaskIntoConstraints = false
                dialerHeaderView.addSubview(backBtn)
                
                NSLayoutConstraint.activate([
                    dialerTitleLabel.centerXAnchor.constraint(equalTo: dialerHeaderView.centerXAnchor),
                    dialerTitleLabel.centerYAnchor.constraint(equalTo: dialerHeaderView.centerYAnchor),
                    
                    backBtn.trailingAnchor.constraint(equalTo: dialerHeaderView.trailingAnchor, constant: -16),
                    backBtn.centerYAnchor.constraint(equalTo: dialerHeaderView.centerYAnchor),
                    backBtn.widthAnchor.constraint(equalToConstant: 28),
                    backBtn.heightAnchor.constraint(equalToConstant: 28)
                ])
                
                dialerHeaderMenuItem.view = dialerHeaderView
                
                dialerView = MenuBarDialerView(frame: NSRect(x: 0, y: 0, width: 240, height: 330))
                dialerView.autoresizingMask = [.width]
                dialerView.onCall = { [weak self] phone in
                    self?.makeCall(phone: phone, name: nil, contactID: nil)
                    self?.menu.cancelTracking()
                }
                dialerMenuItem = NSMenuItem()
                dialerMenuItem.view = dialerView
                
                statusItem?.menu = menu
                buildInitialMenu()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(toggleDialer), object: nil)
            menu = nil
            searchMenuItem = nil
            dialerHeaderMenuItem = nil
            dialerMenuItem = nil
            dialerView = nil
            searchField = nil
            isDialerActive = false
        }
    }
    
    private func buildInitialMenu() {
        menu.removeAllItems()
        menu.addItem(searchMenuItem)
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(toggleDialer), object: nil)
        searchField.stringValue = ""
        isDialerActive = false
        dialerView.updatePlusButtonVisibility()
        refreshMenuItems(searchText: "")

        DispatchQueue.main.async {
            self.searchField.window?.makeFirstResponder(nil)
        }
    }
       
    func menuDidClose(_ menu: NSMenu) {
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.button?.needsDisplay = true
        }
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
    
    @objc func toggleDialer() {
        isDialerActive.toggle()
        searchField.stringValue = ""
        refreshMenuItems(searchText: "")
    
        if isDialerActive {
            DispatchQueue.main.async {
                self.dialerView.focusInput()
            }
        } else {
            DispatchQueue.main.async {
                self.searchField.window?.makeFirstResponder(nil)
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

        // Αφαιρούμε τα πάντα για να τα ξαναχτίσουμε από την αρχή καθαρά
        menu.removeAllItems()
        
        // Αν είμαστε στα Πλήκτρα (Dialer)
        if isDialerActive {
            menu.addItem(dialerHeaderMenuItem)
            menu.addItem(dialerMenuItem)
            addFooterItems()
            menu.update()
            return
        }
        
        // Αν ΔΕΝ είμαστε στα πλήκτρα, δείχνουμε την Αναζήτηση
        menu.addItem(searchMenuItem)
        
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
    private let scrollRowHeight: CGFloat = 28
    private let scrollMaxVisibleRows: CGFloat = 8
    
    private final class ScrollableMenuRow: NSView {
        var onClick: (() -> Void)?
        private let button: NSButton
        
        init(title: String, symbolName: String, width: CGFloat, height: CGFloat) {
            button = NSButton(frame: NSRect(x: 0, y: 0, width: width, height: height))
            super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
            
            button.title = "  " + title
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.alignment = .left
            button.contentTintColor = .labelColor
            button.font = NSFont.menuFont(ofSize: 13)
            button.autoresizingMask = [.width]
            button.target = self
            button.action = #selector(handleClick)
            addSubview(button)
        }
        
        required init?(coder: NSCoder) { fatalError() }
        
        @objc private func handleClick() { onClick?() }
    }
    
    private func makeMoreItem(title: String, entries: [(title: String, symbol: String, action: () -> Void)]) -> NSMenuItem {
        let moreItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        
        if entries.count > scrollThreshold {
            let width: CGFloat = 260
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
        if statusItem?.menu != nil {
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
        if let win = self.window {
            win.makeFirstResponder(self)
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
            self.focusInput()
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
                        self?.focusInput()
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
                        self?.focusInput()
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
        
        // --- ΛΟΓΙΚΗ ΤΑΧΕΙΑΣ ΚΛΗΣΗΣ ---
        if UserDefaults.standard.bool(forKey: "enableSpeedDial"), number.count == 1 {
            if let num = Int(number), num >= 1, num <= 9 {
                if let target = UserDefaults.standard.string(forKey: "SpeedDial_\(num)"), !target.isEmpty {
                    // Αν υπάρχει αποθηκευμένος αριθμός αλλά είναι κενός (π.χ. λάθος), κάνε κανονική κλήση του ψηφίου
                    guard !target.sanitizedForCall.isEmpty else {
                        onCall?(number)
                        return
                    }
                    // Έλεγχος Λειτουργίας Απορρήτου
                    if PrivacyMode.shared.isEnabled {
                        PrivacyMode.shared.showBlockedAlert()
                        return
                    }
                    // Εκτέλεση της ταχείας κλήσης στον αποθηκευμένο αριθμό
                    onCall?(target)
                    displayField.stringValue = "" // Καθαρισμός του πεδίου
                    return
                }
            }
        }
        
        // --- ΚΑΝΟΝΙΚΗ ΚΛΗΣΗ ---
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
        
        // Φορμάρισμα του κειμένου (χρώμα και στοίχιση)
        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center
        self.attributedTitle = NSAttributedString(
            string: digit,
            attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 20, weight: .regular), .paragraphStyle: pStyle]
        )
        
        self.isBordered = false
        self.bezelStyle = .regularSquare // Απαραίτητο για custom μέγεθος στο NSButton
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor
        self.layer?.cornerRadius = 21
        
        // --- ΕΠΑΝΑΦΟΡΑ ΤΩΝ ΔΙΑΣΤΑΣΕΩΝ ΠΟΥ ΕΛΕΙΠΑΝ ---
        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: 42),
            self.heightAnchor.constraint(equalToConstant: 42)
        ])
        
        // Σύνδεση με το εσωτερικό σύστημα του NSButton
        self.target = self
        self.action = #selector(handleClick)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    @objc private func handleClick() {
        onTap?(digit)
    }
    
    // Εφέ Hover
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
    
    // Αφήνουμε το macOS να ελέγξει το κλικ μέσω του super.mouseDown
    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor(white: 0.14, alpha: 1).cgColor
        super.mouseDown(with: event)
        layer?.backgroundColor = NSColor(white: 0.32, alpha: 1).cgColor
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
        
        // Στο κύριο πράσινο κουμπί βάζουμε το background
        if isPrimary { 
            self.layer?.backgroundColor = color.cgColor 
        }
        
        // Διαμόρφωση εικόνας μέσω του ανεξάρτητου NSImageView
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let size = pointSize ?? (isPrimary ? 20 : 16)
        let w = weight ?? .medium
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: w)
        
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        img?.isTemplate = true
        iconView.image = img
        
        // ΕΔΩ εξασφαλίζουμε ότι το πράσινο κουμπί θα έχει ΠΑΝΤΑ ΛΕΥΚΟ τηλέφωνο
        iconView.contentTintColor = isPrimary ? .white : color
        self.addSubview(iconView)
        
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
        
        // Σύνδεση με το εσωτερικό σύστημα του NSButton
        self.target = self
        self.action = #selector(handleClick)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    @objc private func handleClick() {
        onTap?()
    }
    
    // Εφέ Hover
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
        if isPrimary { 
            layer?.backgroundColor = baseColor.blended(withFraction: 0.2, of: .black)?.cgColor 
        } else { 
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.2).cgColor 
        }
        super.mouseDown(with: event)
        mouseEntered(with: event)
    }
    
    // Ανανεώνει σωστά τα χρώματα όταν αλλάζει το Light/Dark Mode
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