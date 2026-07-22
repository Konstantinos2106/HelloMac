import AppKit
import UniformTypeIdentifiers

/// Ζωγραφίζει προγραμματιστικά ένα σταθερό, πολύχρωμο "color wheel" εικονίδιο
/// (ομαλός κυκλικός ουράνιο-τόξο δίσκος, σαν πραγματικός τροχός χρωμάτων),
/// ώστε να δουλεύει πανομοιότυπα σε macOS 11 και μετά, χωρίς καμία εξάρτηση
/// από SF Symbols διαθεσιμότητα.
enum ColorWheelIcon {
    static func make(diameter: CGFloat = 20) -> NSImage {
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()

        let center = NSPoint(x: diameter / 2, y: diameter / 2)
        let radius = diameter / 2

        // Ζωγραφίζουμε πολλά λεπτά ακτινικά "φετάκια" (κάθε 2 μοίρες) ώστε
        // το χρώμα να αλλάζει ομαλά γύρω-γύρω, σαν πραγματικός color wheel,
        // αντί για λίγα ορατά κομμάτια "πίτας".
        let stepDegrees: CGFloat = 2
        let steps = Int(360 / stepDegrees)
        for i in 0..<steps {
            let hue = CGFloat(i) / CGFloat(steps)
            let color = NSColor(hue: hue, saturation: 0.85, brightness: 1.0, alpha: 1)
            let startAngle = CGFloat(i) * stepDegrees
            let endAngle = startAngle + stepDegrees + 0.5 // μικρό overlap, να μη μένουν λευκές γραμμές
            let path = NSBezierPath()
            path.move(to: center)
            path.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            path.close()
            color.setFill()
            path.fill()
        }

        // Λεπτό περίγραμμα ώστε ο τροχός να ξεχωρίζει σε ανοιχτό/σκούρο φόντο.
        let border = NSBezierPath(ovalIn: NSRect(x: 0.5, y: 0.5, width: diameter - 1, height: diameter - 1))
        NSColor.black.withAlphaComponent(0.15).setStroke()
        border.lineWidth = 0.75
        border.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

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

        wheelButton = NSButton()
        wheelButton.title = ""
        wheelButton.bezelStyle = .regularSquare
        wheelButton.isBordered = false
        wheelButton.target = self
        wheelButton.action = #selector(openColorWheel)
        wheelButton.toolTip = L("monogram_color_wheel")
        wheelButton.translatesAutoresizingMaskIntoConstraints = false
        wheelButton.image = ColorWheelIcon.make(diameter: 18)
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

class AddContactWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate, NSTextViewDelegate {
    private var firstNameField: NSTextField!
    private var lastNameField: NSTextField!
    private var phoneField: NSTextField!
    private var notesLabel: NSTextField!
    private var notesScrollView: NSScrollView!
    private var notesTextView: NSTextView!
    private var notesIsShowingPlaceholder = false
    private var avatarView: RoundAvatarView!
    private var monogramColorPicker: MonogramColorPickerView!
    private var changePhotoButton: NSButton!
    private var reCropButton: NSButton!
    private var removePhotoButton: NSButton!
    private var photoActionsRow: NSStackView!
    private var firstNameFieldTopToPicker: NSLayoutConstraint!
    private var firstNameFieldTopToButton: NSLayoutConstraint!
    private var firstNameFieldTopToActionsRow: NSLayoutConstraint!
    private static let notesAreaHeight: CGFloat = 92
    private static let windowHeightWithPicker: CGFloat = 366 + notesAreaHeight
    private static let windowHeightWithoutPicker: CGFloat = 366 - 32 + notesAreaHeight
    private static let windowHeightWithPhotoActions: CGFloat = windowHeightWithoutPicker + 24
    private var selectedImage: NSImage?
    private var didClearImage = false
    private var activeCropController: ImageCropWindowController?
    private var selectedMonogramColor: NSColor?
    
    var contactToEdit: Contact?

    convenience init(contactToEdit: Contact? = nil) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 366 + Self.notesAreaHeight),
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
        contentView.addSubview(avatarView)

        changePhotoButton = NSButton(title: L("choose_photo"), target: self, action: #selector(pickImage))
        changePhotoButton.bezelStyle = .inline
        changePhotoButton.isBordered = false
        changePhotoButton.contentTintColor = NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
        changePhotoButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        changePhotoButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(changePhotoButton)

        reCropButton = NSButton(title: L("adjust_photo"), target: self, action: #selector(reCropExistingPhoto))
        reCropButton.bezelStyle = .inline
        reCropButton.isBordered = false
        reCropButton.contentTintColor = NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
        reCropButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        removePhotoButton = NSButton(title: L("remove_photo"), target: self, action: #selector(removePhoto))
        removePhotoButton.bezelStyle = .inline
        removePhotoButton.isBordered = false
        removePhotoButton.contentTintColor = NSColor(red: 0.9, green: 0.35, blue: 0.35, alpha: 1)
        removePhotoButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)

        photoActionsRow = NSStackView(views: [reCropButton, removePhotoButton])
        photoActionsRow.orientation = .horizontal
        photoActionsRow.spacing = 14
        photoActionsRow.alignment = .centerY
        photoActionsRow.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(photoActionsRow)

        monogramColorPicker = MonogramColorPickerView()
        monogramColorPicker.onColorChange = { [weak self] color in
            guard let self = self else { return }
            self.selectedMonogramColor = color
            self.refreshAvatarAndPickerVisibility()
        }
        contentView.addSubview(monogramColorPicker)

        firstNameField = NSTextField()
        firstNameField.placeholderString = L("first_name_placeholder")
        firstNameField.cell?.usesSingleLineMode = true
        firstNameField.translatesAutoresizingMaskIntoConstraints = false
        firstNameField.delegate = self
        contentView.addSubview(firstNameField)

        firstNameFieldTopToPicker = firstNameField.topAnchor.constraint(equalTo: monogramColorPicker.bottomAnchor, constant: 16)
        firstNameFieldTopToButton = firstNameField.topAnchor.constraint(equalTo: changePhotoButton.bottomAnchor, constant: 16)
        firstNameFieldTopToActionsRow = firstNameField.topAnchor.constraint(equalTo: photoActionsRow.bottomAnchor, constant: 16)

        lastNameField = NSTextField()
        lastNameField.placeholderString = L("last_name_placeholder")
        lastNameField.cell?.usesSingleLineMode = true
        lastNameField.translatesAutoresizingMaskIntoConstraints = false
        lastNameField.delegate = self
        contentView.addSubview(lastNameField)

        phoneField = NSTextField()
        phoneField.placeholderString = L("phone_placeholder")
        phoneField.cell?.usesSingleLineMode = true
        phoneField.translatesAutoresizingMaskIntoConstraints = false
        phoneField.delegate = self 
        contentView.addSubview(phoneField)

        notesLabel = NSTextField(labelWithString: L("notes_title"))
        notesLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        notesLabel.textColor = NSColor(white: 0.5, alpha: 1)
        notesLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(notesLabel)

        notesScrollView = NSScrollView()
        notesScrollView.translatesAutoresizingMaskIntoConstraints = false
        notesScrollView.hasVerticalScroller = true
        notesScrollView.autohidesScrollers = true
        notesScrollView.borderType = .noBorder
        notesScrollView.drawsBackground = true
        notesScrollView.backgroundColor = NSColor(white: 1, alpha: 0.06)
        notesScrollView.wantsLayer = true
        notesScrollView.layer?.cornerRadius = 8
        notesScrollView.layer?.masksToBounds = true
        notesScrollView.layer?.borderWidth = 1
        notesScrollView.layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
        contentView.addSubview(notesScrollView)

        notesTextView = NSTextView()
        notesTextView.delegate = self
        notesTextView.font = NSFont.systemFont(ofSize: 13)
        notesTextView.textColor = .white
        notesTextView.drawsBackground = false
        notesTextView.isRichText = false
        notesTextView.textContainerInset = NSSize(width: 8, height: 8)
        notesTextView.textContainer?.lineFragmentPadding = 0
        notesTextView.isVerticallyResizable = true
        notesTextView.isHorizontallyResizable = false
        notesTextView.autoresizingMask = [.width]
        notesTextView.textContainer?.widthTracksTextView = true
        notesScrollView.documentView = notesTextView

        // Ο τίτλος-placeholder ζωγραφίζεται ΜΕΣΑ στο ίδιο NSTextView (ίδιο
        // textContainer, ίδια γραμματοσειρά, ίδιο layoutManager) ώστε να
        // ευθυγραμμίζεται pixel-perfect με τον κέρσορα — αντί για ξεχωριστό
        // NSTextField που ποτέ δεν ταιριάζει απόλυτα σε μετρήσεις γραμματοσειράς.
        setNotesPlaceholderVisible(true)

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

            photoActionsRow.topAnchor.constraint(equalTo: changePhotoButton.bottomAnchor, constant: 6),
            photoActionsRow.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

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

            notesLabel.topAnchor.constraint(equalTo: phoneField.bottomAnchor, constant: 14),
            notesLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            notesScrollView.topAnchor.constraint(equalTo: notesLabel.bottomAnchor, constant: 6),
            notesScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            notesScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            notesScrollView.heightAnchor.constraint(equalToConstant: Self.notesAreaHeight - 22),

            addButton.topAnchor.constraint(equalTo: notesScrollView.bottomAnchor, constant: 20),
            addButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            addButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            cancelButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -8),
        ])
    }
    
    private func setNotesPlaceholderVisible(_ visible: Bool) {
        notesIsShowingPlaceholder = visible
        if visible {
            notesTextView.string = L("notes_placeholder")
            notesTextView.textColor = NSColor(white: 0.45, alpha: 1)
        } else {
            notesTextView.textColor = .white
        }
    }

    private func populateData() {
        if let contact = contactToEdit {
            firstNameField.stringValue = contact.firstName
            lastNameField.stringValue = contact.lastName
            phoneField.stringValue = contact.phone
            let notes = contact.notes ?? ""
            if notes.isEmpty {
                setNotesPlaceholderVisible(true)
            } else {
                notesTextView.string = notes
                setNotesPlaceholderVisible(false)
            }
            if let hex = contact.monogramColorHex, let color = NSColor(hexString: hex) {
                selectedMonogramColor = color
            }
        } else {
            setNotesPlaceholderVisible(true)
        }
        monogramColorPicker.setSelected(color: selectedMonogramColor)
        refreshAvatarAndPickerVisibility()
    }

    private func refreshAvatarAndPickerVisibility() {
        let image = selectedImage ?? (didClearImage ? nil : contactToEdit?.image)
        avatarView.configure(image: image, initials: currentInitials(), colorOverride: selectedMonogramColor)
        let hasPhoto = (image != nil)
        let showPicker = !hasPhoto

        monogramColorPicker.isHidden = !showPicker
        photoActionsRow.isHidden = !hasPhoto

        firstNameFieldTopToPicker.isActive = showPicker
        firstNameFieldTopToActionsRow.isActive = hasPhoto
        firstNameFieldTopToButton.isActive = !showPicker && !hasPhoto

        resizeWindow(showPicker: showPicker, hasPhoto: hasPhoto)
    }

    private func resizeWindow(showPicker: Bool, hasPhoto: Bool) {
        guard let win = window else { return }
        let targetHeight: CGFloat = showPicker ? Self.windowHeightWithPicker : (hasPhoto ? Self.windowHeightWithPhotoActions : Self.windowHeightWithoutPicker)
        var frame = win.frame
        guard abs(frame.height - targetHeight) > 0.5 else { return }
        let heightDelta = frame.height - targetHeight
        frame.size.height = targetHeight
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

        let notesText = notesIsShowingPlaceholder ? "" : notesTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesValue: String? = notesText.isEmpty ? nil : notesText

        if var contact = contactToEdit {
            contact.firstName = firstName
            contact.lastName = lastName
            contact.phone = phone
            contact.monogramColorHex = selectedMonogramColor?.hexString
            contact.notes = notesValue
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
            newContact.notes = notesValue
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
        setNotesPlaceholderVisible(true)
        window?.close()
    }

    @objc func cancel() {
        window?.close()
    }
    
    func controlTextDidChange(_ obj: Notification) {
        if let textField = obj.object as? NSTextField {
            // Όριο 20 χαρακτήρες για τηλέφωνο, 50 για ονόματα
            let maxLength = (textField == phoneField) ? 20 : 50
        
            // 1. Καθαρισμός χαρακτήρων (μόνο για το τηλέφωνο)
            if textField == phoneField {
                let allowedCharacters = CharacterSet(charactersIn: "+0123456789")
                let currentText = textField.stringValue
                let filteredText = currentText.unicodeScalars.filter { allowedCharacters.contains($0) }
                let newText = String(String.UnicodeScalarView(filteredText))
            
                if currentText != newText {
                    textField.stringValue = newText
                }
            }
        
            // 2. Εφαρμογή Ορίου Χαρακτήρων
            if textField.stringValue.count > maxLength {
                textField.stringValue = String(textField.stringValue.prefix(maxLength))
            }
        
            // 3. Ενημέρωση UI
            if textField == firstNameField || textField == lastNameField {
                refreshAvatarAndPickerVisibility()
            }
        }
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView, textView == notesTextView else { return }
        if notesIsShowingPlaceholder && textView.string != L("notes_placeholder") {
            notesIsShowingPlaceholder = false
            notesTextView.textColor = .white
        }
    }

    func textDidBeginEditing(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView, textView == notesTextView else { return }
    }
    
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        // Διαχείριση του Placeholder
        if textView == notesTextView, notesIsShowingPlaceholder {
            notesIsShowingPlaceholder = false
            textView.textColor = .white
            textView.string = replacementString ?? ""
            return false 
        }
    
        // Όριο Χαρακτήρων (π.χ. 500 χαρακτήρες)
        guard let replacement = replacementString else { return true }
        let currentText = textView.string
        let newLength = currentText.count + replacement.count - affectedCharRange.length
    
        return newLength <= 500
    }
    
    func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange, toCharacterRange newSelectedCharRange: NSRange) -> NSRange {
            if textView == notesTextView, notesIsShowingPlaceholder, textView.window?.firstResponder == textView {
            notesIsShowingPlaceholder = false
            textView.string = ""
            textView.textColor = .white
            
            return NSRange(location: 0, length: 0)
        }
        
        return newSelectedCharRange
    }

    func textDidEndEditing(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView, textView == notesTextView else { return }
        if textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setNotesPlaceholderVisible(true)
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
    private var tabContentViews: [NSView] = []
    private var resizingTabViewController: ResizingTabViewController?
    private var speedDialTextFields: [Int: NSTextField] = [:]

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 380), 
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
            updatesView.widthAnchor.constraint(equalToConstant: 540)
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
        
        let messagesRow = NSStackView()
        messagesRow.orientation = .horizontal
        let messagesLabel = NSTextField(labelWithString: L("show_messages_tab"))
        messagesLabel.font = NSFont.systemFont(ofSize: 14)
        messagesRow.addView(messagesLabel, in: .leading)
        let messagesSwitch = NSSwitch()
        messagesSwitch.target = self
        messagesSwitch.action = #selector(toggleFeature(_:))
        messagesSwitch.identifier = NSUserInterfaceItemIdentifier("showMessagesButton")
        messagesSwitch.state = UserDefaults.standard.bool(forKey: "hideMessagesButton") ? .off : .on
        messagesRow.addView(messagesSwitch, in: .trailing)

        let detailNotesRow = NSStackView()
        detailNotesRow.orientation = .horizontal
        let detailNotesLabel = NSTextField(labelWithString: L("show_contact_notes_in_detail"))
        detailNotesLabel.font = NSFont.systemFont(ofSize: 14)
        detailNotesRow.addView(detailNotesLabel, in: .leading)
        let detailNotesSwitch = NSSwitch()
        detailNotesSwitch.target = self
        detailNotesSwitch.action = #selector(toggleFeature(_:))
        detailNotesSwitch.identifier = NSUserInterfaceItemIdentifier("showContactNotesInDetail")
        detailNotesSwitch.state = UserDefaults.standard.bool(forKey: "hideContactNotesInDetail") ? .off : .on
        detailNotesRow.addView(detailNotesSwitch, in: .trailing)

        let appearanceStack = NSStackView(views: [favoritesRow, historyRow, contactsRow, keypadRow, plusRow, messagesRow, detailNotesRow])
        appearanceStack.orientation = .vertical
        appearanceStack.spacing = 14
        appearanceStack.translatesAutoresizingMaskIntoConstraints = false
        appearanceView.addSubview(appearanceStack)
        
        NSLayoutConstraint.activate([
            appearanceStack.centerXAnchor.constraint(equalTo: appearanceView.centerXAnchor),
            appearanceStack.topAnchor.constraint(equalTo: appearanceView.topAnchor, constant: 28),
            appearanceStack.bottomAnchor.constraint(equalTo: appearanceView.bottomAnchor, constant: -28),
            favoritesRow.widthAnchor.constraint(equalToConstant: 360),
            historyRow.widthAnchor.constraint(equalToConstant: 360),
            contactsRow.widthAnchor.constraint(equalToConstant: 360),
            keypadRow.widthAnchor.constraint(equalToConstant: 360),
            plusRow.widthAnchor.constraint(equalToConstant: 360),
            appearanceView.widthAnchor.constraint(equalToConstant: 540),
            messagesRow.widthAnchor.constraint(equalToConstant: 360),
            detailNotesRow.widthAnchor.constraint(equalToConstant: 360)
        ])
        
        appearanceVC.view = appearanceView
        appearanceVC.title = L("tab_appearance")
        let appearanceTab = NSTabViewItem(viewController: appearanceVC)
        appearanceTab.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        
        // ==========================================
        // ΚΑΡΤΕΛΑ 3: ΑΝΑΖΗΤΗΣΗ
        // ==========================================
        let searchVC = NSViewController()
        let searchView = NSView()

        let searchDescLabel = NSTextField(labelWithString: L("search_visibility_desc"))
        searchDescLabel.font = NSFont.systemFont(ofSize: 13)
        searchDescLabel.textColor = .secondaryLabelColor
        searchDescLabel.translatesAutoresizingMaskIntoConstraints = false

        func createSearchSwitchRow(title: String, defaultsKey: String) -> NSStackView {
            let row = NSStackView()
            row.orientation = .horizontal
            let label = NSTextField(labelWithString: title)
            label.font = NSFont.systemFont(ofSize: 14)
            row.addView(label, in: .leading)
            
            let toggle = NSSwitch()
            toggle.target = self
            toggle.action = #selector(toggleSearchFeature(_:))
            toggle.identifier = NSUserInterfaceItemIdentifier(defaultsKey)
            toggle.state = UserDefaults.standard.bool(forKey: defaultsKey) ? .off : .on
            row.addView(toggle, in: .trailing)
            
            return row
        }

        let contactsSearchRow = createSearchSwitchRow(title: L("search_in_contacts"), defaultsKey: "hideSearchInContacts")
        let favoritesSearchRow = createSearchSwitchRow(title: L("search_in_favorites"), defaultsKey: "hideSearchInFavorites")
        let historySearchRow = createSearchSwitchRow(title: L("search_in_history"), defaultsKey: "hideSearchInHistory")

        let searchStack = NSStackView(views: [searchDescLabel, contactsSearchRow, favoritesSearchRow, historySearchRow])
        searchStack.orientation = .vertical
        searchStack.alignment = .leading
        searchStack.spacing = 14
        searchStack.translatesAutoresizingMaskIntoConstraints = false
        searchView.addSubview(searchStack)

        NSLayoutConstraint.activate([
            searchStack.centerXAnchor.constraint(equalTo: searchView.centerXAnchor),
            searchStack.topAnchor.constraint(equalTo: searchView.topAnchor, constant: 28),
            searchStack.bottomAnchor.constraint(equalTo: searchView.bottomAnchor, constant: -28),
            contactsSearchRow.widthAnchor.constraint(equalToConstant: 300),
            favoritesSearchRow.widthAnchor.constraint(equalToConstant: 300),
            historySearchRow.widthAnchor.constraint(equalToConstant: 300),
            searchView.widthAnchor.constraint(equalToConstant: 540)
        ])

        searchVC.view = searchView
        searchVC.title = L("tab_search")
        let searchTab = NSTabViewItem(viewController: searchVC)
        searchTab.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)

        // ==========================================
        // ΚΑΡΤΕΛΑ 4: ΙΣΤΟΡΙΚΟ
        // ==========================================
        let historySettingsVC = NSViewController()
        let historySettingsView = NSView()

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

        let historySettingsStack = NSStackView(views: [historyAutoDeleteRow, detailHistoryRow])
        historySettingsStack.orientation = .vertical
        historySettingsStack.spacing = 14
        historySettingsStack.translatesAutoresizingMaskIntoConstraints = false
        historySettingsView.addSubview(historySettingsStack)

        NSLayoutConstraint.activate([
            historySettingsStack.centerXAnchor.constraint(equalTo: historySettingsView.centerXAnchor),
            historySettingsStack.topAnchor.constraint(equalTo: historySettingsView.topAnchor, constant: 28),
            historySettingsStack.bottomAnchor.constraint(equalTo: historySettingsView.bottomAnchor, constant: -28),
            historyAutoDeleteRow.widthAnchor.constraint(equalToConstant: 360),
            detailHistoryRow.widthAnchor.constraint(equalToConstant: 360),
            historySettingsView.widthAnchor.constraint(equalToConstant: 540)
        ])

        historySettingsVC.view = historySettingsView
        historySettingsVC.title = L("history")
        let historySettingsTab = NSTabViewItem(viewController: historySettingsVC)
        historySettingsTab.image = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: nil)

        // ==========================================
        // ΚΑΡΤΕΛΑ 5: ΤΑΧΕΙΑ ΚΛΗΣΗ
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
            tf.cell?.usesSingleLineMode = true
            tf.placeholderString = L("phone_placeholder")
            let savedValue = UserDefaults.standard.string(forKey: "SpeedDial_\(i)") ?? ""
            if let contact = ContactStore.shared.contacts.first(where: { $0.phone.sanitizedForCall == savedValue.sanitizedForCall && !savedValue.isEmpty }) {
                tf.stringValue = contact.fullName
                tf.toolTip = contact.phone
            } else {
                tf.stringValue = savedValue
                tf.toolTip = savedValue.isEmpty ? nil : savedValue
            }
            tf.tag = i
            tf.delegate = self
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.widthAnchor.constraint(equalToConstant: 210).isActive = true 
            speedDialTextFields[i] = tf 
            
            let pickBtn = NSButton(image: NSImage(systemSymbolName: "person.crop.circle.badge.plus", accessibilityDescription: nil) ?? NSImage(), target: self, action: #selector(showContactPicker(_:)))
            pickBtn.bezelStyle = .regularSquare
            pickBtn.isBordered = false
            pickBtn.tag = i
            pickBtn.contentTintColor = NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
            pickBtn.translatesAutoresizingMaskIntoConstraints = false
            if let cell = pickBtn.cell as? NSButtonCell { cell.imageScaling = .scaleProportionallyUpOrDown }
            pickBtn.widthAnchor.constraint(equalToConstant: 22).isActive = true
            pickBtn.heightAnchor.constraint(equalToConstant: 22).isActive = true
            row.addView(label, in: .leading)
            row.addView(tf, in: .trailing)
            row.addView(pickBtn, in: .trailing)
            sdStack.addArrangedSubview(row)
        }
        
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

            speedDialView.widthAnchor.constraint(equalToConstant: 540)
        ])
        
        speedDialVC.view = speedDialView
        speedDialVC.title = L("tab_speed_dial")
        let speedDialTab = NSTabViewItem(viewController: speedDialVC)
        speedDialTab.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
        
        // ==========================================
        // ΚΑΡΤΕΛΑ 6: ΔΕΔΟΜΕΝΑ
        // ==========================================
        let dataVC = NSViewController()
        let dataView = NSView()
        
        let dataManagementLabel = NSTextField(labelWithString: L("import_export_title"))
        dataManagementLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        dataManagementLabel.textColor = .labelColor
        dataManagementLabel.translatesAutoresizingMaskIntoConstraints = false
        dataView.addSubview(dataManagementLabel)

        let importBtn = NSButton(title: L("import_contacts"), target: NSApp.delegate, action: Selector(("importContacts")))
        importBtn.bezelStyle = .rounded
        importBtn.translatesAutoresizingMaskIntoConstraints = false
        
        let exportBtn = NSButton(title: L("export_contacts"), target: NSApp.delegate, action: Selector(("exportContacts")))
        exportBtn.bezelStyle = .rounded
        exportBtn.translatesAutoresizingMaskIntoConstraints = false

        let dataStack = NSStackView(views: [importBtn, exportBtn])
        dataStack.orientation = .horizontal
        dataStack.spacing = 10
        dataStack.translatesAutoresizingMaskIntoConstraints = false
        dataView.addSubview(dataStack)
        
        let backupLabel = NSTextField(labelWithString: L("backup_title"))
        backupLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        backupLabel.textColor = .labelColor
        backupLabel.translatesAutoresizingMaskIntoConstraints = false
        dataView.addSubview(backupLabel)

        let importBackupBtn = NSButton(title: L("import_backup"), target: NSApp.delegate, action: Selector(("importBackup")))
        importBackupBtn.bezelStyle = .rounded
        importBackupBtn.translatesAutoresizingMaskIntoConstraints = false
        
        let exportBackupBtn = NSButton(title: L("export_backup"), target: NSApp.delegate, action: Selector(("exportBackup")))
        exportBackupBtn.bezelStyle = .rounded
        exportBackupBtn.translatesAutoresizingMaskIntoConstraints = false

        let backupStack = NSStackView(views: [importBackupBtn, exportBackupBtn])
        backupStack.orientation = .horizontal
        backupStack.spacing = 10
        backupStack.translatesAutoresizingMaskIntoConstraints = false
        dataView.addSubview(backupStack)
        
        let helpBtn = NSButton(title: "", target: NSApp.delegate, action: Selector(("showBackupHelp")))
        helpBtn.bezelStyle = .helpButton
        helpBtn.translatesAutoresizingMaskIntoConstraints = false
        dataView.addSubview(helpBtn)

        NSLayoutConstraint.activate([
            dataManagementLabel.topAnchor.constraint(equalTo: dataView.topAnchor, constant: 32),
            dataManagementLabel.centerXAnchor.constraint(equalTo: dataView.centerXAnchor),
            
            dataStack.topAnchor.constraint(equalTo: dataManagementLabel.bottomAnchor, constant: 12),
            dataStack.centerXAnchor.constraint(equalTo: dataView.centerXAnchor),
            
            backupLabel.topAnchor.constraint(equalTo: dataStack.bottomAnchor, constant: 32),
            backupLabel.centerXAnchor.constraint(equalTo: dataView.centerXAnchor),
            
            backupStack.topAnchor.constraint(equalTo: backupLabel.bottomAnchor, constant: 12),
            backupStack.centerXAnchor.constraint(equalTo: dataView.centerXAnchor),
            
            helpBtn.topAnchor.constraint(equalTo: backupStack.bottomAnchor, constant: 28),
            helpBtn.centerXAnchor.constraint(equalTo: dataView.centerXAnchor),
            helpBtn.bottomAnchor.constraint(equalTo: dataView.bottomAnchor, constant: -32),
            
            dataView.widthAnchor.constraint(equalToConstant: 540)
        ])
        
        dataVC.view = dataView
        dataVC.title = L("tab_data")
        let dataTab = NSTabViewItem(viewController: dataVC)
        dataTab.image = NSImage(systemSymbolName: "externaldrive.fill", accessibilityDescription: nil)

        // ==========================================
        // ΚΑΡΤΕΛΑ 7: ΠΛΗΡΟΦΟΡΙΕΣ
        // ==========================================
        let infoVC = NSViewController()
        let infoView = NSView()

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

        let appTaglineLabel = NSTextField(labelWithString: L("app_tagline"))
        appTaglineLabel.font = NSFont.systemFont(ofSize: 12)
        appTaglineLabel.textColor = .secondaryLabelColor
        appTaglineLabel.lineBreakMode = .byTruncatingTail
        appTaglineLabel.translatesAutoresizingMaskIntoConstraints = false

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

        let descriptionLabel = NSTextField(wrappingLabelWithString: L("app_description"))
        descriptionLabel.font = NSFont.systemFont(ofSize: 13)
        descriptionLabel.textColor = .labelColor
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        infoView.addSubview(descriptionLabel)

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

        let infoVersionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.4"
        let infoVersionLabel = NSTextField(labelWithString: L("current_version", infoVersionString))
        infoVersionLabel.font = NSFont.systemFont(ofSize: 12)
        infoVersionLabel.textColor = .secondaryLabelColor
        infoVersionLabel.translatesAutoresizingMaskIntoConstraints = false
        infoView.addSubview(infoVersionLabel)

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

            infoView.widthAnchor.constraint(equalToConstant: 540)
        ])

        infoVC.view = infoView
        infoVC.title = L("tab_info")
        let infoTab = NSTabViewItem(viewController: infoVC)
        infoTab.image = NSImage(systemSymbolName: "info.circle.fill", accessibilityDescription: nil)

        tabViewController.addTabViewItem(updatesTab)
        tabViewController.addTabViewItem(appearanceTab)
        tabViewController.addTabViewItem(searchTab)
        tabViewController.addTabViewItem(historySettingsTab)
        tabViewController.addTabViewItem(speedDialTab)
        tabViewController.addTabViewItem(dataTab)
        tabViewController.addTabViewItem(infoTab)
        
        window.contentViewController = tabViewController

        self.tabContentViews = [updatesView, appearanceView, searchView, historySettingsView, speedDialView, dataView, infoView]
        self.resizingTabViewController = tabViewController
        tabViewController.onTabWillActivate = { [weak self] index in
            self?.resizeWindow(forTabIndex: index, animated: true)
        }

        DispatchQueue.main.async { [weak self] in
            self?.resizeWindow(forTabIndex: 0, animated: false)
            self?.recenterOnMainWindow()
        }
    }

    /// Επαναφέρει το παράθυρο Ρυθμίσεων στο κέντρο του κύριου παραθύρου της εφαρμογής.
    /// Χρειάζεται γιατί το αρχικό centering στο convenience init() γίνεται με βάση
    /// το placeholder ύψος (380) που δίνεται στο NSWindow(contentRect:), ενώ το
    /// πραγματικό ύψος της πρώτης καρτέλας καθορίζεται αργότερα από resizeWindow(forTabIndex:),
    /// μετατοπίζοντας το παράθυρο εκτός κέντρου.
    private func recenterOnMainWindow() {
        guard let window = self.window else { return }

        if let mainWindow = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.title == "HelloMac" }) {
            let x = mainWindow.frame.midX - window.frame.width / 2
            let y = mainWindow.frame.midY - window.frame.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.center()
        }
    }

    private func resizeWindow(forTabIndex index: Int, animated: Bool) {
        guard let window = self.window,
              index >= 0, index < tabContentViews.count else { return }
        let contentView = tabContentViews[index]

        let targetContentHeight = contentView.fittingSize.height
        let currentContentRect = window.contentRect(forFrameRect: window.frame)
        guard abs(currentContentRect.height - targetContentHeight) > 0.5 else { return }

        var newFrame = window.frame
        let heightDelta = targetContentHeight - currentContentRect.height
        newFrame.size.height += heightDelta
        newFrame.origin.y -= heightDelta

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

            if let tabVC = self.resizingTabViewController {
                self.resizeWindow(forTabIndex: tabVC.selectedTabViewItemIndex, animated: true)
            }
        }
    }

    @objc private func installUpdateTapped() {
        guard let downloadURL = pendingDownloadURL,
              let appDelegate = NSApp.delegate as? AppDelegate else { return }
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
        } else if sender.identifier?.rawValue == "showContactNotesInDetail" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hideContactNotesInDetail")
        } else if sender.identifier?.rawValue == "showMessagesButton" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hideMessagesButton")
        }
        
        NotificationCenter.default.post(name: NSNotification.Name("UpdateUIVisibility"), object: nil)
    }
    
    @objc private func toggleSearchFeature(_ sender: NSSwitch) {
        guard let key = sender.identifier?.rawValue else { return }
        UserDefaults.standard.set(sender.state == .off, forKey: key)
        NotificationCenter.default.post(name: NSNotification.Name("UpdateUIVisibility"), object: nil)
    }

    @objc private func historyAutoDeleteChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: HistoryAutoDeleteInterval.defaultsKey)
        HistoryStore.shared.purgeExpiredRecords()
    }
    
    // --- ΛΕΙΤΟΥΡΓΙΕΣ ΧΕΙΡΟΚΙΝΗΤΗΣ ΠΛΗΚΤΡΟΛΟΓΗΣΗΣ ---

    func controlTextDidBeginEditing(_ obj: Notification) {
        if let tf = obj.object as? NSTextField, tf.tag >= 1, tf.tag <= 9 {
            // Όταν κάνεις κλικ, δείξε πάλι τον αριθμό για να τον επεξεργαστείς
            let savedValue = UserDefaults.standard.string(forKey: "SpeedDial_\(tf.tag)") ?? ""
            tf.stringValue = savedValue
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        if let tf = obj.object as? NSTextField, tf.tag >= 1, tf.tag <= 9 {
            // Όριο 20 χαρακτήρες
            if tf.stringValue.count > 20 {
                tf.stringValue = String(tf.stringValue.prefix(20))
            }
        
            // Όσο πληκτρολογείς, αποθήκευσε το
            UserDefaults.standard.set(tf.stringValue, forKey: "SpeedDial_\(tf.tag)")
        }
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        if let tf = obj.object as? NSTextField, tf.tag >= 1, tf.tag <= 9 {
            let savedValue = tf.stringValue
            UserDefaults.standard.set(savedValue, forKey: "SpeedDial_\(tf.tag)")
            
            // Μόλις κάνεις κλικ αλλού, κάνε το πάλι Όνομα (και τον αριθμό Tooltip)
            if let contact = ContactStore.shared.contacts.first(where: { $0.phone.sanitizedForCall == savedValue.sanitizedForCall && !savedValue.isEmpty }) {
                tf.stringValue = contact.fullName
                tf.toolTip = contact.phone
            } else {
                tf.toolTip = savedValue.isEmpty ? nil : savedValue
            }
        }
    }

    // --- ΛΕΙΤΟΥΡΓΙΕΣ ΜΕΝΟΥ (PICKER) ---

    @objc private func showContactPicker(_ sender: NSButton) {
        let menu = NSMenu()
        
        let contacts = ContactStore.shared.contacts.sorted { 
            $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending 
        }
        
        if contacts.isEmpty {
            menu.addItem(NSMenuItem(title: L("no_contacts"), action: nil, keyEquivalent: ""))
        } else {
            for contact in contacts {
                let title = "\(contact.fullName) - \(contact.phone)"
                let item = NSMenuItem(title: title, action: #selector(contactSelectedForSpeedDial(_:)), keyEquivalent: "")
                item.target = self
                
                item.representedObject = ["tag": sender.tag, "phone": contact.phone, "name": contact.fullName] as [String: Any]
                item.image = NSImage(systemSymbolName: "person.circle", accessibilityDescription: nil)
                
                menu.addItem(item)
            }
        }
        
        let point = NSPoint(x: 0, y: sender.bounds.height + 5)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc private func contactSelectedForSpeedDial(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? [String: Any],
              let tag = data["tag"] as? Int,
              let phone = data["phone"] as? String,
              let name = data["name"] as? String else { return }
        
        if let tf = speedDialTextFields[tag] {
            tf.stringValue = name
            tf.toolTip = phone
            UserDefaults.standard.set(phone, forKey: "SpeedDial_\(tag)")
            
            // Ξε-εστιάζουμε το πεδίο για να δουλεύει το hover αμέσως
            tf.window?.makeFirstResponder(nil)
        }
    }
}