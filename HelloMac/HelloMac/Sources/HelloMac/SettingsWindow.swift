import AppKit

// MARK: - Παράθυρο Προσθήκης Επαφής
class AddContactWindowController: NSWindowController {
    private var firstNameField: NSTextField!
    private var lastNameField: NSTextField!
    private var phoneField: NSTextField!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 210),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("settings_title")
        window.center()
        window.isReleasedWhenClosed = false
        
        self.init(window: window)
        setupUI()
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: L("new_contact"))
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        firstNameField = NSTextField()
        firstNameField.placeholderString = L("first_name_placeholder")
        firstNameField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(firstNameField)

        lastNameField = NSTextField()
        lastNameField.placeholderString = L("last_name_placeholder")
        lastNameField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(lastNameField)

        phoneField = NSTextField()
        phoneField.placeholderString = L("phone_placeholder")
        phoneField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(phoneField)

        let addButton = NSButton(title: L("add_btn"), target: self, action: #selector(addContact))
        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "\r"
        addButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(addButton)

        let cancelButton = NSButton(title: L("cancel_btn"), target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1B}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            firstNameField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            firstNameField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            firstNameField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            lastNameField.topAnchor.constraint(equalTo: firstNameField.bottomAnchor, constant: 10),
            lastNameField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            lastNameField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            phoneField.topAnchor.constraint(equalTo: lastNameField.bottomAnchor, constant: 10),
            phoneField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            phoneField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            addButton.topAnchor.constraint(equalTo: phoneField.bottomAnchor, constant: 20),
            addButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            addButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            cancelButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -8),
        ])
    }

    @objc func addContact() {
        let firstName = firstNameField.stringValue.trimmingCharacters(in: .whitespaces)
        let lastName = lastNameField.stringValue.trimmingCharacters(in: .whitespaces)
        let phone = phoneField.stringValue.trimmingCharacters(in: .whitespaces)

        guard !firstName.isEmpty, !phone.isEmpty else {
            let alert = NSAlert()
            alert.messageText = L("fill_fields")
            alert.runModal()
            return
        }

        var contacts = ContactStore.shared.contacts
        contacts.append(Contact(firstName: firstName, lastName: lastName, phone: phone))
        ContactStore.shared.contacts = contacts
        NotificationCenter.default.post(name: .contactsDidChange, object: nil)

        firstNameField.stringValue = ""
        lastNameField.stringValue = ""
        phoneField.stringValue = ""
        window?.close()
    }

    @objc func cancel() {
        firstNameField.stringValue = ""
        lastNameField.stringValue = ""
        phoneField.stringValue = ""
        window?.close()
    }
}

// MARK: - Παράθυρο Διαγραφής Επαφής
class RemoveContactWindowController: NSWindowController, NSTableViewDelegate, NSTableViewDataSource {
    private var tableView: NSTableView!
    private var contacts: [Contact] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("remove_contact_menu")
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: L("select_to_delete"))
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        tableView = NSTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 36

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = L("name")
        nameCol.width = 125

        let lastNameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("lastName"))
        lastNameCol.title = L("last_name")
        lastNameCol.width = 125

        let phoneCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("phone"))
        phoneCol.title = L("phone")
        phoneCol.width = 135

        tableView.addTableColumn(nameCol)
        tableView.addTableColumn(lastNameCol)
        tableView.addTableColumn(phoneCol)
        
        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        let removeButton = NSButton(title: L("delete_btn"), target: self, action: #selector(removeContact))
        removeButton.bezelStyle = .rounded
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(removeButton)

        let cancelButton = NSButton(title: L("close_btn"), target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1B}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.heightAnchor.constraint(equalToConstant: 180),

            removeButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 16),
            removeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            removeButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16),

            cancelButton.centerYAnchor.constraint(equalTo: removeButton.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -8),
        ])
    }

    override func showWindow(_ sender: Any?) {
        contacts = ContactStore.shared.contacts
        tableView.reloadData()
        super.showWindow(sender)
    }

    @objc func removeContact() {
        let row = tableView.selectedRow
        guard row >= 0 else {
            let alert = NSAlert()
            alert.messageText = L("select_one_to_delete")
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = L("delete_alert_title")
        alert.informativeText = L("delete_alert_text", contacts[row].fullName)
        alert.addButton(withTitle: L("delete_btn"))
        alert.addButton(withTitle: L("cancel_btn"))
        alert.buttons[0].hasDestructiveAction = true
        
        if alert.runModal() == .alertFirstButtonReturn {
            contacts.remove(at: row)
            ContactStore.shared.contacts = contacts
            tableView.reloadData()
            NotificationCenter.default.post(name: .contactsDidChange, object: nil)
        }
    }

    @objc func cancel() {
        window?.close()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { contacts.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let contact = contacts[row]
        let cell = NSTextField()
        cell.isBezeled = false
        cell.isEditable = false
        cell.backgroundColor = .clear
        
        if tableColumn?.identifier.rawValue == "name" {
            cell.stringValue = contact.firstName
        } else if tableColumn?.identifier.rawValue == "lastName" {
            cell.stringValue = contact.lastName
        } else if tableColumn?.identifier.rawValue == "phone" {
            cell.stringValue = contact.phone
        }
        
        return cell
    }
}

// MARK: - Μοντέρνο Παράθυρο Ρυθμίσεων
class SettingsWindowController: NSWindowController {
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), // Αυξήθηκε το ύψος σε 300 για να χωρέσει ο διακόπτης
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("settings_title")
        window.center()
        window.isReleasedWhenClosed = false
        
        self.init(window: window)
        setupUI()
    }
    
    private func setupUI() {
        guard let window = self.window else { return }
        
        let tabViewController = NSTabViewController()
        tabViewController.tabStyle = .toolbar
        
        // ==========================================
        // ΚΑΡΤΕΛΑ 1: ΕΝΗΜΕΡΩΣΕΙΣ
        // ==========================================
        let updatesVC = NSViewController()
        let updatesView = NSView()
        
        let iconImageView = NSImageView(image: NSImage(named: "AppIcon") ?? NSImage())
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.widthAnchor.constraint(equalToConstant: 80).isActive = true
        iconImageView.heightAnchor.constraint(equalToConstant: 80).isActive = true
        
        let versionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1"
        let versionLabel = NSTextField(labelWithString: L("current_version", versionString))
        versionLabel.alignment = .center
        versionLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let checkButton = NSButton(title: L("check_now"), target: NSApp.delegate, action: Selector(("menuCheckUpdates")))
        checkButton.bezelStyle = .rounded
        checkButton.controlSize = .large
        checkButton.translatesAutoresizingMaskIntoConstraints = false
        
        let updatesStack = NSStackView(views: [iconImageView, versionLabel, checkButton])
        updatesStack.orientation = .vertical
        updatesStack.spacing = 16
        updatesStack.alignment = .centerX
        updatesStack.translatesAutoresizingMaskIntoConstraints = false
        updatesView.addSubview(updatesStack)
        
        NSLayoutConstraint.activate([
            updatesStack.centerXAnchor.constraint(equalTo: updatesView.centerXAnchor),
            updatesStack.centerYAnchor.constraint(equalTo: updatesView.centerYAnchor),
            updatesView.widthAnchor.constraint(equalToConstant: 400),
            updatesView.heightAnchor.constraint(equalToConstant: 260) // Προσαρμοσμένο ύψος
        ])
        
        updatesVC.view = updatesView
        updatesVC.title = L("tab_updates")
        let updatesTab = NSTabViewItem(viewController: updatesVC)
        updatesTab.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        
        // ==========================================
        // ΚΑΡΤΕΛΑ 2: ΕΜΦΑΝΙΣΗ
        // ==========================================
        let appearanceVC = NSViewController()
        let appearanceView = NSView()
        
        let favoritesRow = NSStackView()
        favoritesRow.orientation = .horizontal
        let favoritesLabel = NSTextField(labelWithString: L("show_favorites_tab"))
        favoritesLabel.font = NSFont.systemFont(ofSize: 14)
        favoritesRow.addView(favoritesLabel, in: .leading)
        let favoritesSwitch = NSSwitch()
        favoritesSwitch.target = self
        favoritesSwitch.action = #selector(toggleFeature(_:))
        favoritesSwitch.identifier = NSUserInterfaceItemIdentifier("showFavoritesMenu")
        favoritesSwitch.state = UserDefaults.standard.bool(forKey: "hideFavoritesMenu") ? .off : .on
        favoritesRow.addView(favoritesSwitch, in: .trailing)
        
        let separator2 = NSBox()
        separator2.boxType = .separator
        separator2.translatesAutoresizingMaskIntoConstraints = false
        
        let contactsRow = NSStackView()
        contactsRow.orientation = .horizontal
        let contactsLabel = NSTextField(labelWithString: L("show_contacts_tab"))
        contactsLabel.font = NSFont.systemFont(ofSize: 14)
        contactsRow.addView(contactsLabel, in: .leading)
        let contactsSwitch = NSSwitch()
        contactsSwitch.target = self
        contactsSwitch.action = #selector(toggleFeature(_:))
        contactsSwitch.identifier = NSUserInterfaceItemIdentifier("showContactsMenu")
        contactsSwitch.state = UserDefaults.standard.bool(forKey: "hideContactsMenu") ? .off : .on
        contactsRow.addView(contactsSwitch, in: .trailing)
        
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        
        let keypadRow = NSStackView()
        keypadRow.orientation = .horizontal
        let keypadLabel = NSTextField(labelWithString: L("show_keypad_tab"))
        keypadLabel.font = NSFont.systemFont(ofSize: 14)
        keypadRow.addView(keypadLabel, in: .leading)
        let keypadSwitch = NSSwitch()
        keypadSwitch.target = self
        keypadSwitch.action = #selector(toggleFeature(_:))
        keypadSwitch.identifier = NSUserInterfaceItemIdentifier("showKeypadMenu")
        keypadSwitch.state = UserDefaults.standard.bool(forKey: "hideKeypadMenu") ? .off : .on
        keypadRow.addView(keypadSwitch, in: .trailing)
        
        let separator3 = NSBox()
        separator3.boxType = .separator
        separator3.translatesAutoresizingMaskIntoConstraints = false
        
        // Νέος διακόπτης για το πλήκτρο "+"
        let plusRow = NSStackView()
        plusRow.orientation = .horizontal
        let plusLabel = NSTextField(labelWithString: L("show_plus_tab"))
        plusLabel.font = NSFont.systemFont(ofSize: 14)
        plusRow.addView(plusLabel, in: .leading)
        let plusSwitch = NSSwitch()
        plusSwitch.target = self
        plusSwitch.action = #selector(toggleFeature(_:))
        plusSwitch.identifier = NSUserInterfaceItemIdentifier("showPlusButton")
        // Η προεπιλογή είναι να φαίνεται (δηλαδή να μην είναι hide)
        plusSwitch.state = UserDefaults.standard.bool(forKey: "hidePlusButton") ? .off : .on
        plusRow.addView(plusSwitch, in: .trailing)
        
        let appearanceStack = NSStackView(views: [favoritesRow, separator2, contactsRow, separator, keypadRow, separator3, plusRow])
        appearanceStack.orientation = .vertical
        appearanceStack.spacing = 16
        appearanceStack.translatesAutoresizingMaskIntoConstraints = false
        appearanceView.addSubview(appearanceStack)
        
        NSLayoutConstraint.activate([
            appearanceStack.centerXAnchor.constraint(equalTo: appearanceView.centerXAnchor),
            appearanceStack.centerYAnchor.constraint(equalTo: appearanceView.centerYAnchor),
            favoritesRow.widthAnchor.constraint(equalToConstant: 280),
            separator2.widthAnchor.constraint(equalToConstant: 300),
            contactsRow.widthAnchor.constraint(equalToConstant: 280),
            separator.widthAnchor.constraint(equalToConstant: 300),
            keypadRow.widthAnchor.constraint(equalToConstant: 280),
            separator3.widthAnchor.constraint(equalToConstant: 300),
            plusRow.widthAnchor.constraint(equalToConstant: 280),
            appearanceView.widthAnchor.constraint(equalToConstant: 400),
            appearanceView.heightAnchor.constraint(equalToConstant: 260)
        ])
        
        appearanceVC.view = appearanceView
        appearanceVC.title = L("tab_appearance")
        let appearanceTab = NSTabViewItem(viewController: appearanceVC)
        appearanceTab.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        
        tabViewController.addTabViewItem(updatesTab)
        tabViewController.addTabViewItem(appearanceTab)
        
        window.contentViewController = tabViewController
    }
    
    @objc private func toggleFeature(_ sender: NSSwitch) {
        if sender.identifier?.rawValue == "showContactsMenu" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hideContactsMenu")
        } else if sender.identifier?.rawValue == "showKeypadMenu" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hideKeypadMenu")
        } else if sender.identifier?.rawValue == "showFavoritesMenu" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hideFavoritesMenu")
        } else if sender.identifier?.rawValue == "showPlusButton" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hidePlusButton") // Αποθηκεύει τη ρύθμιση για το +
        }
        
        NotificationCenter.default.post(name: NSNotification.Name("UpdateUIVisibility"), object: nil)
    }
}