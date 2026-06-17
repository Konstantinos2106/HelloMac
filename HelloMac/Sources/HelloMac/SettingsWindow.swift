import AppKit

// MARK: - Παράθυρο Προσθήκης Επαφής
class AddContactWindowController: NSWindowController {
    private var nameField: NSTextField!
    private var phoneField: NSTextField!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Προσθήκη Επαφής"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "Νέα Επαφή")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        nameField = NSTextField()
        nameField.placeholderString = "Όνομα"
        nameField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameField)

        phoneField = NSTextField()
        phoneField.placeholderString = "Τηλέφωνο (π.χ. 6971234567)"
        phoneField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(phoneField)

        let addButton = NSButton(title: "Προσθήκη", target: self, action: #selector(addContact))
        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "\r"
        addButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(addButton)

        let cancelButton = NSButton(title: "Άκυρο", target: self, action: #selector(cancel))
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
            alert.messageText = "Συμπλήρωσε όνομα και τηλέφωνο"
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
        window.title = "Διαγραφή Επαφής"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "Επίλεξε επαφή για διαγραφή")
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
        nameCol.title = "Όνομα"
        nameCol.width = 160

        let phoneCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("phone"))
        phoneCol.title = "HelloMac"
        phoneCol.width = 160

        tableView.addTableColumn(nameCol)
        tableView.addTableColumn(phoneCol)
        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        let removeButton = NSButton(title: "🗑 Διαγραφή", target: self, action: #selector(removeContact))
        removeButton.bezelStyle = .rounded
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(removeButton)

        let cancelButton = NSButton(title: "Κλείσιμο", target: self, action: #selector(cancel))
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
            alert.messageText = "Επίλεξε μια επαφή για διαγραφή"
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Διαγραφή επαφής"
        alert.informativeText = "Σίγουρα θέλεις να διαγράψεις τον/την \"\(contacts[row].name)\";"
        alert.addButton(withTitle: "Διαγραφή")
        alert.addButton(withTitle: "Άκυρο")
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
