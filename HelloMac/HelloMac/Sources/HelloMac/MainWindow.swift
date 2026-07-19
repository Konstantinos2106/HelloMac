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
        let isGreek = Locale.preferredLanguages.first?.hasPrefix("el") ?? true
        let newMenu = NSMenu()
        
        newMenu.allowsContextMenuPlugIns = false
        
        newMenu.addItem(NSMenuItem(title: isGreek ? "Αποκοπή" : "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: ""))
        newMenu.addItem(NSMenuItem(title: isGreek ? "Αντιγραφή" : "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: ""))
        newMenu.addItem(NSMenuItem(title: isGreek ? "Επικόλληση" : "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: ""))
        
        var googleItem: NSMenuItem?
        for item in defaultMenu.items {
            let actionStr = item.action?.description ?? ""
            let title = item.title.lowercased()
            if actionStr.contains("WebSearch") || actionStr.contains("Google") || title.contains("google") {
                googleItem = item.copy() as? NSMenuItem
                googleItem?.title = isGreek ? "Αναζήτηση με το Google" : "Search with Google"
            }
        }
        
        var shareItem: NSMenuItem?
        let selectedRange = self.selectedRange()
        if selectedRange.length > 0 {
            shareItem = NSMenuItem(
                title: isGreek ? "Κοινοποίηση..." : "Share...", 
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
    private var favoritesStackView: NSStackView!
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
    
    private var displayLabel: NSTextField!
    
    private var contactsSearchField: NSSearchField!
    private var favoritesSearchField: NSSearchField!

    private var contactsScrollView: NSScrollView!
    private var favoritesScrollView: NSScrollView!
    private var historyScrollView: NSScrollView!
    
    private var addWindowController: AddContactWindowController?
    private var editWindowController: AddContactWindowController?
    
    private var plusButton: DialerKey?
    
    private var emptyContactsLabel: NSTextField!
    private var emptyFavoritesLabel: ClickableLabel!
    private var emptyHistoryLabel: NSTextField!

    private var callToastView: NSView?
    private var callToastHideWorkItem: DispatchWorkItem?
    private var callToastTopConstraint: NSLayoutConstraint?

    private var detailPanelView: ContactDetailPanelView!
    private var detailPanelWidthConstraint: NSLayoutConstraint!
    private var detailPanelSeparator: NSView!
    private static let detailPanelWidth: CGFloat = 300
    private var isDetailPanelOpen = false

    func showContactsPublic()  { showContacts() }
    func showFavoritesPublic() { showFavorites() }
    func showHistoryPublic()   { showHistory() }
    func showDialerPublic()    { showDialer() }
    func openAddPublic()       { openAdd() }
    func focusSearchFieldPublic() { focusSearchField() }

    convenience init() {
        let window = NonFullScreenWindow(
            contentRect: NSRect(x: 0, y: 0, width: 335, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "HelloMac"
        window.titlebarAppearsTransparent = true
        window.center()
        
        window.appearance = NSAppearance(named: .darkAqua) 
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        window.minSize = NSSize(width: 300, height: 550)
        window.maxSize = NSSize(width: 1200, height: 900)
        window.collectionBehavior = [.managed, .fullScreenNone]
        
        self.init(window: window)
        window.delegate = self
        setupUI()
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateUIVisibility), name: NSNotification.Name("UpdateUIVisibility"), object: nil)
        updateUIVisibility()
        DispatchQueue.main.async {
            window.makeFirstResponder(nil)
        }
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

        let tabBar = NSView()
        tabBar.wantsLayer = true
        tabBar.layer?.backgroundColor = NSColor(red: 0.145, green: 0.145, blue: 0.155, alpha: 1).cgColor
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
        emptyLabel.font = NSFont.systemFont(ofSize: 14)
        emptyLabel.textColor = NSColor(white: 0.6, alpha: 1)
        emptyLabel.alignment = .center
        emptyLabel.isEditable = false
        emptyLabel.isSelectable = false
        emptyLabel.isBezeled = false
        emptyLabel.drawsBackground = false
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
        
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAll), name: .contactsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshHistory), name: NSNotification.Name("historyDidChange"), object: nil)
    }

    @objc private func focusSearchField() {
        if !contactsView.isHidden && !contactsSearchField.isHidden {
            window?.makeFirstResponder(contactsSearchField)
        } else if !favoritesView.isHidden && !favoritesSearchField.isHidden {
            window?.makeFirstResponder(favoritesSearchField)
        }
    }
    
    private func scrollToTop(_ scrollView: NSScrollView?) {
        guard let scrollView = scrollView, let documentView = scrollView.documentView else { return }
        let maxY = documentView.isFlipped ? 0 : max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    @objc private func refreshAll() {
        // If the currently-detailed contact was deleted, close the panel
        // first. The (synchronous, layout-heavy) list rebuilds below run
        // only after the window-resize animation has started, so they
        // don't steal its first frame and make it look like a jump cut.
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

    private func syncDetailPanelAfterDataChange() {
        guard isDetailPanelOpen, let id = currentDetailContactID else { return }
        if let contact = ContactStore.shared.contacts.first(where: { $0.id == id }) {
            let history = HistoryStore.shared.records(forContactID: id)
            detailPanelView.configure(contact: contact, history: history)
        } else {
            hideContactDetail()
        }
    }

    private func setupContactsView() {
        let titleLabel = NSTextField(labelWithString: L("contacts"))
        titleLabel.font = NSFont.boldSystemFont(ofSize: 17)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contactsView.addSubview(titleLabel)

        let addImg = NSImage(systemSymbolName: "person.badge.plus", accessibilityDescription: L("add_tooltip"))
        let addBtn = NSButton(image: addImg ?? NSImage(), target: self, action: #selector(openAdd))
        addBtn.bezelStyle = .regularSquare
        addBtn.isBordered = false
        addBtn.contentTintColor = NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        if let cell = addBtn.cell as? NSButtonCell { cell.imageScaling = .scaleProportionallyUpOrDown }
        contactsView.addSubview(addBtn)
        
        contactsSearchField = NSSearchField()
        contactsSearchField.placeholderString = L("search_placeholder")
        contactsSearchField.translatesAutoresizingMaskIntoConstraints = false
        contactsSearchField.delegate = self
        contactsView.addSubview(contactsSearchField)

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
        emptyContactsLabel.font = NSFont.systemFont(ofSize: 13)
        emptyContactsLabel.maximumNumberOfLines = 2
        emptyContactsLabel.isEditable = false
        emptyContactsLabel.isSelectable = false
        emptyContactsLabel.isBezeled = false
        emptyContactsLabel.drawsBackground = false
        emptyContactsLabel.translatesAutoresizingMaskIntoConstraints = false
        contactsView.addSubview(emptyContactsLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contactsView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contactsView.leadingAnchor, constant: 16),

            addBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            addBtn.trailingAnchor.constraint(equalTo: contactsView.trailingAnchor, constant: -14),
            addBtn.widthAnchor.constraint(equalToConstant: 26),
            addBtn.heightAnchor.constraint(equalToConstant: 26),
            
            contactsSearchField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            contactsSearchField.leadingAnchor.constraint(equalTo: contactsView.leadingAnchor, constant: 16),
            contactsSearchField.trailingAnchor.constraint(equalTo: contactsView.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: contactsSearchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contactsView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contactsView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contactsView.bottomAnchor),

            stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            
            emptyContactsLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyContactsLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor, constant: -20)
        ])

        refreshContacts()
    }

    private func setupFavoritesView() {
        let titleLabel = NSTextField(labelWithString: L("favorites"))
        titleLabel.font = NSFont.boldSystemFont(ofSize: 17)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
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

        favoritesStackView = NSStackView()
        favoritesStackView.orientation = .vertical
        favoritesStackView.spacing = 0
        favoritesStackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = favoritesStackView

        emptyFavoritesLabel = ClickableLabel(labelWithString: L("no_favorites"))
        emptyFavoritesLabel.alignment = .center
        emptyFavoritesLabel.textColor = NSColor(white: 0.5, alpha: 1)
        emptyFavoritesLabel.font = NSFont.systemFont(ofSize: 13)
        emptyFavoritesLabel.maximumNumberOfLines = 2
        emptyFavoritesLabel.isEditable = false
        emptyFavoritesLabel.isSelectable = false
        emptyFavoritesLabel.isBezeled = false
        emptyFavoritesLabel.drawsBackground = false
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
            emptyFavoritesLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor, constant: -20)
        ])

        refreshFavorites()
    }
    
    private func setupHistoryView() {
        let titleLabel = NSTextField(labelWithString: L("history"))
        titleLabel.font = NSFont.boldSystemFont(ofSize: 17)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        historyView.addSubview(titleLabel)

        let clearImg = NSImage(systemSymbolName: "trash", accessibilityDescription: L("clear_history"))
        let clearBtn = NSButton(image: clearImg ?? NSImage(), target: self, action: #selector(clearHistory))
        clearBtn.bezelStyle = .regularSquare
        clearBtn.isBordered = false
        clearBtn.contentTintColor = NSColor.systemRed
        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        if let cell = clearBtn.cell as? NSButtonCell { cell.imageScaling = .scaleProportionallyUpOrDown }
        historyView.addSubview(clearBtn)

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
        emptyHistoryLabel.font = NSFont.systemFont(ofSize: 13)
        emptyHistoryLabel.maximumNumberOfLines = 2
        emptyHistoryLabel.isEditable = false
        emptyHistoryLabel.isSelectable = false
        emptyHistoryLabel.isBezeled = false
        emptyHistoryLabel.drawsBackground = false
        emptyHistoryLabel.translatesAutoresizingMaskIntoConstraints = false
        historyView.addSubview(emptyHistoryLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: historyView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: historyView.leadingAnchor, constant: 16),
            
            clearBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            clearBtn.trailingAnchor.constraint(equalTo: historyView.trailingAnchor, constant: -14),
            clearBtn.widthAnchor.constraint(equalToConstant: 26),
            clearBtn.heightAnchor.constraint(equalToConstant: 26),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: historyView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: historyView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: historyView.bottomAnchor),

            historyStackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            
            emptyHistoryLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyHistoryLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor, constant: -20)
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
        let blue = NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
        let gray = NSColor(white: 0.5, alpha: 1)
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
    }

    @objc func keyPressed(_ sender: DialerKey) {
        displayLabel.stringValue += sender.digit
        updateDisplayFont()
    }

    func keyCaptureDidType(digit: String) {
        displayLabel.stringValue += digit
        updateDisplayFont()
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
            if field == contactsSearchField {
                refreshContacts()
            } else if field == favoritesSearchField {
                refreshFavorites()
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
        
        // Λογική Ταχείας Κλήσης
        if UserDefaults.standard.bool(forKey: "enableSpeedDial"), number.count == 1 {
            if let num = Int(number), num >= 1, num <= 9 {
                if let target = UserDefaults.standard.string(forKey: "SpeedDial_\(num)"), !target.isEmpty {
                    makeCall(to: target)
                    displayLabel.stringValue = "" // Εκκαθάριση της οθόνης
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
            displayLabel.stringValue += sanitized
            updateDisplayFont()
        }
    }

    @objc func refreshContacts() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let allContacts = ContactStore.shared.contacts
        let searchString = contactsSearchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        
        let filtered = (searchString.isEmpty ? allContacts : allContacts.filter {
            $0.fullName.lowercased().contains(searchString) || $0.phone.contains(searchString)
        }).sorted {
            $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending
        }
        
        if allContacts.isEmpty {
            emptyContactsLabel.stringValue = L("no_contacts")
            emptyContactsLabel.isHidden = false
        } else if filtered.isEmpty {
            emptyContactsLabel.stringValue = L("no_search_results")
            emptyContactsLabel.isHidden = false
        } else {
            emptyContactsLabel.isHidden = true
        }
        
        for contact in filtered {
            let row = ContactRow(contact: contact, target: self, action: #selector(callRow(_:)), favoriteAction: #selector(toggleFavoriteRow(_:)), editAction: #selector(editContactRow(_:)), deleteAction: #selector(deleteContactRow(_:)), detailAction: #selector(showContactDetail(_:)))
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: 58).isActive = true
        }
        DispatchQueue.main.async { [weak self] in self?.scrollToTop(self?.contactsScrollView) }
    }

    @objc func refreshFavorites() {
        favoritesStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let allFavorites = ContactStore.shared.favorites
        let searchString = favoritesSearchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        
        let filtered = (searchString.isEmpty ? allFavorites : allFavorites.filter {
            $0.fullName.lowercased().contains(searchString) || $0.phone.contains(searchString)
        }).sorted {
            switch ($0.favoritedAt, $1.favoritedAt) {
            case let (lhs?, rhs?):
                return lhs > rhs
            case (nil, nil):
                return false
            case (nil, _):
                // Favorites without a timestamp (added before this field
                // existed) sort after ones we know the order for.
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
        
        for contact in filtered {
            let row = ContactRow(contact: contact, target: self, action: #selector(callRow(_:)), favoriteAction: #selector(toggleFavoriteRow(_:)), editAction: #selector(editContactRow(_:)), deleteAction: #selector(deleteContactRow(_:)), detailAction: #selector(showContactDetail(_:)))
            favoritesStackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: favoritesStackView.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: 58).isActive = true
        }
        DispatchQueue.main.async { [weak self] in self?.scrollToTop(self?.favoritesScrollView) }
    }

    @objc func refreshHistory() {
        historyStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let records = HistoryStore.shared.records
        
        if records.isEmpty {
            emptyHistoryLabel.isHidden = false
        } else {
            emptyHistoryLabel.isHidden = true
            for record in records {
                let row = HistoryRow(record: record, target: self, action: #selector(callHistoryRow(_:)), avatarStyle: .contactPhoto)
                historyStackView.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: historyStackView.widthAnchor).isActive = true
                row.heightAnchor.constraint(equalToConstant: 58).isActive = true
            }
        }
        DispatchQueue.main.async { [weak self] in self?.scrollToTop(self?.historyScrollView) }
        syncDetailPanelAfterDataChange()
    }

    @objc func callRow(_ sender: ContactRow) {
        makeCall(to: sender.phone)
    }

    @objc func callHistoryRow(_ sender: HistoryRow) {
        makeCall(to: sender.phone)
    }

    @objc func clearHistory() {
        guard !HistoryStore.shared.records.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = L("clear_history_alert_title")
        alert.informativeText = L("clear_history_alert_text")
        alert.addButton(withTitle: L("clear_history"))
        alert.addButton(withTitle: L("cancel_btn"))
        alert.buttons[0].hasDestructiveAction = true

        alert.window.appearance = NSAppearance(named: .darkAqua)

        if let appWindow = self.window {
            alert.beginSheetModal(for: appWindow) { response in
                if response == .alertFirstButtonReturn {
                    HistoryStore.shared.clear()
                }
            }
        } else {
            if alert.runModal() == .alertFirstButtonReturn {
                HistoryStore.shared.clear()
            }
        }
    }

    @objc func toggleFavoriteRow(_ sender: ContactRow) {
        ContactStore.shared.toggleFavorite(id: sender.contactID)
    }
    
    private var currentDetailContactID: UUID?

    @objc func showContactDetail(_ sender: ContactRow) {
        guard let contact = ContactStore.shared.contacts.first(where: { $0.id == sender.contactID }) else { return }
        currentDetailContactID = contact.id
        let history = HistoryStore.shared.records(forContactID: contact.id)
        detailPanelView.configure(contact: contact, history: history)

        guard !isDetailPanelOpen, let window = window else {
            return
        }
        isDetailPanelOpen = true
        detailPanelWidthConstraint.constant = MainWindowController.detailPanelWidth

        var frame = window.frame
        let newWidth = frame.width + MainWindowController.detailPanelWidth
        frame.size.width = newWidth
        frame.origin.x -= MainWindowController.detailPanelWidth / 2

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
        detailPanelWidthConstraint.constant = 0

        var frame = window.frame
        frame.size.width -= MainWindowController.detailPanelWidth
        frame.origin.x += MainWindowController.detailPanelWidth / 2

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }, completionHandler: completion)
    }

    private func refreshDetailPanelIfShowing(id: UUID) {
        guard isDetailPanelOpen, currentDetailContactID == id,
              let contact = ContactStore.shared.contacts.first(where: { $0.id == id }) else { return }
        let history = HistoryStore.shared.records(forContactID: id)
        detailPanelView.configure(contact: contact, history: history)
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

    private func deleteContact(_ contact: Contact) {
        let alert = NSAlert()
        alert.messageText = L("delete_alert_title")
        alert.informativeText = L("delete_alert_text", contact.fullName)
        alert.addButton(withTitle: L("delete_btn"))
        alert.addButton(withTitle: L("cancel_btn"))
        alert.buttons[0].hasDestructiveAction = true

        alert.window.appearance = NSAppearance(named: .darkAqua)

        if let appWindow = self.window {
            alert.beginSheetModal(for: appWindow) { response in
                guard response == .alertFirstButtonReturn else { return }
                // The sheet's own dismiss animation is still finishing when
                // this handler fires. Wait for it to clear before starting
                // our window-resize animation, so the two don't compete for
                // frames and the panel close still looks like one smooth
                // motion instead of a jump cut.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    var contacts = ContactStore.shared.contacts
                    contacts.removeAll { $0.id == contact.id }
                    ContactStore.shared.contacts = contacts
                    NotificationCenter.default.post(name: .contactsDidChange, object: nil)
                }
            }
        } else {
            if alert.runModal() == .alertFirstButtonReturn {
                var contacts = ContactStore.shared.contacts
                contacts.removeAll { $0.id == contact.id }
                ContactStore.shared.contacts = contacts
                NotificationCenter.default.post(name: .contactsDidChange, object: nil)
            }
        }
    }

    func makeCall(to phone: String) {
        let urlString = "tel:\(phone.sanitizedForCall)"
        guard let url = URL(string: urlString) else { return }
        
        let match = ContactStore.shared.contacts.first(where: { $0.phone.sanitizedForCall == phone.sanitizedForCall })

        let appDelegate = NSApp.delegate as? AppDelegate
        appDelegate?.suppressFaceTime()

        // Keep the detail panel open if the call being placed belongs to the
        // contact currently shown there — only close it for calls to someone else.
        if !(isDetailPanelOpen && currentDetailContactID != nil && match?.id == currentDetailContactID) {
            // Start the panel-close animation first. Opening the tel: URL
            // activates another app (a context switch that costs a frame or
            // two on our side), and the toast/history-record work also does
            // layout — all of that happens after, in the completion handler,
            // so none of it can steal the animation's first frame.
            hideContactDetail { [weak self] in
                NSWorkspace.shared.open(url)
                self?.showCallInProgressToast()
                HistoryStore.shared.addRecord(phone: phone, name: match?.fullName, contactID: match?.id)
            }
        } else {
            NSWorkspace.shared.open(url)
            showCallInProgressToast()
            HistoryStore.shared.addRecord(phone: phone, name: match?.fullName, contactID: match?.id)
        }
    }

    private var activeVisibleSearchField: NSSearchField? {
        if !contactsView.isHidden && !contactsSearchField.isHidden {
            return contactsSearchField
        } else if !favoritesView.isHidden && !favoritesSearchField.isHidden {
            return favoritesSearchField
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

    private func showCallInProgressToast() {
        guard let contentView = window?.contentView else { return }

        callToastHideWorkItem?.cancel()

        if callToastView == nil {
            let toast = NSView()
            toast.wantsLayer = true
            toast.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.92).cgColor
            toast.layer?.cornerRadius = 10
            toast.translatesAutoresizingMaskIntoConstraints = false
            toast.alphaValue = 0

            let label = NSTextField(labelWithString: L("call_in_progress"))
            label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            label.textColor = NSColor(white: 0.92, alpha: 1)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: hideWorkItem)
    }

    @objc func openAdd() {
        addWindowController = AddContactWindowController(contactToEdit: nil)
        addWindowController?.showWindow(nil)
        addWindowController?.window?.makeKeyAndOrderFront(nil)
    }
    
    @objc private func updateUIVisibility() {
        contactsSearchField.stringValue = ""
        favoritesSearchField.stringValue = ""
        refreshAll()
        
        let hideContacts = UserDefaults.standard.bool(forKey: "hideContactsMenu")
        let hideKeypad = UserDefaults.standard.bool(forKey: "hideKeypadMenu")
        let hideFavorites = UserDefaults.standard.bool(forKey: "hideFavoritesMenu")
        let hideHistory = UserDefaults.standard.bool(forKey: "hideHistoryMenu")
        let hidePlus = UserDefaults.standard.bool(forKey: "hidePlusButton")
        let searchVisibility = UserDefaults.standard.integer(forKey: "searchBarVisibility")
        let hideAll = hideContacts && hideKeypad && hideFavorites && hideHistory

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            
            self.contactsButton.isHidden = hideContacts
            self.dialButton.isHidden = hideKeypad
            self.favoritesButton.isHidden = hideFavorites
            self.historyButton.isHidden = hideHistory
            self.plusButton?.isHidden = hidePlus
            
            self.contactsSearchField.isHidden = (searchVisibility == 1 || searchVisibility == 3)
            self.favoritesSearchField.isHidden = (searchVisibility == 2 || searchVisibility == 3)
            
            if hideAll {
                self.contactsView.isHidden = true
                self.dialerView.isHidden = true
                self.favoritesView.isHidden = true
                self.historyView.isHidden = true
                self.emptyStateView.isHidden = false
            } else {
                self.emptyStateView.isHidden = true

                // Διασφαλίζουμε ότι αν το τρέχον ενεργό μενού μόλις απενεργοποιήθηκε, πάμε σε άλλο διαθέσιμο.
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

            if let id = self.currentDetailContactID {
                self.refreshDetailPanelIfShowing(id: id)
            }
        }
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        return window.isZoomed
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

    convenience init(contact: Contact, target: AnyObject, action: Selector, favoriteAction: Selector? = nil, editAction: Selector? = nil, deleteAction: Selector? = nil, detailAction: Selector? = nil) {
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
        setupUI(contact: contact)
    }

    private func setupUI(contact: Contact) {
        wantsLayer = true

    let avatarView = RoundAvatarView(diameter: 34)
    avatarView.configure(image: contact.image, initials: contact.initials, colorOverride: contact.monogramColor)
    avatarView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(avatarView)

    let nameLabel = NSTextField(labelWithString: contact.fullName)
    nameLabel.font = NSFont.systemFont(ofSize: 15, weight: .medium)
    nameLabel.textColor = .white
    nameLabel.isEditable = false
    nameLabel.isSelectable = false
    nameLabel.isBezeled = false
    nameLabel.drawsBackground = false
    nameLabel.lineBreakMode = .byTruncatingTail
    nameLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(nameLabel)

    let phoneLabel = NSTextField(labelWithString: contact.phone)
    phoneLabel.font = NSFont.systemFont(ofSize: 12)
    phoneLabel.textColor = NSColor(white: 0.55, alpha: 1)
    phoneLabel.isEditable = false
    phoneLabel.isSelectable = false
    phoneLabel.isBezeled = false
    phoneLabel.drawsBackground = false
    phoneLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(phoneLabel)

    let textStack = NSStackView(views: [nameLabel, phoneLabel])
    textStack.orientation = .vertical
    textStack.alignment = .leading
    textStack.spacing = 2
    textStack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(textStack)

    let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let ellipsisImg = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: L("tools"))?.withSymbolConfiguration(config)?.vertical()

        optionsButton = NSButton(image: ellipsisImg ?? NSImage(), target: self, action: #selector(showOptionsMenu))
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

    NSLayoutConstraint.activate([
        avatarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
        avatarView.centerYAnchor.constraint(equalTo: centerYAnchor),
        avatarView.widthAnchor.constraint(equalToConstant: 34),
        avatarView.heightAnchor.constraint(equalToConstant: 34),

        textStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
        textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        textStack.trailingAnchor.constraint(lessThanOrEqualTo: optionsButton.leadingAnchor, constant: -6),
        
        optionsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        optionsButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        optionsButton.widthAnchor.constraint(equalToConstant: 28),
        optionsButton.heightAnchor.constraint(equalToConstant: 28),

        line.bottomAnchor.constraint(equalTo: bottomAnchor),
        line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 58),
        line.trailingAnchor.constraint(equalTo: trailingAnchor),
        line.heightAnchor.constraint(equalToConstant: 0.5),
    ])

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
}

class HistoryRow: NSView {
    /// Πώς εμφανίζεται το avatar της γραμμής:
    /// - `.phoneIcon`: πάντα το ίδιο εικονίδιο τηλεφώνου (χρησιμοποιείται στο
    ///   ιστορικό μέσα στις λεπτομέρειες μιας συγκεκριμένης επαφής, όπου η
    ///   φωτογραφία/μονόγραμμα της επαφής φαίνεται ήδη από πάνω).
    /// - `.contactPhoto`: η πραγματική φωτογραφία/μονόγραμμα της επαφής (ή
    ///   ένα γενικό "#" όταν η κλήση δεν αντιστοιχεί σε αποθηκευμένη επαφή).
    ///   Χρησιμοποιείται στο γενικό μενού «Ιστορικό» όπου κάθε γραμμή αφορά
    ///   ενδεχομένως διαφορετική επαφή.
    enum AvatarStyle {
        case phoneIcon
        case contactPhoto
    }

    var phone: String = ""
    private var target: AnyObject?
    private var action: Selector?

    convenience init(record: CallRecord, target: AnyObject, action: Selector, avatarStyle: AvatarStyle = .phoneIcon) {
        self.init(frame: .zero)
        self.phone = record.phone
        self.target = target
        self.action = action
        setupUI(record: record, avatarStyle: avatarStyle)
    }

    private func setupUI(record: CallRecord, avatarStyle: AvatarStyle) {
        wantsLayer = true

        let avatarView: NSView
        switch avatarStyle {
        case .phoneIcon:
            // Πάντα εικονίδιο τηλεφώνου εδώ αντί για την φωτογραφία/μονόγραμμα
            // της επαφής, ώστε η λίστα ιστορικού να μην επαναλαμβάνει οπτικά
            // την ίδια εικόνα σε κάθε γραμμή.
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
            let matchedContact = record.contactID.flatMap { id in
                ContactStore.shared.contacts.first(where: { $0.id == id })
            }
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

        let displayName = record.contactName ?? record.phone
        let nameLabel = NSTextField(labelWithString: displayName)
        nameLabel.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        nameLabel.textColor = .white
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        nameLabel.isBezeled = false
        nameLabel.drawsBackground = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        let timeLabel = NSTextField(labelWithString: df.string(from: record.date))
        timeLabel.font = NSFont.systemFont(ofSize: 12)
        timeLabel.textColor = NSColor(white: 0.55, alpha: 1)
        timeLabel.isEditable = false
        timeLabel.isSelectable = false
        timeLabel.isBezeled = false
        timeLabel.drawsBackground = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)
        
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            avatarView.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 34),
            avatarView.heightAnchor.constraint(equalToConstant: 34),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),
            
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            line.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 58),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(rowTapped(_:)))
        addGestureRecognizer(click)
    }

    @objc func rowTapped(_ gesture: NSGestureRecognizer) {
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
}

class ContactDetailPanelView: NSView {
    var onClose: (() -> Void)?
    var onCall: ((String) -> Void)?
    var onFavoriteToggle: ((UUID) -> Void)?
    var onEdit: ((Contact) -> Void)?
    var onDelete: ((Contact) -> Void)?

    private var currentContact: Contact?

    private let avatarView = RoundAvatarView(diameter: 84)
    private let nameLabel = NSTextField(labelWithString: "")
    private let phoneLabel = NSTextField(labelWithString: "")
    private let callButton = CircleActionButton()
    private let favoriteButton = CircleActionButton()
    private let editButton = CircleActionButton()
    private let deleteButton = CircleActionButton()
    private let historyTitleLabel = NSTextField(labelWithString: "")
    private let historyScrollView = NSScrollView()
    private let historyStack = NSStackView()
    private let emptyHistoryLabel = NSTextField(labelWithString: "")
    private let historyDivider = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
    wantsLayer = true
    layer?.backgroundColor = NSColor(red: 0.13, green: 0.13, blue: 0.145, alpha: 1).cgColor
    layer?.masksToBounds = true

    let closeConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
    let closeImg = NSImage(systemSymbolName: "xmark", accessibilityDescription: L("close_details"))?.withSymbolConfiguration(closeConfig)
    let closeButton = NSButton(image: closeImg ?? NSImage(), target: self, action: #selector(closeTapped))
    closeButton.bezelStyle = .regularSquare
    closeButton.isBordered = false
    closeButton.contentTintColor = NSColor(white: 0.55, alpha: 1)
    closeButton.translatesAutoresizingMaskIntoConstraints = false
    addSubview(closeButton)

    avatarView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(avatarView)

    nameLabel.font = NSFont.boldSystemFont(ofSize: 18)
    nameLabel.textColor = .white
    nameLabel.alignment = .center
    nameLabel.isEditable = false
    nameLabel.isSelectable = false
    nameLabel.isBezeled = false
    nameLabel.drawsBackground = false
    nameLabel.lineBreakMode = .byTruncatingTail
    nameLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(nameLabel)

    phoneLabel.font = NSFont.systemFont(ofSize: 13)
    phoneLabel.textColor = NSColor(white: 0.55, alpha: 1)
    phoneLabel.alignment = .center
    phoneLabel.isEditable = false
    phoneLabel.isSelectable = false
    phoneLabel.isBezeled = false
    phoneLabel.drawsBackground = false
    phoneLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(phoneLabel)

    // Neutral circular background for every button; color lives only on
    // the glyph itself (previously the whole disc was filled with the
    // action's color, which is what the user asked to change).
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

    // ★ Νέα style: ουδέτερος κύκλος, χρώμα μόνο στο glyph
    styleCircleButton(callButton, glyph: .phone,
                       color: NSColor.systemGreen, accessibility: L("call_tooltip"))
    callButton.target = self
    callButton.action = #selector(callTapped)
    addSubview(callButton)

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

    let actionsStack = NSStackView(views: [callButton, favoriteButton, editButton, deleteButton])
    actionsStack.orientation = .horizontal
    actionsStack.distribution = .equalSpacing
    actionsStack.spacing = 18
    actionsStack.alignment = .centerY
    actionsStack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(actionsStack)

    // Αφαιρούμε το installShadowLayer – τα κουμπιά πλέον είναι flat

    let divider = historyDivider
    divider.wantsLayer = true
    divider.layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor
    divider.translatesAutoresizingMaskIntoConstraints = false
    addSubview(divider)

    historyTitleLabel.stringValue = L("recent_calls")
    historyTitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
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
    emptyHistoryLabel.font = NSFont.systemFont(ofSize: 12)
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

        divider.topAnchor.constraint(equalTo: actionsStack.bottomAnchor, constant: 24),
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
}

    func configure(contact: Contact, history: [CallRecord]) {
        currentContact = contact
        avatarView.configure(image: contact.image, initials: contact.initials, colorOverride: contact.monogramColor)
        nameLabel.stringValue = contact.fullName
        phoneLabel.stringValue = contact.phone

        favoriteButton.isHidden = UserDefaults.standard.bool(forKey: "hideFavoritesMenu")

        favoriteButton.glyph = .star
        favoriteButton.starFilled = contact.isFavorite
        favoriteButton.glyphColor = contact.isFavorite ? NSColor.systemOrange : NSColor(white: 0.55, alpha: 1)

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

    @objc private func callTapped() {
        guard let contact = currentContact else { return }
        onCall?(contact.phone)
    }

    @objc private func favoriteTapped() {
        guard let contact = currentContact else { return }
        onFavoriteToggle?(contact.id)
    }

    @objc private func editTapped() {
        guard let contact = currentContact else { return }
        onEdit?(contact)
    }

    @objc private func deleteTapped() {
        guard let contact = currentContact else { return }
        onDelete?(contact)
    }

    @objc private func historyRowTapped(_ sender: HistoryRow) {
        onCall?(sender.phone)
    }
}

/// Which SF Symbol to draw for this action button. Hand-drawn custom
/// silhouettes were tried here and repeatedly came out wrong (phone looked
/// like a dumbbell, pencil had no distinguishable tip/eraser, trash can
/// looked like a hat) — SF Symbols are already correct, tested, and
/// macOS-native, so we draw those instead, tinted to just the glyph with
/// a neutral circular background behind it.
enum CircleActionGlyph {
    case star
    case phone
    case pencil
    case trash

    var symbolName: String {
        switch self {
        case .star: return "star.fill"
        case .phone: return "phone.fill"
        case .pencil: return "pencil"
        case .trash: return "trash.fill"
        }
    }

    var outlineSymbolName: String {
        switch self {
        case .star: return "star"
        default: return symbolName
        }
    }
}

class CircleActionButton: NSButton {
    private var hovered = false
    private var pressed = false
    private var trackingArea: NSTrackingArea?

    /// Neutral, colorless circular background — the same for every action
    /// button. Previously each button's *entire disc* was filled with the
    /// action's color (green/orange/blue/red); the request was to move
    /// that color onto the glyph only and keep the button itself neutral,
    /// like macOS's own toolbar/segmented-control buttons.
    static let neutralFill = NSColor.white.withAlphaComponent(0.08)

    /// Color applied to the glyph only.
    var glyphColor: NSColor = .white {
        didSet { updateGlyphImageView() }
    }

    var glyph: CircleActionGlyph = .star {
        didSet { updateGlyphImageView() }
    }

    /// Only relevant when glyph == .star: filled vs outline star, mirroring
    /// the favorited / not-favorited state.
    var starFilled: Bool = true {
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
        // No layer-based masking and no system bezel: NSButton's default
        // cell drawing (even with isBordered = false / bezelStyle set) was
        // painting its own rounded-rect bezel on top of our circular layer
        // fill — that stray shape is what rendered as an "oval" in the
        // screenshot. Disabling the cell's own drawing entirely and doing
        // 100% of the rendering in draw(_:) below removes that hidden
        // shape for good.
        wantsLayer = false
        isBordered = false
        showsBorderOnlyWhileMouseInside = false
        title = ""
        (cell as? NSButtonCell)?.isBordered = false
        (cell as? NSButtonCell)?.imageScaling = .scaleNone
        updateGlyphImageView()
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 44, height: 44)
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
        // Neutral circular base — this is the ONLY shape drawn behind the
        // glyph, and it's identical across all four buttons. The glyph
        // itself is a real NSImageView subview (see glyphImageView) rather
        // than something drawn here — using NSImageView + contentTintColor
        // is the same technique already used correctly elsewhere in this
        // app (e.g. the main call button), and avoids the custom
        // lockFocus-based tinting that was producing flipped/rotated
        // glyphs for some symbols.
        let circle = NSBezierPath(ovalIn: bounds)
        CircleActionButton.neutralFill.setFill()
        circle.fill()

        if hovered || pressed {
            NSColor.white.withAlphaComponent(pressed ? 0.14 : 0.08).setFill()
            circle.fill()
        }
        // Deliberately no super.draw(_:) call — that would invoke
        // NSButtonCell's own bezel/background drawing on top of ours.
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
        let symbolName = (glyph == .star && !starFilled) ? glyph.outlineSymbolName : glyph.symbolName
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
        if let existing = trackingArea { removeTrackingArea(existing) }
    }
}

class DialerKey: NSButton {
    var digit: String = ""

    convenience init(digit: String, target: AnyObject, action: Selector) {
        self.init(frame: .zero)
        self.digit = digit
        self.target = target
        self.action = action
        setupUI(digit: digit)
    }

    private func setupUI(digit: String) {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor
        layer?.cornerRadius = 32
        isBordered = false
        bezelStyle = .regularSquare
        title = ""

        let digitLabel = NSTextField(labelWithString: digit)
        digitLabel.font = NSFont.systemFont(ofSize: 28, weight: .light)
        digitLabel.textColor = .white
        digitLabel.alignment = .center
        digitLabel.isEditable = false
        digitLabel.isSelectable = false
        digitLabel.isBezeled = false
        digitLabel.drawsBackground = false
        digitLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(digitLabel)

        NSLayoutConstraint.activate([
            digitLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            digitLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        translatesAutoresizingMaskIntoConstraints = false

        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 64, height: 64)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor(white: 0.32, alpha: 1).cgColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor
    }
    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor(white: 0.14, alpha: 1).cgColor
        super.mouseDown(with: event)
        layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor
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