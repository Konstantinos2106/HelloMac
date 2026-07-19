import AppKit

/// Κυκλική προβολή avatar: δείχνει την εικόνα της επαφής αν υπάρχει,
/// αλλιώς ένα μονόγραμμα πάνω σε έγχρωμο φόντο. Προαιρετικά clickable.
class RoundAvatarView: NSView {
    private let imageView = NSImageView()
    private let initialsLabel = NSTextField(labelWithString: "")
    private var diameter: CGFloat
    var onTap: (() -> Void)?

    private static let palette: [NSColor] = [
        NSColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 1),
        NSColor(red: 0.95, green: 0.45, blue: 0.55, alpha: 1),
        NSColor(red: 0.30, green: 0.75, blue: 0.55, alpha: 1),
        NSColor(red: 0.85, green: 0.55, blue: 0.25, alpha: 1),
        NSColor(red: 0.60, green: 0.45, blue: 0.90, alpha: 1),
        NSColor(red: 0.20, green: 0.70, blue: 0.80, alpha: 1),
    ]

    init(diameter: CGFloat) {
        self.diameter = diameter
        super.init(frame: .zero)
        wantsLayer = true
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        self.diameter = 44
        super.init(coder: coder)
        wantsLayer = true
        setupSubviews()
    }

    private func setupSubviews() {
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        initialsLabel.alignment = .center
        initialsLabel.textColor = .white
        initialsLabel.isEditable = false
        initialsLabel.isSelectable = false
        initialsLabel.isBezeled = false
        initialsLabel.drawsBackground = false
        initialsLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(initialsLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            initialsLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        if onTap != nil || true {
            let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
            addGestureRecognizer(click)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
    }

    override func layout() {
        super.layout()
        let radius = min(bounds.width, bounds.height) / 2
        layer?.cornerRadius = radius
        layer?.cornerCurve = .circular
        layer?.masksToBounds = true
        imageView.layer?.cornerRadius = radius
        imageView.layer?.cornerCurve = .circular
        imageView.layer?.masksToBounds = true
        initialsLabel.font = NSFont.systemFont(ofSize: min(bounds.width, bounds.height) * 0.36, weight: .semibold)
    }

    override func mouseEntered(with event: NSEvent) {
        if onTap != nil { NSCursor.pointingHand.set() }
    }
    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    @objc private func handleClick() {
        onTap?()
    }

    func configure(image: NSImage?, initials: String, colorOverride: NSColor? = nil) {
        if let image = image {
            imageView.image = image
            imageView.isHidden = false
            initialsLabel.isHidden = true
            layer?.backgroundColor = NSColor.clear.cgColor
        } else {
            imageView.image = nil
            imageView.isHidden = true
            initialsLabel.isHidden = false
            initialsLabel.stringValue = initials
            let color = colorOverride ?? RoundAvatarView.colorForInitials(initials)
            layer?.backgroundColor = color.cgColor
        }
    }

    private static func colorForInitials(_ initials: String) -> NSColor {
        let hash = initials.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[hash % palette.count]
    }
}

/// Ένα κουκκίδα-κουμπί χρώματος: κύκλος γεμάτος με το χρώμα, με λευκό δαχτυλίδι
/// επιλογής όταν είναι ενεργό.
private class ColorSwatchButton: NSButton {
    var color: NSColor {
        didSet { needsDisplay = true }
    }
    var isSelectedSwatch: Bool = false {
        didSet { needsDisplay = true }
    }

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        title = ""
        isBordered = false
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = isSelectedSwatch ? 2.5 : 0
        let circleRect = bounds.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(ovalIn: circleRect)
        color.setFill()
        path.fill()

        if isSelectedSwatch {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 2
            NSColor.white.setStroke()
            ring.stroke()
        } else {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 1
            NSColor.white.withAlphaComponent(0.15).setStroke()
            ring.stroke()
        }
    }
}

/// Μια σειρά έτοιμων χρωμάτων μονογράμματος, συν ένα κουμπί που ανοίγει τον
/// τυπικό, πλήρη χρωματικό κύκλο (χρωματοεπιλογέα) του macOS για οποιοδήποτε
/// χρώμα. Εμφανίζεται μόνο όσο η επαφή δεν έχει φωτογραφία.
class MonogramColorPickerView: NSView {
    /// nil = "default" (η αυτόματη hashed απόχρωση χρησιμοποιείται)
    var onColorChange: ((NSColor?) -> Void)?

    private var swatchButtons: [ColorSwatchButton] = []
    private var wheelButton: NSButton!
    private var selectedColor: NSColor?

    static let presetPalette: [NSColor] = [
        NSColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 1),
        NSColor(red: 0.95, green: 0.45, blue: 0.55, alpha: 1),
        NSColor(red: 0.30, green: 0.75, blue: 0.55, alpha: 1),
        NSColor(red: 0.85, green: 0.55, blue: 0.25, alpha: 1),
        NSColor(red: 0.60, green: 0.45, blue: 0.90, alpha: 1),
        NSColor(red: 0.20, green: 0.70, blue: 0.80, alpha: 1),
        NSColor(white: 0.45, alpha: 1),
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for color in Self.presetPalette {
            let swatch = ColorSwatchButton(color: color)
            swatch.target = self
            swatch.action = #selector(swatchTapped(_:))
            swatch.toolTip = L("monogram_color_swatch")
            NSLayoutConstraint.activate([
                swatch.widthAnchor.constraint(equalToConstant: 22),
                swatch.heightAnchor.constraint(equalToConstant: 22),
            ])
            stack.addArrangedSubview(swatch)
            swatchButtons.append(swatch)
        }

        // Native macOS color wheel (NSColorPanel) trigger — lets the person
        // pick literally any color, not just the presets above.
        wheelButton = NSButton()
        wheelButton.title = ""
        wheelButton.bezelStyle = .regularSquare
        wheelButton.isBordered = false
        wheelButton.target = self
        wheelButton.action = #selector(openColorWheel)
        wheelButton.toolTip = L("monogram_color_wheel")
        wheelButton.translatesAutoresizingMaskIntoConstraints = false
        let wheelSymbolCandidates = ["circle.hexagongrid.fill", "paintpalette.fill", "eyedropper.halffull"]
        var wheelImage: NSImage? = nil
        for symbolName in wheelSymbolCandidates {
            if let candidate = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Color wheel") {
                wheelImage = candidate
                break
            }
        }
        if let wheelImage = wheelImage {
            var configuredImage: NSImage? = nil
            if #available(macOS 12.0, *) {
                let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed, .systemGreen, .systemBlue])
                configuredImage = wheelImage.withSymbolConfiguration(config)
            }
            // Fall back to a plain (non-multicolor) rendering if the palette
            // configuration produced nothing, or on pre-Monterey systems.
            wheelButton.image = configuredImage ?? wheelImage.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)) ?? wheelImage
        } else {
            // Last-resort fallback so the button is never left blank.
            wheelButton.title = "🎨"
        }
        (wheelButton.cell as? NSButtonCell)?.imageScaling = .scaleProportionallyUpOrDown
        stack.addArrangedSubview(wheelButton)
        NSLayoutConstraint.activate([
            wheelButton.widthAnchor.constraint(equalToConstant: 22),
            wheelButton.heightAnchor.constraint(equalToConstant: 22),
        ])

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Sets the currently-highlighted color without notifying `onColorChange`.
    func setSelected(color: NSColor?) {
        selectedColor = color
        refreshSelectionRing()
    }

    private func refreshSelectionRing() {
        for swatch in swatchButtons {
            swatch.isSelectedSwatch = selectedColor != nil && colorsMatch(swatch.color, selectedColor!)
        }
    }

    private func colorsMatch(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let ca = a.usingColorSpace(.deviceRGB), let cb = b.usingColorSpace(.deviceRGB) else { return false }
        return abs(ca.redComponent - cb.redComponent) < 0.01
            && abs(ca.greenComponent - cb.greenComponent) < 0.01
            && abs(ca.blueComponent - cb.blueComponent) < 0.01
    }

    @objc private func swatchTapped(_ sender: ColorSwatchButton) {
        selectedColor = sender.color
        refreshSelectionRing()
        onColorChange?(sender.color)
    }

    @objc private func openColorWheel() {
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.color = selectedColor ?? Self.presetPalette[0]
        panel.showsAlpha = false
        panel.orderFront(nil)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        selectedColor = sender.color
        refreshSelectionRing()
        onColorChange?(sender.color)
    }
}


class AddContactWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate, NSMenuDelegate {
    private var firstNameField: NSTextField!
    private var lastNameField: NSTextField!
    private var phoneField: NSTextField!
    private var avatarView: RoundAvatarView!
    private var monogramColorPicker: MonogramColorPickerView!
    private var firstNameFieldTopToPicker: NSLayoutConstraint!
    private var firstNameFieldTopToButton: NSLayoutConstraint!
    private static let windowHeightWithPicker: CGFloat = 366
    private static let windowHeightWithoutPicker: CGFloat = 366 - 32
    private var selectedImage: NSImage?
    private var didClearImage = false
    private var activeCropController: ImageCropWindowController?
    private var selectedMonogramColor: NSColor?
    
    var contactToEdit: Contact?

    convenience init(contactToEdit: Contact? = nil) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 366),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
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
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1).cgColor

        let titleLabel = NSTextField(labelWithString: contactToEdit == nil ? L("new_contact") : L("edit_contact"))
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        avatarView = RoundAvatarView(diameter: 72)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.onTap = { [weak self] in self?.pickImage() }
        let avatarMenu = NSMenu()
        avatarMenu.delegate = self
        let reCropItem = NSMenuItem(title: L("adjust_photo"), action: #selector(reCropExistingPhoto), keyEquivalent: "")
        reCropItem.target = self
        avatarMenu.addItem(reCropItem)
        let removePhotoItem = NSMenuItem(title: L("remove_photo"), action: #selector(removePhoto), keyEquivalent: "")
        removePhotoItem.target = self
        avatarMenu.addItem(removePhotoItem)
        avatarView.menu = avatarMenu
        contentView.addSubview(avatarView)

        let changePhotoButton = NSButton(title: L("choose_photo"), target: self, action: #selector(pickImage))
        changePhotoButton.bezelStyle = .inline
        changePhotoButton.isBordered = false
        changePhotoButton.contentTintColor = NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
        changePhotoButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        changePhotoButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(changePhotoButton)

        // Monogram color picker — only relevant (and shown) while the
        // contact has no photo, since that's when the initials circle with
        // its background color is what actually appears.
        monogramColorPicker = MonogramColorPickerView()
        monogramColorPicker.onColorChange = { [weak self] color in
            guard let self = self else { return }
            self.selectedMonogramColor = color
            self.refreshAvatarAndPickerVisibility()
        }
        contentView.addSubview(monogramColorPicker)

        firstNameField = NSTextField()
        firstNameField.placeholderString = L("first_name_placeholder")
        firstNameField.translatesAutoresizingMaskIntoConstraints = false
        firstNameField.delegate = self
        contentView.addSubview(firstNameField)

        firstNameFieldTopToPicker = firstNameField.topAnchor.constraint(equalTo: monogramColorPicker.bottomAnchor, constant: 16)
        firstNameFieldTopToButton = firstNameField.topAnchor.constraint(equalTo: changePhotoButton.bottomAnchor, constant: 16)

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

            avatarView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            avatarView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 72),
            avatarView.heightAnchor.constraint(equalToConstant: 72),

            changePhotoButton.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 6),
            changePhotoButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            monogramColorPicker.topAnchor.constraint(equalTo: changePhotoButton.bottomAnchor, constant: 10),
            monogramColorPicker.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            monogramColorPicker.heightAnchor.constraint(equalToConstant: 22),

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
            if let hex = contact.monogramColorHex, let color = NSColor(hexString: hex) {
                selectedMonogramColor = color
            }
        }
        monogramColorPicker.setSelected(color: selectedMonogramColor)
        refreshAvatarAndPickerVisibility()
    }

    /// Single source of truth for "does this contact currently have a photo?"
    /// Keeps the avatar preview and the color-picker's visibility in sync
    /// everywhere a photo is added, removed, or re-cropped.
    private func refreshAvatarAndPickerVisibility() {
        let image = selectedImage ?? (didClearImage ? nil : contactToEdit?.image)
        avatarView.configure(image: image, initials: currentInitials(), colorOverride: selectedMonogramColor)
        let showPicker = (image == nil)
        monogramColorPicker.isHidden = !showPicker
        firstNameFieldTopToPicker.isActive = showPicker
        firstNameFieldTopToButton.isActive = !showPicker
        resizeWindow(showPicker: showPicker)
    }

    private func resizeWindow(showPicker: Bool) {
        guard let win = window else { return }
        let targetHeight = showPicker ? Self.windowHeightWithPicker : Self.windowHeightWithoutPicker
        var frame = win.frame
        guard abs(frame.height - targetHeight) > 0.5 else { return }
        let heightDelta = frame.height - targetHeight
        frame.size.height = targetHeight
        // Keep the top edge anchored in place (AppKit windows grow/shrink
        // from the bottom-left origin), so the title bar doesn't jump.
        frame.origin.y += heightDelta
        win.setFrame(frame, display: true, animate: win.isVisible)
    }

    @objc private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "bmp", "webp"]
        panel.title = L("choose_photo")

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url,
                  let image = ImageOrientationFix.normalizedImage(contentsOf: url) else { return }
            self.presentCropSheet(for: image)
        }

        if let win = window {
            panel.beginSheetModal(for: win, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    private func presentCropSheet(for image: NSImage) {
        guard let win = window else { return }
        let cropController = ImageCropWindowController(image: image)
        self.activeCropController = cropController
        cropController.present(on: win) { [weak self] croppedImage in
            guard let self = self else { return }
            self.activeCropController = nil
            guard let croppedImage = croppedImage else { return }
            self.selectedImage = croppedImage
            self.didClearImage = false
            self.refreshAvatarAndPickerVisibility()
        }
    }

    @objc private func removePhoto() {
        selectedImage = nil
        didClearImage = true
        refreshAvatarAndPickerVisibility()
    }

    @objc private func reCropExistingPhoto() {
        guard let currentImage = selectedImage ?? contactToEdit?.image else { return }
        presentCropSheet(for: currentImage)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let hasPhoto = (selectedImage ?? contactToEdit?.image) != nil && !didClearImage
        for item in menu.items {
            item.isEnabled = hasPhoto
        }
    }

    private func currentInitials() -> String {
        let f = firstNameField.stringValue.trimmingCharacters(in: .whitespaces).first
        let l = lastNameField.stringValue.trimmingCharacters(in: .whitespaces).first
        let combined = [f, l].compactMap { $0 }.map { String($0) }.joined()
        return combined.isEmpty ? "?" : combined.uppercased()
    }

    @objc func saveContact() {
        let firstName = firstNameField.stringValue.trimmingCharacters(in: .whitespaces)
        let lastName = lastNameField.stringValue.trimmingCharacters(in: .whitespaces)
        let phone = phoneField.stringValue.trimmingCharacters(in: .whitespaces)

        guard !firstName.isEmpty, !phone.isEmpty else {
            let alert = NSAlert()
            alert.messageText = L("fill_fields")
            alert.addButton(withTitle: L("ok"))
            alert.window.appearance = NSAppearance(named: .darkAqua)
            alert.runModal()
            return
        }

        if var contact = contactToEdit {
            contact.firstName = firstName
            contact.lastName = lastName
            contact.phone = phone
            contact.monogramColorHex = selectedMonogramColor?.hexString
            if let newImage = selectedImage {
                contact.imageFileName = ContactImageStore.saveImage(newImage, existingFileName: contact.imageFileName)
            } else if didClearImage {
                ContactImageStore.deleteImage(fileName: contact.imageFileName)
                contact.imageFileName = nil
            }
            ContactStore.shared.updateContact(contact)
        } else {
            var newContact = Contact(firstName: firstName, lastName: lastName, phone: phone)
            newContact.monogramColorHex = selectedMonogramColor?.hexString
            if let newImage = selectedImage {
                newContact.imageFileName = ContactImageStore.saveImage(newImage)
            }
            var contacts = ContactStore.shared.contacts
            contacts.append(newContact)
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
        } else if let textField = obj.object as? NSTextField, textField == firstNameField || textField == lastNameField {
            refreshAvatarAndPickerVisibility()
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

class ResizingTabViewController: NSTabViewController {
    var onTabWillActivate: ((Int) -> Void)?

    override var selectedTabViewItemIndex: Int {
        didSet {
            onTabWillActivate?(selectedTabViewItemIndex)
        }
    }
}

class SettingsWindowController: NSWindowController, NSTextFieldDelegate {

    private var updateStatusLabel: NSTextField!
    private var updateCheckSpinner: NSProgressIndicator!
    private var checkNowButton: NSButton!
    private var installUpdateButton: NSButton!
    private var pendingDownloadURL: URL?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380), 
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("settings_title")
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
        
        let tabViewController = ResizingTabViewController()
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
        
        let versionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.3"
        let versionLabel = NSTextField(labelWithString: L("current_version", versionString))
        versionLabel.alignment = .center
        versionLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.alignment = .center
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.isHidden = true
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.preferredMaxLayoutWidth = 360
        self.updateStatusLabel = statusLabel

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        self.updateCheckSpinner = spinner

        let checkButton = NSButton(title: L("check_now"), target: self, action: #selector(checkNowTapped))
        checkButton.bezelStyle = .rounded
        checkButton.controlSize = .large
        checkButton.translatesAutoresizingMaskIntoConstraints = false
        self.checkNowButton = checkButton

        let installButton = NSButton(title: L("download"), target: self, action: #selector(installUpdateTapped))
        installButton.bezelStyle = .rounded
        installButton.controlSize = .large
        installButton.translatesAutoresizingMaskIntoConstraints = false
        installButton.isHidden = true
        self.installUpdateButton = installButton

        let updatesStack = NSStackView(views: [iconImageView, versionLabel, spinner, statusLabel, checkButton, installButton])
        updatesStack.orientation = .vertical
        updatesStack.spacing = 16
        updatesStack.alignment = .centerX
        updatesStack.translatesAutoresizingMaskIntoConstraints = false
        updatesView.addSubview(updatesStack)
        
        NSLayoutConstraint.activate([
            updatesStack.centerXAnchor.constraint(equalTo: updatesView.centerXAnchor),
            updatesStack.topAnchor.constraint(equalTo: updatesView.topAnchor, constant: 28),
            updatesStack.bottomAnchor.constraint(equalTo: updatesView.bottomAnchor, constant: -28),
            updatesView.widthAnchor.constraint(equalToConstant: 480)
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

        let historyAutoDeleteRow = NSStackView()
        historyAutoDeleteRow.orientation = .horizontal
        let historyAutoDeleteLabel = NSTextField(labelWithString: L("history_autodelete_label"))
        historyAutoDeleteLabel.font = NSFont.systemFont(ofSize: 14)
        historyAutoDeleteLabel.lineBreakMode = .byClipping
        historyAutoDeleteLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        historyAutoDeleteLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        historyAutoDeleteRow.addView(historyAutoDeleteLabel, in: .leading)

        let historyAutoDeletePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        historyAutoDeletePopup.addItems(withTitles: HistoryAutoDeleteInterval.allCases.map { $0.localizedTitle })
        historyAutoDeletePopup.selectItem(at: HistoryAutoDeleteInterval.current.rawValue)
        historyAutoDeletePopup.target = self
        historyAutoDeletePopup.action = #selector(historyAutoDeleteChanged(_:))
        historyAutoDeletePopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        historyAutoDeleteRow.addView(historyAutoDeletePopup, in: .trailing)
        
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

        let historyRow = NSStackView()
        historyRow.orientation = .horizontal
        let historyLabel = NSTextField(labelWithString: L("show_history_tab"))
        historyLabel.font = NSFont.systemFont(ofSize: 14)
        historyRow.addView(historyLabel, in: .leading)
        let historySwitch = NSSwitch()
        historySwitch.target = self
        historySwitch.action = #selector(toggleFeature(_:))
        historySwitch.identifier = NSUserInterfaceItemIdentifier("showHistoryMenu")
        historySwitch.state = UserDefaults.standard.bool(forKey: "hideHistoryMenu") ? .off : .on
        historyRow.addView(historySwitch, in: .trailing)
        
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
        
        let detailHistoryRow = NSStackView()
        detailHistoryRow.orientation = .horizontal
        let detailHistoryLabel = NSTextField(labelWithString: L("show_contact_history_detail"))
        detailHistoryLabel.font = NSFont.systemFont(ofSize: 14)
        detailHistoryRow.addView(detailHistoryLabel, in: .leading)
        let detailHistorySwitch = NSSwitch()
        detailHistorySwitch.target = self
        detailHistorySwitch.action = #selector(toggleFeature(_:))
        detailHistorySwitch.identifier = NSUserInterfaceItemIdentifier("showContactHistoryInDetail")
        detailHistorySwitch.state = UserDefaults.standard.bool(forKey: "hideContactHistoryInDetail") ? .off : .on
        detailHistoryRow.addView(detailHistorySwitch, in: .trailing)

        let appearanceStack = NSStackView(views: [searchVisibilityRow, historyAutoDeleteRow, separator0, favoritesRow, historyRow, contactsRow, keypadRow, plusRow, detailHistoryRow])
        appearanceStack.orientation = .vertical
        appearanceStack.spacing = 14
        appearanceStack.translatesAutoresizingMaskIntoConstraints = false
        appearanceView.addSubview(appearanceStack)
        
        NSLayoutConstraint.activate([
            appearanceStack.centerXAnchor.constraint(equalTo: appearanceView.centerXAnchor),
            appearanceStack.topAnchor.constraint(equalTo: appearanceView.topAnchor, constant: 28),
            appearanceStack.bottomAnchor.constraint(equalTo: appearanceView.bottomAnchor, constant: -28),
            searchVisibilityRow.widthAnchor.constraint(equalToConstant: 360),
            historyAutoDeleteRow.widthAnchor.constraint(equalToConstant: 360),
            separator0.widthAnchor.constraint(equalToConstant: 360),
            favoritesRow.widthAnchor.constraint(equalToConstant: 360),
            historyRow.widthAnchor.constraint(equalToConstant: 360),
            contactsRow.widthAnchor.constraint(equalToConstant: 360),
            keypadRow.widthAnchor.constraint(equalToConstant: 360),
            plusRow.widthAnchor.constraint(equalToConstant: 360),
            detailHistoryRow.widthAnchor.constraint(equalToConstant: 360),
            appearanceView.widthAnchor.constraint(equalToConstant: 480)
        ])
        
        appearanceVC.view = appearanceView
        appearanceVC.title = L("tab_appearance")
        let appearanceTab = NSTabViewItem(viewController: appearanceVC)
        appearanceTab.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        
        // ==========================================
        // ΚΑΡΤΕΛΑ 3: ΤΑΧΕΙΑ ΚΛΗΣΗ (SPEED DIAL)
        // ==========================================
        let speedDialVC = NSViewController()
        let speedDialView = NSView()
        
        let enableSDRow = NSStackView()
        enableSDRow.orientation = .horizontal
        let enableSDLabel = NSTextField(labelWithString: L("enable_speed_dial"))
        enableSDLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        enableSDRow.addView(enableSDLabel, in: .leading)
        let enableSDSwitch = NSSwitch()
        enableSDSwitch.target = self
        enableSDSwitch.action = #selector(toggleFeature(_:))
        enableSDSwitch.identifier = NSUserInterfaceItemIdentifier("enableSpeedDial")
        enableSDSwitch.state = UserDefaults.standard.bool(forKey: "enableSpeedDial") ? .on : .off
        enableSDRow.addView(enableSDSwitch, in: .trailing)
        enableSDRow.translatesAutoresizingMaskIntoConstraints = false
        speedDialView.addSubview(enableSDRow)
        
        let sdStack = NSStackView()
        sdStack.orientation = .vertical
        sdStack.spacing = 10
        sdStack.translatesAutoresizingMaskIntoConstraints = false
        speedDialView.addSubview(sdStack)
        
        for i in 1...9 {
            let row = NSStackView()
            row.orientation = .horizontal
            row.translatesAutoresizingMaskIntoConstraints = false
            let label = NSTextField(labelWithString: "\(i):")
            label.font = NSFont.systemFont(ofSize: 14)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 20).isActive = true
            
            let tf = NSTextField()
            tf.placeholderString = L("phone_placeholder")
            tf.stringValue = UserDefaults.standard.string(forKey: "SpeedDial_\(i)") ?? ""
            tf.tag = i
            tf.delegate = self
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.widthAnchor.constraint(equalToConstant: 240).isActive = true
            
            row.addView(label, in: .leading)
            row.addView(tf, in: .trailing)
            sdStack.addArrangedSubview(row)
        }
        
        // Sized to fit the enable switch row plus all 9 speed-dial rows
        // exactly, with equal top/bottom breathing room and no scrolling.
        let sdTopPadding: CGFloat = 20
        let sdRowGap: CGFloat = 14
        
        NSLayoutConstraint.activate([
            enableSDRow.topAnchor.constraint(equalTo: speedDialView.topAnchor, constant: sdTopPadding),
            enableSDRow.centerXAnchor.constraint(equalTo: speedDialView.centerXAnchor),
            enableSDRow.widthAnchor.constraint(equalToConstant: 300),
            
            sdStack.topAnchor.constraint(equalTo: enableSDRow.bottomAnchor, constant: sdRowGap),
            sdStack.centerXAnchor.constraint(equalTo: speedDialView.centerXAnchor),
            sdStack.widthAnchor.constraint(equalToConstant: 320),
            sdStack.bottomAnchor.constraint(equalTo: speedDialView.bottomAnchor, constant: -sdTopPadding),

            speedDialView.widthAnchor.constraint(equalToConstant: 480)
        ])
        
        speedDialVC.view = speedDialView
        speedDialVC.title = L("tab_speed_dial")
        let speedDialTab = NSTabViewItem(viewController: speedDialVC)
        speedDialTab.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
        
        // ==========================================
        // ΚΑΡΤΕΛΑ 4: ΠΛΗΡΟΦΟΡΙΕΣ
        // ==========================================
        let infoVC = NSViewController()
        let infoView = NSView()

        // --- Πάνω-αριστερά: λογότυπο + τίτλος/υπότιτλος ---
        let infoIconView = NSImageView(image: NSImage(named: "AppIcon") ?? NSImage())
        infoIconView.imageScaling = .scaleProportionallyUpOrDown
        infoIconView.translatesAutoresizingMaskIntoConstraints = false
        infoIconView.widthAnchor.constraint(equalToConstant: 56).isActive = true
        infoIconView.heightAnchor.constraint(equalToConstant: 56).isActive = true
        infoIconView.setContentHuggingPriority(.required, for: .horizontal)
        infoIconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let appNameLabel = NSTextField(labelWithString: "HelloMac")
        appNameLabel.font = NSFont.boldSystemFont(ofSize: 20)
        appNameLabel.textColor = .white
        appNameLabel.lineBreakMode = .byTruncatingTail
        appNameLabel.translatesAutoresizingMaskIntoConstraints = false
        appNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let appTaglineLabel = NSTextField(labelWithString: L("app_tagline"))
        appTaglineLabel.font = NSFont.systemFont(ofSize: 12)
        appTaglineLabel.textColor = .secondaryLabelColor
        appTaglineLabel.lineBreakMode = .byTruncatingTail
        appTaglineLabel.translatesAutoresizingMaskIntoConstraints = false
        appTaglineLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let titleStack = NSStackView(views: [appNameLabel, appTaglineLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        let headerRow = NSStackView(views: [infoIconView, titleStack])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 12
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        infoView.addSubview(headerRow)

        // --- Περιγραφή εφαρμογής ---
        let descriptionLabel = NSTextField(wrappingLabelWithString: L("app_description"))
        descriptionLabel.font = NSFont.systemFont(ofSize: 13)
        descriptionLabel.textColor = .labelColor
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        infoView.addSubview(descriptionLabel)

        // --- Σύνδεσμοι ---
        let shortcutLabel = NSTextField(labelWithString: L("app_shortcut_label"))
        shortcutLabel.font = NSFont.systemFont(ofSize: 12)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        infoView.addSubview(shortcutLabel)

        let websiteLabel = ClickableLabel(labelWithString: L("app_website_label"))
        websiteLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        websiteLabel.textColor = NSColor.linkColor
        websiteLabel.isLinkActive = true
        websiteLabel.translatesAutoresizingMaskIntoConstraints = false
        let websiteClick = NSClickGestureRecognizer(target: self, action: #selector(openAppWebsite))
        websiteLabel.addGestureRecognizer(websiteClick)
        infoView.addSubview(websiteLabel)

        let githubLabel = ClickableLabel(labelWithString: L("app_github_label"))
        githubLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        githubLabel.textColor = NSColor.linkColor
        githubLabel.isLinkActive = true
        githubLabel.translatesAutoresizingMaskIntoConstraints = false
        let githubClick = NSClickGestureRecognizer(target: self, action: #selector(openAppGitHub))
        githubLabel.addGestureRecognizer(githubClick)
        infoView.addSubview(githubLabel)

        let infoVersionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.3"
        let infoVersionLabel = NSTextField(labelWithString: L("current_version", infoVersionString))
        infoVersionLabel.font = NSFont.systemFont(ofSize: 12)
        infoVersionLabel.textColor = .secondaryLabelColor
        infoVersionLabel.translatesAutoresizingMaskIntoConstraints = false
        infoView.addSubview(infoVersionLabel)

        // Το header/περιγραφή/σύνδεσμοι οριοθετούνται με ακριβή (equalTo)
        // constraints ώστε το view να έχει ένα σαφές, φυσικό μέγεθος
        // περιεχομένου — αυτό είναι απαραίτητο για να υπολογίζεται σωστά
        // το fittingSize όταν αλλάζουμε δυναμικά το μέγεθος του παραθύρου
        // ρυθμίσεων ανά καρτέλα. Αν στο μέλλον μεγαλώσει το παράθυρο, το
        // περιεχόμενο παραμένει προσαρτημένο πάνω-αριστερά (δεν τεντώνεται)
        // χάρη στο ότι δεν υπάρχει stretch constraint στα trailing/bottom.
        NSLayoutConstraint.activate([
            headerRow.topAnchor.constraint(equalTo: infoView.topAnchor, constant: 24),
            headerRow.leadingAnchor.constraint(equalTo: infoView.leadingAnchor, constant: 24),
            headerRow.trailingAnchor.constraint(lessThanOrEqualTo: infoView.trailingAnchor, constant: -24),

            descriptionLabel.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 16),
            descriptionLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            descriptionLabel.widthAnchor.constraint(equalToConstant: 400),

            shortcutLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 20),
            shortcutLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),

            websiteLabel.topAnchor.constraint(equalTo: shortcutLabel.bottomAnchor, constant: 12),
            websiteLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),

            githubLabel.topAnchor.constraint(equalTo: websiteLabel.bottomAnchor, constant: 8),
            githubLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),

            infoVersionLabel.topAnchor.constraint(equalTo: githubLabel.bottomAnchor, constant: 16),
            infoVersionLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            infoVersionLabel.bottomAnchor.constraint(equalTo: infoView.bottomAnchor, constant: -24),

            infoView.widthAnchor.constraint(equalToConstant: 480)
        ])

        infoVC.view = infoView
        infoVC.title = L("tab_info")
        let infoTab = NSTabViewItem(viewController: infoVC)
        infoTab.image = NSImage(systemSymbolName: "info.circle.fill", accessibilityDescription: nil)

        tabViewController.addTabViewItem(updatesTab)
        tabViewController.addTabViewItem(appearanceTab)
        tabViewController.addTabViewItem(speedDialTab)
        tabViewController.addTabViewItem(infoTab)
        
        window.contentViewController = tabViewController

        // Κάθε καρτέλα έχει το δικό της φυσικό ύψος περιεχομένου (χωρίς
        // κενά χώρους πάνω/κάτω). Όταν αλλάζει η επιλεγμένη καρτέλα,
        // προσαρμόζουμε το ύψος του παραθύρου ώστε να ταιριάζει ακριβώς.
        self.tabContentViews = [updatesView, appearanceView, speedDialView, infoView]
        self.resizingTabViewController = tabViewController
        tabViewController.onTabWillActivate = { [weak self] index in
            self?.resizeWindow(forTabIndex: index, animated: true)
        }

        // Αρχικό μέγεθος παραθύρου ώστε να ταιριάζει με την πρώτη καρτέλα.
        // Το layout pass πρέπει να ολοκληρωθεί πρώτα, γι' αυτό αναβάλλουμε
        // στον επόμενο κύκλο του run loop.
        DispatchQueue.main.async { [weak self] in
            self?.resizeWindow(forTabIndex: 0, animated: false)
        }
    }

    private var tabContentViews: [NSView] = []
    private var resizingTabViewController: ResizingTabViewController?

    private func resizeWindow(forTabIndex index: Int, animated: Bool) {
        guard let window = self.window,
              index >= 0, index < tabContentViews.count else { return }
        let contentView = tabContentViews[index]

        // Με tabStyle .toolbar, η μπάρα καρτελών ζει στο toolbar area του
        // παραθύρου, όχι μέσα στο view του tab — άρα το ύψος περιεχομένου
        // του tab ισούται ακριβώς με το ύψος του "page" content area.
        let targetContentHeight = contentView.fittingSize.height
        let currentContentRect = window.contentRect(forFrameRect: window.frame)
        guard abs(currentContentRect.height - targetContentHeight) > 0.5 else { return }

        var newFrame = window.frame
        let heightDelta = targetContentHeight - currentContentRect.height
        newFrame.size.height += heightDelta
        newFrame.origin.y -= heightDelta // keep top edge fixed, grow/shrink from the bottom

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            window.setFrame(newFrame, display: true)
        }
    }
    
    func resetUpdateStatusUI() {
        guard updateStatusLabel != nil else { return }
        updateCheckSpinner.stopAnimation(nil)
        updateCheckSpinner.isHidden = true
        checkNowButton.isEnabled = true
        updateStatusLabel.stringValue = ""
        updateStatusLabel.isHidden = true
        installUpdateButton.isHidden = true
        pendingDownloadURL = nil

        if let tabVC = resizingTabViewController, tabVC.selectedTabViewItemIndex == 0 {
            resizeWindow(forTabIndex: 0, animated: false)
        }
    }

    @objc private func openAppWebsite() {
        if let url = URL(string: "https://konstantinos2106.github.io/HelloMac/") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openAppGitHub() {
        if let url = URL(string: "https://github.com/Konstantinos2106/HelloMac") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func checkNowTapped() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }

        updateStatusLabel.isHidden = true
        installUpdateButton.isHidden = true
        checkNowButton.isEnabled = false
        updateCheckSpinner.isHidden = false
        updateCheckSpinner.startAnimation(nil)
        if let tabVC = resizingTabViewController {
            resizeWindow(forTabIndex: tabVC.selectedTabViewItemIndex, animated: true)
        }

        appDelegate.checkForUpdatesFromSettings { [weak self] result in
            guard let self = self else { return }
            self.updateCheckSpinner.stopAnimation(nil)
            self.updateCheckSpinner.isHidden = true
            self.checkNowButton.isEnabled = true

            switch result {
            case .upToDate:
                self.pendingDownloadURL = nil
                self.installUpdateButton.isHidden = true
                self.updateStatusLabel.stringValue = L("up_to_date_text")
                self.updateStatusLabel.isHidden = false
            case .error:
                self.pendingDownloadURL = nil
                self.installUpdateButton.isHidden = true
                self.updateStatusLabel.stringValue = L("update_error_text")
                self.updateStatusLabel.isHidden = false
            case .updateAvailable(let latestVersion, let downloadURL):
                self.pendingDownloadURL = downloadURL
                self.updateStatusLabel.stringValue = L("update_text", latestVersion)
                self.updateStatusLabel.isHidden = false
                self.installUpdateButton.isHidden = false
            }

            // Το ύψος περιεχομένου της καρτέλας «Ενημερώσεις» άλλαξε
            // (εμφανίστηκε/κρύφτηκε μήνυμα ή κουμπί εγκατάστασης) —
            // προσαρμόζουμε ξανά το παράθυρο ώστε να μη μένει κενός χώρος.
            if let tabVC = self.resizingTabViewController {
                self.resizeWindow(forTabIndex: tabVC.selectedTabViewItemIndex, animated: true)
            }
        }
    }

    @objc private func installUpdateTapped() {
        guard let downloadURL = pendingDownloadURL,
              let appDelegate = NSApp.delegate as? AppDelegate else { return }
        // Το ίδιο το AppDelegate κλείνει τις Ρυθμίσεις πριν ανοίξει το παράθυρο προόδου.
        appDelegate.beginUpdateFromSettings(downloadURL: downloadURL)
    }

    @objc private func toggleFeature(_ sender: NSSwitch) {
        if sender.identifier?.rawValue == "showContactsMenu" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hideContactsMenu")
        } else if sender.identifier?.rawValue == "showKeypadMenu" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hideKeypadMenu")
        } else if sender.identifier?.rawValue == "showFavoritesMenu" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hideFavoritesMenu")
        } else if sender.identifier?.rawValue == "showHistoryMenu" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hideHistoryMenu")
        } else if sender.identifier?.rawValue == "showPlusButton" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hidePlusButton") 
        } else if sender.identifier?.rawValue == "enableSpeedDial" {
            UserDefaults.standard.set(sender.state == .on, forKey: "enableSpeedDial")
        } else if sender.identifier?.rawValue == "showContactHistoryInDetail" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hideContactHistoryInDetail")
        }
        
        NotificationCenter.default.post(name: NSNotification.Name("UpdateUIVisibility"), object: nil)
    }
    
    @objc private func searchVisibilityChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: "searchBarVisibility")
        NotificationCenter.default.post(name: NSNotification.Name("UpdateUIVisibility"), object: nil)
    }

    @objc private func historyAutoDeleteChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: HistoryAutoDeleteInterval.defaultsKey)
        // Εφαρμόζουμε αμέσως τη νέα ρύθμιση στο υπάρχον ιστορικό, αντί να
        // περιμένουμε την επόμενη κλήση ή επανεκκίνηση της εφαρμογής.
        HistoryStore.shared.purgeExpiredRecords()
    }
    
    // Αποθήκευση Ταχείας Κλήσης μόλις ο χρήστης πληκτρολογεί
    func controlTextDidChange(_ obj: Notification) {
        if let tf = obj.object as? NSTextField, tf.tag >= 1, tf.tag <= 9 {
            UserDefaults.standard.set(tf.stringValue, forKey: "SpeedDial_\(tf.tag)")
        }
    }
}