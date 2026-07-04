import AppKit

// NSWindow subclass που αποκλείει πλήρως το full screen
class NonFullScreenWindow: NSWindow {
    override func toggleFullScreen(_ sender: Any?) {
        // Σκόπιμα κενό — το full screen είναι απενεργοποιημένο
    }
}

// MARK: - Πληκτρολόγηση αριθμών από το φυσικό πληκτρολόγιο
protocol KeyCaptureDelegate: AnyObject {
    func keyCaptureDidType(digit: String)
    func keyCaptureDidBackspace()
    func keyCaptureDidPressEnter()
}

class KeyCaptureView: NSView {
    weak var keyDelegate: KeyCaptureDelegate?

    override var acceptsFirstResponder: Bool { true }

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
        case 51, 117: // Delete / Forward Delete
            keyDelegate?.keyCaptureDidBackspace()
        default:
            break
        }
    }
}

class MainWindowController: NSWindowController, NSWindowDelegate, KeyCaptureDelegate {
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
    private var addWindowController: AddContactWindowController?
    private var removeWindowController: RemoveContactWindowController?
    
    private var plusButton: DialerKey?
    
    // Νέα ανεξάρτητα labels για τις άδειες λίστες
    private var emptyContactsLabel: NSTextField!
    private var emptyFavoritesLabel: NSTextField!

    // Expose for menu actions
    func showContactsPublic()  { showContacts() }
    func showFavoritesPublic() { showFavorites() }
    func showDialerPublic()    { showDialer() }
    func openAddPublic()       { openAdd() }
    func openRemovePublic()    { openRemove() }

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

        // Contacts View
        contactsView = NSView()
        contactsView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contactsView)
        setupContactsView()

        // Favorites View
        favoritesView = NSView()
        favoritesView.translatesAutoresizingMaskIntoConstraints = false
        favoritesView.isHidden = true
        contentView.addSubview(favoritesView)
        setupFavoritesView()

        // Dialer View
        dialerView = KeyCaptureView()
        dialerView.keyDelegate = self
        dialerView.translatesAutoresizingMaskIntoConstraints = false
        dialerView.isHidden = true
        contentView.addSubview(dialerView)
        setupDialer()
        
        // Empty State View (Όταν όλα τα μενού είναι κλειστά)
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

        let removeImg = NSImage(systemSymbolName: "person.badge.minus", accessibilityDescription: L("remove_tooltip"))
        let removeBtn = NSButton(image: removeImg ?? NSImage(), target: self, action: #selector(openRemove))
        removeBtn.bezelStyle = .regularSquare
        removeBtn.isBordered = false
        removeBtn.contentTintColor = NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1)
        removeBtn.translatesAutoresizingMaskIntoConstraints = false
        if let cell = removeBtn.cell as? NSButtonCell { cell.imageScaling = .scaleProportionallyUpOrDown }
        contactsView.addSubview(removeBtn)

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

        // Το ανεξάρτητο label για άδεια λίστα επαφών
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

            removeBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            removeBtn.trailingAnchor.constraint(equalTo: contactsView.trailingAnchor, constant: -14),
            removeBtn.widthAnchor.constraint(equalToConstant: 26),
            removeBtn.heightAnchor.constraint(equalToConstant: 26),

            addBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            addBtn.trailingAnchor.constraint(equalTo: removeBtn.leadingAnchor, constant: -10),
            addBtn.widthAnchor.constraint(equalToConstant: 26),
            addBtn.heightAnchor.constraint(equalToConstant: 26),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contactsView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contactsView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contactsView.bottomAnchor),

            stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            
            // Τοποθέτηση του label στο κέντρο του scroll view, ελαφρώς προς τα πάνω
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

        // Το ανεξάρτητο label για άδεια λίστα αγαπημένων
        emptyFavoritesLabel = NSTextField(labelWithString: L("no_favorites"))
        emptyFavoritesLabel.alignment = .center
        emptyFavoritesLabel.textColor = NSColor(white: 0.5, alpha: 1)
        emptyFavoritesLabel.font = NSFont.systemFont(ofSize: 13)
        emptyFavoritesLabel.maximumNumberOfLines = 2
        emptyFavoritesLabel.isEditable = false
        emptyFavoritesLabel.isSelectable = false
        emptyFavoritesLabel.isBezeled = false
        emptyFavoritesLabel.drawsBackground = false
        emptyFavoritesLabel.translatesAutoresizingMaskIntoConstraints = false
        favoritesView.addSubview(emptyFavoritesLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: favoritesView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: favoritesView.leadingAnchor, constant: 16),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: favoritesView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: favoritesView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: favoritesView.bottomAnchor),

            favoritesStackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            
            // Τοποθέτηση του label στο κέντρο του scroll view, ελαφρώς προς τα πάνω
            emptyFavoritesLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyFavoritesLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor, constant: -20)
        ])

        refreshFavorites()
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
        let callImg: NSImage?
        
        if #available(macOS 12.0, *) {
            let callSymbolConfig = NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
            callImg = baseImg?.withSymbolConfiguration(callSymbolConfig)
        } else {
            callImg = baseImg
        }
        
        let callIconView = NSImageView(image: callImg ?? NSImage())
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

    @objc func refreshContacts() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let contacts = ContactStore.shared.contacts
        
        // Διαχείριση της ορατότητας του ανεξάρτητου label
        emptyContactsLabel.isHidden = !contacts.isEmpty
        
        for contact in contacts {
            let row = ContactRow(contact: contact, target: self, action: #selector(callRow(_:)), favoriteAction: #selector(toggleFavoriteRow(_:)))
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: 58).isActive = true
        }
    }

    @objc func refreshFavorites() {
        favoritesStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let favorites = ContactStore.shared.favorites
        
        // Διαχείριση της ορατότητας του ανεξάρτητου label
        emptyFavoritesLabel.isHidden = !favorites.isEmpty
        
        for contact in favorites {
            let row = ContactRow(contact: contact, target: self, action: #selector(callRow(_:)), favoriteAction: #selector(toggleFavoriteRow(_:)))
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

    func makeCall(to phone: String) {
        guard let url = URL(string: "tel:\(phone.sanitizedForCall)") else { return }
        let appDelegate = NSApp.delegate as? AppDelegate
        appDelegate?.suppressFaceTime()
        NSWorkspace.shared.open(url)
    }

    @objc func openAdd() {
        if addWindowController == nil {
            addWindowController = AddContactWindowController()
        }
        addWindowController?.showWindow(nil)
        addWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func openRemove() {
        if removeWindowController == nil {
            removeWindowController = RemoveContactWindowController()
        }
        removeWindowController?.showWindow(nil)
        removeWindowController?.window?.makeKeyAndOrderFront(nil)
    }
    
    @objc private func updateUIVisibility() {
        let hideContacts = UserDefaults.standard.bool(forKey: "hideContactsMenu")
        let hideKeypad = UserDefaults.standard.bool(forKey: "hideKeypadMenu")
        let hideFavorites = UserDefaults.standard.bool(forKey: "hideFavoritesMenu")
        let hidePlus = UserDefaults.standard.bool(forKey: "hidePlusButton")
        let hideAll = hideContacts && hideKeypad && hideFavorites

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.allowsImplicitAnimation = true
            
            self.contactsButton.isHidden = hideContacts
            self.dialButton.isHidden = hideKeypad
            self.favoritesButton.isHidden = hideFavorites
            self.plusButton?.isHidden = hidePlus 
            
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
    private var favoriteButton: NSButton!
    private var isFavorite: Bool = false

    convenience init(contact: Contact, target: AnyObject, action: Selector, favoriteAction: Selector? = nil) {
        self.init(frame: .zero)
        self.phone = contact.phone
        self.contactID = contact.id
        self.target = target
        self.action = action
        self.favoriteAction = favoriteAction
        self.isFavorite = contact.isFavorite
        setupUI(contact: contact)
    }

    private func setupUI(contact: Contact) {
        wantsLayer = true

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

        let starImg = NSImage(systemSymbolName: contact.isFavorite ? "star.fill" : "star",
                               accessibilityDescription: contact.isFavorite ? L("favorite_remove_tooltip") : L("favorite_add_tooltip"))
        
        favoriteButton = NSButton(image: starImg ?? NSImage(), target: nil, action: nil)
        favoriteButton.bezelStyle = .regularSquare
        favoriteButton.isBordered = false
        favoriteButton.contentTintColor = contact.isFavorite ? NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1) : NSColor(white: 0.45, alpha: 1)
        favoriteButton.translatesAutoresizingMaskIntoConstraints = false
        if let cell = favoriteButton.cell as? NSButtonCell { cell.imageScaling = .scaleProportionallyUpOrDown }
        addSubview(favoriteButton)

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

            favoriteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            favoriteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            favoriteButton.widthAnchor.constraint(equalToConstant: 20),
            favoriteButton.heightAnchor.constraint(equalToConstant: 20),

            phoneLabel.trailingAnchor.constraint(equalTo: favoriteButton.leadingAnchor, constant: -12),
            phoneLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            line.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 48),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(rowTapped(_:)))
        addGestureRecognizer(click)
    }

    @objc func rowTapped(_ gesture: NSGestureRecognizer) {
        let location = gesture.location(in: self)
        
        let hitRect = favoriteButton.frame.insetBy(dx: -15, dy: -15)
        
        if hitRect.contains(location) {
            starTapped()
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

    @objc func starTapped() {
        isFavorite.toggle()
        let img = NSImage(systemSymbolName: isFavorite ? "star.fill" : "star",
                           accessibilityDescription: isFavorite ? L("favorite_remove_tooltip") : L("favorite_add_tooltip"))
        favoriteButton.image = img
        favoriteButton.contentTintColor = isFavorite ? NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1) : NSColor(white: 0.45, alpha: 1)
        
        if let favoriteAction = favoriteAction {
            NSApp.sendAction(favoriteAction, to: target, from: self)
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