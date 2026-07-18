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

// MARK: - Ετικέτα με υποστήριξη κέρσορα (Χεράκι) για συνδέσμους
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

// MARK: - Καθαρό Δεξί Κλικ
class CleanFieldEditor: NSTextView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let defaultMenu = super.menu(for: event) ?? NSMenu()
        let isGreek = Locale.preferredLanguages.first?.hasPrefix("el") ?? true
        let newMenu = NSMenu()
        
        // 1. Απενεργοποίηση της αυτόματης προσθήκης του μενού "Υπηρεσίες" (Services) από το macOS
        newMenu.allowsContextMenuPlugIns = false
        
        // 2. Βασικές λειτουργίες στα Ελληνικά/Αγγλικά
        newMenu.addItem(NSMenuItem(title: isGreek ? "Αποκοπή" : "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: ""))
        newMenu.addItem(NSMenuItem(title: isGreek ? "Αντιγραφή" : "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: ""))
        newMenu.addItem(NSMenuItem(title: isGreek ? "Επικόλληση" : "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: ""))
        
        // 3. Αναζήτηση της αυθεντικής επιλογής Google από το σύστημα
        var googleItem: NSMenuItem?
        
        for item in defaultMenu.items {
            let actionStr = item.action?.description ?? ""
            let title = item.title.lowercased()
            
            if actionStr.contains("WebSearch") || actionStr.contains("Google") || title.contains("google") {
                googleItem = item.copy() as? NSMenuItem
                googleItem?.title = isGreek ? "Αναζήτηση με το Google" : "Search with Google"
            }
        }
        
        // 4. Δυναμική δημιουργία του native Share Picker του macOS αν υπάρχει επιλεγμένο κείμενο
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
                
        // 5. Προσθήκη Google & Share στο τέλος (με διαχωριστικό) αν βρέθηκαν
        if googleItem != nil || shareItem != nil {
            newMenu.addItem(NSMenuItem.separator())
            if let g = googleItem { newMenu.addItem(g) }
            if let s = shareItem { newMenu.addItem(s) }
        }
        
        return newMenu
    }
    
    // Εμφάνιση του πλούσιου (native) αναδυόμενου μενού κοινοποίησης του macOS
    @objc private func openSharePicker(_ sender: NSMenuItem) {
        let selectedRange = self.selectedRange()
        guard selectedRange.length > 0 else { return }
        let selectedText = (self.string as NSString).substring(with: selectedRange)
        
        // Δημιουργία του επίσημου Picker με το επιλεγμένο κείμενο
        let picker = NSSharingServicePicker(items: [selectedText])
        
        // Εμφάνιση ακριβώς κάτω από το πεδίο αναζητήσεως
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
    private var contactsView: NSView!
    private var favoritesView: NSView!
    private var dialerView: KeyCaptureView!
    private var emptyStateView: NSView!
    private var contactsButton: NSButton!
    private var favoritesButton: NSButton!
    private var dialButton: NSButton!
    private var displayLabel: NSTextField!
    
    private var contactsSearchField: NSSearchField!
    private var favoritesSearchField: NSSearchField!
    
    private var addWindowController: AddContactWindowController?
    private var editWindowController: AddContactWindowController?
    
    private var plusButton: DialerKey?
    
    private var emptyContactsLabel: NSTextField!
    private var emptyFavoritesLabel: ClickableLabel!

    // MARK: - Ενημέρωση κλήσης (εμφανίζεται σε κάθε κλήση)
    private var callToastView: NSView?
    private var callToastHideWorkItem: DispatchWorkItem?
    private var callToastTopConstraint: NSLayoutConstraint?

    func showContactsPublic()  { showContacts() }
    func showFavoritesPublic() { showFavorites() }
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
        window.maxSize = NSSize(width: 600, height: 900)
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
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let tabBar = NSView()
        tabBar.wantsLayer = true
        tabBar.layer?.backgroundColor = NSColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1).cgColor
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tabBar)

        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(white: 0.28, alpha: 1).cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sep)

        contactsButton = makeTabButton(symbolName: "person.2.fill", title: L("contacts"), action: #selector(showContacts))
        favoritesButton = makeTabButton(symbolName: "star.fill", title: L("favorites"), action: #selector(showFavorites))
        dialButton = makeTabButton(symbolName: "circle.grid.3x3.fill", title: L("keypad"), action: #selector(showDialer))

        let tabStack = NSStackView(views: [favoritesButton, contactsButton, dialButton])
        tabStack.orientation = .horizontal
        tabStack.distribution = .equalSpacing
        tabStack.spacing = 44
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
            
            contactsButton.widthAnchor.constraint(equalToConstant: 70),
            contactsButton.heightAnchor.constraint(equalTo: tabStack.heightAnchor),
            favoritesButton.widthAnchor.constraint(equalToConstant: 70),
            favoritesButton.heightAnchor.constraint(equalTo: tabStack.heightAnchor),
            dialButton.widthAnchor.constraint(equalToConstant: 70),
            dialButton.heightAnchor.constraint(equalTo: tabStack.heightAnchor),

            contactsView.topAnchor.constraint(equalTo: contentView.topAnchor),
            contactsView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contactsView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contactsView.bottomAnchor.constraint(equalTo: sep.topAnchor),

            favoritesView.topAnchor.constraint(equalTo: contentView.topAnchor),
            favoritesView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            favoritesView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            favoritesView.bottomAnchor.constraint(equalTo: sep.topAnchor),

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
        } else if !UserDefaults.standard.bool(forKey: "hideContactsMenu") {
            showContacts()
        } else if !UserDefaults.standard.bool(forKey: "hideKeypadMenu") {
            showDialer()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAll), name: .contactsDidChange, object: nil)
    }

    @objc private func focusSearchField() {
        if !contactsView.isHidden && !contactsSearchField.isHidden {
            window?.makeFirstResponder(contactsSearchField)
        } else if !favoritesView.isHidden && !favoritesSearchField.isHidden {
            window?.makeFirstResponder(favoritesSearchField)
        }
    }
    
    @objc private func refreshAll() {
        refreshContacts()
        refreshFavorites()
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
    
    // MARK: - Διαχείριση κλικ στο κενό μήνυμα Αγαπημένων
@objc private func emptyFavoritesClicked(_ gesture: NSClickGestureRecognizer) {
    // Ελέγχουμε αν βρισκόμαστε πράγματι σε κατάσταση κενής αναζήτησης
    guard !emptyFavoritesLabel.isHidden, !favoritesSearchField.stringValue.isEmpty else { return }
    
    // Μετάβαση στην καρτέλα "Επαφές"
    showContacts()
    
    // Αντιγραφή του κειμένου αναζήτησης στις Επαφές για άμεση εύρεση (Έξυπνο UX!)
    if !favoritesSearchField.stringValue.isEmpty {
        contactsSearchField.stringValue = favoritesSearchField.stringValue
        refreshContacts()
    }
}

// Δημιουργία Styled Text με τη λέξη "Επαφές" ως μπλε υπογραμμισμένο σύνδεσμο
private func setFavoritesEmptySearchText() {
    let text = L("no_favorites_search")
    let linkWord = L("contacts") // Επιστρέφει "Επαφές" στα Ελληνικά και "Contacts" στα Αγγλικά
    
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
            .foregroundColor: NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1), // Μπλε χρώμα εφαρμογής
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
        contactsView.isHidden = false
        favoritesView.isHidden = true
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
        dialerView.isHidden = true
        emptyStateView.isHidden = true
        refreshFavorites()
        updateTabColors(active: "star.fill")
        window?.makeFirstResponder(nil)
        repositionCallToast()
    }

    @objc func showDialer() {
        let hideKeypad = UserDefaults.standard.bool(forKey: "hideKeypadMenu")
        guard !hideKeypad else { return }
        contactsView.isHidden = true
        favoritesView.isHidden = true
        dialerView.isHidden = false
        emptyStateView.isHidden = true
        updateTabColors(active: "circle.grid.3x3.fill")
        window?.makeFirstResponder(dialerView)
        repositionCallToast()
    }

    private func updateTabColors(active: String) {
        let blue = NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
        let gray = NSColor(white: 0.5, alpha: 1)
        for btn in [contactsButton, favoritesButton, dialButton] {
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

    // Εφαρμόζει το καθαρό μενού σε όλες τις αναζητήσεις του παραθύρου
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
        
        let filtered = searchString.isEmpty ? allContacts : allContacts.filter {
            $0.fullName.lowercased().contains(searchString) || $0.phone.contains(searchString)
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
            let row = ContactRow(contact: contact, target: self, action: #selector(callRow(_:)), favoriteAction: #selector(toggleFavoriteRow(_:)), editAction: #selector(editContactRow(_:)), deleteAction: #selector(deleteContactRow(_:)))
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: 58).isActive = true
        }
    }

    @objc func refreshFavorites() {
        favoritesStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let allFavorites = ContactStore.shared.favorites
        let searchString = favoritesSearchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        
        let filtered = searchString.isEmpty ? allFavorites : allFavorites.filter {
            $0.fullName.lowercased().contains(searchString) || $0.phone.contains(searchString)
        }
        
        if allFavorites.isEmpty {
            emptyFavoritesLabel.stringValue = L("no_favorites")
            emptyFavoritesLabel.isLinkActive = false
            emptyFavoritesLabel.isHidden = false
        } else if filtered.isEmpty {
            setFavoritesEmptySearchText()
            emptyFavoritesLabel.isLinkActive = true // Ενεργοποιεί το κλικ και το "χεράκι" στον κέρσορα
            emptyFavoritesLabel.isHidden = false
        } else {
            emptyFavoritesLabel.isLinkActive = false
            emptyFavoritesLabel.isHidden = true
        }
        
        for contact in filtered {
            let row = ContactRow(contact: contact, target: self, action: #selector(callRow(_:)), favoriteAction: #selector(toggleFavoriteRow(_:)), editAction: #selector(editContactRow(_:)), deleteAction: #selector(deleteContactRow(_:)))
            favoritesStackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: favoritesStackView.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: 58).isActive = true
        }
    }

    @objc func callRow(_ sender: ContactRow) {
        makeCall(to: sender.phone)
    }

    @objc func toggleFavoriteRow(_ sender: ContactRow) {
        ContactStore.shared.toggleFavorite(id: sender.contactID)
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
            let alert = NSAlert()
            alert.messageText = L("delete_alert_title")
            alert.informativeText = L("delete_alert_text", contact.fullName)
            alert.addButton(withTitle: L("delete_btn"))
            alert.addButton(withTitle: L("cancel_btn"))
            alert.buttons[0].hasDestructiveAction = true
            
            // Επιβολή Dark Mode
            alert.window.appearance = NSAppearance(named: .darkAqua) 
            
            if let appWindow = self.window {
                alert.beginSheetModal(for: appWindow) { response in
                    if response == .alertFirstButtonReturn {
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
    }

    func makeCall(to phone: String) {
        let urlString = "tel:\(phone.sanitizedForCall)"
        guard let url = URL(string: urlString) else { return }
        
        let appDelegate = NSApp.delegate as? AppDelegate
        appDelegate?.suppressFaceTime()
        
        NSWorkspace.shared.open(url)
        
        // Διακριτική ενημέρωση σε κάθε κλήση: μην ξεκινήσεις άλλη κλήση
        // όσο αυτή είναι ενεργή (δεν υπάρχει τρόπος να το ελέγξουμε προγραμματιστικά).
        showCallInProgressToast()
    }

    // Επιστρέφει το view του ενεργού search field (contacts/favorites), ή nil αν
    // βρισκόμαστε στο πληκτρολόγιο ή αν η μπάρα αναζήτησης είναι κρυμμένη εκεί.
    private var activeVisibleSearchField: NSSearchField? {
        if !contactsView.isHidden && !contactsSearchField.isHidden {
            return contactsSearchField
        } else if !favoritesView.isHidden && !favoritesSearchField.isHidden {
            return favoritesSearchField
        }
        return nil
    }

    // Ενημερώνει τη θέση του toast: κάτω από τη μπάρα αναζήτησης αν είναι ορατή,
    // αλλιώς στη θέση της (ίδιο top offset με τη μπάρα, δηλαδή κάτω από τον τίτλο).
    private func repositionCallToast() {
        guard let contentView = window?.contentView, let toast = callToastView else { return }

        callToastTopConstraint?.isActive = false

        if let searchField = activeVisibleSearchField {
            // Ακριβώς κάτω από τη μπάρα αναζήτησης (για Επαφές & Αγαπημένα όταν η αναζήτηση είναι ορατή)
            callToastTopConstraint = toast.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8)
        } else if !dialerView.isHidden {
            // ΜΟΝΟ στο μενού Πληκτρολόγιο: ανέβασμα ψηλά στην κορυφή του παραθύρου
            // ώστε να μην καλύπτει καθόλου την οθόνη πληκτρολόγησης του αριθμού
            callToastTopConstraint = toast.topAnchor.constraint(equalTo: dialerView.topAnchor, constant: 12)
        } else {
            // Η μπάρα αναζήτησης είναι κρυμμένη στις Επαφές/Αγαπημένα:
            // εμφάνισε το toast κάτω από τον τίτλο (εκεί όπου θα ήταν κανονικά η μπάρα).
            let referenceView: NSView
            if !contactsView.isHidden {
                referenceView = contactsView
            } else if !favoritesView.isHidden {
                referenceView = favoritesView
            } else {
                referenceView = contentView
            }
            callToastTopConstraint = toast.topAnchor.constraint(equalTo: referenceView.topAnchor, constant: 44)
        }

        callToastTopConstraint?.isActive = true
    }

    // MARK: - Διακριτικό toast (χωρίς alert/sheet, δεν διακόπτει τον χρήστη)
    private func showCallInProgressToast() {
        guard let contentView = window?.contentView else { return }

        // Αν υπάρχει ήδη ένα toast, απλά ανανέωσε τον χρόνο εξαφάνισής του
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
            
            // --- ΔΥΝΑΜΙΚΗ ΑΛΛΑΓΗ ΓΡΑΜΜΩΝ ---
            label.maximumNumberOfLines = 0
            label.cell?.wraps = true
            label.cell?.truncatesLastVisibleLine = false
            label.lineBreakMode = .byWordWrapping
            
            // 1. ΚΡΙΣΙΜΟ: Μειώνουμε την αντίσταση οριζόντιας συμπίεσης.
            // Έτσι το AppKit αναγκάζεται να σπάσει το κείμενο σε 2η/3η γραμμή
            // αντί να μεγαλώσει το πλάτος του παραθύρου!
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
                
                // 2. ΚΡΙΣΙΜΟ: Αντί για στατικό 400, περιορίζουμε το μέγιστο πλάτος του toast 
                // αυστηρά στο μέγεθος του παραθύρου μείον τα περιθώρια (20px από κάθε πλευρά).
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
    if addWindowController == nil {
        addWindowController = AddContactWindowController(contactToEdit: nil)
    }
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
        let hidePlus = UserDefaults.standard.bool(forKey: "hidePlusButton")
        let searchVisibility = UserDefaults.standard.integer(forKey: "searchBarVisibility")
        let hideAll = hideContacts && hideKeypad && hideFavorites

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            
            self.contactsButton.isHidden = hideContacts
            self.dialButton.isHidden = hideKeypad
            self.favoritesButton.isHidden = hideFavorites
            self.plusButton?.isHidden = hidePlus
            
            self.contactsSearchField.isHidden = (searchVisibility == 1 || searchVisibility == 3)
            self.favoritesSearchField.isHidden = (searchVisibility == 2 || searchVisibility == 3)
            
            if hideAll {
                self.contactsView.isHidden = true
                self.dialerView.isHidden = true
                self.favoritesView.isHidden = true
                self.emptyStateView.isHidden = false
            } else {
                self.emptyStateView.isHidden = true

                if hideContacts && !self.contactsView.isHidden {
                    if !hideFavorites { self.showFavorites() }
                    else { self.showDialer() }
                } else if hideKeypad && !self.dialerView.isHidden {
                    if !hideFavorites { self.showFavorites() }
                    else { self.showContacts() }
                } else if hideFavorites && !self.favoritesView.isHidden {
                    if !hideContacts { self.showContacts() }
                    else { self.showDialer() }
                } else if self.contactsView.isHidden && self.dialerView.isHidden && self.favoritesView.isHidden {
                    if !hideFavorites { self.showFavorites() }
                    else if !hideContacts { self.showContacts() }
                    else if !hideKeypad { self.showDialer() }
                }
            }

            self.repositionCallToast()
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
    private var optionsButton: NSButton!
    private var isFavorite: Bool = false

    convenience init(contact: Contact, target: AnyObject, action: Selector, favoriteAction: Selector? = nil, editAction: Selector? = nil, deleteAction: Selector? = nil) {
        self.init(frame: .zero)
        self.phone = contact.phone
        self.contactID = contact.id
        self.target = target
        self.action = action
        self.favoriteAction = favoriteAction
        self.editAction = editAction
        self.deleteAction = deleteAction
        self.isFavorite = contact.isFavorite
        setupUI(contact: contact)
    }

    private func setupUI(contact: Contact) {
        wantsLayer = true
        
        let optionsMenu = NSMenu()
        
        // Έλεγχος αν το μενού των Αγαπημένων είναι ενεργό στις ρυθμίσεις
        let hideFavorites = UserDefaults.standard.bool(forKey: "hideFavoritesMenu")
        if !hideFavorites {
            let favTitle = contact.isFavorite ? L("favorite_remove_tooltip") : L("favorite_add_tooltip")
            let favMenuItem = NSMenuItem(title: favTitle, action: #selector(toggleFavoriteTapped), keyEquivalent: "")
            favMenuItem.target = self
            optionsMenu.addItem(favMenuItem)
            optionsMenu.addItem(NSMenuItem.separator())
        }
        
        let editMenuItem = NSMenuItem(title: L("edit_contact"), action: #selector(editTapped), keyEquivalent: "")
        editMenuItem.target = self
        optionsMenu.addItem(editMenuItem)
        
        let deleteMenuItem = NSMenuItem(title: L("remove_contact_menu"), action: #selector(deleteTapped), keyEquivalent: "")
        deleteMenuItem.target = self
        optionsMenu.addItem(deleteMenuItem)
        
        self.menu = optionsMenu // Native Right Click

    let phoneImg = NSImage(systemSymbolName: "phone.fill", accessibilityDescription: L("call_tooltip"))
    let iconView = NSImageView(image: phoneImg ?? NSImage())
    iconView.contentTintColor = NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)
    iconView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(iconView)

    let nameLabel = NSTextField(labelWithString: contact.fullName)
    nameLabel.font = NSFont.systemFont(ofSize: 15, weight: .regular)
    nameLabel.textColor = .white
    nameLabel.isEditable = false
    nameLabel.isSelectable = false
    nameLabel.isBezeled = false
    nameLabel.drawsBackground = false
    nameLabel.lineBreakMode = .byTruncatingTail
    nameLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(nameLabel)

    let phoneLabel = NSTextField(labelWithString: contact.phone)
    phoneLabel.font = NSFont.systemFont(ofSize: 13)
    phoneLabel.textColor = NSColor(white: 0.55, alpha: 1)
    phoneLabel.isEditable = false
    phoneLabel.isSelectable = false
    phoneLabel.isBezeled = false
    phoneLabel.drawsBackground = false
    phoneLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(phoneLabel)
    
    let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let ellipsisImg = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: L("tools"))?.withSymbolConfiguration(config)?.vertical()

        optionsButton = NSButton(image: ellipsisImg ?? NSImage(), target: self, action: #selector(showOptionsMenu))
        optionsButton.bezelStyle = .regularSquare
        optionsButton.isBordered = false
        optionsButton.contentTintColor = NSColor(white: 0.55, alpha: 1)
        optionsButton.translatesAutoresizingMaskIntoConstraints = false
        if let cell = optionsButton.cell as? NSButtonCell { cell.imageScaling = .scaleNone }
        addSubview(optionsButton)
    addSubview(optionsButton)
    let line = NSView()
    line.wantsLayer = true
    line.layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor
    line.translatesAutoresizingMaskIntoConstraints = false
    addSubview(line)

    NSLayoutConstraint.activate([
        iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
        iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
        iconView.widthAnchor.constraint(equalToConstant: 20),
        iconView.heightAnchor.constraint(equalToConstant: 20),

        nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
        nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: phoneLabel.leadingAnchor, constant: -8),
        
        optionsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        optionsButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        optionsButton.widthAnchor.constraint(equalToConstant: 20),
        optionsButton.heightAnchor.constraint(equalToConstant: 20),

        phoneLabel.trailingAnchor.constraint(equalTo: optionsButton.leadingAnchor, constant: -8),
        phoneLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

        line.bottomAnchor.constraint(equalTo: bottomAnchor),
        line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 48),
        line.trailingAnchor.constraint(equalTo: trailingAnchor),
        line.heightAnchor.constraint(equalToConstant: 0.5),
    ])

    let click = NSClickGestureRecognizer(target: self, action: #selector(rowTapped(_:)))
    addGestureRecognizer(click)
}
    
    @objc func showOptionsMenu() {
        let location = NSPoint(x: 0, y: optionsButton.bounds.height)
        self.menu?.popUp(positioning: nil, at: location, in: optionsButton)
    }
    
    @objc func editTapped() {
        if let editAction = editAction {
            _ = target?.perform(editAction, with: self)
        }
    }
    
    @objc func deleteTapped() {
        if let deleteAction = deleteAction {
            _ = target?.perform(deleteAction, with: self)
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

    @objc func toggleFavoriteTapped() {
        if let favoriteAction = favoriteAction {
            _ = target?.perform(favoriteAction, with: self)
        }
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