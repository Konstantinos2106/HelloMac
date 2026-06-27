import AppKit

// NSWindow subclass που αποκλείει πλήρως το full screen
class NonFullScreenWindow: NSWindow {
    override func toggleFullScreen(_ sender: Any?) {
        // Σκόπιμα κενό — το full screen είναι απενεργοποιημένο
    }
}

class MainWindowController: NSWindowController, NSWindowDelegate {
    private var stackView: NSStackView!
    private var favoritesView: NSView!
    private var dialerView: NSView!
    private var favButton: NSButton!
    private var dialButton: NSButton!
    private var displayLabel: NSTextField!
    private var addWindowController: AddContactWindowController?
    private var removeWindowController: RemoveContactWindowController?

    // Expose for menu actions
    func showFavoritesPublic()  { showFavorites() }
    func showDialerPublic()     { showDialer() }
    func openAddPublic()        { openAdd() }
    func openRemovePublic()     { openRemove() }

    convenience init() {
        let window = NonFullScreenWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "HelloMac"
        window.titlebarAppearsTransparent = true
        window.center()
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        window.minSize = NSSize(width: 280, height: 480)
        window.maxSize = NSSize(width: 600, height: 900)
        // Απενεργοποίηση full screen — καμία επιλογή full screen
        window.collectionBehavior = [.managed, .fullScreenNone]
        self.init(window: window)
        window.delegate = self
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        // Tab Bar κάτω
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

        favButton = makeTabButton(symbolName: "star.fill", title: L("contacts"), action: #selector(showFavorites))
        dialButton = makeTabButton(symbolName: "circle.grid.3x3.fill", title: L("keypad"), action: #selector(showDialer))

        tabBar.addSubview(favButton)
        tabBar.addSubview(dialButton)

        // Favorites View
        favoritesView = NSView()
        favoritesView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(favoritesView)
        setupFavoritesView()

        // Dialer View
        dialerView = NSView()
        dialerView.translatesAutoresizingMaskIntoConstraints = false
        dialerView.isHidden = true
        contentView.addSubview(dialerView)
        setupDialer()

        NSLayoutConstraint.activate([
            tabBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            tabBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 60),

            sep.bottomAnchor.constraint(equalTo: tabBar.topAnchor),
            sep.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 0.5),

            favButton.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor),
            favButton.widthAnchor.constraint(equalTo: tabBar.widthAnchor, multiplier: 0.5),
            favButton.topAnchor.constraint(equalTo: tabBar.topAnchor),
            favButton.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor),

            dialButton.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor),
            dialButton.widthAnchor.constraint(equalTo: tabBar.widthAnchor, multiplier: 0.5),
            dialButton.topAnchor.constraint(equalTo: tabBar.topAnchor),
            dialButton.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor),

            favoritesView.topAnchor.constraint(equalTo: contentView.topAnchor),
            favoritesView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            favoritesView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            favoritesView.bottomAnchor.constraint(equalTo: sep.topAnchor),

            dialerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            dialerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            dialerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            dialerView.bottomAnchor.constraint(equalTo: sep.topAnchor),
        ])

        showFavorites()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshContacts), name: .contactsDidChange, object: nil)
    }

    private func setupFavoritesView() {
        let titleLabel = NSTextField(labelWithString: L("contacts"))
        titleLabel.font = NSFont.boldSystemFont(ofSize: 17)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        favoritesView.addSubview(titleLabel)

        // Κουμπί Προσθήκης
        let addImg = NSImage(systemSymbolName: "person.badge.plus", accessibilityDescription: L("add_tooltip"))
        let addBtn = NSButton(image: addImg ?? NSImage(), target: self, action: #selector(openAdd))
        addBtn.bezelStyle = .regularSquare
        addBtn.isBordered = false
        addBtn.contentTintColor = NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        if let cell = addBtn.cell as? NSButtonCell { cell.imageScaling = .scaleProportionallyUpOrDown }
        favoritesView.addSubview(addBtn)

        // Κουμπί Διαγραφής
        let removeImg = NSImage(systemSymbolName: "person.badge.minus", accessibilityDescription: L("remove_tooltip"))
        let removeBtn = NSButton(image: removeImg ?? NSImage(), target: self, action: #selector(openRemove))
        removeBtn.bezelStyle = .regularSquare
        removeBtn.isBordered = false
        removeBtn.contentTintColor = NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1)
        removeBtn.translatesAutoresizingMaskIntoConstraints = false
        if let cell = removeBtn.cell as? NSButtonCell { cell.imageScaling = .scaleProportionallyUpOrDown }
        favoritesView.addSubview(removeBtn)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        favoritesView.addSubview(scrollView)

        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stackView

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: favoritesView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: favoritesView.leadingAnchor, constant: 16),

            // Διαγραφή — πιο δεξιά
            removeBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            removeBtn.trailingAnchor.constraint(equalTo: favoritesView.trailingAnchor, constant: -14),
            removeBtn.widthAnchor.constraint(equalToConstant: 26),
            removeBtn.heightAnchor.constraint(equalToConstant: 26),

            // Προσθήκη — αριστερά από διαγραφή
            addBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            addBtn.trailingAnchor.constraint(equalTo: removeBtn.leadingAnchor, constant: -10),
            addBtn.widthAnchor.constraint(equalToConstant: 26),
            addBtn.heightAnchor.constraint(equalToConstant: 26),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: favoritesView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: favoritesView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: favoritesView.bottomAnchor),

            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        refreshContacts()
    }

    private func setupDialer() {
        // Wrapper για κεντράρισμα όλου του περιεχομένου κάθετα
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

        // Οθόνη αριθμών — απλό label με clip, αριστερή στοίχιση όταν γεμίζει
        displayLabel = NSTextField(labelWithString: "")
        displayLabel.font = NSFont.systemFont(ofSize: 38, weight: .thin)
        displayLabel.textColor = .white
        displayLabel.alignment = .left
        displayLabel.translatesAutoresizingMaskIntoConstraints = false
        displayLabel.lineBreakMode = .byClipping
        displayLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        displayLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        centerWrapper.addSubview(displayLabel)

        // Delete button
        let deleteImg = NSImage(systemSymbolName: "delete.left", accessibilityDescription: L("remove_tooltip"))
        let deleteBtn = NSButton(image: deleteImg ?? NSImage(), target: self, action: #selector(deleteLast))
        deleteBtn.bezelStyle = .regularSquare
        deleteBtn.isBordered = false
        deleteBtn.contentTintColor = NSColor(white: 0.65, alpha: 1)
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        if let cell = deleteBtn.cell as? NSButtonCell { cell.imageScaling = .scaleProportionallyUpOrDown }
        centerWrapper.addSubview(deleteBtn)

        // Grid πληκτρολογίου — μόνο αριθμοί, χωρίς γράμματα
        let keys: [(String, String)] = [
            ("1",""), ("2",""), ("3",""),
            ("4",""), ("5",""), ("6",""),
            ("7",""), ("8",""), ("9",""),
            ("*",""), ("0",""), ("#","")
        ]

        let gridStack = NSStackView()
        gridStack.orientation = .vertical
        gridStack.spacing = 14
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        centerWrapper.addSubview(gridStack)

        for row in 0..<4 {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.spacing = 14
            rowStack.distribution = .fillEqually
            for col in 0..<3 {
                let idx = row * 3 + col
                let (digit, letters) = keys[idx]
                let btn = DialerKey(digit: digit, letters: letters, target: self, action: #selector(keyPressed(_:)))
                rowStack.addArrangedSubview(btn)
            }
            gridStack.addArrangedSubview(rowStack)
        }

        // Κουμπί κλήσης
        let callBtn = NSButton(title: "", target: self, action: #selector(dialNumber))
        callBtn.bezelStyle = .regularSquare
        callBtn.isBordered = false
        callBtn.wantsLayer = true
        callBtn.layer?.backgroundColor = NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1).cgColor
        callBtn.layer?.cornerRadius = 34
        callBtn.translatesAutoresizingMaskIntoConstraints = false
        
        // ΑΣΦΑΛΗΣ ΕΛΕΓΧΟΣ ΓΙΑ macOS 11 (Big Sur)
        let baseImg = NSImage(systemSymbolName: "phone.fill", accessibilityDescription: L("call_tooltip"))
        let callImg: NSImage?
        
        if #available(macOS 12.0, *) {
            let callSymbolConfig = NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
            callImg = baseImg?.withSymbolConfiguration(callSymbolConfig)
        } else {
            // Στο Big Sur χρησιμοποιούμε το απλό εικονίδιο χωρίς το SymbolConfiguration
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
            displayLabel.leadingAnchor.constraint(equalTo: centerWrapper.leadingAnchor, constant: 16),
            displayLabel.trailingAnchor.constraint(equalTo: centerWrapper.trailingAnchor, constant: -52),
            displayLabel.heightAnchor.constraint(equalToConstant: 52),

            deleteBtn.centerYAnchor.constraint(equalTo: displayLabel.centerYAnchor),
            deleteBtn.trailingAnchor.constraint(equalTo: centerWrapper.trailingAnchor, constant: -14),
            deleteBtn.widthAnchor.constraint(equalToConstant: 30),
            deleteBtn.heightAnchor.constraint(equalToConstant: 30),

            gridStack.topAnchor.constraint(equalTo: displayLabel.bottomAnchor, constant: 10),
            gridStack.leadingAnchor.constraint(equalTo: centerWrapper.leadingAnchor, constant: 16),
            gridStack.trailingAnchor.constraint(equalTo: centerWrapper.trailingAnchor, constant: -16),

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

    @objc func showFavorites() {
        favoritesView.isHidden = false
        dialerView.isHidden = true
        updateTabColors(active: "star.fill", inactive: "circle.grid.3x3.fill")
    }

    @objc func showDialer() {
        favoritesView.isHidden = true
        dialerView.isHidden = false
        updateTabColors(active: "circle.grid.3x3.fill", inactive: "star.fill")
    }

    private func updateTabColors(active: String, inactive: String) {
        let blue = NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
        let gray = NSColor(white: 0.5, alpha: 1)
        for btn in [favButton, dialButton] {
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
        case 0...11:  size = 38
        case 12...14: size = 30
        case 15...18: size = 24
        default:      size = 18
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
        if contacts.isEmpty {
            let empty = NSTextField(labelWithString: L("no_contacts"))
            empty.alignment = .center
            empty.textColor = NSColor(white: 0.5, alpha: 1)
            empty.font = NSFont.systemFont(ofSize: 13)
            empty.maximumNumberOfLines = 2
            stackView.addArrangedSubview(empty)
        } else {
            for contact in contacts {
                let row = ContactRow(contact: contact, target: self, action: #selector(callRow(_:)))
                stackView.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
                row.heightAnchor.constraint(equalToConstant: 58).isActive = true
            }
        }
    }

    @objc func callRow(_ sender: ContactRow) {
        makeCall(to: sender.phone)
    }

    func makeCall(to phone: String) {
        guard let url = URL(string: "tel:\(phone)") else { return }
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

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        return window.isZoomed
    }
}

// MARK: - Contact Row
class ContactRow: NSView {
    var phone: String = ""
    private var target: AnyObject?
    private var action: Selector?

    convenience init(contact: Contact, target: AnyObject, action: Selector) {
        self.init(frame: .zero)
        self.phone = contact.phone
        self.target = target
        self.action = action
        setupUI(contact: contact)
    }

    private func setupUI(contact: Contact) {
        wantsLayer = true

        let phoneImg = NSImage(systemSymbolName: "phone.fill", accessibilityDescription: L("call_tooltip"))
        let iconView = NSImageView(image: phoneImg ?? NSImage())
        iconView.contentTintColor = NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        let nameLabel = NSTextField(labelWithString: contact.name)
        nameLabel.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        nameLabel.textColor = .white
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        let phoneLabel = NSTextField(labelWithString: contact.phone)
        phoneLabel.font = NSFont.systemFont(ofSize: 13)
        phoneLabel.textColor = NSColor(white: 0.55, alpha: 1)
        phoneLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(phoneLabel)

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

            phoneLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            phoneLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            line.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 48),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(click)
    }

    @objc func tapped() {
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

// MARK: - Dialer Key
class DialerKey: NSButton {
    var digit: String = ""

    convenience init(digit: String, letters: String, target: AnyObject, action: Selector) {
        self.init(frame: .zero)
        self.digit = digit
        self.target = target
        self.action = action
        setupUI(digit: digit, letters: letters)
    }

    private func setupUI(digit: String, letters: String) {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor
        layer?.cornerRadius = 28
        isBordered = false
        bezelStyle = .regularSquare
        title = ""

        let digitLabel = NSTextField(labelWithString: digit)
        digitLabel.font = NSFont.systemFont(ofSize: 26, weight: .light)
        digitLabel.textColor = .white
        digitLabel.alignment = .center
        digitLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(digitLabel)

        if !letters.isEmpty {
            let lettersLabel = NSTextField(labelWithString: letters)
            lettersLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
            lettersLabel.textColor = NSColor(white: 0.7, alpha: 1)
            lettersLabel.alignment = .center
            lettersLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(lettersLabel)
            NSLayoutConstraint.activate([
                digitLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                digitLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -7),
                lettersLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                lettersLabel.topAnchor.constraint(equalTo: digitLabel.bottomAnchor, constant: 0),
            ])
        } else {
            NSLayoutConstraint.activate([
                digitLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                digitLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        translatesAutoresizingMaskIntoConstraints = false

        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 56, height: 56)
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