import AppKit

// MARK: - Παράθυρο Προσθήκης Επαφής
class AddContactWindowController: NSWindowController {
    private var nameField: NSTextField!
    private var phoneField: NSTextField!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 280),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("settings_title")
        window.center()
        window.isReleasedWhenClosed = false
        
        // 1. Καλούμε πρώτα το self.init
        self.init(window: window)
        
        // 2. Μετά καλούμε το setupUI, που πλέον μπορεί να χρησιμοποιήσει το 'self'
        setupUI()
    }
    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: L("new_contact"))
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        nameField = NSTextField()
        nameField.placeholderString = L("name")
        nameField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameField)

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

            nameField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            nameField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nameField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            phoneField.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 10),
            phoneField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            phoneField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            addButton.topAnchor.constraint(equalTo: phoneField.bottomAnchor, constant: 20),
            addButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            addButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16),

            cancelButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -8),
        ])
    }

    @objc func addContact() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        let phone = phoneField.stringValue.trimmingCharacters(in: .whitespaces)

        guard !name.isEmpty, !phone.isEmpty else {
            let alert = NSAlert()
            alert.messageText = L("fill_fields")
            alert.runModal()
            return
        }

        var contacts = ContactStore.shared.contacts
        contacts.append(Contact(name: name, phone: phone))
        ContactStore.shared.contacts = contacts
        NotificationCenter.default.post(name: .contactsDidChange, object: nil)

        nameField.stringValue = ""
        phoneField.stringValue = ""
        window?.close()
    }

    @objc func cancel() {
        nameField.stringValue = ""
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
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
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
        nameCol.width = 160

        let phoneCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("phone"))
        phoneCol.title = "HelloMac"
        phoneCol.width = 160

        tableView.addTableColumn(nameCol)
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
        // Ανανέωσε τη λίστα κάθε φορά που ανοίγει
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
        alert.informativeText = L("delete_alert_text", contacts[row].name)
        alert.addButton(withTitle: L("remove_tooltip"))
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

    // MARK: TableView
    func numberOfRows(in tableView: NSTableView) -> Int { contacts.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let contact = contacts[row]
        let cell = NSTextField()
        cell.isBezeled = false
        cell.isEditable = false
        cell.backgroundColor = .clear
        cell.stringValue = tableColumn?.identifier.rawValue == "name" ? contact.name : contact.phone
        return cell
    }
}
// MARK: - Μοντέρνο Παράθυρο Ρυθμίσεων (Auto Layout & Κεντράρισμα)
class SettingsWindowController: NSWindowController {
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
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
        
        let versionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
        let versionLabel = NSTextField(labelWithString: L("current_version", versionString))
        versionLabel.alignment = .center
        versionLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let checkButton = NSButton(title: L("check_now"), target: NSApp.delegate, action: Selector(("menuCheckUpdates")))
        checkButton.bezelStyle = .rounded
        checkButton.controlSize = .large
        checkButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Ομαδοποίηση και κεντράρισμα
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
            updatesView.heightAnchor.constraint(equalToConstant: 220)
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
        
        // Γραμμή 1: Επαφές
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
        
        // Γραμμή 2: Πληκτρολόγιο
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
        
        // Ομαδοποίηση και κεντράρισμα
        let appearanceStack = NSStackView(views: [contactsRow, separator, keypadRow])
        appearanceStack.orientation = .vertical
        appearanceStack.spacing = 16
        appearanceStack.translatesAutoresizingMaskIntoConstraints = false
        appearanceView.addSubview(appearanceStack)
        
        NSLayoutConstraint.activate([
            appearanceStack.centerXAnchor.constraint(equalTo: appearanceView.centerXAnchor),
            appearanceStack.centerYAnchor.constraint(equalTo: appearanceView.centerYAnchor),
            contactsRow.widthAnchor.constraint(equalToConstant: 280),
            separator.widthAnchor.constraint(equalToConstant: 300),
            keypadRow.widthAnchor.constraint(equalToConstant: 280),
            appearanceView.widthAnchor.constraint(equalToConstant: 400),
            appearanceView.heightAnchor.constraint(equalToConstant: 220)
        ])
        
        appearanceVC.view = appearanceView
        appearanceVC.title = L("tab_appearance")
        let appearanceTab = NSTabViewItem(viewController: appearanceVC)
        appearanceTab.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        
        // Προσθήκη Καρτελών στον Controller
        tabViewController.addTabViewItem(updatesTab)
        tabViewController.addTabViewItem(appearanceTab)
        
        window.contentViewController = tabViewController
    }
    
    @objc private func toggleFeature(_ sender: NSSwitch) {
        if sender.identifier?.rawValue == "showContactsMenu" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hideContactsMenu")
        } else if sender.identifier?.rawValue == "showKeypadMenu" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hideKeypadMenu")
        }
        
        NotificationCenter.default.post(name: NSNotification.Name("UpdateUIVisibility"), object: nil)
    }
}