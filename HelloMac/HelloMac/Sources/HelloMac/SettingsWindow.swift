import AppKit

// MARK: - Παράθυρο Προσθήκης/Επεξεργασίας Επαφής
class AddContactWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    private var firstNameField: NSTextField!
    private var lastNameField: NSTextField!
    private var phoneField: NSTextField!
    
    var contactToEdit: Contact?

    convenience init(contactToEdit: Contact? = nil) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        // Επιβολή Dark Mode
        window.appearance = NSAppearance(named: .darkAqua)
        
        if let mainWindow = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.title == "HelloMac" }) {
            let x = mainWindow.frame.midX - window.frame.width / 2
            let y = mainWindow.frame.midY - window.frame.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.center()
        }
        
        window.isReleasedWhenClosed = false
        
        self.init(window: window)
        window.delegate = self
        
        self.contactToEdit = contactToEdit
        window.title = contactToEdit == nil ? L("add_contact_menu") : L("edit_contact")
        setupUI()
        populateData()
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: contactToEdit == nil ? L("new_contact") : L("edit_contact"))
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        firstNameField = NSTextField()
        firstNameField.placeholderString = L("first_name_placeholder")
        firstNameField.translatesAutoresizingMaskIntoConstraints = false
        firstNameField.delegate = self
        contentView.addSubview(firstNameField)

        lastNameField = NSTextField()
        lastNameField.placeholderString = L("last_name_placeholder")
        lastNameField.translatesAutoresizingMaskIntoConstraints = false
        lastNameField.delegate = self
        contentView.addSubview(lastNameField)

        phoneField = NSTextField()
        phoneField.placeholderString = L("phone_placeholder")
        phoneField.translatesAutoresizingMaskIntoConstraints = false
        phoneField.delegate = self 
        contentView.addSubview(phoneField)

        let addButton = NSButton(title: contactToEdit == nil ? L("add_btn") : L("save_btn"), target: self, action: #selector(saveContact))
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
    
    private func populateData() {
        if let contact = contactToEdit {
            firstNameField.stringValue = contact.firstName
            lastNameField.stringValue = contact.lastName
            phoneField.stringValue = contact.phone
        }
    }

    @objc func saveContact() {
        let firstName = firstNameField.stringValue.trimmingCharacters(in: .whitespaces)
        let lastName = lastNameField.stringValue.trimmingCharacters(in: .whitespaces)
        let phone = phoneField.stringValue.trimmingCharacters(in: .whitespaces)

        guard !firstName.isEmpty, !phone.isEmpty else {
            let alert = NSAlert()
            alert.messageText = L("fill_fields")
            alert.runModal()
            return
        }

        if var contact = contactToEdit {
            contact.firstName = firstName
            contact.lastName = lastName
            contact.phone = phone
            ContactStore.shared.updateContact(contact)
        } else {
            var contacts = ContactStore.shared.contacts
            contacts.append(Contact(firstName: firstName, lastName: lastName, phone: phone))
            ContactStore.shared.contacts = contacts
            NotificationCenter.default.post(name: .contactsDidChange, object: nil)
        }

        firstNameField.stringValue = ""
        lastNameField.stringValue = ""
        phoneField.stringValue = ""
        window?.close()
    }

    @objc func cancel() {
        window?.close()
    }
    
    func controlTextDidChange(_ obj: Notification) {
        if let textField = obj.object as? NSTextField, textField == phoneField {
            let allowedCharacters = CharacterSet(charactersIn: "+0123456789")
            
            let currentText = textField.stringValue
            let filteredText = currentText.unicodeScalars.filter { allowedCharacters.contains($0) }
            
            let newText = String(String.UnicodeScalarView(filteredText))
            if currentText != newText {
                textField.stringValue = newText
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
}

// MARK: - Μοντέρνο Παράθυρο Ρυθμίσεων
class SettingsWindowController: NSWindowController {
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 350), 
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("settings_title")
        
        // Επιβολή Dark Mode
        window.appearance = NSAppearance(named: .darkAqua)
        
        if let mainWindow = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.title == "HelloMac" }) {
            let x = mainWindow.frame.midX - window.frame.width / 2
            let y = mainWindow.frame.midY - window.frame.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.center()
        }
        
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
        
        let versionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.2"
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
            updatesView.widthAnchor.constraint(equalToConstant: 440),
            updatesView.heightAnchor.constraint(equalToConstant: 310) 
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
        
        // Dropdown Αναζήτησης
        let searchVisibilityRow = NSStackView()
        searchVisibilityRow.orientation = .horizontal
        let searchVisibilityLabel = NSTextField(labelWithString: L("search_visibility"))
        searchVisibilityLabel.font = NSFont.systemFont(ofSize: 14)
        searchVisibilityRow.addView(searchVisibilityLabel, in: .leading)
        
        let searchPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        searchPopup.addItems(withTitles: [L("search_everywhere"), L("search_favorites"), L("search_contacts"), L("search_hidden")])
        searchPopup.selectItem(at: UserDefaults.standard.integer(forKey: "searchBarVisibility"))
        searchPopup.target = self
        searchPopup.action = #selector(searchVisibilityChanged(_:))
        searchVisibilityRow.addView(searchPopup, in: .trailing)
        
        let separator0 = NSBox()
        separator0.boxType = .separator
        separator0.translatesAutoresizingMaskIntoConstraints = false
        
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
        
        let plusRow = NSStackView()
        plusRow.orientation = .horizontal
        let plusLabel = NSTextField(labelWithString: L("show_plus_tab"))
        plusLabel.font = NSFont.systemFont(ofSize: 14)
        plusRow.addView(plusLabel, in: .leading)
        let plusSwitch = NSSwitch()
        plusSwitch.target = self
        plusSwitch.action = #selector(toggleFeature(_:))
        plusSwitch.identifier = NSUserInterfaceItemIdentifier("showPlusButton")
        plusSwitch.state = UserDefaults.standard.bool(forKey: "hidePlusButton") ? .off : .on
        plusRow.addView(plusSwitch, in: .trailing)
        
        let appearanceStack = NSStackView(views: [searchVisibilityRow, separator0, favoritesRow, separator2, contactsRow, separator, keypadRow, separator3, plusRow])
        appearanceStack.orientation = .vertical
        appearanceStack.spacing = 16
        appearanceStack.translatesAutoresizingMaskIntoConstraints = false
        appearanceView.addSubview(appearanceStack)
        
        NSLayoutConstraint.activate([
            appearanceStack.centerXAnchor.constraint(equalTo: appearanceView.centerXAnchor),
            appearanceStack.centerYAnchor.constraint(equalTo: appearanceView.centerYAnchor),
            searchVisibilityRow.widthAnchor.constraint(equalToConstant: 320),
            separator0.widthAnchor.constraint(equalToConstant: 340),
            favoritesRow.widthAnchor.constraint(equalToConstant: 320),
            separator2.widthAnchor.constraint(equalToConstant: 340),
            contactsRow.widthAnchor.constraint(equalToConstant: 320),
            separator.widthAnchor.constraint(equalToConstant: 340),
            keypadRow.widthAnchor.constraint(equalToConstant: 320),
            separator3.widthAnchor.constraint(equalToConstant: 340),
            plusRow.widthAnchor.constraint(equalToConstant: 320),
            appearanceView.widthAnchor.constraint(equalToConstant: 440),
            appearanceView.heightAnchor.constraint(equalToConstant: 310)
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
            UserDefaults.standard.set(sender.state == .off, forKey: "hidePlusButton") 
        }
        
        NotificationCenter.default.post(name: NSNotification.Name("UpdateUIVisibility"), object: nil)
    }
    
    @objc private func searchVisibilityChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: "searchBarVisibility")
        NotificationCenter.default.post(name: NSNotification.Name("UpdateUIVisibility"), object: nil)
    }
}