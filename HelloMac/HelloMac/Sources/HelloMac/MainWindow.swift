import AppKit

class NonFullScreenWindow: NSWindow {
    override func toggleFullScreen(_ sender: Any?) { }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.keyCode == 3 {
            if let controller = self.windowController as? MainWindowController {
                controller.focusSearchFieldPublic()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

class ClickableLabel: NSTextField {
    var isLinkActive: Bool = false {
        didSet {
            if isLinkActive {
                discardCursorRects()
                addCursorRect(bounds, cursor: .pointingHand)
            } else {
                discardCursorRects()
            }
        }
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        if isLinkActive {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

class CleanFieldEditor: NSTextView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let defaultMenu = super.menu(for: event) ?? NSMenu()
        let newMenu = NSMenu()
        
        newMenu.allowsContextMenuPlugIns = false
        
        newMenu.addItem(NSMenuItem(title: L("cut"), action: #selector(NSText.cut(_:)), keyEquivalent: ""))
        newMenu.addItem(NSMenuItem(title: L("copy"), action: #selector(NSText.copy(_:)), keyEquivalent: ""))
        newMenu.addItem(NSMenuItem(title: L("paste"), action: #selector(NSText.paste(_:)), keyEquivalent: ""))
        
        var googleItem: NSMenuItem?
        for item in defaultMenu.items {
            let actionStr = item.action?.description ?? ""
            let title = item.title.lowercased()
            if actionStr.contains("WebSearch") || actionStr.contains("Google") || title.contains("google") {
                googleItem = item.copy() as? NSMenuItem
                googleItem?.title = L("search_with_google")
            }
        }
        
        var shareItem: NSMenuItem?
        let selectedRange = self.selectedRange()
        if selectedRange.length > 0 {
            shareItem = NSMenuItem(
                title: L("share_menu"), 
                action: #selector(openSharePicker(_:)), 
                keyEquivalent: ""
            )
            shareItem?.target = self
        }
                
        if googleItem != nil || shareItem != nil {
            newMenu.addItem(NSMenuItem.separator())
            if let g = googleItem { newMenu.addItem(g) }
            if let s = shareItem { newMenu.addItem(s) }
        }
        return newMenu
    }
    
    @objc private func openSharePicker(_ sender: NSMenuItem) {
        let selectedRange = self.selectedRange()
        guard selectedRange.length > 0 else { return }
        let selectedText = (self.string as NSString).substring(with: selectedRange)
        let picker = NSSharingServicePicker(items: [selectedText])
        picker.show(relativeTo: self.bounds, of: self, preferredEdge: .minY)
    }
}

protocol KeyCaptureDelegate: AnyObject {
    func keyCaptureDidType(digit: String)
    func keyCaptureDidBackspace()
    func keyCaptureDidPressEnter()
    func keyCaptureDidPaste()
}

class KeyCaptureView: NSView {
    weak var keyDelegate: KeyCaptureDelegate?
    override var acceptsFirstResponder: Bool { true }

    @objc func paste(_ sender: Any?) {
        keyDelegate?.keyCaptureDidPaste()
    }

    override func keyDown(with event: NSEvent) {
        if let characters = event.characters {
            if characters == "\r" || characters == "\u{3}" {
                keyDelegate?.keyCaptureDidPressEnter()
                return
            }
            for scalar in characters.unicodeScalars {
                if CharacterSet.decimalDigits.contains(scalar) || scalar == "+" {
                    keyDelegate?.keyCaptureDidType(digit: String(scalar))
                }
            }
        }
        switch event.keyCode {
        case 51, 117: keyDelegate?.keyCaptureDidBackspace()
        default: break
        }
    }
}

class MainWindowController: NSWindowController, NSWindowDelegate, KeyCaptureDelegate, NSSearchFieldDelegate {
    private var stackView: NSStackView!
    private var favoritesStackView: FavoritesDropStackView!
    private var historyStackView: NSStackView!
    
    private var contactsView: NSView!
    private var favoritesView: NSView!
    private var historyView: NSView!
    private var dialerView: KeyCaptureView!
    private var emptyStateView: NSView!
    
    private var contactsButton: NSButton!
    private var favoritesButton: NSButton!
    private var historyButton: NSButton!
    private var dialButton: NSButton!
    private var currentActiveTabIdentifier: String = "clock.fill"
    
    private var displayLabel: NSTextField!
    
    private var contactsSearchField: NSSearchField!
    private var favoritesSearchField: NSSearchField!
    private var contactsGroupFilterIconButton: NSButton!
    private var groupFilterPopover: NSPopover?
    private var selectedGroupFilterIDs: Set<UUID> = []

    private var contactsScrollView: NSScrollView!
    private var favoritesScrollView: NSScrollView!
    private var historyScrollView: NSScrollView!
    private var lastContactsSearchString: String = ""
    private var lastFavoritesSearchString: String = ""
    private var lastHistorySearchString: String = ""
    
    private var addWindowController: AddContactWindowController?
    private var editWindowController: AddContactWindowController?
    
    private var plusButton: DialerKey?
    
    private var emptyContactsLabel: NSTextField!
    private var emptyFavoritesLabel: ClickableLabel!
    private var emptyHistoryLabel: NSTextField!
    private var contactsTitleLabel: NSTextField!
    private var favoritesTitleLabel: NSTextField!
    private var historyTitleLabel: NSTextField!

    private var callToastView: NSView?
    private var callToastHideWorkItem: DispatchWorkItem?
    private var callToastTopConstraint: NSLayoutConstraint?

    private var detailPanelView: ContactDetailPanelView!
    private var detailPanelWidthConstraint: NSLayoutConstraint!
    private var detailPanelSeparator: NSView!
    private static let detailPanelWidth: CGFloat = 300
    private var currentDetailPanelWidth: CGFloat = 300
    private var isDetailPanelOpen = false
    
    private var historySearchField: NSSearchField!

    private var privacyModeButton: NSButton!
    private var speedDialButton: NSButton!
    private var speedDialPopover: NSPopover?

    private var bellButton: NSButton!
    private var notificationsWindowController: NotificationsWindowController?

    func showContactsPublic()  { showContacts() }
    func showFavoritesPublic() { showFavorites() }
    func showHistoryPublic()   { showHistory() }
    func showDialerPublic()    { showDialer() }
    func openAddPublic()       { openAdd() }
    func focusSearchFieldPublic() { focusSearchField() }

    convenience init() {
        let window = NonFullScreenWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "HelloMac"
        window.titlebarAppearsTransparent = true
        window.center()
        
        window.appearance = NSAppearance(named: .darkAqua) 
        window.isReleasedWhenClosed = false
        window.backgroundColor = nil
        window.minSize = NSSize(width: 300, height: 580)
        window.maxSize = NSSize(width: 1200, height: 900)
        window.collectionBehavior = [.managed, .fullScreenNone]
        
        self.init(window: window)
        window.delegate = self
        setupUI()
        setupTitleBarAccessories()
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateUIVisibility(_:)), name: NSNotification.Name("UpdateUIVisibility"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateTitleBarAccessoryVisibility), name: .privacyModeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateTitleBarAccessoryVisibility), name: .speedDialSettingsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshBellButtonState), name: .reminderHistoryDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshBellButtonState), name: .remindersSettingsDidChange, object: nil)
        updateUIVisibility()
        updateTitleBarAccessoryVisibility()
        refreshBellButtonState()
        DispatchQueue.main.async {
            window.makeFirstResponder(nil)
        }
    }

    private func setupTitleBarAccessories() {
        let accessoryVC = NSTitlebarAccessoryViewController()
        accessoryVC.layoutAttribute = .right

        let eyeConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let eyeImg = NSImage(systemSymbolName: "eye.slash.fill", accessibilityDescription: L("privacy_mode_active_tooltip"))?
            .withSymbolConfiguration(eyeConfig)
        let eyeButton = NSButton(frame: NSRect(x: 0, y: 0, width: 26, height: 22))
        eyeButton.image = eyeImg
        eyeButton.imagePosition = .imageOnly
        eyeButton.isBordered = false
        eyeButton.bezelStyle = .regularSquare
        eyeButton.contentTintColor = NSColor(red: 1.0, green: 0.65, blue: 0.2, alpha: 1)
        eyeButton.toolTip = L("privacy_mode_active_tooltip")
        eyeButton.target = self
        eyeButton.action = #selector(privacyModeButtonTapped)
        eyeButton.translatesAutoresizingMaskIntoConstraints = false
        eyeButton.widthAnchor.constraint(equalToConstant: 26).isActive = true
        eyeButton.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let boltConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let boltImg = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: L("speed_dial_active_tooltip"))?
            .withSymbolConfiguration(boltConfig)
        let boltButton = NSButton(frame: NSRect(x: 0, y: 0, width: 26, height: 22))
        boltButton.image = boltImg
        boltButton.imagePosition = .imageOnly
        boltButton.isBordered = false
        boltButton.bezelStyle = .regularSquare
        boltButton.contentTintColor = NSColor.systemYellow
        boltButton.toolTip = L("speed_dial_active_tooltip")
        boltButton.target = self
        boltButton.action = #selector(speedDialButtonTapped)
        boltButton.translatesAutoresizingMaskIntoConstraints = false
        boltButton.widthAnchor.constraint(equalToConstant: 26).isActive = true
        boltButton.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let stack = NSStackView(views: [eyeButton, boltButton])
        stack.orientation = .horizontal
        stack.spacing = 0
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 60, height: 22))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        accessoryVC.view = container
        window?.addTitlebarAccessoryViewController(accessoryVC)
        privacyModeButton = eyeButton
        speedDialButton = boltButton
    }

    @objc private func updateTitleBarAccessoryVisibility() {
        let isDialerActive = currentActiveTabIdentifier == "circle.grid.3x3.fill"
        speedDialButton?.isHidden = !(isDialerActive && UserDefaults.standard.bool(forKey: "enableSpeedDial"))
        privacyModeButton?.isHidden = !PrivacyMode.shared.isEnabled
    }

    @objc private func privacyModeButtonTapped() {
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

        if let appWindow = self.window {
            alert.beginSheetModal(for: appWindow, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    @objc private func speedDialButtonTapped() {
        guard let button = speedDialButton else { return }
        presentSpeedDialPopover(relativeTo: button)
    }

    private func presentSpeedDialPopover(relativeTo view: NSView) {
        let vc = SpeedDialPickerPopoverViewController()
        vc.onNumberSelected = { [weak self] phone in
            self?.speedDialPopover?.close()
            guard let self = self else { return }
            if PrivacyMode.shared.isEnabled {
                PrivacyMode.shared.showBlockedAlert()
                return
            }
            self.makeCall(to: phone)
        }
        vc.onManageTapped = { [weak self] in
            self?.speedDialPopover?.close()
            (NSApp.delegate as? AppDelegate)?.showSettingsToSpeedDial()
        }
        let popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .semitransient
        popover.appearance = AccessibilityManager.shared.preferredWindowAppearance

        if let windowFrame = window?.frame {
            _ = vc.view
            let popoverWidth = max(vc.view.frame.width, 260)
            let margin: CGFloat = 8

            let buttonRectInWindow = view.convert(view.bounds, to: nil)
            let buttonOrigin = window!.convertPoint(toScreen: buttonRectInWindow.origin)
            let buttonFrameOnScreen = NSRect(origin: buttonOrigin, size: buttonRectInWindow.size)

            let windowMinXOnScreen = windowFrame.minX + margin
            let desiredMinXOnScreen = buttonFrameOnScreen.maxX - popoverWidth
            let anchorMinXOnScreen = max(windowMinXOnScreen, desiredMinXOnScreen)

            let anchorRect = NSRect(
                x: anchorMinXOnScreen - buttonFrameOnScreen.minX,
                y: 0,
                width: buttonFrameOnScreen.maxX - anchorMinXOnScreen,
                height: view.bounds.height
            )
            popover.show(relativeTo: anchorRect, of: view, preferredEdge: .maxY)
        } else {
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        }
        speedDialPopover = popover
    }

    private func setupUI() {
        guard let outerContentView = window?.contentView else { return }
        outerContentView.wantsLayer = true

        let mainContentView = NSView()
        mainContentView.translatesAutoresizingMaskIntoConstraints = false
        outerContentView.addSubview(mainContentView)

        detailPanelSeparator = NSView()
        detailPanelSeparator.wantsLayer = true
        detailPanelSeparator.layer?.backgroundColor = NSColor(white: 0.24, alpha: 1).cgColor
        detailPanelSeparator.translatesAutoresizingMaskIntoConstraints = false
        outerContentView.addSubview(detailPanelSeparator)

        detailPanelView = ContactDetailPanelView()
        detailPanelView.translatesAutoresizingMaskIntoConstraints = false
        detailPanelView.onClose = { [weak self] in self?.hideContactDetail() }
        detailPanelView.onCall = { [weak self] phone in self?.makeCall(to: phone) }
        detailPanelView.onFavoriteToggle = { [weak self] id in
            ContactStore.shared.toggleFavorite(id: id)
            self?.refreshDetailPanelIfShowing(id: id)
        }
        detailPanelView.onEdit = { [weak self] contact in
            self?.editWindowController = AddContactWindowController(contactToEdit: contact)
            self?.editWindowController?.showWindow(nil)
            self?.editWindowController?.window?.makeKeyAndOrderFront(nil)
        }
        detailPanelView.onDelete = { [weak self] contact in
            self?.deleteContact(contact)
        }
        detailPanelView.onAddToNewContact = { [weak self] phone in
            self?.editWindowController = AddContactWindowController(prefillPhone: phone)
            self?.editWindowController?.showWindow(nil)
            self?.editWindowController?.window?.makeKeyAndOrderFront(nil)
        }
        detailPanelView.onReminder = { [weak self] contact in
            self?.openReminderSetup(for: contact)
        }
        detailPanelView.jumpToContact = { [weak self] contactID in
            self?.showContactDetail(forContactID: contactID)
        }
        detailPanelView.onApplyGroupFilter = { [weak self] groupID in
            self?.applyGroupFilterFromDetail(groupID)
        }
        outerContentView.addSubview(detailPanelView)

        detailPanelWidthConstraint = detailPanelView.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            mainContentView.topAnchor.constraint(equalTo: outerContentView.topAnchor),
            mainContentView.bottomAnchor.constraint(equalTo: outerContentView.bottomAnchor),
            mainContentView.leadingAnchor.constraint(equalTo: outerContentView.leadingAnchor),
            mainContentView.trailingAnchor.constraint(equalTo: detailPanelSeparator.leadingAnchor),
            mainContentView.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),

            detailPanelSeparator.topAnchor.constraint(equalTo: outerContentView.topAnchor),
            detailPanelSeparator.bottomAnchor.constraint(equalTo: outerContentView.bottomAnchor),
            detailPanelSeparator.leadingAnchor.constraint(equalTo: mainContentView.trailingAnchor),
            detailPanelSeparator.widthAnchor.constraint(equalToConstant: 0.5),

            detailPanelView.topAnchor.constraint(equalTo: outerContentView.topAnchor),
            detailPanelView.bottomAnchor.constraint(equalTo: outerContentView.bottomAnchor),
            detailPanelView.leadingAnchor.constraint(equalTo: detailPanelSeparator.trailingAnchor),
            detailPanelView.trailingAnchor.constraint(equalTo: outerContentView.trailingAnchor),
            detailPanelWidthConstraint,
        ])

        let contentView = mainContentView

        let tabBar = NSVisualEffectView()
        tabBar.material = .underWindowBackground
        tabBar.blendingMode = .withinWindow
        tabBar.state = .active
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tabBar)

        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(white: 0.28, alpha: 1).cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sep)

        favoritesButton = makeTabButton(symbolName: "star.fill", title: L("favorites"), action: #selector(showFavorites))
        historyButton = makeTabButton(symbolName: "clock.fill", title: L("history"), action: #selector(showHistory))
        contactsButton = makeTabButton(symbolName: "person.2.fill", title: L("contacts"), action: #selector(showContacts))
        dialButton = makeTabButton(symbolName: "circle.grid.3x3.fill", title: L("keypad"), action: #selector(showDialer))

        let tabStack = NSStackView(views: [favoritesButton, historyButton, contactsButton, dialButton])
        tabStack.orientation = .horizontal
        tabStack.distribution = .equalSpacing
        tabStack.spacing = 20
        tabStack.alignment = .centerY
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        tabBar.addSubview(tabStack)

        contactsView = NSView()
        contactsView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contactsView)
        setupContactsView()

        favoritesView = NSView()
        favoritesView.translatesAutoresizingMaskIntoConstraints = false
        favoritesView.isHidden = true
        contentView.addSubview(favoritesView)
        setupFavoritesView()

        historyView = NSView()
        historyView.translatesAutoresizingMaskIntoConstraints = false
        historyView.isHidden = true
        contentView.addSubview(historyView)
        setupHistoryView()

        dialerView = KeyCaptureView()
        dialerView.keyDelegate = self
        dialerView.translatesAutoresizingMaskIntoConstraints = false
        dialerView.isHidden = true
        
        let pasteMenu = NSMenu()
        let pasteItem = NSMenuItem(title: L("paste"), action: #selector(pasteNumber), keyEquivalent: "")
        pasteItem.target = self
        pasteMenu.addItem(pasteItem)
        dialerView.menu = pasteMenu
        
        contentView.addSubview(dialerView)
        setupDialer()
        
        emptyStateView = NSView()
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.isHidden = true
        contentView.addSubview(emptyStateView)
        
        let warningIcon = NSImageView(image: NSImage(systemSymbolName: "eye.slash.fill", accessibilityDescription: nil) ?? NSImage())
        warningIcon.contentTintColor = NSColor(white: 0.4, alpha: 1)
        warningIcon.translatesAutoresizingMaskIntoConstraints = false
        
        let emptyLabel = NSTextField(labelWithString: L("all_features_disabled"))
        emptyLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 14)
        emptyLabel.textColor = NSColor(white: 0.6, alpha: 1)
        emptyLabel.alignment = .center
        emptyLabel.isEditable = false
        emptyLabel.isSelectable = false
        emptyLabel.isBezeled = false
        emptyLabel.drawsBackground = false
        emptyLabel.preferredMaxLayoutWidth = 312
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let openSettingsBtn = NSButton(title: L("enable_features_btn"), target: NSApp.delegate, action: Selector(("showSettingsToAppearance")))
        openSettingsBtn.bezelStyle = .rounded
        openSettingsBtn.translatesAutoresizingMaskIntoConstraints = false
        
        let emptyStack = NSStackView(views: [warningIcon, emptyLabel, openSettingsBtn])
        emptyStack.orientation = .vertical
        emptyStack.spacing = 16
        emptyStack.alignment = .centerX
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(emptyStack)

        NSLayoutConstraint.activate([
            tabBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            tabBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 60),

            sep.bottomAnchor.constraint(equalTo: tabBar.topAnchor),
            sep.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 0.5),

            tabStack.centerXAnchor.constraint(equalTo: tabBar.centerXAnchor),
            tabStack.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            tabStack.heightAnchor.constraint(equalTo: tabBar.heightAnchor),
            
            contactsButton.widthAnchor.constraint(equalToConstant: 65),
            contactsButton.heightAnchor.constraint(equalTo: tabStack.heightAnchor),
            favoritesButton.widthAnchor.constraint(equalToConstant: 65),
            favoritesButton.heightAnchor.constraint(equalTo: tabStack.heightAnchor),
            historyButton.widthAnchor.constraint(equalToConstant: 65),
            historyButton.heightAnchor.constraint(equalTo: tabStack.heightAnchor),
            dialButton.widthAnchor.constraint(equalToConstant: 65),
            dialButton.heightAnchor.constraint(equalTo: tabStack.heightAnchor),

            contactsView.topAnchor.constraint(equalTo: contentView.topAnchor),
            contactsView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contactsView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contactsView.bottomAnchor.constraint(equalTo: sep.topAnchor),

            favoritesView.topAnchor.constraint(equalTo: contentView.topAnchor),
            favoritesView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            favoritesView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            favoritesView.bottomAnchor.constraint(equalTo: sep.topAnchor),

            historyView.topAnchor.constraint(equalTo: contentView.topAnchor),
            historyView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            historyView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            historyView.bottomAnchor.constraint(equalTo: sep.topAnchor),

            dialerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            dialerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            dialerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            dialerView.bottomAnchor.constraint(equalTo: sep.topAnchor),
            
            emptyStateView.topAnchor.constraint(equalTo: contentView.topAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: sep.topAnchor),
            emptyStack.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor),
            warningIcon.widthAnchor.constraint(equalToConstant: 40),
            warningIcon.heightAnchor.constraint(equalToConstant: 32)
        ])

        if !UserDefaults.standard.bool(forKey: "hideFavoritesMenu") {
            showFavorites()
        } else if !UserDefaults.standard.bool(forKey: "hideHistoryMenu") {
            showHistory()
        } else if !UserDefaults.standard.bool(forKey: "hideContactsMenu") {
            showContacts()
        } else if !UserDefaults.standard.bool(forKey: "hideKeypadMenu") {
            showDialer()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleContactsDidChange(_:)), name: .contactsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAll), name: .privacyModeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshHistory), name: NSNotification.Name("historyDidChange"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshHistory), name: .appTimeZoneDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(groupsDidChange), name: .contactGroupsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyAccessibilityToWholeWindow), name: .accessibilitySettingsDidChange, object: nil)
        applyAccessibilityToWholeWindow()
    }

    @objc private func focusSearchField() {
        if !contactsView.isHidden && !contactsSearchField.isHidden {
            window?.makeFirstResponder(contactsSearchField)
        } else if !favoritesView.isHidden && !favoritesSearchField.isHidden {
            window?.makeFirstResponder(favoritesSearchField)
        } else if !historyView.isHidden && !historySearchField.isHidden {
            window?.makeFirstResponder(historySearchField)
        }
    }
    
    private func scrollToTop(_ scrollView: NSScrollView?) {
        guard let scrollView = scrollView, let documentView = scrollView.documentView else { return }
        let maxY = documentView.isFlipped ? 0 : max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func currentScrollOffsetFromTop(_ scrollView: NSScrollView?) -> CGFloat? {
        guard let scrollView = scrollView, let documentView = scrollView.documentView else { return nil }
        let visibleY = scrollView.contentView.bounds.origin.y
        if documentView.isFlipped {
            return visibleY
        } else {
            let maxY = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
            return maxY - visibleY
        }
    }

    private func restoreScrollOffsetFromTop(_ offset: CGFloat?, in scrollView: NSScrollView?) {
        guard let offset = offset, let scrollView = scrollView, let documentView = scrollView.documentView else { return }
        let clampedMaxOffset = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
        let clampedOffset = min(max(0, offset), clampedMaxOffset)
        let y: CGFloat = documentView.isFlipped ? clampedOffset : (clampedMaxOffset - clampedOffset)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    @objc private func refreshAll() {
        if isDetailPanelOpen, let id = currentDetailContactID,
           !ContactStore.shared.contacts.contains(where: { $0.id == id }) {
            hideContactDetail { [weak self] in
                self?.refreshContacts()
                self?.refreshFavorites()
                self?.refreshHistory()
            }
            return
        }
        refreshContacts()
        refreshFavorites()
        refreshHistory()
        syncDetailPanelAfterDataChange()
    }
    
    @objc private func handleContactsDidChange(_ notification: Notification) {
        let isFavoriteToggle = notification.userInfo?["isFavoriteToggle"] as? Bool ?? false
        
        if isDetailPanelOpen, let id = currentDetailContactID,
           !ContactStore.shared.contacts.contains(where: { $0.id == id }) {
            hideContactDetail { [weak self] in
                if !isFavoriteToggle { self?.refreshContacts() }
                self?.refreshFavorites()
                if !isFavoriteToggle { self?.refreshHistory() }
            }
            return
        }
        if !isFavoriteToggle {
            refreshContacts()
            refreshHistory()
        }
        refreshFavorites()
        syncDetailPanelAfterDataChange()
    }

    @objc private func applyAccessibilityToStaticLabels() {
        let a11y = AccessibilityManager.shared
        contactsTitleLabel?.font = a11y.adjustedFont(baseSize: 17, weight: .bold)
        favoritesTitleLabel?.font = a11y.adjustedFont(baseSize: 17, weight: .bold)
        historyTitleLabel?.font = a11y.adjustedFont(baseSize: 17, weight: .bold)
        emptyContactsLabel?.font = a11y.adjustedFont(baseSize: 13)
        emptyFavoritesLabel?.font = a11y.adjustedFont(baseSize: 13)
        emptyHistoryLabel?.font = a11y.adjustedFont(baseSize: 13)
    }

    @objc private func applyAccessibilityToWholeWindow() {
        applyAccessibilityToStaticLabels()
        guard let window = window else { return }
        let a11y = AccessibilityManager.shared
        a11y.applyPreferredAppearance(to: window)
        window.a11yBaseBackgroundColor = nil
        window.a11yHasCapturedBackgroundColor = true
        if a11y.isGrayscaleEnabled && a11y.isEffectivelyColorInverted {
            window.backgroundColor = .white
        } else if a11y.isGrayscaleEnabled {
            window.backgroundColor = .black
        } else {
            window.backgroundColor = nil
        }

        guard let contentView = window.contentView else { return }
        AccessibilityManager.shared.applyToViewTree(contentView)
        updateTabColors(active: currentActiveTabIdentifier)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateTabColors(active: self.currentActiveTabIdentifier)
        }
    }

    private func syncDetailPanelAfterDataChange() {
        guard isDetailPanelOpen else { return }
        if let id = currentDetailContactID {
            if let contact = ContactStore.shared.contacts.first(where: { $0.id == id }) {
                let history = HistoryStore.shared.records(forContactID: id, phone: contact.phone)
                detailPanelView.configure(contact: contact, history: history)
                resizeDetailPanelIfNeeded()
            } else {
                hideContactDetail()
            }
        } else if let phone = currentDetailUnknownPhone {
            let target = phone.sanitizedForCall
            if let contact = ContactStore.shared.contacts.first(where: { $0.phone.sanitizedForCall == target }) {
                showContactDetail(forContactID: contact.id)
            } else {
                let history = HistoryStore.shared.records(forPhone: phone)
                detailPanelView.configure(unknownPhone: phone, history: history)
                resizeDetailPanelIfNeeded()
            }
        }
    }

    private func resizeDetailPanelIfNeeded() {
        guard isDetailPanelOpen, let window = window else { return }
        let neededWidth = max(MainWindowController.detailPanelWidth, detailPanelView.requiredActionsWidth)
        guard abs(neededWidth - currentDetailPanelWidth) > 0.5 else { return }

        var frame = window.frame
        let delta = neededWidth - currentDetailPanelWidth
        frame.size.width += delta
        frame.origin.x -= delta / 2
        currentDetailPanelWidth = neededWidth
        detailPanelWidthConstraint.constant = neededWidth

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    private func setupContactsView() {
        let titleLabel = NSTextField(labelWithString: L("contacts"))
        titleLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 17, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contactsTitleLabel = titleLabel
        contactsView.addSubview(titleLabel)

        let addImg = NSImage(systemSymbolName: "person.badge.plus", accessibilityDescription: L("add_tooltip"))
        let addBtn = NSButton(image: addImg ?? NSImage(), target: self, action: #selector(openAdd))
        addBtn.bezelStyle = .regularSquare
        addBtn.isBordered = false
        addBtn.contentTintColor = NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        if let cell = addBtn.cell as? NSButtonCell { cell.imageScaling = .scaleProportionallyUpOrDown }
        contactsView.addSubview(addBtn)

        let bellBtn = NSButton(image: NSImage(systemSymbolName: "bell", accessibilityDescription: L("notifications_tooltip")) ?? NSImage(), target: self, action: #selector(openNotifications))
        bellBtn.bezelStyle = .regularSquare
        bellBtn.isBordered = false
        bellBtn.contentTintColor = NSColor.systemPurple
        bellBtn.translatesAutoresizingMaskIntoConstraints = false
        if let cell = bellBtn.cell as? NSButtonCell { cell.imageScaling = .scaleProportionallyUpOrDown }
        bellBtn.isHidden = UserDefaults.standard.bool(forKey: "hideGeneralReminderButton") || !ReminderManager.shared.isEnabled
        contactsView.addSubview(bellBtn)
        bellButton = bellBtn
        
        contactsSearchField = NSSearchField()
        contactsSearchField.placeholderString = L("search_placeholder")
        contactsSearchField.translatesAutoresizingMaskIntoConstraints = false
        contactsSearchField.delegate = self
        contactsView.addSubview(contactsSearchField)

        let groupFilterColor = NSColor(red: 0.2, green: 0.8, blue: 0.6, alpha: 1)

        let groupFilterImg = NSImage(systemSymbolName: "person.3", accessibilityDescription: L("groups_filter_tooltip"))
        let groupFilterBtn = NSButton(image: groupFilterImg ?? NSImage(), target: self, action: #selector(groupFilterIconTapped))
        groupFilterBtn.bezelStyle = .regularSquare
        groupFilterBtn.isBordered = false

        groupFilterBtn.contentTintColor = groupFilterColor
        groupFilterBtn.translatesAutoresizingMaskIntoConstraints = false

        if let cell = groupFilterBtn.cell as? NSButtonCell { cell.imageScaling = .scaleProportionallyUpOrDown }

        groupFilterBtn.wantsLayer = true
        groupFilterBtn.layer?.cornerRadius = 13
        groupFilterBtn.isHidden = true

        contactsView.addSubview(groupFilterBtn)
        contactsGroupFilterIconButton = groupFilterBtn

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay 
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        contactsView.addSubview(scrollView)
        contactsScrollView = scrollView

        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stackView

        emptyContactsLabel = NSTextField(labelWithString: L("no_contacts"))
        emptyContactsLabel.alignment = .center
        emptyContactsLabel.textColor = NSColor(white: 0.5, alpha: 1)
        emptyContactsLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 13)
        emptyContactsLabel.maximumNumberOfLines = 2
        emptyContactsLabel.isEditable = false
        emptyContactsLabel.isSelectable = false
        emptyContactsLabel.isBezeled = false
        emptyContactsLabel.drawsBackground = false
        emptyContactsLabel.preferredMaxLayoutWidth = 312
        emptyContactsLabel.translatesAutoresizingMaskIntoConstraints = false
        contactsView.addSubview(emptyContactsLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contactsView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contactsView.leadingAnchor, constant: 16),

            addBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            addBtn.trailingAnchor.constraint(equalTo: contactsView.trailingAnchor, constant: -14),
            addBtn.widthAnchor.constraint(equalToConstant: 26),
            addBtn.heightAnchor.constraint(equalToConstant: 26),

            bellBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            bellBtn.trailingAnchor.constraint(equalTo: addBtn.leadingAnchor, constant: -14),
            bellBtn.widthAnchor.constraint(equalToConstant: 26),
            bellBtn.heightAnchor.constraint(equalToConstant: 26),

            groupFilterBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            groupFilterBtn.trailingAnchor.constraint(equalTo: bellBtn.leadingAnchor, constant: -14),
            groupFilterBtn.widthAnchor.constraint(equalToConstant: 36),
            groupFilterBtn.heightAnchor.constraint(equalToConstant: 26),
            
            contactsSearchField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            contactsSearchField.leadingAnchor.constraint(equalTo: contactsView.leadingAnchor, constant: 16),
            contactsSearchField.trailingAnchor.constraint(equalTo: contactsView.trailingAnchor, constant: -16),

            scrollView.leadingAnchor.constraint(equalTo: contactsView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contactsView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contactsView.bottomAnchor),

            stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            
            emptyContactsLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyContactsLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor, constant: -20),
            emptyContactsLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contactsView.leadingAnchor, constant: 24),
            emptyContactsLabel.trailingAnchor.constraint(lessThanOrEqualTo: contactsView.trailingAnchor, constant: -24)
        ])

        scrollView.topAnchor.constraint(equalTo: contactsSearchField.bottomAnchor, constant: 8).isActive = true

        refreshGroupFilterVisibility()
        refreshContacts()
    }

    private func setupFavoritesView() {
        let titleLabel = NSTextField(labelWithString: L("favorites"))
        titleLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 17, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        favoritesTitleLabel = titleLabel
        favoritesView.addSubview(titleLabel)
        
        favoritesSearchField = NSSearchField()
        favoritesSearchField.placeholderString = L("search_placeholder")
        favoritesSearchField.translatesAutoresizingMaskIntoConstraints = false
        favoritesSearchField.delegate = self
        favoritesView.addSubview(favoritesSearchField)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        favoritesView.addSubview(scrollView)
        favoritesScrollView = scrollView

        favoritesStackView = FavoritesDropStackView()
        favoritesStackView.orientation = .vertical
        favoritesStackView.spacing = 0
        favoritesStackView.translatesAutoresizingMaskIntoConstraints = false
        favoritesStackView.onReorder = { [weak self] orderedIDs in
            ContactStore.shared.reorderFavorites(orderedIDs: orderedIDs)
            self?.refreshFavorites()
        }
        scrollView.documentView = favoritesStackView

        emptyFavoritesLabel = ClickableLabel(labelWithString: L("no_favorites"))
        emptyFavoritesLabel.alignment = .center
        emptyFavoritesLabel.textColor = NSColor(white: 0.5, alpha: 1)
        emptyFavoritesLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 13)
        emptyFavoritesLabel.maximumNumberOfLines = 2
        emptyFavoritesLabel.isEditable = false
        emptyFavoritesLabel.isSelectable = false
        emptyFavoritesLabel.isBezeled = false
        emptyFavoritesLabel.drawsBackground = false
        emptyFavoritesLabel.preferredMaxLayoutWidth = 312
        emptyFavoritesLabel.translatesAutoresizingMaskIntoConstraints = false
        let click = NSClickGestureRecognizer(target: self, action: #selector(emptyFavoritesClicked(_:)))
        emptyFavoritesLabel.addGestureRecognizer(click)
        favoritesView.addSubview(emptyFavoritesLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: favoritesView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: favoritesView.leadingAnchor, constant: 16),
            
            favoritesSearchField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            favoritesSearchField.leadingAnchor.constraint(equalTo: favoritesView.leadingAnchor, constant: 16),
            favoritesSearchField.trailingAnchor.constraint(equalTo: favoritesView.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: favoritesSearchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: favoritesView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: favoritesView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: favoritesView.bottomAnchor),

            favoritesStackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            
            emptyFavoritesLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyFavoritesLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor, constant: -20),
            emptyFavoritesLabel.leadingAnchor.constraint(greaterThanOrEqualTo: favoritesView.leadingAnchor, constant: 24),
            emptyFavoritesLabel.trailingAnchor.constraint(lessThanOrEqualTo: favoritesView.trailingAnchor, constant: -24)
        ])

        refreshFavorites()
    }
    
    private func setupHistoryView() {
    let titleLabel = NSTextField(labelWithString: L("history"))
    titleLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 17, weight: .bold)
    titleLabel.textColor = .white
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    self.historyTitleLabel = titleLabel
    historyView.addSubview(titleLabel)

    let clearImg = NSImage(systemSymbolName: "trash", accessibilityDescription: L("clear_history"))
    let clearBtn = NSButton(image: clearImg ?? NSImage(), target: self, action: #selector(clearHistory))
    clearBtn.bezelStyle = .regularSquare
    clearBtn.isBordered = false
    clearBtn.contentTintColor = NSColor.systemRed
    clearBtn.translatesAutoresizingMaskIntoConstraints = false
    if let cell = clearBtn.cell as? NSButtonCell { cell.imageScaling = .scaleProportionallyUpOrDown }
    historyView.addSubview(clearBtn)
    
    historySearchField = NSSearchField()
    historySearchField.placeholderString = L("search_placeholder")
    historySearchField.translatesAutoresizingMaskIntoConstraints = false
    historySearchField.delegate = self
    historyView.addSubview(historySearchField)

    let scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    historyView.addSubview(scrollView)
    historyScrollView = scrollView

    historyStackView = NSStackView()
    historyStackView.orientation = .vertical
    historyStackView.spacing = 0
    historyStackView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.documentView = historyStackView

    emptyHistoryLabel = NSTextField(labelWithString: L("no_history"))
    emptyHistoryLabel.alignment = .center
    emptyHistoryLabel.textColor = NSColor(white: 0.5, alpha: 1)
    emptyHistoryLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 13)
    emptyHistoryLabel.maximumNumberOfLines = 2
    emptyHistoryLabel.isEditable = false
    emptyHistoryLabel.isSelectable = false
    emptyHistoryLabel.isBezeled = false
    emptyHistoryLabel.drawsBackground = false
    emptyHistoryLabel.preferredMaxLayoutWidth = 312
    emptyHistoryLabel.translatesAutoresizingMaskIntoConstraints = false
    historyView.addSubview(emptyHistoryLabel)

    NSLayoutConstraint.activate([
        titleLabel.topAnchor.constraint(equalTo: historyView.topAnchor, constant: 16),
        titleLabel.leadingAnchor.constraint(equalTo: historyView.leadingAnchor, constant: 16),
        
        clearBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        clearBtn.trailingAnchor.constraint(equalTo: historyView.trailingAnchor, constant: -14),
        clearBtn.widthAnchor.constraint(equalToConstant: 26),
        clearBtn.heightAnchor.constraint(equalToConstant: 26),
        
        historySearchField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
        historySearchField.leadingAnchor.constraint(equalTo: historyView.leadingAnchor, constant: 16),
        historySearchField.trailingAnchor.constraint(equalTo: historyView.trailingAnchor, constant: -16),

        scrollView.topAnchor.constraint(equalTo: historySearchField.bottomAnchor, constant: 8),
        scrollView.leadingAnchor.constraint(equalTo: historyView.leadingAnchor),
        scrollView.trailingAnchor.constraint(equalTo: historyView.trailingAnchor),
        scrollView.bottomAnchor.constraint(equalTo: historyView.bottomAnchor),

        historyStackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        
        emptyHistoryLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
        emptyHistoryLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor, constant: -20),
        emptyHistoryLabel.leadingAnchor.constraint(greaterThanOrEqualTo: historyView.leadingAnchor, constant: 24),
        emptyHistoryLabel.trailingAnchor.constraint(lessThanOrEqualTo: historyView.trailingAnchor, constant: -24)
    ])

    refreshHistory()
}

    @objc private func emptyFavoritesClicked(_ gesture: NSClickGestureRecognizer) {
        guard !emptyFavoritesLabel.isHidden, !favoritesSearchField.stringValue.isEmpty else { return }
        showContacts()
        if !favoritesSearchField.stringValue.isEmpty {
            contactsSearchField.stringValue = favoritesSearchField.stringValue
            refreshContacts()
        }
    }

    private func setFavoritesEmptySearchText() {
        let text = L("no_favorites_search")
        let linkWord = L("contacts") 
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let attrStr = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor(white: 0.5, alpha: 1),
            .paragraphStyle: paragraphStyle
        ])
        
        if let range = text.range(of: linkWord) {
            let nsRange = NSRange(range, in: text)
            attrStr.addAttributes([
                .foregroundColor: NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
            ], range: nsRange)
        }
        
        emptyFavoritesLabel.attributedStringValue = attrStr
    }

    private func setupDialer() {
        let centerWrapper = NSView()
        centerWrapper.translatesAutoresizingMaskIntoConstraints = false
        dialerView.addSubview(centerWrapper)

        NSLayoutConstraint.activate([
            centerWrapper.leadingAnchor.constraint(equalTo: dialerView.leadingAnchor),
            centerWrapper.trailingAnchor.constraint(equalTo: dialerView.trailingAnchor),
            centerWrapper.centerYAnchor.constraint(equalTo: dialerView.centerYAnchor),
            centerWrapper.topAnchor.constraint(greaterThanOrEqualTo: dialerView.topAnchor, constant: 8),
            centerWrapper.bottomAnchor.constraint(lessThanOrEqualTo: dialerView.bottomAnchor, constant: -8),
        ])

        displayLabel = NSTextField(labelWithString: "")
        displayLabel.font = NSFont.systemFont(ofSize: 44, weight: .thin)
        displayLabel.textColor = .white
        displayLabel.alignment = .left
        displayLabel.translatesAutoresizingMaskIntoConstraints = false
        displayLabel.lineBreakMode = .byClipping
        displayLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        displayLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        centerWrapper.addSubview(displayLabel)

        let deleteImg = NSImage(systemSymbolName: "delete.left", accessibilityDescription: L("remove_tooltip"))
        let deleteBtn = NSButton(image: deleteImg ?? NSImage(), target: self, action: #selector(deleteLast))
        deleteBtn.bezelStyle = .regularSquare
        deleteBtn.isBordered = false
        deleteBtn.contentTintColor = NSColor(white: 0.65, alpha: 1)
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        if let cell = deleteBtn.cell as? NSButtonCell { cell.imageScaling = .scaleProportionallyUpOrDown }
        centerWrapper.addSubview(deleteBtn)

        let keys: [String] = [
            "1", "2", "3",
            "4", "5", "6",
            "7", "8", "9",
            "+", "0", ""
        ]

        let gridStack = NSStackView()
        gridStack.orientation = .vertical
        gridStack.spacing = 14
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        centerWrapper.addSubview(gridStack)

        for row in 0..<4 {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.spacing = 20
            rowStack.distribution = .fillEqually
            for col in 0..<3 {
                let idx = row * 3 + col
                let digit = keys[idx]
                
                if digit.isEmpty {
                    let dummy = NSView()
                    dummy.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        dummy.widthAnchor.constraint(equalToConstant: 64),
                        dummy.heightAnchor.constraint(equalToConstant: 64)
                    ])
                    rowStack.addArrangedSubview(dummy)
                } else if digit == "+" {
                    let wrapper = NSView()
                    wrapper.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        wrapper.widthAnchor.constraint(equalToConstant: 64),
                        wrapper.heightAnchor.constraint(equalToConstant: 64)
                    ])
                    let btn = DialerKey(digit: digit, target: self, action: #selector(keyPressed(_:)))
                    btn.translatesAutoresizingMaskIntoConstraints = false
                    wrapper.addSubview(btn)
                    NSLayoutConstraint.activate([
                        btn.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                        btn.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
                        btn.widthAnchor.constraint(equalTo: wrapper.widthAnchor),
                        btn.heightAnchor.constraint(equalTo: wrapper.heightAnchor)
                    ])
                    self.plusButton = btn
                    btn.isHidden = UserDefaults.standard.bool(forKey: "hidePlusButton")
                    rowStack.addArrangedSubview(wrapper)
                } else {
                    let btn = DialerKey(digit: digit, target: self, action: #selector(keyPressed(_:)))
                    rowStack.addArrangedSubview(btn)
                }
            }
            gridStack.addArrangedSubview(rowStack)
        }

        let callBtn = NSButton(title: "", target: self, action: #selector(dialNumber))
        callBtn.bezelStyle = .regularSquare
        callBtn.isBordered = false
        callBtn.wantsLayer = true
        callBtn.layer?.backgroundColor = NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1).cgColor
        callBtn.layer?.cornerRadius = 34
        callBtn.translatesAutoresizingMaskIntoConstraints = false
        
        let baseImg = NSImage(systemSymbolName: "phone.fill", accessibilityDescription: L("call_tooltip"))
        let callSymbolConfig = NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        let callImg = baseImg?.withSymbolConfiguration(callSymbolConfig)
        
        let callIconView = NSImageView(image: callImg ?? NSImage())
        callIconView.imageScaling = .scaleProportionallyUpOrDown
        callIconView.contentTintColor = .white
        callIconView.translatesAutoresizingMaskIntoConstraints = false
        callBtn.addSubview(callIconView)
        NSLayoutConstraint.activate([
            callIconView.centerXAnchor.constraint(equalTo: callBtn.centerXAnchor),
            callIconView.centerYAnchor.constraint(equalTo: callBtn.centerYAnchor),
            callIconView.widthAnchor.constraint(equalToConstant: 32),
            callIconView.heightAnchor.constraint(equalToConstant: 32),
        ])
        centerWrapper.addSubview(callBtn)

        NSLayoutConstraint.activate([
            displayLabel.topAnchor.constraint(equalTo: centerWrapper.topAnchor),
            displayLabel.leadingAnchor.constraint(equalTo: centerWrapper.leadingAnchor, constant: 20),
            displayLabel.trailingAnchor.constraint(equalTo: centerWrapper.trailingAnchor, constant: -52),
            displayLabel.heightAnchor.constraint(equalToConstant: 58),

            deleteBtn.centerYAnchor.constraint(equalTo: displayLabel.centerYAnchor),
            deleteBtn.trailingAnchor.constraint(equalTo: centerWrapper.trailingAnchor, constant: -16),
            deleteBtn.widthAnchor.constraint(equalToConstant: 34),
            deleteBtn.heightAnchor.constraint(equalToConstant: 34),

            gridStack.topAnchor.constraint(equalTo: displayLabel.bottomAnchor, constant: 14),
            gridStack.leadingAnchor.constraint(equalTo: centerWrapper.leadingAnchor, constant: 24),
            gridStack.trailingAnchor.constraint(equalTo: centerWrapper.trailingAnchor, constant: -24),

            callBtn.topAnchor.constraint(equalTo: gridStack.bottomAnchor, constant: 16),
            callBtn.centerXAnchor.constraint(equalTo: centerWrapper.centerXAnchor),
            callBtn.widthAnchor.constraint(equalToConstant: 68),
            callBtn.heightAnchor.constraint(equalToConstant: 68),
            callBtn.bottomAnchor.constraint(equalTo: centerWrapper.bottomAnchor),
        ])
    }

    private func makeTabButton(symbolName: String, title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: "", target: self, action: action)
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        btn.translatesAutoresizingMaskIntoConstraints = false

        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        let imgView = NSImageView(image: img ?? NSImage())
        imgView.contentTintColor = NSColor(white: 0.5, alpha: 1)
        imgView.translatesAutoresizingMaskIntoConstraints = false
        imgView.widthAnchor.constraint(equalToConstant: 20).isActive = true
        imgView.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let lbl = NSTextField(labelWithString: title)
        lbl.font = NSFont.systemFont(ofSize: 10)
        lbl.textColor = NSColor(white: 0.5, alpha: 1)

        let stack = NSStackView(views: [imgView, lbl])
        stack.orientation = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false
        stack.identifier = a11ySelfManagedIdentifier

        btn.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: btn.centerYAnchor),
        ])

        btn.identifier = NSUserInterfaceItemIdentifier(symbolName)
        return btn
    }

    @objc func showContacts() {
        let hideContacts = UserDefaults.standard.bool(forKey: "hideContactsMenu")
        guard !hideContacts else { return }
        hideContactDetail()
        contactsView.isHidden = false
        favoritesView.isHidden = true
        historyView.isHidden = true
        dialerView.isHidden = true
        emptyStateView.isHidden = true
        updateTabColors(active: "person.2.fill")
        window?.makeFirstResponder(nil)
        repositionCallToast()
    }

    @objc func showFavorites() {
        let hideFavorites = UserDefaults.standard.bool(forKey: "hideFavoritesMenu")
        guard !hideFavorites else { return }
        contactsView.isHidden = true
        favoritesView.isHidden = false
        historyView.isHidden = true
        dialerView.isHidden = true
        emptyStateView.isHidden = true
        hideContactDetail { [weak self] in self?.refreshFavorites() }
        updateTabColors(active: "star.fill")
        window?.makeFirstResponder(nil)
        repositionCallToast()
    }

    @objc func showHistory() {
        let hideHistory = UserDefaults.standard.bool(forKey: "hideHistoryMenu")
        guard !hideHistory else { return }
        contactsView.isHidden = true
        favoritesView.isHidden = true
        historyView.isHidden = false
        dialerView.isHidden = true
        emptyStateView.isHidden = true
        hideContactDetail { [weak self] in self?.refreshHistory() }
        updateTabColors(active: "clock.fill")
        window?.makeFirstResponder(nil)
        repositionCallToast()
    }

    @objc func showDialer() {
        let hideKeypad = UserDefaults.standard.bool(forKey: "hideKeypadMenu")
        guard !hideKeypad else { return }
        hideContactDetail()
        contactsView.isHidden = true
        favoritesView.isHidden = true
        historyView.isHidden = true
        dialerView.isHidden = false
        emptyStateView.isHidden = true
        updateTabColors(active: "circle.grid.3x3.fill")
        window?.makeFirstResponder(dialerView)
        repositionCallToast()
    }

    private func updateTabColors(active: String) {
        currentActiveTabIdentifier = active
        let a11y = AccessibilityManager.shared
        let blue = a11y.isGrayscaleEnabled
            ? NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1).desaturated()
            : NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
        let gray = a11y.adjustedColor(NSColor(white: 0.5, alpha: 1))
        for btn in [contactsButton, favoritesButton, historyButton, dialButton] {
            guard let btn = btn else { continue }
            let isActive = btn.identifier?.rawValue == active
            let color = isActive ? blue : gray
            for sub in btn.subviews {
                if let stack = sub as? NSStackView {
                    for view in stack.arrangedSubviews {
                        if let iv = view as? NSImageView { iv.contentTintColor = color }
                        if let lbl = view as? NSTextField { lbl.textColor = color }
                    }
                }
            }
        }
        updateTitleBarAccessoryVisibility()
    }

    @objc func keyPressed(_ sender: DialerKey) {
        if let firstChar = sender.digit.first {
            DialerSound.playAppKeypadSoundIfEnabled(digit: firstChar)
        }
        if displayLabel.stringValue.count < 20 { // Όριο 20 ψηφία
            displayLabel.stringValue += sender.digit
            updateDisplayFont()
        }
    }

    func keyCaptureDidType(digit: String) {
        if let firstChar = digit.first {
            DialerSound.playAppKeypadSoundIfEnabled(digit: firstChar)
        }
        if displayLabel.stringValue.count < 20 { // Όριο 20 ψηφία
            displayLabel.stringValue += digit
            updateDisplayFont()
        }
    }

    func keyCaptureDidBackspace() {
        deleteLast()
    }

    func keyCaptureDidPressEnter() {
        dialNumber()
    }
    
    func keyCaptureDidPaste() {
        pasteNumber()
    }

    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSSearchField {
            if field.stringValue.count > 50 {
                field.stringValue = String(field.stringValue.prefix(50))
            }
        
            if field == contactsSearchField {
                refreshContacts()
            } else if field == favoritesSearchField {
                refreshFavorites()
            } else if field == historySearchField {
                refreshHistory()
            }
        }
    }

    private var customFieldEditor: CleanFieldEditor?
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        if customFieldEditor == nil {
            customFieldEditor = CleanFieldEditor()
            customFieldEditor?.isFieldEditor = true
        }
        return customFieldEditor
    }

    @objc func deleteLast() {
        let s = displayLabel.stringValue
        if !s.isEmpty {
            displayLabel.stringValue = String(s.dropLast())
            updateDisplayFont()
        }
    }

    private func updateDisplayFont() {
        let count = displayLabel.stringValue.count
        let size: CGFloat
        switch count {
        case 0...11:  size = 44
        case 12...14: size = 36
        case 15...18: size = 28
        default:      size = 22
        }
        displayLabel.font = NSFont.systemFont(ofSize: size, weight: .thin)
    }

    @objc func dialNumber() {
        let number = displayLabel.stringValue.trimmingCharacters(in: .whitespaces)
        guard !number.isEmpty else { return }
        
        if UserDefaults.standard.bool(forKey: "enableSpeedDial"), number.count == 1 {
            if let num = Int(number), num >= 1, num <= 9 {
                if let target = UserDefaults.standard.string(forKey: "SpeedDial_\(num)"), !target.isEmpty {
                    guard !target.sanitizedForCall.isEmpty else {
                        makeCall(to: number)
                        return
                    }
                    if PrivacyMode.shared.isEnabled {
                        PrivacyMode.shared.showBlockedAlert()
                        return
                    }
                    makeCall(to: target)
                    displayLabel.stringValue = ""
                    updateDisplayFont()
                    return
                }
            }
        }
        
        makeCall(to: number)
    }
    
    @objc func pasteNumber() {
        if let pastedString = NSPasteboard.general.string(forType: .string) {
            let sanitized = pastedString.sanitizedForCall
        
            let currentCount = displayLabel.stringValue.count
            let allowedCount = max(0, 20 - currentCount) 
        
            displayLabel.stringValue += String(sanitized.prefix(allowedCount))
            updateDisplayFont()
        }
    }

    @objc func refreshGroupFilterVisibility() {
        guard let iconButton = contactsGroupFilterIconButton else { return }
        let groups = ContactGroupStore.shared.sortedGroups

        let shouldShow = ContactGroupStore.shared.isEnabled
        iconButton.isHidden = !shouldShow

        selectedGroupFilterIDs = Set(selectedGroupFilterIDs.filter { id in groups.contains(where: { $0.id == id }) })
        
        if !shouldShow {
            selectedGroupFilterIDs.removeAll()
        }

        let isActive = shouldShow && !selectedGroupFilterIDs.isEmpty
        let symbolName = isActive ? "person.3.fill" : "person.3"
        let groupFilterColor = NSColor(red: 0.2, green: 0.8, blue: 0.6, alpha: 1)
        iconButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: L("groups_filter_tooltip"))
        iconButton.contentTintColor = groupFilterColor

        updateSearchPlaceholder()
    }
    
    private func updateSearchPlaceholder() {
        guard let field = contactsSearchField else { return }
        if selectedGroupFilterIDs.isEmpty {
            field.placeholderString = L("search_placeholder")
        } else if selectedGroupFilterIDs.count == 1,
                  let firstID = selectedGroupFilterIDs.first,
                  let group = ContactGroupStore.shared.group(withID: firstID) {
            let displayName = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(group.name) : group.name
            field.placeholderString = L("search_in_group_placeholder", displayName)
        } else {
            field.placeholderString = L("search_in_selected_groups")
        }
    }

    @objc private func groupFilterIconTapped() {
        guard let button = contactsGroupFilterIconButton else { return }
        presentGroupFilterPickerPopover(relativeTo: button)
    }

    private func presentGroupFilterPickerPopover(relativeTo view: NSView) {
        let groups = ContactGroupStore.shared.sortedGroups
        let vc = GroupFilterPickerPopoverViewController(groups: groups, selectedGroupIDs: selectedGroupFilterIDs)
        vc.presentingWindow = self.window
        vc.onSelectionChanged = { [weak self] newSelection, didSelectAll in
            self?.selectedGroupFilterIDs = newSelection
            self?.refreshGroupFilterVisibility()
            self?.refreshContacts()
            if didSelectAll {
                self?.groupFilterPopover?.close()
            }
        }
        vc.onManageGroupsTapped = { [weak self] in
            self?.groupFilterPopover?.close()
            (NSApp.delegate as? AppDelegate)?.showSettingsToGroups()
        }
        let popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .semitransient
        popover.appearance = AccessibilityManager.shared.preferredWindowAppearance
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        groupFilterPopover = popover
    }
    
    func applyGroupFilterFromDetail(_ groupID: UUID) {
        showContacts()
        selectedGroupFilterIDs = [groupID]
        refreshGroupFilterVisibility()
        refreshContacts()
    }

    @objc private func groupsDidChange() {
        let oldSelection = selectedGroupFilterIDs
        refreshGroupFilterVisibility()
        if oldSelection != selectedGroupFilterIDs {
            refreshContacts()
        }
        
        syncDetailPanelAfterDataChange()
    }

    @objc func refreshContacts() {
        let searchString = contactsSearchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        let searchChanged = searchString != lastContactsSearchString
        lastContactsSearchString = searchString
        let preservedOffset = searchChanged ? nil : currentScrollOffsetFromTop(contactsScrollView)

        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var allContacts = ContactStore.shared.contacts

        if PrivacyMode.shared.isEnabled && !searchString.isEmpty {
            emptyContactsLabel.stringValue = L("privacy_mode_search_disabled")
            emptyContactsLabel.isHidden = false
            return
        }

        let isGroupFilterActive = ContactGroupStore.shared.isEnabled && !selectedGroupFilterIDs.isEmpty

        if ContactGroupStore.shared.isEnabled, !selectedGroupFilterIDs.isEmpty {
            allContacts = allContacts.filter { contact in
                !selectedGroupFilterIDs.isDisjoint(with: contact.groupIDs)
            }
        }
        
        let filtered = (searchString.isEmpty ? allContacts : allContacts.filter {
            $0.fullName.lowercased().contains(searchString) || $0.phone.contains(searchString)
        }).sorted {
            $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending
        }
        
        if allContacts.isEmpty {
            if isGroupFilterActive {
                if selectedGroupFilterIDs.count == 1,
                   let groupID = selectedGroupFilterIDs.first,
                   let group = ContactGroupStore.shared.group(withID: groupID) {
                    let displayName = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(group.name) : group.name
                    emptyContactsLabel.stringValue = L("no_group_filter_results_single", displayName)
                } else {
                    emptyContactsLabel.stringValue = L("no_group_filter_results_multiple")
                }
            } else {
                emptyContactsLabel.stringValue = L("no_contacts")
            }
            emptyContactsLabel.isHidden = false
        } else if filtered.isEmpty {
            emptyContactsLabel.stringValue = L("no_search_results")
            emptyContactsLabel.isHidden = false
        } else {
            emptyContactsLabel.isHidden = true
        }
        
        RoundAvatarView.resetColorSequence()
        for contact in filtered {
            let row = ContactRow(contact: contact, target: self, action: #selector(callRow(_:)), favoriteAction: #selector(toggleFavoriteRow(_:)), editAction: #selector(editContactRow(_:)), deleteAction: #selector(deleteContactRow(_:)), detailAction: #selector(showContactDetail(_:)))
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: 58).isActive = true
        }
        AccessibilityManager.shared.applyToViewTree(stackView)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if searchChanged {
                self.scrollToTop(self.contactsScrollView)
            } else {
                self.restoreScrollOffsetFromTop(preservedOffset, in: self.contactsScrollView)
            }
        }
    }

    @objc func refreshFavorites() {
        let searchString = favoritesSearchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        let searchChanged = searchString != lastFavoritesSearchString
        lastFavoritesSearchString = searchString
        let preservedOffset = searchChanged ? nil : currentScrollOffsetFromTop(favoritesScrollView)

        favoritesStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let allFavorites = ContactStore.shared.favorites

        if PrivacyMode.shared.isEnabled && !searchString.isEmpty {
            emptyFavoritesLabel.stringValue = L("privacy_mode_search_disabled")
            emptyFavoritesLabel.isLinkActive = false
            emptyFavoritesLabel.isHidden = false
            return
        }
        
        let filtered = (searchString.isEmpty ? allFavorites : allFavorites.filter {
            $0.fullName.lowercased().contains(searchString) || $0.phone.contains(searchString)
        }).sorted {
            switch ($0.favoriteSortIndex, $1.favoriteSortIndex) {
            case let (lhs?, rhs?):
                return lhs < rhs
            case (nil, nil):
                break
            case (nil, _):
                return false
            case (_, nil):
                return true
            }
            switch ($0.favoritedAt, $1.favoritedAt) {
            case let (lhs?, rhs?):
                return lhs > rhs
            case (nil, nil):
                return false
            case (nil, _):
                return false
            case (_, nil):
                return true
            }
        }
        
        if allFavorites.isEmpty {
            emptyFavoritesLabel.stringValue = L("no_favorites")
            emptyFavoritesLabel.isLinkActive = false
            emptyFavoritesLabel.isHidden = false
        } else if filtered.isEmpty {
            setFavoritesEmptySearchText()
            emptyFavoritesLabel.isLinkActive = true 
            emptyFavoritesLabel.isHidden = false
        } else {
            emptyFavoritesLabel.isLinkActive = false
            emptyFavoritesLabel.isHidden = true
        }
        
        RoundAvatarView.resetColorSequence()
        for contact in filtered {
            let row = ContactRow(contact: contact, target: self, action: #selector(callRow(_:)), favoriteAction: #selector(toggleFavoriteRow(_:)), editAction: #selector(editContactRow(_:)), deleteAction: #selector(deleteContactRow(_:)), detailAction: #selector(showContactDetail(_:)), isDraggable: searchString.isEmpty)
            favoritesStackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: favoritesStackView.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: 58).isActive = true
        }
        AccessibilityManager.shared.applyToViewTree(favoritesStackView)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if searchChanged {
                self.scrollToTop(self.favoritesScrollView)
            } else {
                self.restoreScrollOffsetFromTop(preservedOffset, in: self.favoritesScrollView)
            }
        }
    }

    @objc func refreshHistory() {
        historyStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let allRecords = HistoryStore.shared.records
        let searchString = historySearchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()

        if PrivacyMode.shared.isEnabled && !searchString.isEmpty {
            emptyHistoryLabel.stringValue = L("privacy_mode_search_disabled")
            emptyHistoryLabel.isHidden = false
            return
        }
    
        let filtered = searchString.isEmpty ? allRecords : allRecords.filter { record in
            let liveName = HistoryRow.resolveContact(for: record)?.fullName ?? record.contactName
            let nameMatch = liveName?.lowercased().contains(searchString) ?? false
            let phoneMatch = record.phone.contains(searchString)
            return nameMatch || phoneMatch
        }
    
        if allRecords.isEmpty {
            emptyHistoryLabel.stringValue = L("no_history")
            emptyHistoryLabel.isHidden = false
        } else if filtered.isEmpty {
            emptyHistoryLabel.stringValue = L("no_search_results")
            emptyHistoryLabel.isHidden = false
        } else {
            emptyHistoryLabel.isHidden = true
            for record in filtered {
                let row = HistoryRow(record: record, target: self, action: #selector(callHistoryRow(_:)), avatarStyle: .contactPhoto, optionsAction: #selector(showHistoryRowOptions(_:)))
                historyStackView.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: historyStackView.widthAnchor).isActive = true
                row.heightAnchor.constraint(equalToConstant: 58).isActive = true
            }
        }
        DispatchQueue.main.async { [weak self] in self?.scrollToTop(self?.historyScrollView) }
        AccessibilityManager.shared.applyToViewTree(historyStackView)
        syncDetailPanelAfterDataChange()
    }

    @objc func callRow(_ sender: ContactRow) {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        makeCall(to: sender.phone)
    }

    @objc func callHistoryRow(_ sender: HistoryRow) {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        makeCall(to: sender.phone)
    }

    @objc func showHistoryRowOptions(_ sender: HistoryRow) {
        if let contactID = sender.contactID,
           let contact = ContactStore.shared.contacts.first(where: { $0.id == contactID }) {
            showContactDetail(forContactID: contact.id)
        } else {
            showContactDetail(forUnknownPhone: sender.phone)
        }
    }

    @objc func clearHistory() {
        guard !HistoryStore.shared.records.isEmpty else { return }
        let alert = NSAlert()
        AccessibilityManager.shared.applyAccessibility(to: alert)
        alert.messageText = L("clear_history_alert_title")
        alert.informativeText = L("clear_history_alert_text")
        alert.addButton(withTitle: L("clear_history"))
        alert.addButton(withTitle: L("cancel_btn"))
        alert.buttons[0].hasDestructiveAction = true

        alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance

        if let appWindow = self.window {
            alert.beginSheetModal(for: appWindow) { response in
                guard response == .alertFirstButtonReturn else { return }
                if PrivacyMode.shared.isEnabled {
                    PrivacyMode.shared.showBlockedAlert()
                    return
                }
                HistoryStore.shared.clear()
            }
        } else {
            if alert.runModal() == .alertFirstButtonReturn {
                if PrivacyMode.shared.isEnabled {
                    PrivacyMode.shared.showBlockedAlert()
                    return
                }
                HistoryStore.shared.clear()
            }
        }
    }

    @objc func toggleFavoriteRow(_ sender: ContactRow) {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        ContactStore.shared.toggleFavorite(id: sender.contactID)
    }
    
    private var currentDetailContactID: UUID?
    private var currentDetailUnknownPhone: String?

    @objc func showContactDetail(_ sender: ContactRow) {
        showContactDetail(forContactID: sender.contactID)
    }

    func showContactDetail(forContactID contactID: UUID) {

        if isDetailPanelOpen && currentDetailContactID == contactID {
            hideContactDetail()
            return
        }
        guard let contact = ContactStore.shared.contacts.first(where: { $0.id == contactID }) else { return }
        currentDetailContactID = contact.id
        currentDetailUnknownPhone = nil
        let history = HistoryStore.shared.records(forContactID: contact.id, phone: contact.phone)
        detailPanelView.configure(contact: contact, history: history)
        AccessibilityManager.shared.applyToViewTree(detailPanelView)
        openDetailPanelIfNeeded()
    }

    func showContactDetail(forUnknownPhone phone: String) {
        if isDetailPanelOpen && currentDetailUnknownPhone == phone {
            hideContactDetail()
            return
        }
        currentDetailContactID = nil
        currentDetailUnknownPhone = phone
        let history = HistoryStore.shared.records(forPhone: phone)
        detailPanelView.configure(unknownPhone: phone, history: history)
        AccessibilityManager.shared.applyToViewTree(detailPanelView)
        openDetailPanelIfNeeded()
    }

    private func openDetailPanelIfNeeded() {
        guard !isDetailPanelOpen, let window = window else {
            return
        }
        isDetailPanelOpen = true
        let panelWidth = max(MainWindowController.detailPanelWidth, detailPanelView.requiredActionsWidth)
        currentDetailPanelWidth = panelWidth
        detailPanelWidthConstraint.constant = panelWidth

        var frame = window.frame
        let newWidth = frame.width + panelWidth
        frame.size.width = newWidth
        frame.origin.x -= panelWidth / 2

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    func hideContactDetail(completion: (() -> Void)? = nil) {
        guard isDetailPanelOpen, let window = window else {
            completion?()
            return
        }
        isDetailPanelOpen = false
        currentDetailContactID = nil
        currentDetailUnknownPhone = nil
        detailPanelWidthConstraint.constant = 0

        var frame = window.frame
        frame.size.width -= currentDetailPanelWidth
        frame.origin.x += currentDetailPanelWidth / 2

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }, completionHandler: completion)
    }

    private func refreshDetailPanelIfShowing(id: UUID) {
        guard isDetailPanelOpen, currentDetailContactID == id,
              let contact = ContactStore.shared.contacts.first(where: { $0.id == id }) else { return }
        let history = HistoryStore.shared.records(forContactID: id, phone: contact.phone)
        detailPanelView.configure(contact: contact, history: history)
        resizeDetailPanelIfNeeded()
    }

    @objc func editContactRow(_ sender: ContactRow) {
        if let contactToEdit = ContactStore.shared.contacts.first(where: { $0.id == sender.contactID }) {
            editWindowController = AddContactWindowController(contactToEdit: contactToEdit)
            editWindowController?.showWindow(nil)
            editWindowController?.window?.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc func deleteContactRow(_ sender: ContactRow) {
        if let contact = ContactStore.shared.contacts.first(where: { $0.id == sender.contactID }) {
            deleteContact(contact)
        }
    }

    private var reminderSetupWindowController: NotificationsWindowController?
    private func openReminderSetup(for contact: Contact) {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        guard ReminderManager.shared.isEnabled else { return }
        reminderSetupWindowController = NotificationsWindowController(filterContact: contact)
        reminderSetupWindowController?.shouldCascadeWindows = false
        if let notifWin = reminderSetupWindowController?.window, let mainWin = self.window {
            let x = mainWin.frame.midX - notifWin.frame.width / 2
            let y = mainWin.frame.midY - notifWin.frame.height / 2
            notifWin.setFrameOrigin(NSPoint(x: x, y: y))
        }
        reminderSetupWindowController?.showWindow(nil)
        reminderSetupWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func deleteContact(_ contact: Contact) {
        let alert = NSAlert()
        AccessibilityManager.shared.applyAccessibility(to: alert)
        alert.messageText = L("delete_alert_title")
        alert.informativeText = L("delete_alert_text", PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(contact.fullName) : contact.fullName)
        alert.addButton(withTitle: L("delete_btn"))
        alert.addButton(withTitle: L("cancel_btn"))
        alert.buttons[0].hasDestructiveAction = true

        alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance

        if let appWindow = self.window {
            alert.beginSheetModal(for: appWindow) { response in
                guard response == .alertFirstButtonReturn else { return }
                if PrivacyMode.shared.isEnabled {
                    PrivacyMode.shared.showBlockedAlert()
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    var contacts = ContactStore.shared.contacts
                    contacts.removeAll { $0.id == contact.id }
                    ContactStore.shared.contacts = contacts
                    NotificationCenter.default.post(name: .contactsDidChange, object: nil)
                }
            }
        } else {
            if alert.runModal() == .alertFirstButtonReturn {
                if PrivacyMode.shared.isEnabled {
                    PrivacyMode.shared.showBlockedAlert()
                    return
                }
                var contacts = ContactStore.shared.contacts
                contacts.removeAll { $0.id == contact.id }
                ContactStore.shared.contacts = contacts
                NotificationCenter.default.post(name: .contactsDidChange, object: nil)
            }
        }
    }

    func makeCall(to phone: String) {
        guard !phone.sanitizedForCall.isEmpty else { return }

        let urlString = "tel:\(phone.sanitizedForCall)"
        guard let url = URL(string: urlString) else { return }
        
        let match = ContactStore.shared.contacts.first(where: { $0.phone.sanitizedForCall == phone.sanitizedForCall })

        let appDelegate = NSApp.delegate as? AppDelegate
        appDelegate?.suppressFaceTime()

        if !(isDetailPanelOpen && currentDetailContactID != nil && match?.id == currentDetailContactID) {
            hideContactDetail { [weak self] in
                NSWorkspace.shared.open(url)
                self?.showToast(message: L("call_in_progress"))
                HistoryStore.shared.addRecord(phone: phone, name: match?.fullName, contactID: match?.id)
            }
        } else {
            NSWorkspace.shared.open(url)
            showToast(message: L("call_in_progress"))
            HistoryStore.shared.addRecord(phone: phone, name: match?.fullName, contactID: match?.id)
        }
    }

    private var activeVisibleSearchField: NSSearchField? {
        if !contactsView.isHidden && !contactsSearchField.isHidden {
            return contactsSearchField
        } else if !favoritesView.isHidden && !favoritesSearchField.isHidden {
            return favoritesSearchField
        } else if !historyView.isHidden && !historySearchField.isHidden {
            return historySearchField
        }
        return nil
    }

    private func repositionCallToast() {
        guard let contentView = window?.contentView, let toast = callToastView else { return }

        callToastTopConstraint?.isActive = false

        if let searchField = activeVisibleSearchField {
            callToastTopConstraint = toast.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8)
        } else if !dialerView.isHidden {
            callToastTopConstraint = toast.topAnchor.constraint(equalTo: dialerView.topAnchor, constant: 12)
        } else {
            let referenceView: NSView
            if !contactsView.isHidden {
                referenceView = contactsView
            } else if !favoritesView.isHidden {
                referenceView = favoritesView
            } else if !historyView.isHidden {
                referenceView = historyView
            } else {
                referenceView = contentView
            }
            callToastTopConstraint = toast.topAnchor.constraint(equalTo: referenceView.topAnchor, constant: 44)
        }

        callToastTopConstraint?.isActive = true
    }

    func showToast(message: String) {
        guard let contentView = window?.contentView else { return }
        callToastHideWorkItem?.cancel()
        let label: NSTextField
        if callToastView == nil {
            let toast = NSView()
            toast.wantsLayer = true
            toast.layer?.cornerRadius = 10
            toast.translatesAutoresizingMaskIntoConstraints = false
            toast.alphaValue = 0

            label = NSTextField(labelWithString: message)
            label.tag = 999
            label.font = AccessibilityManager.shared.adjustedFont(baseSize: 11, weight: .medium)
            label.isEditable = false
            label.isSelectable = false
            label.isBezeled = false
            label.drawsBackground = false
            label.alignment = .center
            
            label.maximumNumberOfLines = 0
            label.cell?.wraps = true
            label.cell?.truncatesLastVisibleLine = false
            label.lineBreakMode = .byWordWrapping
            
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.translatesAutoresizingMaskIntoConstraints = false
            toast.addSubview(label)
            contentView.addSubview(toast)

            NSLayoutConstraint.activate([
                toast.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20),
                toast.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),
                toast.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

                label.topAnchor.constraint(equalTo: toast.topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: toast.bottomAnchor, constant: -8),
                label.leadingAnchor.constraint(equalTo: toast.leadingAnchor, constant: 14),
                label.trailingAnchor.constraint(equalTo: toast.trailingAnchor, constant: -14),
                
                toast.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, constant: -40)
            ])

            callToastView = toast
        } else {
            label = callToastView?.viewWithTag(999) as? NSTextField ?? NSTextField()
            label.stringValue = message
        }
        let a11y = AccessibilityManager.shared
        callToastView?.layer?.backgroundColor = a11y.adjustedBackgroundOrTextColor(NSColor(white: 0.12, alpha: 0.92)).cgColor
        label.textColor = a11y.adjustedBackgroundOrTextColor(NSColor(white: 0.92, alpha: 1))
        
        if a11y.isEffectivelyColorInverted {
            callToastView?.layer?.borderWidth = max(a11y.highContrastBorderWidth, 1)
            callToastView?.layer?.borderColor = NSColor(white: 0, alpha: 0.15).cgColor
        } else if a11y.isHighContrastEnabled {
            callToastView?.layer?.borderWidth = a11y.highContrastBorderWidth
            callToastView?.layer?.borderColor = a11y.highContrastBorderColor
        } else {
            callToastView?.layer?.borderWidth = 0
        }

        repositionCallToast()

        callToastView?.layer?.removeAllAnimations()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            callToastView?.animator().alphaValue = 1
        }

        let hideWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                self.callToastView?.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.callToastView?.removeFromSuperview()
                self?.callToastView = nil
            })
        }
        callToastHideWorkItem = hideWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: hideWorkItem)
    }
    
    @objc func openAdd() {
        addWindowController = AddContactWindowController(contactToEdit: nil)
        addWindowController?.showWindow(nil)
        addWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func openNotifications() {
        if notificationsWindowController == nil {
            notificationsWindowController = NotificationsWindowController()
        }
        notificationsWindowController?.showWindow(nil)
        if let notifWin = notificationsWindowController?.window, let mainWin = self.window {
            let x = mainWin.frame.midX - notifWin.frame.width / 2
            let y = mainWin.frame.midY - notifWin.frame.height / 2
            notifWin.setFrameOrigin(NSPoint(x: x, y: y))
        }
        notificationsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func refreshBellButtonState() {
        guard let bellButton = bellButton else { return }
        bellButton.image = NSImage(systemSymbolName: "bell", accessibilityDescription: L("notifications_tooltip"))
        bellButton.isHidden = UserDefaults.standard.bool(forKey: "hideGeneralReminderButton") || !ReminderManager.shared.isEnabled
    }
    
    @objc private func updateUIVisibility(_ notification: Notification? = nil) {
        contactsSearchField.stringValue = ""
        favoritesSearchField.stringValue = ""
        historySearchField.stringValue = ""
        let hideContacts = UserDefaults.standard.bool(forKey: "hideContactsMenu")
        let hideKeypad = UserDefaults.standard.bool(forKey: "hideKeypadMenu")
        let hideFavorites = UserDefaults.standard.bool(forKey: "hideFavoritesMenu")
        let hideHistory = UserDefaults.standard.bool(forKey: "hideHistoryMenu")
        let hidePlus = UserDefaults.standard.bool(forKey: "hidePlusButton")
        let hideAll = hideContacts && hideKeypad && hideFavorites && hideHistory

        self.contactsButton.isHidden = hideContacts
        self.dialButton.isHidden = hideKeypad
        self.favoritesButton.isHidden = hideFavorites
        self.historyButton.isHidden = hideHistory
        self.plusButton?.isHidden = hidePlus
        self.bellButton?.isHidden = UserDefaults.standard.bool(forKey: "hideGeneralReminderButton") || !ReminderManager.shared.isEnabled

        self.contactsSearchField.isHidden = UserDefaults.standard.bool(forKey: "hideSearchInContacts")
        self.favoritesSearchField.isHidden = UserDefaults.standard.bool(forKey: "hideSearchInFavorites")
        self.historySearchField.isHidden = UserDefaults.standard.bool(forKey: "hideSearchInHistory")
        refreshGroupFilterVisibility()

        if hideAll {
            self.contactsView.isHidden = true
            self.dialerView.isHidden = true
            self.favoritesView.isHidden = true
            self.historyView.isHidden = true
            self.emptyStateView.isHidden = false
        } else {
            self.emptyStateView.isHidden = true

            let currentlyVisibleGotDisabled =
                (!self.contactsView.isHidden && hideContacts) ||
                (!self.favoritesView.isHidden && hideFavorites) ||
                (!self.historyView.isHidden && hideHistory) ||
                (!self.dialerView.isHidden && hideKeypad)

            if currentlyVisibleGotDisabled {
                if !hideFavorites { self.showFavorites() }
                else if !hideHistory { self.showHistory() }
                else if !hideContacts { self.showContacts() }
                else if !hideKeypad { self.showDialer() }
            }
        }

        self.repositionCallToast()
        let needsFullRebuild = (notification?.userInfo?["needsFullRebuild"] as? Bool) ?? true
        if needsFullRebuild {
            refreshAll()
        }

        syncDetailPanelAfterDataChange()
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        return window.isZoomed
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = self.window,
              let appDelegate = NSApp.delegate as? AppDelegate,
              !appDelegate.isApplyingUIScale else { return }
        let scale = AccessibilityManager.shared.uiScaleFactor
        let currentSize = window.frame.size
        appDelegate.naturalWindowSize = NSSize(width: currentSize.width / scale,
                                                height: currentSize.height / scale)
    }
    func windowWillClose(_ notification: Notification) {
        notificationsWindowController?.close()
        notificationsWindowController = nil
        reminderSetupWindowController?.close()
        reminderSetupWindowController = nil
        addWindowController?.close()
        addWindowController = nil
        editWindowController?.close()
        editWindowController = nil
    }
}

class FavoritesDropStackView: NSStackView {
    var onReorder: (([UUID]) -> Void)?

    private var dropIndicator: NSView?

    override func awakeFromNib() {
        super.awakeFromNib()
        registerForDraggedTypes([.favoriteContactRow])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.favoriteContactRow])
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.favoriteContactRow])
    }

    private func showDropIndicator(atY y: CGFloat) {
        let indicator: NSView
        if let existing = dropIndicator {
            indicator = existing
        } else {
            indicator = NSView()
            indicator.wantsLayer = true
            indicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            addSubview(indicator)
            dropIndicator = indicator
        }
        indicator.frame = NSRect(x: 0, y: y - 1, width: bounds.width, height: 2)
    }

    private func hideDropIndicator() {
        dropIndicator?.removeFromSuperview()
        dropIndicator = nil
    }

    private func insertionIndex(forDraggingLocation location: NSPoint) -> Int {
        let rows = arrangedSubviews
        for (index, row) in rows.enumerated() {
            let midY = row.frame.midY
            if isFlipped {
                if location.y < midY { return index }
            } else {
                if location.y > midY { return index }
            }
        }
        return rows.count
    }

    private func yPosition(forInsertionIndex index: Int) -> CGFloat {
        let rows = arrangedSubviews
        if rows.isEmpty { return 0 }
        if index >= rows.count {
            return isFlipped ? rows.last!.frame.maxY : rows.last!.frame.minY
        }
        let row = rows[index]
        return isFlipped ? row.frame.minY : row.frame.maxY
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: [.favoriteContactRow]) != nil else { return [] }
        let location = convert(sender.draggingLocation, from: nil)
        let index = insertionIndex(forDraggingLocation: location)
        showDropIndicator(atY: yPosition(forInsertionIndex: index))
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: [.favoriteContactRow]) != nil else { return [] }
        let location = convert(sender.draggingLocation, from: nil)
        let index = insertionIndex(forDraggingLocation: location)
        showDropIndicator(atY: yPosition(forInsertionIndex: index))
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hideDropIndicator()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        hideDropIndicator()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hideDropIndicator()
        guard let idString = sender.draggingPasteboard.string(forType: .favoriteContactRow),
              let draggedID = UUID(uuidString: idString) else { return false }

        var rows = arrangedSubviews.compactMap { $0 as? ContactRow }
        guard let fromIndex = rows.firstIndex(where: { $0.contactID == draggedID }) else { return false }

        let location = convert(sender.draggingLocation, from: nil)
        var toIndex = insertionIndex(forDraggingLocation: location)
        if toIndex > fromIndex { toIndex -= 1 }
        toIndex = max(0, min(toIndex, rows.count - 1))

        guard toIndex != fromIndex else { return true }

        let moved = rows.remove(at: fromIndex)
        rows.insert(moved, at: toIndex)

        onReorder?(rows.map { $0.contactID })
        return true
    }
}

class ContactRow: NSView {
    var phone: String = ""
    var contactID: UUID = UUID()
    private var target: AnyObject?
    private var action: Selector?
    private var favoriteAction: Selector?
    private var editAction: Selector?
    private var deleteAction: Selector?
    private var detailAction: Selector?
    private var optionsButton: NSButton!
    private var isFavorite: Bool = false
    private var messageButton: NSButton!
    private var nameLabelRef: NSTextField!
    private var realFullName: String = ""
    private var messageButtonWidthConstraint: NSLayoutConstraint?
    private var messageButtonHeightConstraint: NSLayoutConstraint?
    private var optionsButtonWidthConstraint: NSLayoutConstraint?
    private var optionsButtonHeightConstraint: NSLayoutConstraint?

    var isDraggable: Bool = false
    private var dragStartLocation: NSPoint?

    convenience init(contact: Contact, target: AnyObject, action: Selector, favoriteAction: Selector? = nil, editAction: Selector? = nil, deleteAction: Selector? = nil, detailAction: Selector? = nil, isDraggable: Bool = false) {
        self.init(frame: .zero)
        self.phone = contact.phone
        self.contactID = contact.id
        self.target = target
        self.action = action
        self.favoriteAction = favoriteAction
        self.editAction = editAction
        self.deleteAction = deleteAction
        self.detailAction = detailAction
        self.isFavorite = contact.isFavorite
        self.isDraggable = isDraggable
        setupUI(contact: contact)
    }

private func setupUI(contact: Contact) {
        wantsLayer = true

        let avatarView = RoundAvatarView(diameter: 34)
        avatarView.configure(image: contact.image, initials: contact.initials, colorOverride: contact.monogramColor)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(avatarView)

        realFullName = contact.fullName
        let nameLabel = NSTextField(labelWithString: PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(contact.fullName) : contact.fullName)
        nameLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 15, weight: .medium)
        nameLabel.textColor = .white
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        nameLabel.isBezeled = false
        nameLabel.drawsBackground = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        nameLabel.cell?.truncatesLastVisibleLine = true
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)
        nameLabelRef = nameLabel
        NotificationCenter.default.addObserver(self, selector: #selector(privacyModeChanged), name: .privacyModeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accessibilitySettingsChanged), name: .accessibilitySettingsDidChange, object: nil)

        let msgConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let msgImg = NSImage(systemSymbolName: "message.fill", accessibilityDescription: L("message_tooltip"))?.withSymbolConfiguration(msgConfig)
        
        messageButton = NSButton(image: msgImg ?? NSImage(), target: nil, action: nil)
        messageButton.bezelStyle = .regularSquare
        messageButton.isBordered = false
        messageButton.contentTintColor = NSColor(white: 0.55, alpha: 1)
        messageButton.translatesAutoresizingMaskIntoConstraints = false
        messageButton.isHidden = UserDefaults.standard.bool(forKey: "hideMessagesButton")
        if let cell = messageButton.cell as? NSButtonCell { cell.imageScaling = .scaleNone }
        addSubview(messageButton)

        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let ellipsisImg = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: L("tools"))?.withSymbolConfiguration(config)?.vertical()

        optionsButton = NSButton(image: ellipsisImg ?? NSImage(), target: nil, action: nil)
        optionsButton.bezelStyle = .regularSquare
        optionsButton.isBordered = false
        optionsButton.contentTintColor = NSColor(white: 0.55, alpha: 1)
        optionsButton.translatesAutoresizingMaskIntoConstraints = false
        if let cell = optionsButton.cell as? NSButtonCell { cell.imageScaling = .scaleNone }
        addSubview(optionsButton)
    
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)

        let a11y = AccessibilityManager.shared
        let hitInset = a11y.hitTargetInset
        let buttonSize: CGFloat = 28 + hitInset

        let messageWidthConstraint = messageButton.widthAnchor.constraint(equalToConstant: buttonSize)
        let messageHeightConstraint = messageButton.heightAnchor.constraint(equalToConstant: buttonSize)
        let optionsWidthConstraint = optionsButton.widthAnchor.constraint(equalToConstant: buttonSize)
        let optionsHeightConstraint = optionsButton.heightAnchor.constraint(equalToConstant: buttonSize)
        messageButtonWidthConstraint = messageWidthConstraint
        messageButtonHeightConstraint = messageHeightConstraint
        optionsButtonWidthConstraint = optionsWidthConstraint
        optionsButtonHeightConstraint = optionsHeightConstraint

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            avatarView.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 34),
            avatarView.heightAnchor.constraint(equalToConstant: 34),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: messageButton.leadingAnchor, constant: -6),
            
            messageButton.trailingAnchor.constraint(equalTo: optionsButton.leadingAnchor, constant: -2),
            messageButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageWidthConstraint,
            messageHeightConstraint,

            optionsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            optionsButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            optionsWidthConstraint,
            optionsHeightConstraint,

            line.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 58),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        a11y.applyHighContrastBorder(to: messageButton, cornerRadius: 6)
        a11y.applyHighContrastBorder(to: optionsButton, cornerRadius: 6)

        let click = NSClickGestureRecognizer(target: self, action: #selector(rowTapped(_:)))
        addGestureRecognizer(click)
    }

    @objc func showOptionsMenu() {
        if let detailAction = detailAction {
            _ = target?.perform(detailAction, with: self)
        }
    }

   @objc func rowTapped(_ gesture: NSGestureRecognizer) {
        let location = gesture.location(in: self)
        let optHitRect = optionsButton.frame.insetBy(dx: -10, dy: -10)
        let msgHitRect = messageButton.frame.insetBy(dx: -5, dy: -5)

        if !messageButton.isHidden && msgHitRect.contains(location) {
            messageTapped()
            return
        }
        if optHitRect.contains(location) {
            showOptionsMenu()
            return
        }

        wantsLayer = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            self.layer?.backgroundColor = NSColor(white: 0.3, alpha: 0.4).cgColor
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                self.layer?.backgroundColor = .none
            })
        })
        _ = target?.perform(action, with: self)
    }

    @objc func messageTapped() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        if let url = URL(string: "sms://\(phone.sanitizedForCall)") {
            NSWorkspace.shared.open(url)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if isDraggable {
            dragStartLocation = convert(event.locationInWindow, from: nil)
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggable, let startLocation = dragStartLocation else {
            super.mouseDragged(with: event)
            return
        }
        let currentLocation = convert(event.locationInWindow, from: nil)
        let distance = hypot(currentLocation.x - startLocation.x, currentLocation.y - startLocation.y)
        guard distance > 4 else { return }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(contactID.uuidString, forType: .favoriteContactRow)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let dragImage = self.snapshotImage()
        draggingItem.setDraggingFrame(bounds, contents: dragImage)

        wantsLayer = true
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        dragStartLocation = nil
    }

    private func snapshotImage() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            layer?.render(in: ctx)
        }
        image.unlockFocus()
        return image
    }

    @objc private func privacyModeChanged() {
        nameLabelRef?.stringValue = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(realFullName) : realFullName
    }

    @objc private func accessibilitySettingsChanged() {
        let a11y = AccessibilityManager.shared
        nameLabelRef?.font = a11y.adjustedFont(baseSize: 15, weight: .medium)
        let buttonSize: CGFloat = 28 + a11y.hitTargetInset
        messageButtonWidthConstraint?.constant = buttonSize
        messageButtonHeightConstraint?.constant = buttonSize
        optionsButtonWidthConstraint?.constant = buttonSize
        optionsButtonHeightConstraint?.constant = buttonSize
        a11y.applyHighContrastBorder(to: messageButton, cornerRadius: 6)
        a11y.applyHighContrastBorder(to: optionsButton, cornerRadius: 6)
        needsLayout = true
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension NSPasteboard.PasteboardType {
    static let favoriteContactRow = NSPasteboard.PasteboardType("com.hellomac.favoriteContactRow")
}

extension ContactRow: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .move
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        alphaValue = 0.4
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        alphaValue = 1.0
    }
}

class HistoryRow: NSView {
    enum AvatarStyle {
        case phoneIcon
        case contactPhoto
    }

    var phone: String = ""
    var contactID: UUID?
    private var target: AnyObject?
    private var action: Selector?
    private var optionsAction: Selector?
    private var optionsButton: NSButton!
    private var nameLabelRef: NSTextField!
    private var timeLabelRef: NSTextField!
    private var realDisplayName: String = ""
    private var optionsButtonWidthConstraint: NSLayoutConstraint?
    private var optionsButtonHeightConstraint: NSLayoutConstraint?
    var optionsButtonView: NSView? { optionsButton }
    static func resolveContact(for record: CallRecord) -> Contact? {
        if let id = record.contactID, let contact = ContactStore.shared.contacts.first(where: { $0.id == id }) {
            return contact
        }
        let target = record.phone.sanitizedForCall
        guard !target.isEmpty else { return nil }
        return ContactStore.shared.contacts.first(where: { $0.phone.sanitizedForCall == target })
    }

    convenience init(record: CallRecord, target: AnyObject, action: Selector, avatarStyle: AvatarStyle = .phoneIcon, optionsAction: Selector? = nil) {
        self.init(frame: .zero)
        self.phone = record.phone
        self.contactID = HistoryRow.resolveContact(for: record)?.id ?? record.contactID
        self.target = target
        self.action = action
        self.optionsAction = optionsAction
        setupUI(record: record, avatarStyle: avatarStyle)
    }

    private func setupUI(record: CallRecord, avatarStyle: AvatarStyle) {
        wantsLayer = true

        let avatarView: NSView
        switch avatarStyle {
        case .phoneIcon:
            let iconContainer = NSView()
            iconContainer.wantsLayer = true
            iconContainer.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
            iconContainer.layer?.cornerRadius = 17
            iconContainer.layer?.cornerCurve = .circular
            iconContainer.layer?.masksToBounds = true
            iconContainer.translatesAutoresizingMaskIntoConstraints = false

            let phoneIconConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            let phoneIcon = NSImageView(image: NSImage(systemSymbolName: "phone.fill", accessibilityDescription: L("call_tooltip"))?
                .withSymbolConfiguration(phoneIconConfig) ?? NSImage())
            phoneIcon.contentTintColor = NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)
            phoneIcon.translatesAutoresizingMaskIntoConstraints = false
            iconContainer.addSubview(phoneIcon)

            NSLayoutConstraint.activate([
                phoneIcon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
                phoneIcon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            ])
            avatarView = iconContainer

        case .contactPhoto:
            let matchedContact = HistoryRow.resolveContact(for: record)
            let roundAvatar = RoundAvatarView(diameter: 34)
            if let contact = matchedContact {
                roundAvatar.configure(image: contact.image, initials: contact.initials, colorOverride: contact.monogramColor)
            } else {
                roundAvatar.configure(image: nil, initials: "#")
            }
            avatarView = roundAvatar
        }
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(avatarView)
        let displayName = HistoryRow.resolveContact(for: record)?.fullName ?? record.contactName ?? record.phone
        realDisplayName = displayName
        let nameLabel = NSTextField(labelWithString: PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(displayName) : displayName)
        nameLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 15, weight: .regular)
        nameLabel.textColor = .white
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        nameLabel.isBezeled = false
        nameLabel.drawsBackground = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        nameLabel.cell?.truncatesLastVisibleLine = true
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)
        nameLabelRef = nameLabel
        NotificationCenter.default.addObserver(self, selector: #selector(privacyModeChanged), name: .privacyModeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accessibilitySettingsChanged), name: .accessibilitySettingsDidChange, object: nil)

        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        df.timeZone = AppTimeZone.current
        let timeLabel = NSTextField(labelWithString: df.string(from: record.date))
        timeLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 12)
        timeLabel.textColor = NSColor(white: 0.55, alpha: 1)
        timeLabel.isEditable = false
        timeLabel.isSelectable = false
        timeLabel.isBezeled = false
        timeLabel.drawsBackground = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)
        timeLabelRef = timeLabel
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let ellipsisImg = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: L("tools"))?.withSymbolConfiguration(config)?.vertical()
        optionsButton = NSButton(image: ellipsisImg ?? NSImage(), target: nil, action: nil)
        optionsButton.bezelStyle = .regularSquare
        optionsButton.isBordered = false
        optionsButton.contentTintColor = NSColor(white: 0.55, alpha: 1)
        optionsButton.translatesAutoresizingMaskIntoConstraints = false
        optionsButton.isHidden = optionsAction == nil
        if let cell = optionsButton.cell as? NSButtonCell { cell.imageScaling = .scaleNone }
        addSubview(optionsButton)
        
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)

        let a11y = AccessibilityManager.shared
        let buttonSize: CGFloat = 28 + a11y.hitTargetInset
        let widthConstraint = optionsButton.widthAnchor.constraint(equalToConstant: buttonSize)
        let heightConstraint = optionsButton.heightAnchor.constraint(equalToConstant: buttonSize)
        optionsButtonWidthConstraint = widthConstraint
        optionsButtonHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            avatarView.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 34),
            avatarView.heightAnchor.constraint(equalToConstant: 34),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),
            
            timeLabel.trailingAnchor.constraint(equalTo: optionsButton.leadingAnchor, constant: optionsAction == nil ? 16 : -6),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            optionsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            optionsButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthConstraint,
            heightConstraint,

            line.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 58),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        a11y.applyHighContrastBorder(to: optionsButton, cornerRadius: 6)
        wantsLayer = true
        layer?.cornerRadius = a11y.isHighContrastEnabled ? 8 : 0
        layer?.borderWidth = a11y.highContrastBorderWidth
        layer?.borderColor = a11y.highContrastBorderColor

        let click = NSClickGestureRecognizer(target: self, action: #selector(rowTapped(_:)))
        addGestureRecognizer(click)
    }

    @objc func showOptionsMenu() {
        if let optionsAction = optionsAction {
            _ = target?.perform(optionsAction, with: self)
        }
    }

    @objc func rowTapped(_ gesture: NSGestureRecognizer) {
        let location = gesture.location(in: self)
        if optionsAction != nil {
            let optHitRect = optionsButton.frame.insetBy(dx: -10, dy: -10)
            if optHitRect.contains(location) {
                showOptionsMenu()
                return
            }
        }

        wantsLayer = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            self.layer?.backgroundColor = NSColor(white: 0.3, alpha: 0.4).cgColor
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                self.layer?.backgroundColor = .none
            })
        })
        _ = target?.perform(action, with: self)
    }

    @objc private func privacyModeChanged() {
        nameLabelRef?.stringValue = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(realDisplayName) : realDisplayName
    }

    @objc private func accessibilitySettingsChanged() {
        let a11y = AccessibilityManager.shared
        nameLabelRef?.font = a11y.adjustedFont(baseSize: 15, weight: .regular)
        timeLabelRef?.font = a11y.adjustedFont(baseSize: 12)
        let buttonSize: CGFloat = 28 + a11y.hitTargetInset
        optionsButtonWidthConstraint?.constant = buttonSize
        optionsButtonHeightConstraint?.constant = buttonSize
        a11y.applyHighContrastBorder(to: optionsButton, cornerRadius: 6)
        wantsLayer = true
        layer?.cornerRadius = a11y.isHighContrastEnabled ? 8 : 0
        layer?.borderWidth = a11y.highContrastBorderWidth
        layer?.borderColor = a11y.highContrastBorderColor
        needsLayout = true
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

class ContactDetailPanelView: NSView {
    var onClose: (() -> Void)?
    var onCall: ((String) -> Void)?
    var onFavoriteToggle: ((UUID) -> Void)?
    var onEdit: ((Contact) -> Void)?
    var onDelete: ((Contact) -> Void)?
    var onAddToNewContact: ((String) -> Void)?

    private var currentContact: Contact?
    private var currentUnknownPhone: String?
    private var imagePreviewWindowController: ImagePreviewWindowController?

    private let avatarView = RoundAvatarView(diameter: 84)
    private let nameLabel = NSTextField(labelWithString: "")
    private let phoneLabel = NSTextField(labelWithString: "")
    private let callButton = CircleActionButton()
    private let favoriteButton = CircleActionButton()
    private let editButton = CircleActionButton()
    private let deleteButton = CircleActionButton()
    private let addToContactButton = CircleActionButton()
    private let historyTitleLabel = NSTextField(labelWithString: "")
    private let historyScrollView = NSScrollView()
    private let historyStack = NSStackView()
    private let emptyHistoryLabel = NSTextField(labelWithString: "")
    private let historyDivider = NSView()
    private let messageButton = CircleActionButton()
    private let reminderButton = CircleActionButton()
    var onReminder: ((Contact) -> Void)?
    private var actionsStack: NSStackView!
    private let actionsStackMinSpacing: CGFloat = 18
    private let actionsStackSideMargin: CGFloat = 16

    private let notesCard = NSView()
    private let notesTitleLabel = NSTextField(labelWithString: "")
    private let notesScrollView = NSScrollView()
    private let notesTextView = NSTextView()
    private var notesCardTopToActions: NSLayoutConstraint!
    private var dividerTopToNotesCard: NSLayoutConstraint!
    private var dividerTopToActions: NSLayoutConstraint!
    private var notesHeightConstraint: NSLayoutConstraint!
    private let groupBadgeButton = NSButton()
    private var groupBadgeWidthConstraint: NSLayoutConstraint?
    private var groupsPopover: NSPopover?
    private var currentContactGroups: [ContactGroup] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
        NotificationCenter.default.addObserver(self, selector: #selector(privacyModeChanged), name: .privacyModeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accessibilitySettingsChanged), name: .accessibilitySettingsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reminderHistoryChanged), name: .reminderHistoryDidChange, object: nil)
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
        NotificationCenter.default.addObserver(self, selector: #selector(privacyModeChanged), name: .privacyModeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accessibilitySettingsChanged), name: .accessibilitySettingsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reminderHistoryChanged), name: .reminderHistoryDidChange, object: nil)
    }
    static func hasUpcomingReminder(for contact: Contact) -> Bool {
        ReminderHistoryStore.shared.upcoming.contains {
            if let contactID = $0.contactID { return contactID == contact.id }
            return $0.phone.sanitizedForCall == contact.phone.sanitizedForCall
        }
    }

    @objc private func reminderHistoryChanged() {
        guard let contact = currentContact else { return }
        reminderButton.bellFilled = Self.hasUpcomingReminder(for: contact)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func privacyModeChanged() {
        if let contact = currentContact {
            applyPrivacyDisplayedText(for: contact)
            if let image = contact.image, !PrivacyMode.shared.isEnabled {
                avatarView.onTap = { [weak self] in
                    self?.presentImagePreview(image)
                }
            } else {
                avatarView.onTap = nil
            }
        } else if let phone = currentUnknownPhone {
            nameLabel.stringValue = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(phone) : phone
        }
    }

    @objc private func accessibilitySettingsChanged() {
        let a11y = AccessibilityManager.shared
        nameLabel.font = a11y.adjustedFont(baseSize: 18, weight: .bold)
        phoneLabel.font = a11y.adjustedFont(baseSize: 13)
        notesTitleLabel.font = a11y.adjustedFont(baseSize: 11, weight: .semibold)
        notesTextView.font = a11y.adjustedFont(baseSize: 13)
        notesTextView.textColor = a11y.isEffectivelyColorInverted ? .black : NSColor(white: 0.92, alpha: 1)
        historyTitleLabel.font = a11y.adjustedFont(baseSize: 12, weight: .semibold)
        emptyHistoryLabel.font = a11y.adjustedFont(baseSize: 12)
        notesCard.layer?.borderWidth = a11y.isHighContrastEnabled ? a11y.highContrastBorderWidth : 1
        notesCard.layer?.borderColor = a11y.isHighContrastEnabled
            ? a11y.highContrastBorderColor
            : NSColor(white: 1, alpha: 0.08).cgColor
        if let primary = currentContactGroups.first {
            let badgeAlpha: CGFloat = a11y.isEffectivelyColorInverted ? 1.0 : 0.85
            groupBadgeButton.layer?.backgroundColor = (primary.color ?? NSColor.systemIndigo).withAlphaComponent(badgeAlpha).cgColor
        }
        needsLayout = true
    }

    private func applyPrivacyDisplayedText(for contact: Contact) {
        if PrivacyMode.shared.isEnabled {
            nameLabel.stringValue = PrivacyMode.shared.maskedText(contact.fullName)
            phoneLabel.stringValue = PrivacyMode.shared.maskedText(contact.phone)
        } else {
            nameLabel.stringValue = contact.fullName
            phoneLabel.stringValue = contact.phone
        }
        let trimmedNotes = contact.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        notesTextView.string = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(trimmedNotes) : trimmedNotes
    }

    private func setup() {
    wantsLayer = true
    layer?.masksToBounds = true

    let backgroundEffect = NSVisualEffectView()
    backgroundEffect.material = .underWindowBackground
    backgroundEffect.blendingMode = .withinWindow
    backgroundEffect.state = .active
    backgroundEffect.translatesAutoresizingMaskIntoConstraints = false
    addSubview(backgroundEffect)
    NSLayoutConstraint.activate([
        backgroundEffect.topAnchor.constraint(equalTo: topAnchor),
        backgroundEffect.bottomAnchor.constraint(equalTo: bottomAnchor),
        backgroundEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
        backgroundEffect.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])

    let closeConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
    let closeImg = NSImage(systemSymbolName: "xmark", accessibilityDescription: L("close_details"))?.withSymbolConfiguration(closeConfig)
    let closeButton = NSButton(image: closeImg ?? NSImage(), target: self, action: #selector(closeTapped))
    closeButton.bezelStyle = .regularSquare
    closeButton.isBordered = false
    closeButton.contentTintColor = NSColor(white: 0.55, alpha: 1)
    closeButton.translatesAutoresizingMaskIntoConstraints = false
    addSubview(closeButton)

    groupBadgeButton.bezelStyle = .regularSquare
    groupBadgeButton.isBordered = false
    groupBadgeButton.wantsLayer = true
    groupBadgeButton.layer?.cornerRadius = 10
    groupBadgeButton.font = AccessibilityManager.shared.adjustedFont(baseSize: 11, weight: .semibold)
    groupBadgeButton.contentTintColor = .white
    groupBadgeButton.alignment = .center
    groupBadgeButton.target = self
    groupBadgeButton.action = #selector(groupBadgeTapped)
    groupBadgeButton.toolTip = L("groups_detail_badge_tooltip")
    groupBadgeButton.translatesAutoresizingMaskIntoConstraints = false
    groupBadgeButton.isHidden = true
    addSubview(groupBadgeButton)

    avatarView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(avatarView)

    nameLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 18, weight: .bold)
    nameLabel.textColor = .white
    nameLabel.alignment = .center
    nameLabel.isEditable = false
    nameLabel.isSelectable = true
    nameLabel.isBezeled = false
    nameLabel.drawsBackground = false
    nameLabel.lineBreakMode = .byWordWrapping
    nameLabel.maximumNumberOfLines = 0
    nameLabel.cell?.truncatesLastVisibleLine = false
    nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    nameLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(nameLabel)

    phoneLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 13)
    phoneLabel.textColor = NSColor(white: 0.55, alpha: 1)
    phoneLabel.alignment = .center
    phoneLabel.isEditable = false
    phoneLabel.isSelectable = true
    phoneLabel.isBezeled = false
    phoneLabel.drawsBackground = false
    phoneLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(phoneLabel)
    phoneLabel.lineBreakMode = .byTruncatingTail
    phoneLabel.maximumNumberOfLines = 1

    func styleCircleButton(_ button: CircleActionButton, glyph: CircleActionGlyph, color: NSColor, accessibility: String) {
        button.glyph = glyph
        button.glyphColor = color
        button.setAccessibilityLabel(accessibility)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    styleCircleButton(callButton, glyph: .phone,
                       color: NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1), accessibility: L("call_tooltip"))
    callButton.target = self
    callButton.action = #selector(callTapped)
    addSubview(callButton)

    styleCircleButton(messageButton, glyph: .message,
                       color: NSColor.systemBlue, accessibility: L("message_tooltip"))
    messageButton.target = self
    messageButton.action = #selector(messageTapped)
    addSubview(messageButton)

    styleCircleButton(reminderButton, glyph: .bell, color: NSColor.systemPurple, accessibility: L("set_reminder_tooltip"))
    reminderButton.target = self
    reminderButton.action = #selector(reminderTapped)
    addSubview(reminderButton)

    styleCircleButton(favoriteButton, glyph: .star,
                       color: NSColor.systemOrange, accessibility: L("favorite_add_tooltip"))
    favoriteButton.target = self
    favoriteButton.action = #selector(favoriteTapped)
    addSubview(favoriteButton)

    styleCircleButton(editButton, glyph: .pencil,
                       color: NSColor.systemBlue, accessibility: L("edit_contact"))
    editButton.target = self
    editButton.action = #selector(editTapped)
    addSubview(editButton)

    styleCircleButton(deleteButton, glyph: .trash,
                       color: NSColor.systemRed, accessibility: L("remove_contact_menu"))
    deleteButton.target = self
    deleteButton.action = #selector(deleteTapped)
    addSubview(deleteButton)

    styleCircleButton(addToContactButton, glyph: .addContact,
                       color: NSColor.systemBlue, accessibility: L("add_number_to_new_contact"))
    addToContactButton.target = self
    addToContactButton.action = #selector(addToNewContactTapped)
    addSubview(addToContactButton)

    let actionsStack = NSStackView(views: [callButton, messageButton, reminderButton, favoriteButton, editButton, deleteButton, addToContactButton])
    actionsStack.orientation = .horizontal
    actionsStack.distribution = .equalSpacing
    actionsStack.spacing = actionsStackMinSpacing
    actionsStack.alignment = .centerY
    actionsStack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(actionsStack)
    self.actionsStack = actionsStack

    notesCard.wantsLayer = true
    notesCard.layer?.backgroundColor = NSColor(white: 1, alpha: 0.055).cgColor
    notesCard.layer?.cornerRadius = 10
    do {
        let a11y = AccessibilityManager.shared
        notesCard.layer?.borderWidth = a11y.isHighContrastEnabled ? a11y.highContrastBorderWidth : 1
        notesCard.layer?.borderColor = a11y.isHighContrastEnabled
            ? a11y.highContrastBorderColor
            : NSColor(white: 1, alpha: 0.08).cgColor
    }
    notesCard.translatesAutoresizingMaskIntoConstraints = false
    notesCard.isHidden = true
    addSubview(notesCard)

    let notesIconConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
    let notesIconView = NSImageView(image: NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)?.withSymbolConfiguration(notesIconConfig) ?? NSImage())
    notesIconView.contentTintColor = NSColor(white: 0.5, alpha: 1)
    notesIconView.translatesAutoresizingMaskIntoConstraints = false
    notesCard.addSubview(notesIconView)

    notesTitleLabel.stringValue = L("notes_title")
    notesTitleLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 11, weight: .semibold)
    notesTitleLabel.textColor = NSColor(white: 0.5, alpha: 1)
    notesTitleLabel.isEditable = false
    notesTitleLabel.isSelectable = false
    notesTitleLabel.isBezeled = false
    notesTitleLabel.drawsBackground = false
    notesTitleLabel.translatesAutoresizingMaskIntoConstraints = false
    notesCard.addSubview(notesTitleLabel)

    notesScrollView.translatesAutoresizingMaskIntoConstraints = false
    notesScrollView.hasVerticalScroller = true
    notesScrollView.autohidesScrollers = true
    notesScrollView.drawsBackground = false
    notesScrollView.borderType = .noBorder
    notesCard.addSubview(notesScrollView)

    notesTextView.isEditable = false
    notesTextView.isSelectable = true
    notesTextView.drawsBackground = false
    notesTextView.backgroundColor = .clear
    notesTextView.font = AccessibilityManager.shared.adjustedFont(baseSize: 13)
    notesTextView.textColor = AccessibilityManager.shared.isEffectivelyColorInverted ? .black : NSColor(white: 0.92, alpha: 1)
    notesTextView.textContainerInset = NSSize(width: 0, height: 0)
    notesTextView.textContainer?.lineFragmentPadding = 0
    notesTextView.isVerticallyResizable = true
    notesTextView.isHorizontallyResizable = false
    notesTextView.autoresizingMask = [.width]
    notesTextView.textContainer?.widthTracksTextView = true
    notesScrollView.documentView = notesTextView
    notesHeightConstraint = notesScrollView.heightAnchor.constraint(equalToConstant: 80)

    NSLayoutConstraint.activate([
        notesIconView.topAnchor.constraint(equalTo: notesCard.topAnchor, constant: 12),
        notesIconView.leadingAnchor.constraint(equalTo: notesCard.leadingAnchor, constant: 12),
        notesIconView.widthAnchor.constraint(equalToConstant: 12),
        notesIconView.heightAnchor.constraint(equalToConstant: 12),

        notesTitleLabel.centerYAnchor.constraint(equalTo: notesIconView.centerYAnchor),
        notesTitleLabel.leadingAnchor.constraint(equalTo: notesIconView.trailingAnchor, constant: 6),
        notesTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: notesCard.trailingAnchor, constant: -12),

        notesScrollView.topAnchor.constraint(equalTo: notesIconView.bottomAnchor, constant: 8),
        notesScrollView.leadingAnchor.constraint(equalTo: notesCard.leadingAnchor, constant: 12),
        notesScrollView.trailingAnchor.constraint(equalTo: notesCard.trailingAnchor, constant: -12),
        notesScrollView.bottomAnchor.constraint(equalTo: notesCard.bottomAnchor, constant: -12),
        notesHeightConstraint,
    ])

    let divider = historyDivider
    divider.wantsLayer = true
    divider.layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor
    divider.translatesAutoresizingMaskIntoConstraints = false
    addSubview(divider)
    
    historyTitleLabel.stringValue = L("recent_calls")
    historyTitleLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 12, weight: .semibold)
    historyTitleLabel.textColor = NSColor(white: 0.5, alpha: 1)
    historyTitleLabel.isEditable = false
    historyTitleLabel.isSelectable = false
    historyTitleLabel.isBezeled = false
    historyTitleLabel.drawsBackground = false
    historyTitleLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(historyTitleLabel)

    historyScrollView.drawsBackground = false
    historyScrollView.borderType = .noBorder
    historyScrollView.hasVerticalScroller = true
    historyScrollView.autohidesScrollers = true
    historyScrollView.scrollerStyle = .overlay
    historyScrollView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(historyScrollView)

    historyStack.orientation = .vertical
    historyStack.spacing = 0
    historyStack.translatesAutoresizingMaskIntoConstraints = false
    historyScrollView.documentView = historyStack

    emptyHistoryLabel.stringValue = L("no_calls_yet")
    emptyHistoryLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 12)
    emptyHistoryLabel.textColor = NSColor(white: 0.45, alpha: 1)
    emptyHistoryLabel.alignment = .center
    emptyHistoryLabel.isEditable = false
    emptyHistoryLabel.isSelectable = false
    emptyHistoryLabel.isBezeled = false
    emptyHistoryLabel.drawsBackground = false
    emptyHistoryLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(emptyHistoryLabel)

    NSLayoutConstraint.activate([
        closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 16),
        closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        closeButton.widthAnchor.constraint(equalToConstant: 20),
        closeButton.heightAnchor.constraint(equalToConstant: 20),

        groupBadgeButton.topAnchor.constraint(equalTo: topAnchor, constant: 16),
        groupBadgeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
        groupBadgeButton.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),
        groupBadgeButton.heightAnchor.constraint(equalToConstant: 20),

        avatarView.topAnchor.constraint(equalTo: topAnchor, constant: 40),
        avatarView.centerXAnchor.constraint(equalTo: centerXAnchor),
        avatarView.widthAnchor.constraint(equalToConstant: 84),
        avatarView.heightAnchor.constraint(equalToConstant: 84),

        nameLabel.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 14),
        nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
        nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

        phoneLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
        phoneLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
        phoneLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

        actionsStack.topAnchor.constraint(equalTo: phoneLabel.bottomAnchor, constant: 20),
        actionsStack.centerXAnchor.constraint(equalTo: centerXAnchor),

        notesCard.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
        notesCard.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

        divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
        divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        divider.heightAnchor.constraint(equalToConstant: 0.5),

        historyTitleLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 16),
        historyTitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

        historyScrollView.topAnchor.constraint(equalTo: historyTitleLabel.bottomAnchor, constant: 8),
        historyScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
        historyScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        historyScrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),

        historyStack.widthAnchor.constraint(equalTo: historyScrollView.widthAnchor),

        emptyHistoryLabel.centerXAnchor.constraint(equalTo: historyScrollView.centerXAnchor),
        emptyHistoryLabel.topAnchor.constraint(equalTo: historyScrollView.topAnchor, constant: 20),
    ])

    notesCardTopToActions = notesCard.topAnchor.constraint(equalTo: actionsStack.bottomAnchor, constant: 20)
    dividerTopToNotesCard = divider.topAnchor.constraint(equalTo: notesCard.bottomAnchor, constant: 20)
    dividerTopToActions = divider.topAnchor.constraint(equalTo: actionsStack.bottomAnchor, constant: 24)
    dividerTopToActions.isActive = true
}

    var requiredActionsWidth: CGFloat {
    let buttons = [callButton, messageButton, reminderButton, favoriteButton, editButton, deleteButton, addToContactButton]
    let visibleCount = buttons.filter { !$0.isHidden }.count
    guard visibleCount > 0 else { return 0 }
    let buttonWidth: CGFloat = 44
    let totalButtonsWidth = CGFloat(visibleCount) * buttonWidth
    let totalSpacing = CGFloat(max(0, visibleCount - 1)) * actionsStackMinSpacing
    return totalButtonsWidth + totalSpacing + (actionsStackSideMargin * 2)
}

    func configure(contact: Contact, history: [CallRecord]) {
        currentContact = contact
        currentUnknownPhone = nil
        avatarView.configure(image: contact.image, initials: contact.initials, colorOverride: contact.monogramColor)
        if let image = contact.image, !PrivacyMode.shared.isEnabled {
            avatarView.onTap = { [weak self] in
                self?.presentImagePreview(image)
            }
        } else {
            avatarView.onTap = nil
        }
        applyPrivacyDisplayedText(for: contact)
        messageButton.isHidden = UserDefaults.standard.bool(forKey: "hideMessagesButton")
        reminderButton.isHidden = UserDefaults.standard.bool(forKey: "hideDetailReminderButton") || !ReminderManager.shared.isEnabled
        reminderButton.glyph = .bell
        reminderButton.bellFilled = Self.hasUpcomingReminder(for: contact)

        favoriteButton.isHidden = UserDefaults.standard.bool(forKey: "hideFavoritesMenu")
        editButton.isHidden = false
        deleteButton.isHidden = false
        addToContactButton.isHidden = true

        favoriteButton.glyph = .star
        favoriteButton.starFilled = contact.isFavorite
        favoriteButton.glyphColor = NSColor.systemOrange

        let notesEnabled = !UserDefaults.standard.bool(forKey: "hideContactNotesInDetail")
        let trimmedNotes = contact.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let showNotes = notesEnabled && !trimmedNotes.isEmpty
        notesTextView.string = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(trimmedNotes) : trimmedNotes
        
        if showNotes {
            let panelWidth = max(300, requiredActionsWidth)
            let textWidth = panelWidth - 56
            
            let font = notesTextView.font ?? NSFont.systemFont(ofSize: 13)
            
            let textStorage = NSTextStorage(string: notesTextView.string, attributes: [.font: font])
            let textContainer = NSTextContainer(containerSize: NSSize(width: textWidth, height: .greatestFiniteMagnitude))
            textContainer.lineFragmentPadding = 0
            
            let layoutManager = NSLayoutManager()
            layoutManager.addTextContainer(textContainer)
            textStorage.addLayoutManager(layoutManager)
            
            layoutManager.ensureLayout(for: textContainer)
            let rect = layoutManager.usedRect(for: textContainer)
            
            notesHeightConstraint.constant = max(16, min(ceil(rect.height), 80))
        }

        notesCard.isHidden = !showNotes
        notesCardTopToActions.isActive = showNotes
        dividerTopToNotesCard.isActive = showNotes
        dividerTopToActions.isActive = !showNotes

        configureGroupBadge(for: contact)
        populateHistoryList(history)
    }

    private func configureGroupBadge(for contact: Contact) {
        guard ContactGroupStore.shared.isEnabled, !contact.groupIDs.isEmpty else {
            groupBadgeButton.isHidden = true
            currentContactGroups = []
            return
        }
        let allGroups = ContactGroupStore.shared.groups
        let groups = contact.groupIDs.compactMap { id in allGroups.first { $0.id == id } }
        guard !groups.isEmpty else {
            groupBadgeButton.isHidden = true
            currentContactGroups = []
            return
        }
        currentContactGroups = groups
        let primary = groups[0]
        let extraCount = groups.count - 1
        let title = extraCount > 0 ? "\(primary.name) +\(extraCount)" : primary.name
        let font = groupBadgeButton.font ?? NSFont.systemFont(ofSize: 11, weight: .semibold)
        groupBadgeButton.attributedTitle = Self.paddedBadgeTitle(title, font: font)
        updateGroupBadgeWidth(for: title, font: font)
        let badgeAlpha: CGFloat = AccessibilityManager.shared.isEffectivelyColorInverted ? 1.0 : 0.85
        groupBadgeButton.layer?.backgroundColor = (primary.color ?? NSColor.systemIndigo).withAlphaComponent(badgeAlpha).cgColor
        groupBadgeButton.isHidden = false
    }

    private static func paddedBadgeTitle(_ text: String, font: NSFont) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ])
    }

    private static let groupBadgeHorizontalPadding: CGFloat = 10
    private func updateGroupBadgeWidth(for title: String, font: NSFont) {
        let textWidth = (title as NSString).size(withAttributes: [.font: font]).width
        let desiredWidth = ceil(textWidth) + Self.groupBadgeHorizontalPadding * 2
        groupBadgeWidthConstraint?.isActive = false
        let constraint = groupBadgeButton.widthAnchor.constraint(equalToConstant: desiredWidth)
        constraint.priority = .defaultHigh
        constraint.isActive = true
        groupBadgeWidthConstraint = constraint
    }

    @objc private func groupBadgeTapped() {
        guard !currentContactGroups.isEmpty else { return }
        if currentContactGroups.count == 1 {
            onApplyGroupFilter?(currentContactGroups[0].id)
        } else {
            presentGroupPickerPopover(for: currentContactGroups, relativeTo: groupBadgeButton)
        }
    }

    private func presentGroupPickerPopover(for groups: [ContactGroup], relativeTo view: NSView) {
        let vc = GroupPickerPopoverViewController(groups: groups)
        vc.onSelectGroupID = { [weak self] groupID in
            self?.groupsPopover?.close()
            self?.onApplyGroupFilter?(groupID)
        }
        let popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.appearance = AccessibilityManager.shared.preferredWindowAppearance
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        groupsPopover = popover
    }

    private func presentGroupContactsPopover(for group: ContactGroup, relativeTo view: NSView) {
        let members = ContactStore.shared.contacts(inGroup: group.id).filter { $0.id != currentContact?.id }
        let vc = GroupMembersPopoverViewController(group: group, members: members)
        vc.onSelectContactID = { [weak self] contactID in
            self?.groupsPopover?.close()
            self?.jumpToContact?(contactID)
        }
        let popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.appearance = AccessibilityManager.shared.preferredWindowAppearance
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        groupsPopover = popover
    }

    var jumpToContact: ((UUID) -> Void)?
    var onApplyGroupFilter: ((UUID) -> Void)?
    func configure(unknownPhone phone: String, history: [CallRecord]) {
        currentContact = nil
        currentUnknownPhone = phone
        avatarView.configure(image: nil, initials: "#")
        avatarView.onTap = nil
        nameLabel.stringValue = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(phone) : phone
        phoneLabel.stringValue = ""
        notesTextView.string = ""
        groupBadgeButton.isHidden = true
        currentContactGroups = []
        messageButton.isHidden = UserDefaults.standard.bool(forKey: "hideMessagesButton")
        reminderButton.isHidden = true
        favoriteButton.isHidden = true
        editButton.isHidden = true
        deleteButton.isHidden = true
        addToContactButton.isHidden = false
        notesCard.isHidden = true
        notesCardTopToActions.isActive = false
        dividerTopToNotesCard.isActive = false
        dividerTopToActions.isActive = true
        populateHistoryList(history)
    }

    private func populateHistoryList(_ history: [CallRecord]) {
        historyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if history.isEmpty {
            emptyHistoryLabel.isHidden = false
        } else {
            emptyHistoryLabel.isHidden = true
            for record in history {
                let row = HistoryRow(record: record, target: self, action: #selector(historyRowTapped(_:)))
                historyStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: historyStack.widthAnchor).isActive = true
                row.heightAnchor.constraint(equalToConstant: 52).isActive = true
            }
            AccessibilityManager.shared.applyToViewTree(historyStack)
        }

        let showHistory = !UserDefaults.standard.bool(forKey: "hideContactHistoryInDetail")
        historyDivider.isHidden = !showHistory
        historyTitleLabel.isHidden = !showHistory
        historyScrollView.isHidden = !showHistory
        if !showHistory {
            emptyHistoryLabel.isHidden = true
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let documentView = self.historyScrollView.documentView else { return }
            let maxY = documentView.isFlipped ? 0 : max(0, documentView.bounds.height - self.historyScrollView.contentView.bounds.height)
            self.historyScrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
            self.historyScrollView.reflectScrolledClipView(self.historyScrollView.contentView)
        }
    }

    @objc private func closeTapped() { onClose?() }

    private func presentImagePreview(_ image: NSImage) {
        guard let parentWindow = self.window else { return }
        let controller = ImagePreviewWindowController(image: image)
        imagePreviewWindowController = controller
        controller.present(on: parentWindow)
    }

    @objc private func callTapped() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        guard let phone = currentContact?.phone ?? currentUnknownPhone else { return }
        onCall?(phone)
    }
    
    @objc private func messageTapped() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        guard let phone = currentContact?.phone ?? currentUnknownPhone,
              let url = URL(string: "sms://\(phone.sanitizedForCall)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func reminderTapped() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        guard let contact = currentContact else { return }
        onReminder?(contact)
    }

    @objc private func favoriteTapped() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        guard let contact = currentContact else { return }
        favoriteButton.starFilled.toggle()
        DispatchQueue.main.async {
            self.onFavoriteToggle?(contact.id)
        }
    }

    @objc private func editTapped() {
        guard let contact = currentContact else { return }
        onEdit?(contact)
    }

    @objc private func deleteTapped() {
        guard let contact = currentContact else { return }
        onDelete?(contact)
    }

    @objc private func addToNewContactTapped() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        guard let phone = currentUnknownPhone else { return }
        onAddToNewContact?(phone)
    }

    @objc private func historyRowTapped(_ sender: HistoryRow) {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        onCall?(sender.phone)
    }
}

class GroupFilterPickerPopoverViewController: NSViewController {
    private var groups: [ContactGroup]
    private var selectedGroupIDs: Set<UUID>
    var onSelectionChanged: ((Set<UUID>, Bool) -> Void)?
    var onManageGroupsTapped: (() -> Void)?
    weak var presentingWindow: NSWindow?
    
    private var stackView: NSStackView!
    private var scrollHeightConstraint: NSLayoutConstraint!
    private var scrollView: NSScrollView!
    private static let width: CGFloat = 220
    private static let rowHeight: CGFloat = 32
    private static let maxVisibleRows = 6
    private static let newGroupRowHeight: CGFloat = 32
    private static let manageGroupsRowHeight: CGFloat = 32

    private var rowCount: Int { groups.count + 1 }
    private var listHeight: CGFloat {
        CGFloat(min(rowCount, Self.maxVisibleRows)) * Self.rowHeight + 8
    }
    private var totalHeight: CGFloat {
        listHeight + 1 + Self.newGroupRowHeight + Self.manageGroupsRowHeight + 4
    }

    init(groups: [ContactGroup], selectedGroupIDs: Set<UUID>) {
        self.groups = groups
        self.selectedGroupIDs = selectedGroupIDs
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func loadView() {
        let width = Self.width

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: totalHeight))
        container.wantsLayer = true
        container.layer?.masksToBounds = true

        let blurView = NSVisualEffectView()
        blurView.material = .popover
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(blurView)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = rowCount > Self.maxVisibleRows
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        container.addSubview(scrollView)
        self.scrollView = scrollView

        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stackView

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(divider)

        let newGroupRow = GroupFilterActionRow(
            title: L("groups_new_group_menu_item"),
            symbolName: "plus.circle",
            tint: NSColor(red: 0.2, green: 0.8, blue: 0.6, alpha: 1),
            target: self, action: #selector(newGroupTapped)
        )
        newGroupRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(newGroupRow)

        let manageGroupsRow = GroupFilterActionRow(
            title: L("groups_manage_menu_item"),
            symbolName: "gearshape",
            tint: .secondaryLabelColor,
            target: self, action: #selector(manageGroupsTapped)
        )
        manageGroupsRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(manageGroupsRow)

        let scrollHeight = scrollView.heightAnchor.constraint(equalToConstant: listHeight - 4)
        self.scrollHeightConstraint = scrollHeight

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: container.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollHeight,

            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            divider.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            newGroupRow.topAnchor.constraint(equalTo: divider.bottomAnchor),
            newGroupRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            newGroupRow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            newGroupRow.heightAnchor.constraint(equalToConstant: Self.newGroupRowHeight),

            manageGroupsRow.topAnchor.constraint(equalTo: newGroupRow.bottomAnchor),
            manageGroupsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            manageGroupsRow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            manageGroupsRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            manageGroupsRow.heightAnchor.constraint(equalToConstant: Self.manageGroupsRowHeight),
        ])

        self.view = container
        self.preferredContentSize = NSSize(width: width, height: totalHeight)
        
        rebuildRows()
    }

    private func rebuildRows() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let rowHeight = Self.rowHeight

        let allRow = GroupFilterPickerRow(title: L("groups_filter_all"), color: nil, isSelected: selectedGroupIDs.isEmpty, groupID: nil, target: self, action: #selector(rowTapped(_:)))
        stackView.addArrangedSubview(allRow)
        allRow.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        allRow.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true

        for group in groups {
            let displayName = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(group.name) : group.name
            let row = GroupFilterPickerRow(title: displayName, color: group.color, isSelected: selectedGroupIDs.contains(group.id), groupID: group.id, target: self, action: #selector(rowTapped(_:)))
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        }
    }

    @objc private func rowTapped(_ sender: NSClickGestureRecognizer) {
        guard let row = sender.view as? GroupFilterPickerRow else { return }
        let didSelectAll = (row.groupID == nil)
        
        if let id = row.groupID {
            if selectedGroupIDs.contains(id) {
                selectedGroupIDs.remove(id)
            } else {
                selectedGroupIDs.insert(id)
            }
        } else {
            selectedGroupIDs.removeAll()
        }
        
        rebuildRows()
        onSelectionChanged?(selectedGroupIDs, didSelectAll)
    }

    @objc private func newGroupTapped() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        let alert = NSAlert()
        alert.messageText = L("groups_add_prompt_title")
        alert.addButton(withTitle: L("save_btn"))
        alert.addButton(withTitle: L("cancel_btn"))

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.placeholderString = L("groups_add_placeholder")
        alert.accessoryView = input
        AccessibilityManager.shared.applyAccessibility(to: alert)
        alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance

        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            guard let self = self else { return }
            let sanitized = ContactGroup.sanitizedName(input.stringValue)
            guard !sanitized.isEmpty else { return }
            guard let newGroup = ContactGroupStore.shared.addGroup(name: sanitized) else {
                return
            }
            self.groups.append(newGroup)
            self.groups.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            self.selectedGroupIDs.insert(newGroup.id)
            self.rebuildRows()
            self.scrollView.hasVerticalScroller = self.rowCount > Self.maxVisibleRows
            self.scrollHeightConstraint.constant = self.listHeight - 4
            self.preferredContentSize = NSSize(width: Self.width, height: self.totalHeight)
            self.onSelectionChanged?(self.selectedGroupIDs, false)
        }

        if let win = presentingWindow ?? view.window {
            alert.beginSheetModal(for: win, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    @objc private func manageGroupsTapped() {
        onManageGroupsTapped?()
    }
}

private class GroupFilterActionRow: NSView {
    init(title: String, symbolName: String, tint: NSColor, target: AnyObject, action: Selector) {
        super.init(frame: .zero)

        let iconConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let icon = NSImageView(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(iconConfig) ?? NSImage())
        icon.contentTintColor = tint
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = tint
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 12),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])

        let click = NSClickGestureRecognizer(target: target, action: action)
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
}

private class GroupFilterPickerRow: NSView {
    let groupID: UUID?

    init(title: String, color: NSColor?, isSelected: Bool, groupID: UUID?, target: AnyObject, action: Selector) {
        self.groupID = groupID
        super.init(frame: .zero)
        let activeGreenColor = NSColor(red: 0.2, green: 0.8, blue: 0.6, alpha: 1)
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = isSelected ? activeGreenColor.cgColor : (color ?? NSColor(white: 0.4, alpha: 1)).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = AccessibilityManager.shared.isEffectivelyColorInverted ? .black : NSColor(white: 0.92, alpha: 1)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(dot)
        addSubview(label)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),

            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        if isSelected {
            let checkConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            let checkImg = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?.withSymbolConfiguration(checkConfig)
            let checkView = NSImageView(image: checkImg ?? NSImage())
            checkView.contentTintColor = activeGreenColor
            checkView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(checkView)
            NSLayoutConstraint.activate([
                checkView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                checkView.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: checkView.leadingAnchor, constant: -6),
            ])
        } else {
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12).isActive = true
        }

        let click = NSClickGestureRecognizer(target: target, action: action)
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
}

class SpeedDialPickerPopoverViewController: NSViewController {
    var onManageTapped: (() -> Void)?
    var onNumberSelected: ((String) -> Void)?

    private var stackView: NSStackView!
    private static let width: CGFloat = 220
    private static let rowHeight: CGFloat = 32
    private static let maxVisibleRows = 6
    private static let manageRowHeight: CGFloat = 32

    private var entries: [(slot: Int, display: String, phone: String)] {
        var result: [(slot: Int, display: String, phone: String)] = []
        for i in 1...9 {
            let savedValue = UserDefaults.standard.string(forKey: "SpeedDial_\(i)") ?? ""
            guard !savedValue.isEmpty else { continue }
            if let contact = ContactStore.shared.contacts.first(where: { $0.phone.sanitizedForCall == savedValue.sanitizedForCall }) {
                let display = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(contact.fullName) : contact.fullName
                result.append((slot: i, display: display, phone: contact.phone))
            } else {
                let display = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(savedValue) : savedValue
                result.append((slot: i, display: display, phone: savedValue))
            }
        }
        return result
    }

    private var rowCount: Int { max(entries.count, 1) }
    private var isEmptyState: Bool { entries.isEmpty }
    private static let emptyStateHeight: CGFloat = 64
    private var listHeight: CGFloat {
        if isEmptyState {
            return Self.emptyStateHeight
        }
        return CGFloat(min(rowCount, Self.maxVisibleRows)) * Self.rowHeight + 8
    }
    private var totalHeight: CGFloat {
        listHeight + 1 + Self.manageRowHeight + 4
    }

    override func loadView() {
        let width = Self.width

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: totalHeight))
        container.wantsLayer = true
        container.layer?.masksToBounds = true

        let blurView = NSVisualEffectView()
        blurView.material = .popover
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(blurView)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = rowCount > Self.maxVisibleRows
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        container.addSubview(scrollView)

        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stackView

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(divider)

        let manageRow = GroupFilterActionRow(
            title: L("speed_dial_manage_menu_item"),
            symbolName: "gearshape",
            tint: .secondaryLabelColor,
            target: self, action: #selector(manageTapped)
        )
        manageRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(manageRow)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: container.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: listHeight - 4),

            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            divider.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            manageRow.topAnchor.constraint(equalTo: divider.bottomAnchor),
            manageRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            manageRow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            manageRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            manageRow.heightAnchor.constraint(equalToConstant: Self.manageRowHeight),
        ])

        self.view = container
        self.preferredContentSize = NSSize(width: width, height: totalHeight)

        rebuildRows()
    }

    private func rebuildRows() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let rowHeight = Self.rowHeight
        let currentEntries = entries

        if currentEntries.isEmpty {
            let emptyLabel = NSTextField(wrappingLabelWithString: L("speed_dial_empty"))
            emptyLabel.font = NSFont.systemFont(ofSize: 12)
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.alignment = .center
            emptyLabel.lineBreakMode = .byWordWrapping
            emptyLabel.maximumNumberOfLines = 0
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false

            let emptyContainer = NSView()
            emptyContainer.translatesAutoresizingMaskIntoConstraints = false
            emptyContainer.addSubview(emptyLabel)
            NSLayoutConstraint.activate([
                emptyLabel.topAnchor.constraint(equalTo: emptyContainer.topAnchor, constant: 10),
                emptyLabel.bottomAnchor.constraint(equalTo: emptyContainer.bottomAnchor, constant: -10),
                emptyLabel.leadingAnchor.constraint(equalTo: emptyContainer.leadingAnchor, constant: 14),
                emptyLabel.trailingAnchor.constraint(equalTo: emptyContainer.trailingAnchor, constant: -14),
            ])

            stackView.addArrangedSubview(emptyContainer)
            emptyContainer.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            return
        }

        for entry in currentEntries {
            let row = SpeedDialPickerRow(slot: entry.slot, title: entry.display, target: self, action: #selector(rowTapped(_:)))
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        }
    }

    @objc private func rowTapped(_ sender: NSClickGestureRecognizer) {
        guard let row = sender.view as? SpeedDialPickerRow else { return }
        guard let entry = entries.first(where: { $0.slot == row.slot }) else { return }
        onNumberSelected?(entry.phone)
    }

    @objc private func manageTapped() {
        onManageTapped?()
    }
}

private class SpeedDialPickerRow: NSView {
    let slot: Int

    init(slot: Int, title: String, target: AnyObject, action: Selector) {
        self.slot = slot
        super.init(frame: .zero)
        let activeYellowColor = NSColor.systemYellow

        let slotLabel = NSTextField(labelWithString: "\(slot)")
        slotLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        slotLabel.textColor = activeYellowColor
        slotLabel.alignment = .center
        slotLabel.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = AccessibilityManager.shared.isEffectivelyColorInverted ? .black : NSColor(white: 0.92, alpha: 1)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(slotLabel)
        addSubview(label)

        NSLayoutConstraint.activate([
            slotLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            slotLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            slotLabel.widthAnchor.constraint(equalToConstant: 14),

            label.leadingAnchor.constraint(equalTo: slotLabel.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])

        let click = NSClickGestureRecognizer(target: target, action: action)
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
}

class GroupMembersPopoverViewController: NSViewController {
    private let group: ContactGroup
    private let members: [Contact]
    var onSelectContactID: ((UUID) -> Void)?

    init(group: ContactGroup, members: [Contact]) {
        self.group = group
        self.members = members
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func loadView() {
        let width: CGFloat = 260
        let rowHeight: CGFloat = 44
        let headerHeight: CGFloat = 36
        let maxVisibleRows = 6
        let contentRowCount = max(1, members.count)
        let listHeight = min(maxVisibleRows, contentRowCount) * Int(rowHeight)
        let totalHeight = headerHeight + CGFloat(listHeight) + 8

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: totalHeight))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 0.13, green: 0.13, blue: 0.145, alpha: 1).cgColor

        let headerLabel = NSTextField(labelWithString: L("groups_detail_popover_title", group.name))
        headerLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 12, weight: .semibold)
        headerLabel.textColor = NSColor(white: 0.6, alpha: 1)
        headerLabel.lineBreakMode = .byTruncatingTail
        headerLabel.maximumNumberOfLines = 1
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(headerLabel)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        container.addSubview(scrollView)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack

        if members.isEmpty {
            let emptyLabel = NSTextField(labelWithString: L("groups_detail_popover_empty"))
            emptyLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 12)
            emptyLabel.textColor = NSColor(white: 0.45, alpha: 1)
            emptyLabel.alignment = .center
            emptyLabel.lineBreakMode = .byWordWrapping
            emptyLabel.maximumNumberOfLines = 2
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(emptyLabel)
            emptyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            emptyLabel.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        } else {
            RoundAvatarView.resetColorSequence()
            for contact in members {
                let row = ContactRow(contact: contact, target: self, action: #selector(rowTapped(_:)))
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            }
        }

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            headerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            headerLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),

            scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        self.view = container
        self.preferredContentSize = NSSize(width: width, height: totalHeight)
    }

    @objc private func rowTapped(_ sender: ContactRow) {
        onSelectContactID?(sender.contactID)
    }
}

class GroupPickerPopoverViewController: NSViewController {
    private let groups: [ContactGroup]
    var onSelectGroupID: ((UUID) -> Void)?

    init(groups: [ContactGroup]) {
        self.groups = groups
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func loadView() {
        let width: CGFloat = 220
        let rowHeight: CGFloat = 32
        let maxVisibleRows = 6
        let visibleRowCount = min(groups.count, maxVisibleRows)
        let totalHeight = CGFloat(visibleRowCount) * rowHeight + 8

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: totalHeight))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 0.13, green: 0.13, blue: 0.145, alpha: 1).cgColor

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = groups.count > maxVisibleRows
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        container.addSubview(scrollView)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack

        for group in groups {
            let row = GroupPickerRow(group: group, target: self, action: #selector(rowTapped(_:)))
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),

            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        self.view = container
        self.preferredContentSize = NSSize(width: width, height: totalHeight)
    }

    @objc private func rowTapped(_ sender: NSClickGestureRecognizer) {
        guard let row = sender.view as? GroupPickerRow, let id = row.groupID else { return }
        onSelectGroupID?(id)
    }
}

private class GroupPickerRow: NSView {
    var groupID: UUID?

    init(group: ContactGroup, target: AnyObject, action: Selector) {
        self.groupID = group.id
        super.init(frame: .zero)

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = (group.color ?? NSColor.systemIndigo).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: group.name)
        label.font = NSFont.systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(dot)
        addSubview(label)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),

            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let click = NSClickGestureRecognizer(target: target, action: action)
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
}

enum CircleActionGlyph {
    case star, phone, pencil, trash, message, addContact, bell

    var symbolName: String {
        switch self {
        case .star: return "star.fill"
        case .phone: return "phone.fill"
        case .pencil: return "pencil"
        case .trash: return "trash.fill"
        case .message: return "message.fill"
        case .addContact: return "person.crop.circle.badge.plus"
        case .bell: return "bell.fill"
        }
    }

    var outlineSymbolName: String {
        switch self {
        case .star: return "star"
        case .message: return "message"
        case .bell: return "bell"
        default: return symbolName
        }
    }
}

class CircleActionButton: NSButton {
    private var hovered = false
    private var pressed = false
    private var trackingArea: NSTrackingArea?
    static let neutralFill = NSColor.white.withAlphaComponent(0.08)
    private static let invertedRestColor = NSColor(white: 0.88, alpha: 1)
    private static let invertedHoverColor = NSColor(white: 0.80, alpha: 1)
    private static let invertedPressedColor = NSColor(white: 0.72, alpha: 1)

    var glyphColor: NSColor = .white {
        didSet { updateGlyphImageView() }
    }

    var glyph: CircleActionGlyph = .star {
        didSet { updateGlyphImageView() }
    }

    var starFilled: Bool = true {
        didSet { updateGlyphImageView() }
    }
    var bellFilled: Bool = false {
        didSet { updateGlyphImageView() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = false
        isBordered = false
        showsBorderOnlyWhileMouseInside = false
        title = ""
        (cell as? NSButtonCell)?.isBordered = false
        (cell as? NSButtonCell)?.imageScaling = .scaleNone
        updateGlyphImageView()
        NotificationCenter.default.addObserver(self, selector: #selector(accessibilitySettingsChanged), name: .accessibilitySettingsDidChange, object: nil)
    }

    @objc private func accessibilitySettingsChanged() {
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        let side: CGFloat = 44 + AccessibilityManager.shared.hitTargetInset
        return NSSize(width: side, height: side)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        hovered = false
        pressed = false
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        pressed = true
        needsDisplay = true
        super.mouseDown(with: event)
        pressed = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let a11y = AccessibilityManager.shared
        let circle = NSBezierPath(ovalIn: bounds)
        
        if a11y.isEffectivelyColorInverted {
            CircleActionButton.invertedRestColor.setFill()
        } else {
            a11y.adjustedColor(CircleActionButton.neutralFill).setFill()
        }
        circle.fill()

        if hovered || pressed {
            if a11y.isEffectivelyColorInverted {
                (pressed ? CircleActionButton.invertedPressedColor : CircleActionButton.invertedHoverColor).setFill()
            } else {
                a11y.adjustedColor(NSColor.white.withAlphaComponent(pressed ? 0.14 : 0.08)).setFill()
            }
            circle.fill()
        }

        if a11y.isHighContrastEnabled {
            let ringRect = bounds.insetBy(dx: 0.75, dy: 0.75)
            let ring = NSBezierPath(ovalIn: ringRect)
            ring.lineWidth = a11y.highContrastBorderWidth
            NSColor.white.setStroke()
            ring.stroke()
        } else if a11y.isEffectivelyColorInverted {
            let ringRect = bounds.insetBy(dx: 0.75, dy: 0.75)
            let ring = NSBezierPath(ovalIn: ringRect)
            ring.lineWidth = max(a11y.highContrastBorderWidth, 1)
            NSColor(white: 0, alpha: 0.15).setStroke()
            ring.stroke()
        }
    }

    private lazy var glyphImageView: NSImageView = {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private var glyphConstraints: [NSLayoutConstraint] = []

    private func updateGlyphImageView() {
        if glyphImageView.superview == nil {
            addSubview(glyphImageView)
        }
        let symbolName: String
        if glyph == .star && !starFilled {
            symbolName = glyph.outlineSymbolName
        } else if glyph == .bell && !bellFilled {
            symbolName = glyph.outlineSymbolName
        } else {
            symbolName = glyph.symbolName
        }
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        img?.isTemplate = true
        glyphImageView.image = img
        glyphImageView.contentTintColor = glyphColor

        NSLayoutConstraint.deactivate(glyphConstraints)
        glyphConstraints = [
            glyphImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyphImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyphImageView.widthAnchor.constraint(equalToConstant: 20),
            glyphImageView.heightAnchor.constraint(equalToConstant: 20),
        ]
        NSLayoutConstraint.activate(glyphConstraints)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let existing = trackingArea { removeTrackingArea(existing) }
    }
}

class DialerKey: NSButton {
    var digit: String = ""
    private var digitLabel: NSTextField!

    convenience init(digit: String, target: AnyObject, action: Selector) {
        self.init(frame: .zero)
        self.digit = digit
        self.target = target
        self.action = action
        identifier = a11ySelfManagedIdentifier
        setupUI(digit: digit)
    }

    private func setupUI(digit: String) {
        wantsLayer = true
        layer?.backgroundColor = DialerKey.currentRestColor.cgColor
        layer?.cornerRadius = 32
        isBordered = false
        bezelStyle = .regularSquare
        title = ""

        let digitLabel = NSTextField(labelWithString: digit)
        digitLabel.font = NSFont.systemFont(ofSize: 28, weight: .light)
        digitLabel.alignment = .center
        digitLabel.isEditable = false
        digitLabel.isSelectable = false
        digitLabel.isBezeled = false
        digitLabel.drawsBackground = false
        digitLabel.translatesAutoresizingMaskIntoConstraints = false
        self.digitLabel = digitLabel
        updateDigitLabelColor()
        addSubview(digitLabel)

        NSLayoutConstraint.activate([
            digitLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            digitLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        translatesAutoresizingMaskIntoConstraints = false

        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        NotificationCenter.default.addObserver(self, selector: #selector(accessibilitySettingsChanged), name: .accessibilitySettingsDidChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func accessibilitySettingsChanged() {
        layer?.backgroundColor = DialerKey.currentRestColor.cgColor
        updateDigitLabelColor()
        needsLayout = true
    }

    private func updateDigitLabelColor() {
        let a11y = AccessibilityManager.shared
        digitLabel.textColor = a11y.isEffectivelyColorInverted ? .black : .white
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 64, height: 64)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        let a11y = AccessibilityManager.shared
        if a11y.isHighContrastEnabled {
            layer?.borderWidth = a11y.highContrastBorderWidth
            layer?.borderColor = a11y.highContrastBorderColor
        } else if a11y.isEffectivelyColorInverted {
            layer?.borderWidth = 1
            layer?.borderColor = NSColor(white: 0, alpha: 0.12).cgColor
        } else {
            layer?.borderWidth = 1
            layer?.borderColor = NSColor(white: 1, alpha: 0.10).cgColor
        }
    }

    private static let restColor = NSColor(white: 0.16, alpha: 0.9)
    private static let hoverColor = NSColor(white: 0.22, alpha: 0.9)
    private static let pressedColor = NSColor(white: 0.10, alpha: 0.9)
    private static let invertedRestColor = NSColor(white: 0.88, alpha: 1)
    private static let invertedHoverColor = NSColor(white: 0.80, alpha: 1)
    private static let invertedPressedColor = NSColor(white: 0.72, alpha: 1)

    private static var currentRestColor: NSColor {
        let a11y = AccessibilityManager.shared
        return a11y.isEffectivelyColorInverted ? invertedRestColor : a11y.adjustedColor(restColor)
    }
    private static var currentHoverColor: NSColor {
        let a11y = AccessibilityManager.shared
        return a11y.isEffectivelyColorInverted ? invertedHoverColor : a11y.adjustedColor(hoverColor)
    }
    private static var currentPressedColor: NSColor {
        let a11y = AccessibilityManager.shared
        return a11y.isEffectivelyColorInverted ? invertedPressedColor : a11y.adjustedColor(pressedColor)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = DialerKey.currentHoverColor.cgColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = DialerKey.currentRestColor.cgColor
    }
    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = DialerKey.currentPressedColor.cgColor
        super.mouseDown(with: event)
        layer?.backgroundColor = DialerKey.currentRestColor.cgColor
    }
}

extension NSStackView {
    var isUserInteractionEnabled: Bool {
        get { return true }
        set { }
    }
}

extension Notification.Name {
    static let contactsDidChange = Notification.Name("contactsDidChange")
}

extension NSImage {
    func vertical() -> NSImage {
        guard size.width > 0 && size.height > 0 else { return self }
        let newImage = NSImage(size: NSSize(width: size.height, height: size.width))
        newImage.isTemplate = true
        newImage.lockFocus()
        let transform = NSAffineTransform()
        transform.translateX(by: size.height / 2, yBy: size.width / 2)
        transform.rotate(byDegrees: 90)
        transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
        transform.concat()
        self.draw(in: NSRect(origin: .zero, size: self.size))
        newImage.unlockFocus()
        return newImage
    }
}