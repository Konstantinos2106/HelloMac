import AppKit
import UniformTypeIdentifiers
import UserNotifications

enum ColorWheelIcon {
    static func make(diameter: CGFloat = 20) -> NSImage {
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()

        let center = NSPoint(x: diameter / 2, y: diameter / 2)
        let radius = diameter / 2

        let stepDegrees: CGFloat = 2
        let steps = Int(360 / stepDegrees)
        for i in 0..<steps {
            let hue = CGFloat(i) / CGFloat(steps)
            let color = NSColor(hue: hue, saturation: 0.85, brightness: 1.0, alpha: 1)
            let startAngle = CGFloat(i) * stepDegrees
            let endAngle = startAngle + stepDegrees + 0.5
            let path = NSBezierPath()
            path.move(to: center)
            path.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            path.close()
            color.setFill()
            path.fill()
        }

        let border = NSBezierPath(ovalIn: NSRect(x: 0.5, y: 0.5, width: diameter - 1, height: diameter - 1))
        NSColor.black.withAlphaComponent(0.15).setStroke()
        border.lineWidth = 0.75
        border.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

class RoundAvatarView: NSView {
    private let imageView = NSImageView()
    private let initialsLabel = NSTextField(labelWithString: "")
    private let privacyBlurOverlay = NSVisualEffectView()
    private var diameter: CGFloat
    var onTap: (() -> Void)? {
        didSet { updateTooltip() }
    }

    private func updateTooltip() {
        toolTip = onTap != nil ? L("click_to_view_photo") : nil
    }

    private var storedImage: NSImage?
    private var storedInitials: String = ""
    private var storedColorOverride: NSColor?

    private static let palette: [NSColor] = [
        NSColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 1),
        NSColor(red: 0.95, green: 0.45, blue: 0.55, alpha: 1),
        NSColor(red: 0.30, green: 0.75, blue: 0.55, alpha: 1),
        NSColor(red: 0.85, green: 0.55, blue: 0.25, alpha: 1),
        NSColor(red: 0.60, green: 0.45, blue: 0.90, alpha: 1),
        NSColor(red: 0.20, green: 0.70, blue: 0.80, alpha: 1),
        NSColor(red: 0.90, green: 0.35, blue: 0.65, alpha: 1),
        NSColor(red: 0.45, green: 0.65, blue: 0.25, alpha: 1),
        NSColor(red: 0.95, green: 0.65, blue: 0.15, alpha: 1),
        NSColor(red: 0.40, green: 0.40, blue: 0.85, alpha: 1),
        NSColor(red: 0.20, green: 0.60, blue: 0.45, alpha: 1),
        NSColor(red: 0.80, green: 0.30, blue: 0.30, alpha: 1),
    ]

    init(diameter: CGFloat) {
        self.diameter = diameter
        super.init(frame: .zero)
        wantsLayer = true
        identifier = a11ySelfManagedIdentifier
        setupSubviews()
        NotificationCenter.default.addObserver(self, selector: #selector(privacyModeChanged), name: .privacyModeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accessibilitySettingsChanged), name: .accessibilitySettingsDidChange, object: nil)
    }

    required init?(coder: NSCoder) {
        self.diameter = 44
        super.init(coder: coder)
        wantsLayer = true
        identifier = a11ySelfManagedIdentifier
        setupSubviews()
        NotificationCenter.default.addObserver(self, selector: #selector(privacyModeChanged), name: .privacyModeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accessibilitySettingsChanged), name: .accessibilitySettingsDidChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func privacyModeChanged() {
        applyCurrentConfiguration()
    }

    @objc private func accessibilitySettingsChanged() {
        applyCurrentConfiguration()
        needsLayout = true
    }

    private func setupSubviews() {
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.identifier = a11yUserPhotoIdentifier
        addSubview(imageView)

        initialsLabel.alignment = .center
        initialsLabel.textColor = .white
        initialsLabel.isEditable = false
        initialsLabel.isSelectable = false
        initialsLabel.isBezeled = false
        initialsLabel.drawsBackground = false
        initialsLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(initialsLabel)

        privacyBlurOverlay.material = .hudWindow
        privacyBlurOverlay.blendingMode = .withinWindow
        privacyBlurOverlay.state = .active
        privacyBlurOverlay.wantsLayer = true
        privacyBlurOverlay.translatesAutoresizingMaskIntoConstraints = false
        privacyBlurOverlay.isHidden = true
        addSubview(privacyBlurOverlay)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            initialsLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            privacyBlurOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            privacyBlurOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            privacyBlurOverlay.topAnchor.constraint(equalTo: topAnchor),
            privacyBlurOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
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
        privacyBlurOverlay.layer?.cornerRadius = radius
        privacyBlurOverlay.layer?.cornerCurve = .circular
        privacyBlurOverlay.layer?.masksToBounds = true
        initialsLabel.font = AccessibilityManager.shared.adjustedFont(
            baseSize: min(bounds.width, bounds.height) * 0.36, weight: .semibold)
        let a11y = AccessibilityManager.shared
        layer?.borderWidth = a11y.highContrastBorderWidth
        layer?.borderColor = a11y.highContrastBorderColor
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

    private var storedColorSeed: String?

    func configure(image: NSImage?, initials: String, colorOverride: NSColor? = nil, colorSeed: String? = nil) {
        storedImage = image
        storedInitials = initials
        storedColorOverride = colorOverride
        storedColorSeed = colorSeed
        applyCurrentConfiguration()
    }

    private func applyCurrentConfiguration() {
        let privacyOn = PrivacyMode.shared.isEnabled
        let a11y = AccessibilityManager.shared

        if let image = storedImage {
            imageView.image = a11y.desaturatedImage(image)
            imageView.isHidden = false
            initialsLabel.isHidden = true
            layer?.backgroundColor = NSColor.clear.cgColor
            privacyBlurOverlay.isHidden = !privacyOn
        } else {
            imageView.image = nil
            imageView.isHidden = true
            initialsLabel.isHidden = false
            initialsLabel.stringValue = privacyOn ? PrivacyMode.shared.maskedInitials : storedInitials
            let seed = (storedColorSeed?.isEmpty == false ? storedColorSeed! : storedInitials)
            let baseColor = storedColorOverride ?? RoundAvatarView.colorForSeed(seed)
            layer?.backgroundColor = a11y.adjustedColor(baseColor).cgColor
            initialsLabel.textColor = a11y.adjustedColor(.white)
            privacyBlurOverlay.isHidden = true
        }
    }

    static func resetColorSequence() {
        // Σκόπιμα κενό.
    }

    private static func colorForSeed(_ seed: String) -> NSColor {
        return palette[colorIndexForSeed(seed)]
    }

    private static func colorIndexForSeed(_ seed: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for scalar in seed.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash = hash &* prime
        }
        hash ^= (hash >> 33)
        hash = hash &* 0xff51afd7ed558ccd
        hash ^= (hash >> 33)
        return Int(hash % UInt64(palette.count))
    }
}

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
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        selectedColor = sender.color
        refreshSelectionRing()
        onColorChange?(sender.color)
    }

    @objc private func openColorWheel() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
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
    private static let groupsAreaHeight: CGFloat = 50
    private static let windowHeightWithPicker: CGFloat = 366 + notesAreaHeight
    private static let windowHeightWithoutPicker: CGFloat = 366 - 32 + notesAreaHeight
    private static let windowHeightWithPhotoActions: CGFloat = windowHeightWithoutPicker + 24
    private var selectedImage: NSImage?
    private var didClearImage = false
    private var activeCropController: ImageCropWindowController?
    private var selectedMonogramColor: NSColor?
    private var groupsLabel: NSTextField!
    private var groupsButton: NSPopUpButton!
    private var groupsFieldTopToNotes: NSLayoutConstraint!
    private var notesTopToGroupsField: NSLayoutConstraint!
    private var notesTopToPhoneField: NSLayoutConstraint!
    private var selectedGroupIDs: Set<UUID> = []
    
    var contactToEdit: Contact?
    private var prefillPhone: String?

    convenience init(contactToEdit: Contact? = nil, prefillPhone: String? = nil) {
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
        self.prefillPhone = prefillPhone
        window.title = contactToEdit == nil ? L("add_contact_menu") : L("edit_contact")
        setupUI()
        populateData()
        NotificationCenter.default.addObserver(self, selector: #selector(privacyModeChangedRepopulate), name: .privacyModeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyAccessibilityToWholeAddContactWindow), name: .accessibilitySettingsDidChange, object: nil)
        applyAccessibilityToWholeAddContactWindow()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func privacyModeChangedRepopulate() {
        populateData()
    }

    @objc private func applyAccessibilityToWholeAddContactWindow() {
        guard let window = window else { return }
        let a11y = AccessibilityManager.shared
        a11y.applyPreferredAppearance(to: window)
        window.a11yBaseBackgroundColor = nil
        window.a11yHasCapturedBackgroundColor = true
        if a11y.isGrayscaleEnabled && a11y.isEffectivelyColorInverted {
            window.backgroundColor = .white
        } else if a11y.isGrayscaleEnabled {
            window.backgroundColor = .black
        } else {
            window.backgroundColor = nil
        }

        guard let contentView = window.contentView else { return }
        AccessibilityManager.shared.applyToViewTree(contentView)
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let backgroundEffect = NSVisualEffectView()
        backgroundEffect.material = .underWindowBackground
        backgroundEffect.blendingMode = .withinWindow
        backgroundEffect.state = .active
        backgroundEffect.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backgroundEffect)
        NSLayoutConstraint.activate([
            backgroundEffect.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundEffect.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            backgroundEffect.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundEffect.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

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

        groupsLabel = NSTextField(labelWithString: L("groups_field_label"))
        groupsLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        groupsLabel.textColor = NSColor(white: 0.5, alpha: 1)
        groupsLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(groupsLabel)
        groupsButton = NSPopUpButton()
        groupsButton.pullsDown = true
        groupsButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(groupsButton)

        notesLabel = NSTextField(labelWithString: L("notes_title"))
        notesLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        notesLabel.textColor = NSColor(white: 0.5, alpha: 1)
        notesLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(notesLabel)

        notesTopToGroupsField = notesLabel.topAnchor.constraint(equalTo: groupsButton.bottomAnchor, constant: 14)
        notesTopToPhoneField = notesLabel.topAnchor.constraint(equalTo: phoneField.bottomAnchor, constant: 14)

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

            groupsLabel.topAnchor.constraint(equalTo: phoneField.bottomAnchor, constant: 14),
            groupsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            groupsButton.topAnchor.constraint(equalTo: groupsLabel.bottomAnchor, constant: 6),
            groupsButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            groupsButton.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),

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
        let privacyOn = PrivacyMode.shared.isEnabled
        if let contact = contactToEdit {
            if privacyOn {
                firstNameField.stringValue = PrivacyMode.shared.maskedText(contact.firstName)
                lastNameField.stringValue = PrivacyMode.shared.maskedText(contact.lastName)
                phoneField.stringValue = PrivacyMode.shared.maskedText(contact.phone)
            } else {
                firstNameField.stringValue = contact.firstName
                lastNameField.stringValue = contact.lastName
                phoneField.stringValue = contact.phone
            }
            let notes = contact.notes ?? ""
            if notes.isEmpty {
                setNotesPlaceholderVisible(true)
            } else if privacyOn {
                notesTextView.string = PrivacyMode.shared.maskedText(notes)
                setNotesPlaceholderVisible(false)
            } else {
                notesTextView.string = notes
                setNotesPlaceholderVisible(false)
            }
            if let hex = contact.monogramColorHex, let color = NSColor(hexString: hex) {
                selectedMonogramColor = color
            }
            let existingGroupIDs = Set(ContactGroupStore.shared.groups.map { $0.id })
            selectedGroupIDs = Set(contact.groupIDs).intersection(existingGroupIDs)
        } else {
            setNotesPlaceholderVisible(true)
            if let prefillPhone {
                phoneField.stringValue = privacyOn ? PrivacyMode.shared.maskedText(prefillPhone) : prefillPhone
            }
        }

        firstNameField.isEditable = !privacyOn
        lastNameField.isEditable = !privacyOn
        phoneField.isEditable = !privacyOn
        notesTextView.isEditable = !privacyOn
        groupsButton.isEnabled = !privacyOn

        monogramColorPicker.setSelected(color: selectedMonogramColor)
        refreshAvatarAndPickerVisibility()
    }

    private func refreshAvatarAndPickerVisibility() {
        let image = selectedImage ?? (didClearImage ? nil : contactToEdit?.image)
        avatarView.configure(image: image, initials: currentInitials(), colorOverride: selectedMonogramColor, colorSeed: contactToEdit?.id.uuidString)
        let hasPhoto = (image != nil)
        let showPicker = !hasPhoto

        monogramColorPicker.isHidden = !showPicker
        photoActionsRow.isHidden = !hasPhoto

        firstNameFieldTopToPicker.isActive = showPicker
        firstNameFieldTopToActionsRow.isActive = hasPhoto
        firstNameFieldTopToButton.isActive = !showPicker && !hasPhoto

        refreshGroupsFieldVisibility()
        resizeWindow(showPicker: showPicker, hasPhoto: hasPhoto)
    }

    private func refreshGroupsFieldVisibility() { 
        let hasGroupsFeature = ContactGroupStore.shared.isEnabled
        
        groupsLabel.isHidden = !hasGroupsFeature
        groupsButton.isHidden = !hasGroupsFeature
        notesTopToGroupsField.isActive = hasGroupsFeature
        notesTopToPhoneField.isActive = !hasGroupsFeature
        rebuildGroupsMenu()
    }

    private func rebuildGroupsMenu() {
        let menu = NSMenu()
        for group in ContactGroupStore.shared.sortedGroups {
            let item = NSMenuItem(title: group.name, action: #selector(toggleGroupSelection(_:)), keyEquivalent: "")
            item.target = self
            item.state = selectedGroupIDs.contains(group.id) ? .on : .off
            item.representedObject = group.id
            menu.addItem(item)
        }

        if !menu.items.isEmpty {
            menu.addItem(NSMenuItem.separator())
        }
        let newGroupItem = NSMenuItem(title: L("groups_new_group_menu_item"), action: #selector(createGroupFromContactForm), keyEquivalent: "")
        newGroupItem.target = self
        let plusConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        newGroupItem.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: nil)?.withSymbolConfiguration(plusConfig)
        menu.addItem(newGroupItem)

        groupsButton.menu = menu
        updateGroupsButtonTitle()
    }

    @objc private func createGroupFromContactForm() {
        let alert = NSAlert()
        alert.messageText = L("groups_add_prompt_title")
        alert.addButton(withTitle: L("save_btn"))
        alert.addButton(withTitle: L("cancel_btn"))

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.placeholderString = L("groups_add_placeholder")
        alert.accessoryView = input
        AccessibilityManager.shared.applyAccessibility(to: alert)

        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            guard let self = self else { return }
            let sanitized = ContactGroup.sanitizedName(input.stringValue)
            guard !sanitized.isEmpty else { return }
            guard let newGroup = ContactGroupStore.shared.addGroup(name: sanitized) else {
                return
            }
            self.selectedGroupIDs.insert(newGroup.id)
            self.refreshAvatarAndPickerVisibility()
        }

        if let win = window {
            alert.beginSheetModal(for: win, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    @objc private func toggleGroupSelection(_ sender: NSMenuItem) {
        guard let groupID = sender.representedObject as? UUID else { return }
        if selectedGroupIDs.contains(groupID) {
            selectedGroupIDs.remove(groupID)
        } else {
            selectedGroupIDs.insert(groupID)
        }
        rebuildGroupsMenu()
    }

    private func updateGroupsButtonTitle() {
        let names = ContactGroupStore.shared.sortedGroups
            .filter { selectedGroupIDs.contains($0.id) }
            .map { $0.name }
        let title = names.isEmpty ? L("groups_none_selected") : names.joined(separator: ", ")
        let titleItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        groupsButton.menu?.insertItem(titleItem, at: 0)
        groupsButton.selectItem(at: 0)
    }

    private func resizeWindow(showPicker: Bool, hasPhoto: Bool) {
        guard let win = window else { return }
        var targetHeight: CGFloat = showPicker ? Self.windowHeightWithPicker : (hasPhoto ? Self.windowHeightWithPhotoActions : Self.windowHeightWithoutPicker)
        if !groupsButton.isHidden {
            targetHeight += Self.groupsAreaHeight
        }
        var frame = win.frame
        guard abs(frame.height - targetHeight) > 0.5 else { return }
        let heightDelta = frame.height - targetHeight
        frame.size.height = targetHeight
        frame.origin.y += heightDelta
        win.setFrame(frame, display: true, animate: win.isVisible)
    }

    @objc private func pickImage() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
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
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        selectedImage = nil
        didClearImage = true
        refreshAvatarAndPickerVisibility()
    }

    @objc private func reCropExistingPhoto() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
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
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }

        let firstName = firstNameField.stringValue.trimmingCharacters(in: .whitespaces)
        let lastName = lastNameField.stringValue.trimmingCharacters(in: .whitespaces)
        let phone = phoneField.stringValue.trimmingCharacters(in: .whitespaces)

        guard !firstName.isEmpty, !phone.isEmpty else {
            let alert = NSAlert()
            alert.messageText = L("fill_fields")
            alert.addButton(withTitle: L("ok"))
            AccessibilityManager.shared.applyAccessibility(to: alert)
            alert.runModal()
            return
        }

        let notesText = notesIsShowingPlaceholder ? "" : notesTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesValue: String? = notesText.isEmpty ? nil : notesText
        let groupsToSave: [UUID] = ContactGroupStore.shared.isEnabled
            ? Array(selectedGroupIDs)
            : (contactToEdit?.groupIDs ?? [])

        if var contact = contactToEdit {
            contact.firstName = firstName
            contact.lastName = lastName
            contact.phone = phone
            contact.monogramColorHex = selectedMonogramColor?.hexString
            contact.notes = notesValue
            contact.groupIDs = groupsToSave
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
            newContact.groupIDs = groupsToSave
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
        selectedGroupIDs = []
        closeWindowClearingAnyStuckSheet()
    }

    @objc func cancel() {
        closeWindowClearingAnyStuckSheet()
    }

    private func closeWindowClearingAnyStuckSheet() {
        if let win = window, let stuckSheet = win.attachedSheet {
            win.endSheet(stuckSheet)
        }
        window?.close()
    }
    
    func controlTextDidChange(_ obj: Notification) {
        if let textField = obj.object as? NSTextField {
            let maxLength = (textField == phoneField) ? 20 : 50
        
            if textField == phoneField {
                let allowedCharacters = CharacterSet(charactersIn: "+0123456789")
                let currentText = textField.stringValue
                let filteredText = currentText.unicodeScalars.filter { allowedCharacters.contains($0) }
                let newText = String(String.UnicodeScalarView(filteredText))
            
                if currentText != newText {
                    textField.stringValue = newText
                }
            }
        
            if textField.stringValue.count > maxLength {
                textField.stringValue = String(textField.stringValue.prefix(maxLength))
            }
        
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
        if textView == notesTextView, notesIsShowingPlaceholder {
            notesIsShowingPlaceholder = false
            textView.textColor = .white
            textView.string = replacementString ?? ""
            return false 
        }
    
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

// MARK: - SettingsSidebarTableView
private class SettingsSidebarTableView: NSTableView {
    override func highlightSelection(inClipRect clipRect: NSRect) {
        guard selectedRowIndexes.count > 0 else { return }
        NSColor.controlAccentColor.setFill()
        for row in selectedRowIndexes {
            let rowRect = rect(ofRow: row)
            let fullWidthRowRect = NSRect(x: bounds.minX, y: rowRect.minY, width: bounds.width, height: rowRect.height)
            let insetRect = fullWidthRowRect.insetBy(dx: 10, dy: 2).integral
            let path = NSBezierPath(roundedRect: insetRect, xRadius: 6, yRadius: 6)
            path.fill()
        }
    }
}

private struct SearchableItem {
    let label: String
    weak var anchorView: NSView?
}

private struct SettingsCategory {
    let title: String
    let symbolName: String
    let tintColor: NSColor
    let view: NSView
    let searchableItems: [SearchableItem]
}

private enum SidebarSearchRow {
    case sectionHeader(categoryIndex: Int)
    case matchedItem(categoryIndex: Int, item: SearchableItem)
}

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private class LeaderLine: NSView {
    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: 10)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.5, alpha: 0.3).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.setLineDash([2, 4], count: 2, phase: 0)
        path.move(to: NSPoint(x: 0, y: bounds.midY))
        path.line(to: NSPoint(x: bounds.width, y: bounds.midY))
        path.stroke()
    }
}

private class SettingsIconBadge: NSView {
    private let imageView = NSImageView()
    private let diameter: CGFloat = 26
    private let baseTint: NSColor

    static func loadSymbol(_ name: String, fallback: String) -> NSImage? {
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            return image
        }
        return NSImage(systemSymbolName: fallback, accessibilityDescription: nil)
    }

    init(symbolName: String, tint: NSColor) {
        self.baseTint = tint
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        identifier = a11ySelfManagedIdentifier
        layer?.cornerRadius = 6.5
        layer?.cornerCurve = .continuous

        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        imageView.image = SettingsIconBadge.loadSymbol(symbolName, fallback: "questionmark.circle")?
            .withSymbolConfiguration(config)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateColors()
        NotificationCenter.default.addObserver(self, selector: #selector(updateColors), name: .accessibilitySettingsDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func updateColors() {
        let a11y = AccessibilityManager.shared
        layer?.backgroundColor = a11y.adjustedColor(baseTint).cgColor
        imageView.contentTintColor = .white
        layer?.borderWidth = a11y.highContrastBorderWidth
        layer?.borderColor = a11y.highContrastBorderColor
    }
}

private class SettingsSidebarRowView: NSTableCellView {
    private let badge: SettingsIconBadge
    private let label = NSTextField(labelWithString: "")

    init(category: SettingsCategory) {
        badge = SettingsIconBadge(symbolName: category.symbolName, tint: category.tintColor)
        super.init(frame: .zero)

        label.stringValue = category.title
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [badge, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
}

private class SettingsSidebarSectionHeaderView: NSTableCellView {
    init(category: SettingsCategory) {
        super.init(frame: .zero)
        let badge = SettingsIconBadge(symbolName: category.symbolName, tint: category.tintColor)
        let label = NSTextField(labelWithString: category.title)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [badge, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
}

private class SettingsSidebarMatchedItemView: NSTableCellView {
    init(label text: String) {
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 46),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
}

private class GroupSettingsRowView: NSView {
    var groupID: UUID?

    init(group: ContactGroup, displayName: String? = nil, target: AnyObject, renameAction: Selector, deleteAction: Selector) {
        self.groupID = group.id
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.05).cgColor
        layer?.cornerRadius = 8

        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.05).cgColor
        layer?.cornerRadius = 8

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = (group.color ?? NSColor.systemIndigo).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: displayName ?? group.name)
        nameLabel.font = NSFont.systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let renameConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let renameImg = NSImage(systemSymbolName: "pencil", accessibilityDescription: L("groups_rename_tooltip"))?.withSymbolConfiguration(renameConfig)
        let renameButton = NSButton(image: renameImg ?? NSImage(), target: nil, action: nil)
        renameButton.bezelStyle = .regularSquare
        renameButton.isBordered = false
        renameButton.contentTintColor = NSColor(white: 0.6, alpha: 1)
        renameButton.translatesAutoresizingMaskIntoConstraints = false

        let deleteConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let deleteImg = NSImage(systemSymbolName: "trash", accessibilityDescription: L("groups_delete_tooltip"))?.withSymbolConfiguration(deleteConfig)
        let deleteButton = NSButton(image: deleteImg ?? NSImage(), target: nil, action: nil)
        deleteButton.bezelStyle = .regularSquare
        deleteButton.isBordered = false
        deleteButton.contentTintColor = NSColor.systemRed
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(dot)
        addSubview(nameLabel)
        addSubview(renameButton)
        addSubview(deleteButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),

            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),

            nameLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: renameButton.leadingAnchor, constant: -6),

            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 22),
            deleteButton.heightAnchor.constraint(equalToConstant: 22),

            renameButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -4),
            renameButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            renameButton.widthAnchor.constraint(equalToConstant: 22),
            renameButton.heightAnchor.constraint(equalToConstant: 22),
        ])

        self.outerTarget = target
        self.outerRenameAction = renameAction
        self.outerDeleteAction = deleteAction
        renameButton.target = self
        renameButton.action = #selector(renameButtonTapped)
        deleteButton.target = self
        deleteButton.action = #selector(deleteButtonTapped)
    }

    private weak var outerTarget: AnyObject?
    private var outerRenameAction: Selector?
    private var outerDeleteAction: Selector?

    @objc private func renameButtonTapped() {
        guard let action = outerRenameAction else { return }
        _ = outerTarget?.perform(action, with: self)
    }

    @objc private func deleteButtonTapped() {
        guard let action = outerDeleteAction else { return }
        _ = outerTarget?.perform(action, with: self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
}

private class SettingsSidebarController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    let categories: [SettingsCategory]
    var onSelect: ((Int, NSView?) -> Void)?
    private let tableView = SettingsSidebarTableView()

    private var displayedRows: [SidebarSearchRow] = []

    init(categories: [SettingsCategory]) {
        self.categories = categories
        super.init(nibName: nil, bundle: nil)
        self.displayedRows = categories.indices.map { .sectionHeader(categoryIndex: $0) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.rowSizeStyle = .custom
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.style = .sourceList
        tableView.gridStyleMask = []

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("category"))
        column.width = 200
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.reloadData()
        
        let lastCategory = UserDefaults.standard.integer(forKey: "SettingsLastSelectedCategory")
        let targetIndex = (lastCategory >= 0 && lastCategory < categories.count) ? lastCategory : 0
        
        if let row = displayedRows.firstIndex(where: {
            if case .sectionHeader(let idx) = $0 { return idx == targetIndex }
            return false
        }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if !displayedRows.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func applyFilter(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            displayedRows = categories.indices.map { .sectionHeader(categoryIndex: $0) }
        } else {
            var rows: [SidebarSearchRow] = []
            for idx in categories.indices {
                let category = categories[idx]
                let titleMatches = category.title.localizedCaseInsensitiveContains(trimmed)
                let matchedItems = category.searchableItems.filter {
                    $0.label.localizedCaseInsensitiveContains(trimmed)
                }
                guard titleMatches || !matchedItems.isEmpty else { continue }

                rows.append(.sectionHeader(categoryIndex: idx))
                for item in matchedItems {
                    rows.append(.matchedItem(categoryIndex: idx, item: item))
                }
            }
            displayedRows = rows
        }

        tableView.reloadData()

        if let firstRow = displayedRows.first {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            switch firstRow {
            case .sectionHeader(let idx):
                onSelect?(idx, nil)
            case .matchedItem(let idx, let item):
                onSelect?(idx, item.anchorView)
            }
        }
    }

    func selectRow(_ categoryIndex: Int) {
        guard !isSearching else { return }
        guard let row = displayedRows.firstIndex(where: {
            if case .sectionHeader(let idx) = $0 { return idx == categoryIndex }
            return false
        }) else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private var isSearching: Bool {
        displayedRows.contains { if case .matchedItem = $0 { return true }; return false }
            || displayedRows.count != categories.count
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        displayedRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch displayedRows[row] {
        case .sectionHeader(let idx):
            return SettingsSidebarRowView(category: categories[idx])
        case .matchedItem(_, let item):
            return SettingsSidebarMatchedItemView(label: item.label)
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch displayedRows[row] {
        case .sectionHeader: return 34
        case .matchedItem: return 22
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < displayedRows.count else { return }
        switch displayedRows[row] {
        case .sectionHeader(let idx):
            onSelect?(idx, nil)
        case .matchedItem(let idx, let item):
            onSelect?(idx, item.anchorView)
        }
    }
}

class SettingsWindowController: NSWindowController, NSTextFieldDelegate, NSSearchFieldDelegate, NSTextViewDelegate {

    private var updateStatusLabel: NSTextField!
    private var updateStatusIconView: NSImageView!
    private var updateStatusCard: NSStackView!
    private var updateCheckSpinner: NSProgressIndicator!
    private var updateCheckingLabel: NSTextField!
    private var checkNowButton: NSButton!
    private var installUpdateButton: NSButton!
    private var pendingDownloadURL: URL?
    private var tabContentViews: [NSView] = []
    private var sidebarController: SettingsSidebarController?
    private var sidebarSearchField: NSSearchField!
    private var contentScrollView: NSScrollView?
    private var currentContentView: NSView?
    private var settingsCategories: [SettingsCategory] = []
    private var sectionTitlePill: NSView!
    private var sectionTitlePillBlur: NSVisualEffectView!
    private var sectionTitlePillLabel: NSTextField!
    private var sectionTitlePillIcon: NSImageView!
    private static let sectionTitlePillHeight: CGFloat = 44
    private var speedDialTextFields: [Int: NSTextField] = [:]
    private var speedDialFieldsActivelyEditing: Set<Int> = []
    private var selectedCategoryIndex: Int = 0
    
    // MARK: - Release Notes (What's New)
    private weak var releaseNotesTextView: NSTextView?
    private var releaseNotesRawText: String = ""
    private var releaseNotesDetailsBlocks: [String: (summary: String, content: String)] = [:]
    private var releaseNotesOpenDetailsIDs: Set<String> = []

    // MARK: - Reminders Tab
    private var callRemindersSwitch: NSSwitch!
    private var detailReminderSwitch: NSSwitch!
    private var generalReminderSwitch: NSSwitch!
    private var keepReminderHistorySwitch: NSSwitch!

    // MARK: - Groups tab
    private var groupsEnableSwitch: NSSwitch!
    private var newGroupNameField: NSTextField!
    private var groupsListStack: NSStackView!
    private var groupsEmptyLabel: NSTextField!
    private var groupsErrorLabel: NSTextField!
    private var groupsManageContainer: NSStackView!

    // MARK: - Contacts Sync tab
    private var contactsSyncEnabledSwitch: NSSwitch!
    private var contactsAutoSyncSwitch: NSSwitch!
    private var contactsSyncNowButton: NSButton!
    private var contactsLastSyncLabel: NSTextField!
    private var contactsAutoSyncRow: NSStackView!
    private var contactsSyncStatusRow: NSStackView!

    // MARK: - Factory reset
    private var factoryResetButton: NSButton!
    private var factoryResetCountdownTimer: Timer?

    // MARK: - Accessibility tab
    private var a11ySwitches: [NSSwitch] = []
    private var a11yTextSizePopup: NSPopUpButton!
    private var a11yUIScalePopup: NSPopUpButton!
    private var themePopup: NSPopUpButton!
    private var timeZonePopup: NSPopUpButton!
    private var customTimeZonePopup: NSPopUpButton!
    private var customTimeZoneRow: NSStackView!
    private var sidebarBackgroundView: NSVisualEffectView?

    @objc private func applyAccessibilityToWholeSettingsWindow() {
        guard let window = window else { return }
        let a11y = AccessibilityManager.shared
        a11y.applyPreferredAppearance(to: window)
        
        if !window.a11yHasCapturedBackgroundColor {
            window.a11yBaseBackgroundColor = nil
            window.a11yHasCapturedBackgroundColor = true
        }

        if a11y.isGrayscaleEnabled && a11y.isEffectivelyColorInverted {
            window.backgroundColor = .white
        } else if a11y.isGrayscaleEnabled {
            window.backgroundColor = .black
        } else {
            window.backgroundColor = nil
        }
        
        sidebarBackgroundView?.needsDisplay = true
        window.contentView?.needsDisplay = true
        window.displayIfNeeded()

        DispatchQueue.main.async { [weak self] in
            self?.updateSectionTitlePillAppearance()
        }
        
        guard let contentView = window.contentView else { return }
        a11y.applyToViewTree(contentView)
    }

    private func updateSectionTitlePillAppearance() {
        guard let pill = sectionTitlePill else { return }
        let isLight = AccessibilityManager.shared.isEffectivelyColorInverted
        sectionTitlePillBlur?.material = isLight ? .popover : .hudWindow
        if isLight {
            pill.layer?.borderWidth = 1
            pill.layer?.borderColor = NSColor(white: 0, alpha: 0.12).cgColor
            pill.layer?.shadowColor = NSColor.black.cgColor
            pill.layer?.shadowOpacity = 0.12
            pill.layer?.shadowRadius = 6
            pill.layer?.shadowOffset = CGSize(width: 0, height: -1)
            sectionTitlePillLabel?.textColor = .black
        } else {
            pill.layer?.borderWidth = 1
            pill.layer?.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
            pill.layer?.shadowColor = NSColor.black.cgColor
            pill.layer?.shadowOpacity = 0.25
            pill.layer?.shadowRadius = 8
            pill.layer?.shadowOffset = CGSize(width: 0, height: -2)
            sectionTitlePillLabel?.textColor = .white
        }
    }

    private static let windowWidth: CGFloat = 780
    private static let windowHeight: CGFloat = 520 + SettingsWindowController.sectionTitlePillHeight + 14
    private static let sidebarWidth: CGFloat = 220
    
    private func createRow(with label: String, control: NSView) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        
        let lbl = NSTextField(labelWithString: label)
        lbl.font = NSFont.systemFont(ofSize: 13)
        row.addArrangedSubview(lbl)
        
        let leader = LeaderLine()
        leader.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(leader)
        
        row.addArrangedSubview(control)
        return row
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsWindowController.windowWidth, height: SettingsWindowController.windowHeight),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("settings_title")
        window.appearance = AccessibilityManager.shared.preferredWindowAppearance

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
        NotificationCenter.default.addObserver(self, selector: #selector(privacyModeChangedRefreshSpeedDial), name: .privacyModeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshContactsSyncUI), name: .contactsSyncSettingsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshCallRemindersUI), name: .remindersSettingsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyAccessibilityToWholeSettingsWindow), name: .accessibilitySettingsDidChange, object: nil)
        applyAccessibilityToWholeSettingsWindow()
    }

    deinit {
        factoryResetCountdownTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func privacyModeChangedRefreshSpeedDial() {
        let privacyOn = PrivacyMode.shared.isEnabled
        refreshGroupsListUI()
        for (i, tf) in speedDialTextFields {
            tf.isEditable = !privacyOn
            let savedValue = UserDefaults.standard.string(forKey: "SpeedDial_\(i)") ?? ""
            if let contact = ContactStore.shared.contacts.first(where: { $0.phone.sanitizedForCall == savedValue.sanitizedForCall && !savedValue.isEmpty }) {
                if privacyOn {
                    tf.stringValue = PrivacyMode.shared.maskedText(contact.fullName)
                    tf.toolTip = nil
                } else {
                    tf.stringValue = contact.fullName
                    tf.toolTip = contact.phone
                }
            } else {
                if privacyOn && !savedValue.isEmpty {
                    tf.stringValue = PrivacyMode.shared.maskedText(savedValue)
                    tf.toolTip = nil
                } else {
                    tf.stringValue = savedValue
                    tf.toolTip = savedValue.isEmpty ? nil : savedValue
                }
            }
        }
    }
    
    private func setupUI() {
        guard let window = self.window else { return }
        let rowWidth: CGFloat = 480
        
        // ==========================================
        // ΚΑΡΤΕΛΑ 1: ΕΝΗΜΕΡΩΣΕΙΣ
        // ==========================================
        let updatesView = NSView()
        
        let iconImageView = NSImageView(image: NSImage(named: "AppIcon") ?? NSImage())
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.widthAnchor.constraint(equalToConstant: 72).isActive = true
        iconImageView.heightAnchor.constraint(equalToConstant: 72).isActive = true
        
        let versionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0"
        let versionLabel = NSTextField(labelWithString: L("current_version", versionString))
        versionLabel.alignment = .center
        versionLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusIconView = NSImageView()
        statusIconView.translatesAutoresizingMaskIntoConstraints = false
        statusIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        self.updateStatusIconView = statusIconView

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.alignment = .left
        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping
        self.updateStatusLabel = statusLabel

        let statusCard = NSStackView(views: [statusIconView, statusLabel])
        statusCard.orientation = .horizontal
        statusCard.spacing = 7
        statusCard.alignment = .centerY
        statusCard.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        statusCard.translatesAutoresizingMaskIntoConstraints = false
        statusCard.wantsLayer = true
        statusCard.layer?.cornerRadius = 10
        statusCard.layer?.cornerCurve = .continuous
        statusCard.layer?.masksToBounds = true
        statusCard.layer?.backgroundColor = NSColor.clear.cgColor
        statusCard.isHidden = true
        statusCard.widthAnchor.constraint(lessThanOrEqualToConstant: rowWidth).isActive = true
        self.updateStatusCard = statusCard

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        self.updateCheckSpinner = spinner

        let checkingLabel = NSTextField(labelWithString: L("checking_for_updates"))
        checkingLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        checkingLabel.textColor = .secondaryLabelColor
        checkingLabel.translatesAutoresizingMaskIntoConstraints = false
        checkingLabel.isHidden = true
        self.updateCheckingLabel = checkingLabel

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

        let statusRow = NSStackView(views: [spinner, checkingLabel, statusCard])
        statusRow.orientation = .horizontal
        statusRow.spacing = 8
        statusRow.alignment = .centerY
        statusRow.translatesAutoresizingMaskIntoConstraints = false

        let updatesStack = NSStackView(views: [iconImageView, versionLabel, checkButton, statusRow, installButton])
        updatesStack.orientation = .vertical
        updatesStack.spacing = 14
        updatesStack.alignment = .centerX
        updatesStack.translatesAutoresizingMaskIntoConstraints = false
        updatesView.addSubview(updatesStack)
        
        NSLayoutConstraint.activate([
            updatesStack.centerXAnchor.constraint(equalTo: updatesView.centerXAnchor),
            updatesStack.topAnchor.constraint(equalTo: updatesView.topAnchor, constant: 28),
            updatesView.bottomAnchor.constraint(greaterThanOrEqualTo: updatesStack.bottomAnchor, constant: 28)
        ])
        
        // ==========================================
        // ΚΑΡΤΕΛΑ 2: ΕΜΦΑΝΙΣΗ
        // ==========================================
        let appearanceView = NSView()

        let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        themePopup.addItems(withTitles: [L("theme_dark"), L("theme_light"), L("theme_auto")])
        themePopup.selectItem(at: AccessibilityManager.shared.colorAdjustmentTheme.rawValue)
        themePopup.target = self
        themePopup.action = #selector(themeChanged(_:))
        self.themePopup = themePopup
        let themeRow = createRow(with: L("theme_picker_label"), control: themePopup)

        let timeZonePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        timeZonePopup.addItems(withTitles: TimeZoneOption.allCases.map { $0.localizedTitle })
        timeZonePopup.selectItem(at: TimeZoneOption.current.rawValue)
        timeZonePopup.target = self
        timeZonePopup.action = #selector(timeZoneOptionChanged(_:))
        self.timeZonePopup = timeZonePopup
        let timeZoneRow = createRow(with: L("timezone_picker_label"), control: timeZonePopup)

        let customTimeZonePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        let allTimeZoneIdentifiers = TimeZone.knownTimeZoneIdentifiers.sorted()
        customTimeZonePopup.addItems(withTitles: allTimeZoneIdentifiers)
        let savedIdentifier = UserDefaults.standard.string(forKey: TimeZoneOption.customIdentifierKey) ?? TimeZone.current.identifier
        if let idx = allTimeZoneIdentifiers.firstIndex(of: savedIdentifier) {
            customTimeZonePopup.selectItem(at: idx)
        }
        customTimeZonePopup.target = self
        customTimeZonePopup.action = #selector(customTimeZoneChanged(_:))
        self.customTimeZonePopup = customTimeZonePopup
        let customTimeZoneRow = createRow(with: L("timezone_custom_picker_label"), control: customTimeZonePopup)
        customTimeZoneRow.isHidden = TimeZoneOption.current != .custom
        self.customTimeZoneRow = customTimeZoneRow

        let themeSeparator = NSBox()
        themeSeparator.boxType = .separator
        themeSeparator.translatesAutoresizingMaskIntoConstraints = false

        let menuBarSwitch = NSSwitch()
        menuBarSwitch.target = self
        menuBarSwitch.action = #selector(toggleFeature(_:))
        menuBarSwitch.identifier = NSUserInterfaceItemIdentifier("showMenuBarIcon")
        menuBarSwitch.state = UserDefaults.standard.bool(forKey: "showMenuBarIcon") ? .on : .off
        let menuBarRow = createRow(with: L("show_menu_bar_icon"), control: menuBarSwitch)
        
        let favoritesSwitch = NSSwitch()
        favoritesSwitch.target = self
        favoritesSwitch.action = #selector(toggleFeature(_:))
        favoritesSwitch.identifier = NSUserInterfaceItemIdentifier("showFavoritesMenu")
        favoritesSwitch.state = UserDefaults.standard.bool(forKey: "hideFavoritesMenu") ? .off : .on
        let favoritesRow = createRow(with: L("show_favorites_tab"), control: favoritesSwitch)
        
        let contactsSwitch = NSSwitch()
        contactsSwitch.target = self
        contactsSwitch.action = #selector(toggleFeature(_:))
        contactsSwitch.identifier = NSUserInterfaceItemIdentifier("showContactsMenu")
        contactsSwitch.state = UserDefaults.standard.bool(forKey: "hideContactsMenu") ? .off : .on
        let contactsRow = createRow(with: L("show_contacts_tab"), control: contactsSwitch)

        let keypadSwitch = NSSwitch()
        keypadSwitch.target = self
        keypadSwitch.action = #selector(toggleFeature(_:))
        keypadSwitch.identifier = NSUserInterfaceItemIdentifier("showKeypadMenu")
        keypadSwitch.state = UserDefaults.standard.bool(forKey: "hideKeypadMenu") ? .off : .on
        let keypadRow = createRow(with: L("show_keypad_tab"), control: keypadSwitch)
        
        let plusSwitch = NSSwitch()
        plusSwitch.target = self
        plusSwitch.action = #selector(toggleFeature(_:))
        plusSwitch.identifier = NSUserInterfaceItemIdentifier("showPlusButton")
        plusSwitch.state = UserDefaults.standard.bool(forKey: "hidePlusButton") ? .off : .on
        let plusRow = createRow(with: L("show_plus_tab"), control: plusSwitch)
        
        let menuBarPlusSwitch = NSSwitch()
        menuBarPlusSwitch.target = self
        menuBarPlusSwitch.action = #selector(toggleFeature(_:))
        menuBarPlusSwitch.identifier = NSUserInterfaceItemIdentifier("showMenuBarPlusButton")
        menuBarPlusSwitch.state = UserDefaults.standard.bool(forKey: "hideMenuBarPlusButton") ? .off : .on
        let menuBarPlusRow = createRow(with: L("show_menu_bar_plus_tab"), control: menuBarPlusSwitch)

        let messagesSwitch = NSSwitch()
        messagesSwitch.target = self
        messagesSwitch.action = #selector(toggleFeature(_:))
        messagesSwitch.identifier = NSUserInterfaceItemIdentifier("showMessagesButton")
        messagesSwitch.state = UserDefaults.standard.bool(forKey: "hideMessagesButton") ? .off : .on
        let messagesRow = createRow(with: L("show_messages_tab"), control: messagesSwitch)

        let detailNotesSwitch = NSSwitch()
        detailNotesSwitch.target = self
        detailNotesSwitch.action = #selector(toggleFeature(_:))
        detailNotesSwitch.identifier = NSUserInterfaceItemIdentifier("showContactNotesInDetail")
        detailNotesSwitch.state = UserDefaults.standard.bool(forKey: "hideContactNotesInDetail") ? .off : .on
        let detailNotesRow = createRow(with: L("show_contact_notes_in_detail"), control: detailNotesSwitch)

        let servicesSeparator = NSBox()
        servicesSeparator.boxType = .separator
        servicesSeparator.translatesAutoresizingMaskIntoConstraints = false

        let servicesHintLabel = NSTextField(wrappingLabelWithString: L("contacts_services_hint"))
        servicesHintLabel.font = NSFont.systemFont(ofSize: 13)
        servicesHintLabel.translatesAutoresizingMaskIntoConstraints = false
        servicesHintLabel.preferredMaxLayoutWidth = rowWidth

        let openServicesSettingsBtn = NSButton(title: L("contacts_open_services_settings_btn"), target: self, action: #selector(openServicesKeyboardSettingsTapped))
        openServicesSettingsBtn.bezelStyle = .rounded
        openServicesSettingsBtn.font = NSFont.systemFont(ofSize: 13)

        let servicesRow = NSStackView(views: [servicesHintLabel, openServicesSettingsBtn])
        servicesRow.orientation = .vertical
        servicesRow.alignment = .leading
        servicesRow.spacing = 8

        let appearanceStack = NSStackView(views: [themeRow, timeZoneRow, customTimeZoneRow, themeSeparator, menuBarRow, favoritesRow, messagesRow, detailNotesRow, servicesSeparator, servicesRow])
        appearanceStack.orientation = .vertical
        appearanceStack.spacing = 14
        appearanceStack.translatesAutoresizingMaskIntoConstraints = false
        appearanceView.addSubview(appearanceStack)
        
        NSLayoutConstraint.activate([
            appearanceStack.centerXAnchor.constraint(equalTo: appearanceView.centerXAnchor),
            appearanceStack.topAnchor.constraint(equalTo: appearanceView.topAnchor, constant: 28),
            appearanceView.bottomAnchor.constraint(greaterThanOrEqualTo: appearanceStack.bottomAnchor, constant: 28),
            themeRow.widthAnchor.constraint(equalToConstant: rowWidth),
            timeZoneRow.widthAnchor.constraint(equalToConstant: rowWidth),
            customTimeZoneRow.widthAnchor.constraint(equalToConstant: rowWidth),
            themeSeparator.widthAnchor.constraint(equalToConstant: rowWidth),
            menuBarRow.widthAnchor.constraint(equalToConstant: rowWidth),
            favoritesRow.widthAnchor.constraint(equalToConstant: rowWidth),
            messagesRow.widthAnchor.constraint(equalToConstant: rowWidth),
            detailNotesRow.widthAnchor.constraint(equalToConstant: rowWidth),
            servicesSeparator.widthAnchor.constraint(equalToConstant: rowWidth),
            servicesRow.widthAnchor.constraint(equalToConstant: rowWidth)
        ])

        // ==========================================
        // ΝΕΑ ΕΝΟΤΗΤΑ: ΥΠΕΝΘΥΜΙΣΕΙΣ
        // ==========================================
        let remindersView = NSView()

        let remindersSwitch = NSSwitch()
        remindersSwitch.target = self
        remindersSwitch.action = #selector(toggleCallRemindersEnabled(_:))
        remindersSwitch.identifier = NSUserInterfaceItemIdentifier("enableCallReminders")
        remindersSwitch.state = ReminderManager.shared.isEnabled ? .on : .off
        callRemindersSwitch = remindersSwitch
        let remindersRow = createRow(with: L("enable_call_reminders_tab"), control: remindersSwitch)

        let detRemSwitch = NSSwitch()
        detRemSwitch.target = self
        detRemSwitch.action = #selector(toggleFeature(_:))
        detRemSwitch.identifier = NSUserInterfaceItemIdentifier("showDetailReminderButton")
        detRemSwitch.state = UserDefaults.standard.bool(forKey: "hideDetailReminderButton") ? .off : .on
        detRemSwitch.isEnabled = ReminderManager.shared.isEnabled
        detailReminderSwitch = detRemSwitch
        let detailRemRow = createRow(with: L("show_detail_reminder_btn"), control: detRemSwitch)

        let genRemSwitch = NSSwitch()
        genRemSwitch.target = self
        genRemSwitch.action = #selector(toggleFeature(_:))
        genRemSwitch.identifier = NSUserInterfaceItemIdentifier("showGeneralReminderButton")
        genRemSwitch.state = UserDefaults.standard.bool(forKey: "hideGeneralReminderButton") ? .off : .on
        genRemSwitch.isEnabled = ReminderManager.shared.isEnabled
        generalReminderSwitch = genRemSwitch
        let generalRemRow = createRow(with: L("show_general_reminder_btn"), control: genRemSwitch)

        let keepHistorySwitch = NSSwitch()
        keepHistorySwitch.target = self
        keepHistorySwitch.action = #selector(toggleKeepReminderHistory(_:))
        keepHistorySwitch.identifier = NSUserInterfaceItemIdentifier("keepReminderNotificationHistory")
        keepHistorySwitch.state = ReminderHistoryStore.shared.keepHistoryEnabled ? .on : .off
        keepHistorySwitch.isEnabled = ReminderManager.shared.isEnabled
        keepReminderHistorySwitch = keepHistorySwitch
        let keepHistoryRow = createRow(with: L("keep_reminder_history_tab"), control: keepHistorySwitch)

        let remindersStack = NSStackView(views: [remindersRow, detailRemRow, generalRemRow, keepHistoryRow])
        remindersStack.orientation = .vertical
        remindersStack.spacing = 14
        remindersStack.translatesAutoresizingMaskIntoConstraints = false
        remindersView.addSubview(remindersStack)

        NSLayoutConstraint.activate([
            remindersStack.centerXAnchor.constraint(equalTo: remindersView.centerXAnchor),
            remindersStack.topAnchor.constraint(equalTo: remindersView.topAnchor, constant: 28),
            remindersView.bottomAnchor.constraint(greaterThanOrEqualTo: remindersStack.bottomAnchor, constant: 28),
            remindersRow.widthAnchor.constraint(equalToConstant: rowWidth),
            detailRemRow.widthAnchor.constraint(equalToConstant: rowWidth),
            generalRemRow.widthAnchor.constraint(equalToConstant: rowWidth),
            keepHistoryRow.widthAnchor.constraint(equalToConstant: rowWidth)
        ])

        // ==========================================
        // ΕΝΟΤΗΤΑ: ΠΛΗΚΤΡΑ
        // ==========================================
        let buttonsView = NSView()

        let soundSeparator = NSBox()
        soundSeparator.boxType = .separator
        soundSeparator.translatesAutoresizingMaskIntoConstraints = false

        let appKeypadSoundSwitch = NSSwitch()
        appKeypadSoundSwitch.target = self
        appKeypadSoundSwitch.action = #selector(toggleKeypadSound(_:))
        appKeypadSoundSwitch.identifier = NSUserInterfaceItemIdentifier("playAppKeypadSound")
        appKeypadSoundSwitch.state = (UserDefaults.standard.object(forKey: "playAppKeypadSound") as? Bool ?? true) ? .on : .off
        let appKeypadSoundRow = createRow(with: L("play_app_keypad_sound"), control: appKeypadSoundSwitch)

        let menuBarKeypadSoundSwitch = NSSwitch()
        menuBarKeypadSoundSwitch.target = self
        menuBarKeypadSoundSwitch.action = #selector(toggleKeypadSound(_:))
        menuBarKeypadSoundSwitch.identifier = NSUserInterfaceItemIdentifier("playMenuBarKeypadSound")
        menuBarKeypadSoundSwitch.state = (UserDefaults.standard.object(forKey: "playMenuBarKeypadSound") as? Bool ?? true) ? .on : .off
        let menuBarKeypadSoundRow = createRow(with: L("play_menu_bar_keypad_sound"), control: menuBarKeypadSoundSwitch)

        let keyButtonsStack = NSStackView(views: [keypadRow, plusRow, menuBarPlusRow, soundSeparator, appKeypadSoundRow, menuBarKeypadSoundRow])
        keyButtonsStack.orientation = .vertical
        keyButtonsStack.spacing = 14
        keyButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        buttonsView.addSubview(keyButtonsStack)

        NSLayoutConstraint.activate([
            keyButtonsStack.centerXAnchor.constraint(equalTo: buttonsView.centerXAnchor),
            keyButtonsStack.topAnchor.constraint(equalTo: buttonsView.topAnchor, constant: 28),
            buttonsView.bottomAnchor.constraint(greaterThanOrEqualTo: keyButtonsStack.bottomAnchor, constant: 28),
            keypadRow.widthAnchor.constraint(equalToConstant: rowWidth),
            plusRow.widthAnchor.constraint(equalToConstant: rowWidth),
            menuBarPlusRow.widthAnchor.constraint(equalToConstant: rowWidth),
            soundSeparator.widthAnchor.constraint(equalToConstant: rowWidth),
            appKeypadSoundRow.widthAnchor.constraint(equalToConstant: rowWidth),
            menuBarKeypadSoundRow.widthAnchor.constraint(equalToConstant: rowWidth)
        ])
        
        // ==========================================
        // ΚΑΡΤΕΛΑ: ΟΜΑΔΕΣ ΕΠΑΦΩΝ
        // ==========================================
        let groupsView = NSView()

        let groupsEnableSwitch = NSSwitch()
        groupsEnableSwitch.target = self
        groupsEnableSwitch.action = #selector(toggleGroupsEnabled(_:))
        groupsEnableSwitch.identifier = NSUserInterfaceItemIdentifier("enableContactGroups")
        groupsEnableSwitch.state = ContactGroupStore.shared.isEnabled ? .on : .off
        self.groupsEnableSwitch = groupsEnableSwitch
        let groupsEnableRow = createRow(with: L("groups_enable_toggle"), control: groupsEnableSwitch)

        let groupsEnableDescLabel = NSTextField(labelWithString: L("groups_enable_desc"))
        groupsEnableDescLabel.font = NSFont.systemFont(ofSize: 11)
        groupsEnableDescLabel.textColor = .secondaryLabelColor
        groupsEnableDescLabel.lineBreakMode = .byWordWrapping
        groupsEnableDescLabel.maximumNumberOfLines = 2
        groupsEnableDescLabel.preferredMaxLayoutWidth = rowWidth
        groupsEnableDescLabel.translatesAutoresizingMaskIntoConstraints = false

        let groupsManageSeparator = NSBox()
        groupsManageSeparator.boxType = .separator
        groupsManageSeparator.translatesAutoresizingMaskIntoConstraints = false

        let groupsManageTitleLabel = NSTextField(labelWithString: L("groups_manage_title"))
        groupsManageTitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        groupsManageTitleLabel.textColor = .secondaryLabelColor
        groupsManageTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let groupNameField = NSTextField()
        groupNameField.placeholderString = L("groups_add_placeholder")
        groupNameField.cell?.usesSingleLineMode = true
        groupNameField.delegate = self
        groupNameField.identifier = NSUserInterfaceItemIdentifier("newGroupNameField")
        groupNameField.translatesAutoresizingMaskIntoConstraints = false
        self.newGroupNameField = groupNameField

        let addGroupButton = NSButton(title: L("groups_add_btn"), target: self, action: #selector(addGroupTapped))
        addGroupButton.bezelStyle = .rounded
        addGroupButton.translatesAutoresizingMaskIntoConstraints = false

        let addGroupRow = NSStackView(views: [groupNameField, addGroupButton])
        addGroupRow.orientation = .horizontal
        addGroupRow.spacing = 8
        addGroupRow.alignment = .centerY
        addGroupRow.translatesAutoresizingMaskIntoConstraints = false

        let groupsCharLimitLabel = NSTextField(labelWithString: L("groups_char_limit_hint"))
        groupsCharLimitLabel.font = NSFont.systemFont(ofSize: 10)
        groupsCharLimitLabel.textColor = .tertiaryLabelColor
        groupsCharLimitLabel.translatesAutoresizingMaskIntoConstraints = false

        let groupsErrorLabel = NSTextField(labelWithString: "")
        groupsErrorLabel.font = NSFont.systemFont(ofSize: 10)
        groupsErrorLabel.textColor = .systemRed
        groupsErrorLabel.isHidden = true
        groupsErrorLabel.translatesAutoresizingMaskIntoConstraints = false
        self.groupsErrorLabel = groupsErrorLabel

        let groupsListStack = NSStackView()
        groupsListStack.orientation = .vertical
        groupsListStack.spacing = 8
        groupsListStack.translatesAutoresizingMaskIntoConstraints = false
        self.groupsListStack = groupsListStack

        let groupsEmptyLabel = NSTextField(labelWithString: L("groups_empty"))
        groupsEmptyLabel.font = NSFont.systemFont(ofSize: 12)
        groupsEmptyLabel.textColor = .secondaryLabelColor
        groupsEmptyLabel.translatesAutoresizingMaskIntoConstraints = false
        self.groupsEmptyLabel = groupsEmptyLabel

        let groupsManageContainer = NSStackView(views: [groupsManageTitleLabel, addGroupRow, groupsCharLimitLabel, groupsErrorLabel, groupsEmptyLabel, groupsListStack])
        groupsManageContainer.orientation = .vertical
        groupsManageContainer.alignment = .leading
        groupsManageContainer.spacing = 8
        groupsManageContainer.translatesAutoresizingMaskIntoConstraints = false
        self.groupsManageContainer = groupsManageContainer

        let groupsStack = NSStackView(views: [groupsEnableRow, groupsEnableDescLabel, groupsManageSeparator, groupsManageContainer])
        groupsStack.orientation = .vertical
        groupsStack.alignment = .leading
        groupsStack.spacing = 14
        groupsStack.translatesAutoresizingMaskIntoConstraints = false
        groupsView.addSubview(groupsStack)

        NSLayoutConstraint.activate([
            groupsStack.centerXAnchor.constraint(equalTo: groupsView.centerXAnchor),
            groupsStack.topAnchor.constraint(equalTo: groupsView.topAnchor, constant: 28),
            groupsView.bottomAnchor.constraint(greaterThanOrEqualTo: groupsStack.bottomAnchor, constant: 28),
            groupsEnableRow.widthAnchor.constraint(equalToConstant: rowWidth),
            groupsEnableDescLabel.widthAnchor.constraint(equalToConstant: rowWidth),
            groupsManageSeparator.widthAnchor.constraint(equalToConstant: rowWidth),
            groupsManageContainer.widthAnchor.constraint(equalToConstant: rowWidth),
            addGroupRow.widthAnchor.constraint(equalToConstant: rowWidth),
            groupNameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])

        refreshGroupsListUI()
        refreshGroupsManageEnabledState()

        // ==========================================
        // ΚΑΡΤΕΛΑ: ΑΝΑΖΗΤΗΣΗ
        // ==========================================
        let searchView = NSView()

        let searchDescLabel = NSTextField(labelWithString: L("search_visibility_desc"))
        searchDescLabel.font = NSFont.systemFont(ofSize: 13)
        searchDescLabel.textColor = .secondaryLabelColor
        searchDescLabel.translatesAutoresizingMaskIntoConstraints = false
        
        func createSearchSwitchRow(title: String, defaultsKey: String) -> NSStackView {
            let toggle = NSSwitch()
            toggle.target = self
            toggle.action = #selector(toggleSearchFeature(_:))
            toggle.identifier = NSUserInterfaceItemIdentifier(defaultsKey)
            toggle.state = UserDefaults.standard.bool(forKey: defaultsKey) ? .off : .on
            return createRow(with: title, control: toggle)
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
            searchView.bottomAnchor.constraint(greaterThanOrEqualTo: searchStack.bottomAnchor, constant: 28),
            contactsSearchRow.widthAnchor.constraint(equalToConstant: rowWidth),
            favoritesSearchRow.widthAnchor.constraint(equalToConstant: rowWidth),
            historySearchRow.widthAnchor.constraint(equalToConstant: rowWidth)
        ])

        // ==========================================
        // ΚΑΡΤΕΛΑ: ΙΣΤΟΡΙΚΟ
        // ==========================================
        let historySettingsView = NSView()

        let historySwitch = NSSwitch()
        historySwitch.target = self
        historySwitch.action = #selector(toggleFeature(_:))
        historySwitch.identifier = NSUserInterfaceItemIdentifier("showHistoryMenu")
        historySwitch.state = UserDefaults.standard.bool(forKey: "hideHistoryMenu") ? .off : .on
        let historyRow = createRow(with: L("show_history_tab"), control: historySwitch)

        let historyAutoDeletePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        historyAutoDeletePopup.addItems(withTitles: HistoryAutoDeleteInterval.allCases.map { $0.localizedTitle })
        historyAutoDeletePopup.selectItem(at: HistoryAutoDeleteInterval.current.rawValue)
        historyAutoDeletePopup.target = self
        historyAutoDeletePopup.action = #selector(historyAutoDeleteChanged(_:))
        let historyAutoDeleteRow = createRow(with: L("history_autodelete_label"), control: historyAutoDeletePopup)

        let detailHistorySwitch = NSSwitch()
        detailHistorySwitch.target = self
        detailHistorySwitch.action = #selector(toggleFeature(_:))
        detailHistorySwitch.identifier = NSUserInterfaceItemIdentifier("showContactHistoryInDetail")
        detailHistorySwitch.state = UserDefaults.standard.bool(forKey: "hideContactHistoryInDetail") ? .off : .on
        let detailHistoryRow = createRow(with: L("show_contact_history_detail"), control: detailHistorySwitch)

        let historySettingsStack = NSStackView(views: [historyRow, historyAutoDeleteRow, detailHistoryRow])
        historySettingsStack.orientation = .vertical
        historySettingsStack.spacing = 14
        historySettingsStack.translatesAutoresizingMaskIntoConstraints = false
        historySettingsView.addSubview(historySettingsStack)

        NSLayoutConstraint.activate([
            historySettingsStack.centerXAnchor.constraint(equalTo: historySettingsView.centerXAnchor),
            historySettingsStack.topAnchor.constraint(equalTo: historySettingsView.topAnchor, constant: 28),
            historySettingsView.bottomAnchor.constraint(greaterThanOrEqualTo: historySettingsStack.bottomAnchor, constant: 28),
            historyRow.widthAnchor.constraint(equalToConstant: rowWidth),
            historyAutoDeleteRow.widthAnchor.constraint(equalToConstant: rowWidth),
            detailHistoryRow.widthAnchor.constraint(equalToConstant: rowWidth)
        ])

        // ==========================================
        // ΚΑΡΤΕΛΑ: ΤΑΧΕΙΑ ΚΛΗΣΗ
        // ==========================================
        let speedDialView = NSView()
        
        let introText = L("settings_speeddial_intro")
        let sdIntroLabel = NSTextField(wrappingLabelWithString: introText)
        sdIntroLabel.font = NSFont.systemFont(ofSize: 12)
        sdIntroLabel.textColor = .secondaryLabelColor
        sdIntroLabel.alignment = .center
        sdIntroLabel.translatesAutoresizingMaskIntoConstraints = false
        sdIntroLabel.preferredMaxLayoutWidth = rowWidth
        
        let enableSDSwitch = NSSwitch()
        enableSDSwitch.target = self
        enableSDSwitch.action = #selector(toggleFeature(_:))
        enableSDSwitch.identifier = NSUserInterfaceItemIdentifier("enableSpeedDial")
        enableSDSwitch.state = UserDefaults.standard.bool(forKey: "enableSpeedDial") ? .on : .off
        let enableSDRow = createRow(with: L("enable_speed_dial"), control: enableSDSwitch)
        
        let sdGridStack = NSStackView()
        sdGridStack.orientation = .vertical
        sdGridStack.spacing = 10
        sdGridStack.translatesAutoresizingMaskIntoConstraints = false
        
        for i in 1...9 {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false
            
            let label = NSTextField(labelWithString: "\(i):")
            label.font = NSFont.systemFont(ofSize: 14)
            label.alignment = .right
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 20).isActive = true
            row.addArrangedSubview(label)
            
            let tf = NSTextField()
            tf.cell?.usesSingleLineMode = true
            tf.placeholderString = L("phone_placeholder")
            let savedValue = UserDefaults.standard.string(forKey: "SpeedDial_\(i)") ?? ""
            if let contact = ContactStore.shared.contacts.first(where: { $0.phone.sanitizedForCall == savedValue.sanitizedForCall && !savedValue.isEmpty }) {
                if PrivacyMode.shared.isEnabled {
                    tf.stringValue = PrivacyMode.shared.maskedText(contact.fullName)
                    tf.toolTip = nil
                } else {
                    tf.stringValue = contact.fullName
                    tf.toolTip = contact.phone
                }
            } else {
                if PrivacyMode.shared.isEnabled && !savedValue.isEmpty {
                    tf.stringValue = PrivacyMode.shared.maskedText(savedValue)
                    tf.toolTip = nil
                } else {
                    tf.stringValue = savedValue
                    tf.toolTip = savedValue.isEmpty ? nil : savedValue
                }
            }
            tf.tag = i
            tf.delegate = self
            tf.isEditable = !PrivacyMode.shared.isEnabled
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.widthAnchor.constraint(equalToConstant: 220).isActive = true 
            speedDialTextFields[i] = tf 
            row.addArrangedSubview(tf)
            
            let pickBtn = NSButton(image: NSImage(systemSymbolName: "person.crop.circle.badge.plus", accessibilityDescription: nil) ?? NSImage(), target: self, action: #selector(showContactPicker(_:)))
            pickBtn.bezelStyle = .regularSquare
            pickBtn.isBordered = false
            pickBtn.tag = i
            pickBtn.contentTintColor = NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
            pickBtn.translatesAutoresizingMaskIntoConstraints = false
            if let cell = pickBtn.cell as? NSButtonCell { cell.imageScaling = .scaleProportionallyUpOrDown }
            pickBtn.widthAnchor.constraint(equalToConstant: 22).isActive = true
            pickBtn.heightAnchor.constraint(equalToConstant: 22).isActive = true
            row.addArrangedSubview(pickBtn)
            
            sdGridStack.addArrangedSubview(row)
        }
        
        let sdMainStack = NSStackView(views: [sdIntroLabel, enableSDRow, sdGridStack])
        sdMainStack.orientation = .vertical
        sdMainStack.alignment = .centerX
        sdMainStack.spacing = 16
        sdMainStack.translatesAutoresizingMaskIntoConstraints = false
        speedDialView.addSubview(sdMainStack)

        NSLayoutConstraint.activate([
            sdMainStack.topAnchor.constraint(equalTo: speedDialView.topAnchor, constant: 28),
            sdMainStack.centerXAnchor.constraint(equalTo: speedDialView.centerXAnchor),
            sdMainStack.widthAnchor.constraint(equalToConstant: rowWidth),
            enableSDRow.widthAnchor.constraint(equalToConstant: rowWidth),
            sdGridStack.widthAnchor.constraint(equalToConstant: rowWidth),
            speedDialView.bottomAnchor.constraint(greaterThanOrEqualTo: sdMainStack.bottomAnchor, constant: 28)
        ])

        // ==========================================
        // ΚΑΡΤΕΛΑ: ΕΠΑΦΕΣ (Συγχρονισμός iCloud)
        // ==========================================
        let contactsSyncView = NSView()

        let contactsSyncIntroLabel = NSTextField(wrappingLabelWithString: L("contacts_sync_settings_intro"))
        contactsSyncIntroLabel.font = NSFont.systemFont(ofSize: 12)
        contactsSyncIntroLabel.textColor = .secondaryLabelColor
        contactsSyncIntroLabel.alignment = .center
        contactsSyncIntroLabel.translatesAutoresizingMaskIntoConstraints = false
        contactsSyncIntroLabel.preferredMaxLayoutWidth = rowWidth
        contactsSyncView.addSubview(contactsSyncIntroLabel)

        let contactsMenuSeparator = NSBox()
        contactsMenuSeparator.boxType = .separator
        contactsMenuSeparator.translatesAutoresizingMaskIntoConstraints = false

        let syncEnableSwitch = NSSwitch()
        syncEnableSwitch.target = self
        syncEnableSwitch.action = #selector(toggleContactsSyncEnabled(_:))
        syncEnableSwitch.state = ContactsSyncManager.shared.isFeatureEnabled ? .on : .off
        contactsSyncEnabledSwitch = syncEnableSwitch
        let syncEnableRow = createRow(with: L("contacts_sync_enable_toggle"), control: syncEnableSwitch)

        let autoSyncSwitch = NSSwitch()
        autoSyncSwitch.target = self
        autoSyncSwitch.action = #selector(toggleContactsAutoSync(_:))
        autoSyncSwitch.state = ContactsSyncManager.shared.isAutoSyncEnabled ? .on : .off
        contactsAutoSyncSwitch = autoSyncSwitch
        let autoSyncRow = createRow(with: L("contacts_sync_auto_toggle"), control: autoSyncSwitch)
        contactsAutoSyncRow = autoSyncRow

        let autoSyncHintLabel = NSTextField(wrappingLabelWithString: L("contacts_sync_auto_hint"))
        autoSyncHintLabel.font = NSFont.systemFont(ofSize: 11)
        autoSyncHintLabel.textColor = .tertiaryLabelColor
        autoSyncHintLabel.translatesAutoresizingMaskIntoConstraints = false
        autoSyncHintLabel.preferredMaxLayoutWidth = rowWidth

        let syncStatusRow = NSStackView()
        syncStatusRow.orientation = .vertical
        syncStatusRow.alignment = .leading
        syncStatusRow.spacing = 8
        let lastSyncLabel = NSTextField(wrappingLabelWithString: "")
        lastSyncLabel.font = NSFont.systemFont(ofSize: 12)
        lastSyncLabel.textColor = .secondaryLabelColor
        lastSyncLabel.lineBreakMode = .byWordWrapping
        lastSyncLabel.preferredMaxLayoutWidth = rowWidth
        contactsLastSyncLabel = lastSyncLabel
        syncStatusRow.addView(lastSyncLabel, in: .leading)

        let syncNowBtn = NSButton(title: L("contacts_sync_now_btn"), target: self, action: #selector(syncContactsNowTapped))
        syncNowBtn.bezelStyle = .rounded
        syncStatusRow.addView(syncNowBtn, in: .leading)
        contactsSyncNowButton = syncNowBtn
        contactsSyncStatusRow = syncStatusRow

        let syncToggleStack = NSStackView(views: [contactsRow, contactsMenuSeparator, syncEnableRow, autoSyncRow, autoSyncHintLabel, syncStatusRow])
        syncToggleStack.orientation = .vertical
        syncToggleStack.spacing = 14
        syncToggleStack.alignment = .leading
        syncToggleStack.translatesAutoresizingMaskIntoConstraints = false
        contactsSyncView.addSubview(syncToggleStack)

        NSLayoutConstraint.activate([
            contactsSyncIntroLabel.topAnchor.constraint(equalTo: contactsSyncView.topAnchor, constant: 28),
            contactsSyncIntroLabel.centerXAnchor.constraint(equalTo: contactsSyncView.centerXAnchor),
            contactsSyncIntroLabel.widthAnchor.constraint(equalToConstant: rowWidth),

            syncToggleStack.topAnchor.constraint(equalTo: contactsSyncIntroLabel.bottomAnchor, constant: 24),
            syncToggleStack.centerXAnchor.constraint(equalTo: contactsSyncView.centerXAnchor),
            contactsSyncView.bottomAnchor.constraint(greaterThanOrEqualTo: syncToggleStack.bottomAnchor, constant: 28),

            syncEnableRow.widthAnchor.constraint(equalToConstant: rowWidth),
            autoSyncRow.widthAnchor.constraint(equalToConstant: rowWidth),
            autoSyncHintLabel.widthAnchor.constraint(equalToConstant: rowWidth),
            syncStatusRow.widthAnchor.constraint(equalToConstant: rowWidth),
            contactsRow.widthAnchor.constraint(equalToConstant: rowWidth),
            contactsMenuSeparator.widthAnchor.constraint(equalToConstant: rowWidth)
        ])

        // ==========================================
        // ΚΑΡΤΕΛΑ: ΔΕΔΟΜΕΝΑ
        // ==========================================
        let dataView = NSView()
        
        let dataManagementLabel = NSTextField(labelWithString: L("import_export_title"))
        dataManagementLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        dataManagementLabel.textColor = .labelColor
        
        let importBtn = NSButton(title: L("import_contacts"), target: NSApp.delegate, action: Selector(("importContacts")))
        importBtn.bezelStyle = .rounded
        let exportBtn = NSButton(title: L("export_contacts"), target: NSApp.delegate, action: Selector(("exportContacts")))
        exportBtn.bezelStyle = .rounded
        let dataStack = NSStackView(views: [importBtn, exportBtn])
        dataStack.orientation = .horizontal
        dataStack.spacing = 10
        
        let backupLabel = NSTextField(labelWithString: L("backup_title"))
        backupLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        backupLabel.textColor = .labelColor

        let importBackupBtn = NSButton(title: L("import_backup"), target: NSApp.delegate, action: Selector(("importBackup")))
        importBackupBtn.bezelStyle = .rounded
        let exportBackupBtn = NSButton(title: L("export_backup"), target: NSApp.delegate, action: Selector(("exportBackup")))
        exportBackupBtn.bezelStyle = .rounded
        let backupStack = NSStackView(views: [importBackupBtn, exportBackupBtn])
        backupStack.orientation = .horizontal
        backupStack.spacing = 10
        
        let helpBtn = NSButton(title: "", target: NSApp.delegate, action: Selector(("showBackupHelp")))
        helpBtn.bezelStyle = .helpButton

        let resetLabel = NSTextField(labelWithString: L("factory_reset_title"))
        resetLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        resetLabel.textColor = .labelColor

        let resetHintLabel = NSTextField(wrappingLabelWithString: L("factory_reset_hint"))
        resetHintLabel.font = NSFont.systemFont(ofSize: 11)
        resetHintLabel.textColor = .secondaryLabelColor
        resetHintLabel.alignment = .center
        resetHintLabel.preferredMaxLayoutWidth = rowWidth

        let resetBtn = NSButton(title: L("factory_reset_btn"), target: self, action: #selector(factoryResetFirstConfirmTapped))
        resetBtn.bezelStyle = .rounded
        resetBtn.contentTintColor = .systemRed
        factoryResetButton = resetBtn
        
        let dataStackView = NSStackView(views: [dataManagementLabel, dataStack, backupLabel, backupStack, helpBtn, resetLabel, resetHintLabel, resetBtn])
        dataStackView.orientation = .vertical
        dataStackView.alignment = .centerX
        dataStackView.spacing = 16
        dataStackView.setCustomSpacing(32, after: dataStack)
        dataStackView.setCustomSpacing(32, after: backupStack)
        dataStackView.setCustomSpacing(40, after: helpBtn)
        dataStackView.setCustomSpacing(8, after: resetLabel)
        dataStackView.translatesAutoresizingMaskIntoConstraints = false
        dataView.addSubview(dataStackView)

        NSLayoutConstraint.activate([
            dataStackView.topAnchor.constraint(equalTo: dataView.topAnchor, constant: 32),
            dataStackView.centerXAnchor.constraint(equalTo: dataView.centerXAnchor),
            dataView.bottomAnchor.constraint(greaterThanOrEqualTo: dataStackView.bottomAnchor, constant: 32),
            dataStackView.widthAnchor.constraint(equalToConstant: rowWidth)
        ])

        // ==========================================
        // ΚΑΡΤΕΛΑ: ΠΛΗΡΟΦΟΡΙΕΣ
        // ==========================================
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

        let appTaglineLabel = NSTextField(labelWithString: L("app_tagline"))
        appTaglineLabel.font = NSFont.systemFont(ofSize: 12)
        appTaglineLabel.textColor = .secondaryLabelColor
        appTaglineLabel.lineBreakMode = .byTruncatingTail

        let titleStack = NSStackView(views: [appNameLabel, appTaglineLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2

        let headerRow = NSStackView(views: [infoIconView, titleStack])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 12

        let descriptionLabel = NSTextField(wrappingLabelWithString: L("app_description"))
        descriptionLabel.font = NSFont.systemFont(ofSize: 13)
        descriptionLabel.textColor = .labelColor
        descriptionLabel.preferredMaxLayoutWidth = rowWidth

        let shortcutLabel = NSTextField(labelWithString: L("app_shortcut_label"))
        shortcutLabel.font = NSFont.systemFont(ofSize: 12)
        shortcutLabel.textColor = .secondaryLabelColor

        let websiteLabel = ClickableLabel(labelWithString: L("app_website_label"))
        websiteLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        websiteLabel.textColor = NSColor.linkColor
        websiteLabel.isLinkActive = true
        let websiteClick = NSClickGestureRecognizer(target: self, action: #selector(openAppWebsite))
        websiteLabel.addGestureRecognizer(websiteClick)

        let githubLabel = ClickableLabel(labelWithString: L("app_github_label"))
        githubLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        githubLabel.textColor = NSColor.linkColor
        githubLabel.isLinkActive = true
        let githubClick = NSClickGestureRecognizer(target: self, action: #selector(openAppGitHub))
        githubLabel.addGestureRecognizer(githubClick)

        let infoVersionLabel = NSTextField(labelWithString: L("current_version", versionString))
        infoVersionLabel.font = NSFont.systemFont(ofSize: 12)
        infoVersionLabel.textColor = .secondaryLabelColor
        
        let infoMainStack = NSStackView(views: [headerRow, descriptionLabel, shortcutLabel, websiteLabel, githubLabel, infoVersionLabel])
        infoMainStack.orientation = .vertical
        infoMainStack.alignment = .leading
        infoMainStack.spacing = 16
        infoMainStack.setCustomSpacing(24, after: headerRow)
        infoMainStack.setCustomSpacing(24, after: shortcutLabel)
        infoMainStack.setCustomSpacing(8, after: websiteLabel)
        infoMainStack.setCustomSpacing(24, after: githubLabel)
        
        infoMainStack.translatesAutoresizingMaskIntoConstraints = false
        infoView.addSubview(infoMainStack)

        NSLayoutConstraint.activate([
            infoMainStack.topAnchor.constraint(equalTo: infoView.topAnchor, constant: 32),
            infoMainStack.centerXAnchor.constraint(equalTo: infoView.centerXAnchor),
            infoView.bottomAnchor.constraint(greaterThanOrEqualTo: infoMainStack.bottomAnchor, constant: 32),
            infoMainStack.widthAnchor.constraint(equalToConstant: rowWidth)
        ])

        // ==========================================
        // ΚΑΡΤΕΛΑ: ΤΙ ΝΕΟ ΥΠΑΡΧΕΙ (Release Notes)
        // ==========================================
        let releaseNotesView = NSView()

        let rnIconView = NSImageView(image: NSImage(named: "AppIcon") ?? NSImage())
        rnIconView.imageScaling = .scaleProportionallyUpOrDown
        rnIconView.translatesAutoresizingMaskIntoConstraints = false
        rnIconView.widthAnchor.constraint(equalToConstant: 48).isActive = true
        rnIconView.heightAnchor.constraint(equalToConstant: 48).isActive = true
        rnIconView.setContentHuggingPriority(.required, for: .horizontal)

        let rnNameLabel = NSTextField(labelWithString: "HelloMac")
        rnNameLabel.font = NSFont.boldSystemFont(ofSize: 18)
        rnNameLabel.textColor = .white
        rnNameLabel.lineBreakMode = .byTruncatingTail

        let rnVersionLabel = NSTextField(labelWithString: L("current_version", versionString))
        rnVersionLabel.font = NSFont.systemFont(ofSize: 12)
        rnVersionLabel.textColor = .secondaryLabelColor

        let rnTitleStack = NSStackView(views: [rnNameLabel, rnVersionLabel])
        rnTitleStack.orientation = .vertical
        rnTitleStack.alignment = .leading
        rnTitleStack.spacing = 2

        let rnHeaderRow = NSStackView(views: [rnIconView, rnTitleStack])
        rnHeaderRow.orientation = .horizontal
        rnHeaderRow.alignment = .centerY
        rnHeaderRow.spacing = 12
        rnHeaderRow.translatesAutoresizingMaskIntoConstraints = false

        let rnOpenButton = NSButton()
        let openConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        rnOpenButton.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)?.withSymbolConfiguration(openConfig)
        rnOpenButton.bezelStyle = .regularSquare
        rnOpenButton.isBordered = false
        rnOpenButton.contentTintColor = .linkColor
        rnOpenButton.target = self
        rnOpenButton.action = #selector(openReleasesOnGitHub)
        rnOpenButton.toolTip = L("settings_view_on_github")
        rnOpenButton.translatesAutoresizingMaskIntoConstraints = false

        let rnScrollView = NSTextView.scrollableTextView()
        rnScrollView.hasVerticalScroller = true
        rnScrollView.hasHorizontalScroller = false 
        rnScrollView.autohidesScrollers = true
        rnScrollView.borderType = .noBorder
        rnScrollView.drawsBackground = true
        rnScrollView.backgroundColor = NSColor(white: 1, alpha: 0.04)
        rnScrollView.wantsLayer = true
        rnScrollView.layer?.cornerRadius = 8
        rnScrollView.translatesAutoresizingMaskIntoConstraints = false

        let rnTextView = rnScrollView.documentView as! NSTextView
        rnTextView.isEditable = false
        rnTextView.isSelectable = true
        rnTextView.drawsBackground = false
        rnTextView.isRichText = true
        rnTextView.textContainerInset = NSSize(width: 12, height: 12)
        rnTextView.delegate = self
        rnTextView.linkTextAttributes = [:]
        rnTextView.wantsLayer = true
        releaseNotesTextView = rnTextView
        
        rnTextView.minSize = NSSize(width: 0, height: 0)
        rnTextView.maxSize = NSSize(width: rowWidth, height: .greatestFiniteMagnitude)
        rnTextView.isVerticallyResizable = true
        rnTextView.isHorizontallyResizable = false
        rnTextView.autoresizingMask = [.width]
        rnTextView.textContainer?.containerSize = NSSize(width: rowWidth, height: .greatestFiniteMagnitude)
        rnTextView.textContainer?.widthTracksTextView = true
        
        rnTextView.string = L("settings_loading_release_notes")

        releaseNotesView.addSubview(rnHeaderRow)
        releaseNotesView.addSubview(rnOpenButton)
        releaseNotesView.addSubview(rnScrollView)

        NSLayoutConstraint.activate([
            rnHeaderRow.topAnchor.constraint(equalTo: releaseNotesView.topAnchor, constant: 28),
            rnHeaderRow.leadingAnchor.constraint(equalTo: releaseNotesView.leadingAnchor, constant: 30),
            
            rnOpenButton.centerYAnchor.constraint(equalTo: rnHeaderRow.centerYAnchor),
            rnOpenButton.trailingAnchor.constraint(equalTo: rnScrollView.trailingAnchor),
            
            rnScrollView.topAnchor.constraint(equalTo: rnHeaderRow.bottomAnchor, constant: 16),
            rnScrollView.centerXAnchor.constraint(equalTo: releaseNotesView.centerXAnchor),
            rnScrollView.widthAnchor.constraint(equalToConstant: rowWidth),
            rnScrollView.heightAnchor.constraint(equalToConstant: 380),
            releaseNotesView.bottomAnchor.constraint(greaterThanOrEqualTo: rnScrollView.bottomAnchor, constant: 28)
        ])

        fetchReleaseNotes { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let localizedText = self.extractLocalizedReleaseNotes(text, isGreek: self.isGreek)
                self.releaseNotesRawText = localizedText
                self.releaseNotesOpenDetailsIDs.removeAll()
                self.releaseNotesDetailsBlocks.removeAll()
                self.renderReleaseNotes()
            }
        }

        // ==========================================
        // ΚΑΡΤΕΛΑ: ΠΡΟΣΒΑΣΙΜΟΤΗΤΑ (ACCESSIBILITY)
        // ==========================================
        let accessibilityView = NSView()

        let a11yIntroLabel = NSTextField(wrappingLabelWithString: L("accessibility_intro"))
        a11yIntroLabel.font = NSFont.systemFont(ofSize: 12)
        a11yIntroLabel.textColor = .secondaryLabelColor
        a11yIntroLabel.translatesAutoresizingMaskIntoConstraints = false
        a11yIntroLabel.preferredMaxLayoutWidth = rowWidth

        func a11ySectionHeader(_ title: String) -> NSTextField {
            let lbl = NSTextField(labelWithString: title)
            lbl.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            lbl.textColor = .secondaryLabelColor
            lbl.translatesAutoresizingMaskIntoConstraints = false
            return lbl
        }

        func a11ySwitchRow(title: String, desc: String, key: String, defaultOn: Bool = false, action: Selector) -> (row: NSStackView, switchControl: NSSwitch) {
            let toggle = NSSwitch()
            toggle.target = self
            toggle.action = action
            toggle.identifier = NSUserInterfaceItemIdentifier(key)
            toggle.state = UserDefaults.standard.bool(forKey: key) ? .on : .off

            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.font = NSFont.systemFont(ofSize: 13)
            titleLabel.translatesAutoresizingMaskIntoConstraints = false

            let descLabel = NSTextField(wrappingLabelWithString: desc)
            descLabel.font = NSFont.systemFont(ofSize: 11)
            descLabel.textColor = .secondaryLabelColor
            descLabel.translatesAutoresizingMaskIntoConstraints = false
            descLabel.preferredMaxLayoutWidth = rowWidth - 60

            let textStack = NSStackView(views: [titleLabel, descLabel])
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.spacing = 2
            textStack.translatesAutoresizingMaskIntoConstraints = false
            textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let leader = LeaderLine()
            leader.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let row = NSStackView(views: [textStack, leader, toggle])
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 12
            row.translatesAutoresizingMaskIntoConstraints = false

            return (row, toggle)
        }

        func a11yPopupRow(title: String, desc: String, control: NSPopUpButton) -> NSStackView {
            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.font = NSFont.systemFont(ofSize: 13)
            titleLabel.translatesAutoresizingMaskIntoConstraints = false

            let descLabel = NSTextField(wrappingLabelWithString: desc)
            descLabel.font = NSFont.systemFont(ofSize: 11)
            descLabel.textColor = .secondaryLabelColor
            descLabel.translatesAutoresizingMaskIntoConstraints = false
            descLabel.preferredMaxLayoutWidth = rowWidth - 60

            let textStack = NSStackView(views: [titleLabel, descLabel])
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.spacing = 2
            textStack.translatesAutoresizingMaskIntoConstraints = false
            textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let leader = LeaderLine()
            leader.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let row = NSStackView(views: [textStack, leader, control])
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 12
            row.translatesAutoresizingMaskIntoConstraints = false

            return row
        }

        let a11yDisplaySection = a11ySectionHeader(L("a11y_section_display"))
        let (highContrastRow, highContrastSwitch) = a11ySwitchRow(
            title: L("a11y_high_contrast"), desc: L("a11y_high_contrast_desc"),
            key: "a11yHighContrast", action: #selector(toggleAccessibilityFeature(_:)))
        let (grayscaleRow, grayscaleSwitch) = a11ySwitchRow(
            title: L("a11y_grayscale"), desc: L("a11y_grayscale_desc"),
            key: "a11yGrayscale", action: #selector(toggleAccessibilityFeature(_:)))
        self.a11ySwitches.append(contentsOf: [highContrastSwitch, grayscaleSwitch])

        let a11yDisplaySeparator = NSBox()
        a11yDisplaySeparator.boxType = .separator
        a11yDisplaySeparator.translatesAutoresizingMaskIntoConstraints = false

        let a11yTextSection = a11ySectionHeader(L("a11y_section_text"))
        let textSizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        textSizePopup.addItems(withTitles: [
            L("text_size_off"), L("text_size_step2"),
            L("text_size_step3"), L("text_size_largest")
        ])
        let currentStep = AccessibilityManager.shared.textSizeStep
        textSizePopup.selectItem(at: AccessibilityManager.shared.isIncreaseTextSizeEnabled
            ? max(1, currentStep - 1) : 0)
        textSizePopup.target = self
        textSizePopup.action = #selector(textSizeStepChanged(_:))
        self.a11yTextSizePopup = textSizePopup
        let textSizeRow = a11yPopupRow(
            title: L("a11y_increase_text_size"), desc: L("a11y_increase_text_size_desc"),
            control: textSizePopup)

        let (boldTextRow, boldTextSwitch) = a11ySwitchRow(
            title: L("a11y_bold_text"), desc: L("a11y_bold_text_desc"),
            key: "a11yBoldText", action: #selector(toggleAccessibilityFeature(_:)))
        self.a11ySwitches.append(boldTextSwitch)

        let a11yTextSeparator = NSBox()
        a11yTextSeparator.boxType = .separator
        a11yTextSeparator.translatesAutoresizingMaskIntoConstraints = false

        let a11yInterfaceSection = a11ySectionHeader(L("a11y_section_interface"))
        let uiScalePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        uiScalePopup.addItems(withTitles: [L("percent_100"), L("percent_110"), L("percent_120"), L("percent_130")])
        uiScalePopup.selectItem(at: AccessibilityManager.shared.uiScaleStep)
        uiScalePopup.target = self
        uiScalePopup.action = #selector(uiScaleStepChanged(_:))
        self.a11yUIScalePopup = uiScalePopup
        let uiScaleRow = createRow(with: L("a11y_ui_scale_label"), control: uiScalePopup)

        let (largerHitTargetsRow, largerHitTargetsSwitch) = a11ySwitchRow(
            title: L("a11y_larger_hit_targets"), desc: L("a11y_larger_hit_targets_desc"),
            key: "a11yLargerHitTargets", action: #selector(toggleAccessibilityFeature(_:)))
        self.a11ySwitches.append(largerHitTargetsSwitch)

        let a11yInterfaceSeparator = NSBox()
        a11yInterfaceSeparator.boxType = .separator
        a11yInterfaceSeparator.translatesAutoresizingMaskIntoConstraints = false

        let a11yResetBtn = NSButton(title: L("a11y_reset_btn"), target: self, action: #selector(resetAccessibilityTapped))
        a11yResetBtn.bezelStyle = .rounded
        a11yResetBtn.contentTintColor = .systemRed

        let a11yRestartHintLabel = NSTextField(wrappingLabelWithString: L("a11y_restart_hint"))
        a11yRestartHintLabel.font = NSFont.systemFont(ofSize: 11)
        a11yRestartHintLabel.textColor = .tertiaryLabelColor
        a11yRestartHintLabel.alignment = .center
        a11yRestartHintLabel.preferredMaxLayoutWidth = rowWidth

        let accessibilityStack = NSStackView(views: [
            a11yIntroLabel,
            a11yDisplaySection, highContrastRow, grayscaleRow,
            a11yDisplaySeparator,
            a11yTextSection, textSizeRow, boldTextRow,
            a11yTextSeparator,
            a11yInterfaceSection, uiScaleRow, largerHitTargetsRow,
            a11yInterfaceSeparator,
            a11yResetBtn, a11yRestartHintLabel
        ])
        accessibilityStack.orientation = .vertical
        accessibilityStack.alignment = .leading
        accessibilityStack.spacing = 12
        accessibilityStack.setCustomSpacing(18, after: a11yIntroLabel)
        accessibilityStack.setCustomSpacing(18, after: a11yDisplaySeparator)
        accessibilityStack.setCustomSpacing(18, after: a11yTextSeparator)
        accessibilityStack.setCustomSpacing(18, after: a11yInterfaceSeparator)
        accessibilityStack.setCustomSpacing(10, after: a11yResetBtn)
        accessibilityStack.translatesAutoresizingMaskIntoConstraints = false
        accessibilityView.addSubview(accessibilityStack)

        NSLayoutConstraint.activate([
            accessibilityStack.topAnchor.constraint(equalTo: accessibilityView.topAnchor, constant: 28),
            accessibilityStack.centerXAnchor.constraint(equalTo: accessibilityView.centerXAnchor),
            accessibilityView.bottomAnchor.constraint(greaterThanOrEqualTo: accessibilityStack.bottomAnchor, constant: 28),
            a11yIntroLabel.widthAnchor.constraint(equalToConstant: rowWidth),
            highContrastRow.widthAnchor.constraint(equalToConstant: rowWidth),
            grayscaleRow.widthAnchor.constraint(equalToConstant: rowWidth),
            a11yDisplaySeparator.widthAnchor.constraint(equalToConstant: rowWidth),
            textSizeRow.widthAnchor.constraint(equalToConstant: rowWidth),
            boldTextRow.widthAnchor.constraint(equalToConstant: rowWidth),
            a11yTextSeparator.widthAnchor.constraint(equalToConstant: rowWidth),
            uiScaleRow.widthAnchor.constraint(equalToConstant: rowWidth),
            largerHitTargetsRow.widthAnchor.constraint(equalToConstant: rowWidth),
            a11yInterfaceSeparator.widthAnchor.constraint(equalToConstant: rowWidth),
            a11yRestartHintLabel.widthAnchor.constraint(equalToConstant: rowWidth),
        ])

        // ==========================================
        // Συναρμολόγηση
        // ==========================================
        let categories: [SettingsCategory] = [
            SettingsCategory(
                title: L("tab_updates"), symbolName: "arrow.triangle.2.circlepath", tintColor: NSColor.systemGray, view: updatesView,
                searchableItems: [
                    SearchableItem(label: L("check_now"), anchorView: checkButton),
                    SearchableItem(label: L("download"), anchorView: installButton),
                ]
            ),
            SettingsCategory(
                title: L("settings_whats_new"), symbolName: "sparkles", tintColor: NSColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1), view: releaseNotesView,
                searchableItems: []
            ),
            SettingsCategory(
                title: L("tab_appearance"), symbolName: "macwindow", tintColor: NSColor.systemBlue, view: appearanceView,
                searchableItems: [
                    SearchableItem(label: L("theme_picker_label"), anchorView: themeRow),
                    SearchableItem(label: L("timezone_picker_label"), anchorView: timeZoneRow),
                    SearchableItem(label: L("show_menu_bar_icon"), anchorView: menuBarRow),
                    SearchableItem(label: L("show_favorites_tab"), anchorView: favoritesRow),
                    SearchableItem(label: L("show_messages_tab"), anchorView: messagesRow),
                    SearchableItem(label: L("show_contact_notes_in_detail"), anchorView: detailNotesRow),
                    SearchableItem(label: L("contacts_open_services_settings_btn"), anchorView: servicesRow),
                ]
            ),
            SettingsCategory(
                title: L("tab_reminders"), symbolName: "bell.fill", tintColor: NSColor.systemPurple, view: remindersView,
                searchableItems: [
                    SearchableItem(label: L("enable_call_reminders_tab"), anchorView: remindersRow),
                    SearchableItem(label: L("show_detail_reminder_btn"), anchorView: detailRemRow),
                    SearchableItem(label: L("show_general_reminder_btn"), anchorView: generalRemRow),
                    SearchableItem(label: L("keep_reminder_history_tab"), anchorView: keepHistoryRow),
                ]
            ),
            SettingsCategory(
                title: L("tab_buttons"), symbolName: "circle.grid.3x3.fill", tintColor: NSColor.systemPink, view: buttonsView,
                searchableItems: [
                    SearchableItem(label: L("show_keypad_tab"), anchorView: keypadRow),
                    SearchableItem(label: L("show_plus_tab"), anchorView: plusRow),
                    SearchableItem(label: L("show_menu_bar_plus_tab"), anchorView: menuBarPlusRow),
                    SearchableItem(label: L("play_app_keypad_sound"), anchorView: appKeypadSoundRow),
                    SearchableItem(label: L("play_menu_bar_keypad_sound"), anchorView: menuBarKeypadSoundRow),
                ]
            ),
            SettingsCategory(
                title: L("tab_search"), symbolName: "magnifyingglass", tintColor: NSColor.systemIndigo, view: searchView,
                searchableItems: [
                    SearchableItem(label: L("search_in_contacts"), anchorView: contactsSearchRow),
                    SearchableItem(label: L("search_in_favorites"), anchorView: favoritesSearchRow),
                    SearchableItem(label: L("search_in_history"), anchorView: historySearchRow),
                ]
            ),
            SettingsCategory(
                title: L("history"), symbolName: "clock.fill", tintColor: NSColor.systemOrange, view: historySettingsView,
                searchableItems: [
                    SearchableItem(label: L("show_history_tab"), anchorView: historyRow),
                    SearchableItem(label: L("show_contact_history_detail"), anchorView: detailHistoryRow),
                ]
            ),
            SettingsCategory(
                title: L("tab_speed_dial"), symbolName: "bolt.fill", tintColor: NSColor.systemYellow, view: speedDialView,
                searchableItems: [
                    SearchableItem(label: L("enable_speed_dial"), anchorView: enableSDRow),
                ]
            ),
            SettingsCategory(
                title: L("tab_contacts_sync"), symbolName: "person.crop.circle.badge.checkmark", tintColor: NSColor.systemGreen, view: contactsSyncView,
                searchableItems: [
                    SearchableItem(label: L("show_contacts_tab"), anchorView: contactsRow),
                    SearchableItem(label: L("contacts_sync_enable_toggle"), anchorView: syncEnableRow),
                    SearchableItem(label: L("contacts_sync_auto_toggle"), anchorView: autoSyncRow),
                    SearchableItem(label: L("contacts_sync_now_btn"), anchorView: syncStatusRow),
                ]
            ),
            SettingsCategory(
                title: L("tab_groups"), symbolName: "person.3.fill", tintColor: NSColor.systemIndigo, view: groupsView,
                searchableItems: [
                    SearchableItem(label: L("groups_enable_toggle"), anchorView: groupsEnableRow),
                    SearchableItem(label: L("groups_manage_title"), anchorView: groupsManageContainer),
                ]
            ),
            SettingsCategory(
                title: L("tab_data"), symbolName: "externaldrive.fill", tintColor: NSColor.systemTeal, view: dataView,
                searchableItems: [
                    SearchableItem(label: L("import_contacts"), anchorView: dataStackView),
                    SearchableItem(label: L("export_contacts"), anchorView: dataStackView),
                    SearchableItem(label: L("import_backup"), anchorView: dataStackView),
                    SearchableItem(label: L("export_backup"), anchorView: dataStackView),
                    SearchableItem(label: L("factory_reset_title"), anchorView: factoryResetButton),
                ]
            ),
            SettingsCategory(
                title: L("tab_info"), symbolName: "info.circle.fill", tintColor: NSColor(red: 0.9, green: 0.35, blue: 0.35, alpha: 1), view: infoView,
                searchableItems: [
                    SearchableItem(label: L("app_website_label"), anchorView: websiteLabel),
                    SearchableItem(label: L("app_github_label"), anchorView: githubLabel),
                ]
            ),
            SettingsCategory(
                title: L("tab_accessibility"), symbolName: "eye", tintColor: NSColor(red: 0.20, green: 0.68, blue: 0.78, alpha: 1), view: accessibilityView,
                searchableItems: [
                    SearchableItem(label: L("a11y_high_contrast"), anchorView: highContrastRow),
                    SearchableItem(label: L("a11y_grayscale"), anchorView: grayscaleRow),
                    SearchableItem(label: L("a11y_increase_text_size"), anchorView: textSizeRow),
                    SearchableItem(label: L("a11y_bold_text"), anchorView: boldTextRow),
                    SearchableItem(label: L("a11y_ui_scale"), anchorView: uiScaleRow),
                    SearchableItem(label: L("a11y_larger_hit_targets"), anchorView: largerHitTargetsRow),
                ]
            )
        ]
        self.tabContentViews = categories.map { $0.view }
        self.settingsCategories = categories

        let sidebar = SettingsSidebarController(categories: categories)
        sidebar.onSelect = { [weak self] index, anchorView in
            self?.showCategory(at: index, highlighting: anchorView)
        }
        self.sidebarController = sidebar

        let sidebarBackground = NSVisualEffectView()
        sidebarBackground.material = .sidebar
        sidebarBackground.blendingMode = .withinWindow
        sidebarBackground.state = .active
        sidebarBackground.translatesAutoresizingMaskIntoConstraints = false
        self.sidebarBackgroundView = sidebarBackground

        let searchField = NSSearchField()
        searchField.placeholderString = L("settings_search_placeholder")
        searchField.target = self
        searchField.action = #selector(settingsSearchFieldChanged(_:))
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        sidebarBackground.addSubview(searchField)
        self.sidebarSearchField = searchField

        sidebarBackground.addSubview(sidebar.view)
        sidebar.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: sidebarBackground.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: sidebarBackground.trailingAnchor, constant: -10),
            searchField.topAnchor.constraint(equalTo: sidebarBackground.topAnchor, constant: 10),

            sidebar.view.leadingAnchor.constraint(equalTo: sidebarBackground.leadingAnchor),
            sidebar.view.trailingAnchor.constraint(equalTo: sidebarBackground.trailingAnchor),
            sidebar.view.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            sidebar.view.bottomAnchor.constraint(equalTo: sidebarBackground.bottomAnchor, constant: -8),
        ])

        let contentScroll = NSScrollView()
        contentScroll.hasVerticalScroller = true
        contentScroll.hasHorizontalScroller = false
        contentScroll.autohidesScrollers = true
        contentScroll.borderType = .noBorder
        contentScroll.drawsBackground = false
        contentScroll.translatesAutoresizingMaskIntoConstraints = false
        self.contentScrollView = contentScroll

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let sidebarDivider = NSBox()
        sidebarDivider.boxType = .separator
        sidebarDivider.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(sidebarBackground)
        container.addSubview(sidebarDivider)
        container.addSubview(contentScroll)

        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.cornerRadius = SettingsWindowController.sectionTitlePillHeight / 2
        pill.layer?.cornerCurve = .continuous
        pill.layer?.masksToBounds = true
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.shadow = NSShadow()
        self.sectionTitlePill = pill

        let pillBlur = NSVisualEffectView()
        pillBlur.material = .popover
        pillBlur.blendingMode = .withinWindow
        pillBlur.state = .active
        pillBlur.wantsLayer = true
        pillBlur.layer?.cornerRadius = SettingsWindowController.sectionTitlePillHeight / 2
        pillBlur.layer?.cornerCurve = .continuous
        pillBlur.layer?.masksToBounds = true
        pillBlur.translatesAutoresizingMaskIntoConstraints = false
        self.sectionTitlePillBlur = pillBlur
        pill.addSubview(pillBlur)

        let pillIcon = NSImageView()
        pillIcon.translatesAutoresizingMaskIntoConstraints = false
        pillIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        self.sectionTitlePillIcon = pillIcon

        let pillLabel = NSTextField(labelWithString: "")
        pillLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        pillLabel.translatesAutoresizingMaskIntoConstraints = false
        pillLabel.lineBreakMode = .byTruncatingTail
        self.sectionTitlePillLabel = pillLabel

        pill.addSubview(pillIcon)
        pill.addSubview(pillLabel)
        container.addSubview(pill)
        updateSectionTitlePillAppearance()

        NSLayoutConstraint.activate([
            pillBlur.leadingAnchor.constraint(equalTo: pill.leadingAnchor),
            pillBlur.trailingAnchor.constraint(equalTo: pill.trailingAnchor),
            pillBlur.topAnchor.constraint(equalTo: pill.topAnchor),
            pillBlur.bottomAnchor.constraint(equalTo: pill.bottomAnchor),

            pillIcon.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 18),
            pillIcon.centerYAnchor.constraint(equalTo: pill.centerYAnchor),

            pillLabel.leadingAnchor.constraint(equalTo: pillIcon.trailingAnchor, constant: 10),
            pillLabel.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -20),
            pillLabel.centerYAnchor.constraint(equalTo: pill.centerYAnchor),

            pill.topAnchor.constraint(equalTo: contentScroll.topAnchor, constant: 14),
            pill.centerXAnchor.constraint(equalTo: contentScroll.centerXAnchor),
            pill.heightAnchor.constraint(equalToConstant: SettingsWindowController.sectionTitlePillHeight),
            pill.widthAnchor.constraint(lessThanOrEqualTo: contentScroll.widthAnchor, constant: -40),
        ])

        NSLayoutConstraint.activate([
            sidebarBackground.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sidebarBackground.topAnchor.constraint(equalTo: container.topAnchor),
            sidebarBackground.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sidebarBackground.widthAnchor.constraint(equalToConstant: SettingsWindowController.sidebarWidth),

            sidebarDivider.leadingAnchor.constraint(equalTo: sidebarBackground.trailingAnchor),
            sidebarDivider.topAnchor.constraint(equalTo: container.topAnchor),
            sidebarDivider.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sidebarDivider.widthAnchor.constraint(equalToConstant: 1),

            contentScroll.leadingAnchor.constraint(equalTo: sidebarDivider.trailingAnchor),
            contentScroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentScroll.topAnchor.constraint(equalTo: container.topAnchor),
            contentScroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            container.widthAnchor.constraint(equalToConstant: SettingsWindowController.windowWidth),
            container.heightAnchor.constraint(equalToConstant: SettingsWindowController.windowHeight),
        ])

        window.contentView = container

        let lastCategory = UserDefaults.standard.integer(forKey: "SettingsLastSelectedCategory")
        let initialIndex = (lastCategory >= 0 && lastCategory < categories.count) ? lastCategory : 0
        showCategory(at: initialIndex)
        
        recenterOnMainWindow()
        refreshContactsSyncUI()
        refreshCallRemindersUI()
    }

    private var isGreek: Bool {
        return Locale.preferredLanguages.first?.hasPrefix("el") ?? true
    }

    private func fetchReleaseNotes(completion: @escaping (String) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/Konstantinos2106/HelloMac/releases/latest") else { return }
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            let fallback = L("settings_release_notes_load_error")
            guard let data = data, error == nil else {
                completion(fallback)
                return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let body = json["body"] as? String {
                completion(body)
            } else {
                completion(fallback)
            }
        }
        task.resume()
    }

    private func extractLocalizedReleaseNotes(_ rawText: String, isGreek: Bool) -> String {
        guard let range = rawText.range(of: "---") else {
            return rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if isGreek {
            return String(rawText[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return String(rawText[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func sanitizeSummaryText(_ raw: String) -> String {
        var s = raw
        if let regex = try? NSRegularExpression(pattern: "</?(b|strong|i|em)>", options: .caseInsensitive) {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
        }
        s = s.replacingOccurrences(of: "**", with: "")
        if let regex = try? NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)") {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func renderReleaseNotes(animated: Bool = false) {
        guard let textView = releaseNotesTextView else { return }
        let newAttrString = parseMarkdown(releaseNotesRawText)
        
        guard animated else {
            textView.textStorage?.setAttributedString(newAttrString)
            return
        }

        let fadeOutDuration: TimeInterval = 0.08
        let fadeInDuration: TimeInterval = 0.16
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            textView.animator().alphaValue = 0
        }, completionHandler: { [weak textView] in
            guard let textView = textView else { return }
            textView.textStorage?.setAttributedString(newAttrString)
            textView.alphaValue = 0
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = fadeInDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                textView.animator().alphaValue = 1
            })
        })
    }

    private func stableDetailsID(summary: String, content: String) -> String {
        let combined = summary + "\u{0}" + content
        var hasher = Hasher()
        hasher.combine(combined)
        let hash = hasher.finalize()
        return String(format: "%016x", UInt(bitPattern: hash))
    }

    private func extractDetailsBlocks(_ text: String) -> String {
        var result = text
        
        guard let regex = try? NSRegularExpression(
            pattern: "<details>\\s*<summary>(.*?)</summary>(.*?)</details>",
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else { return result }
        
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: (result as NSString).length))
        let ns = result as NSString
        var replacements: [(NSRange, String)] = []
        
        for match in matches {
            let summaryRange = match.range(at: 1)
            let contentRange = match.range(at: 2)
            let summary = ns.substring(with: summaryRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let content = ns.substring(with: contentRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let id = stableDetailsID(summary: summary, content: content)
            releaseNotesDetailsBlocks[id] = (summary: summary, content: content)
            replacements.append((match.range, "@@DETAILS:\(id)@@"))
        }
        
        for (range, placeholder) in replacements.reversed() {
            result = (result as NSString).replacingCharacters(in: range, with: placeholder)
        }
        
        return result
    }
    
    private func parseMarkdown(_ rawText: String) -> NSAttributedString {
        let text = extractDetailsBlocks(rawText)
        let baseFont = NSFont.systemFont(ofSize: 13)
        let boldFont = NSFont.boldSystemFont(ofSize: 13)
        let h2Font = NSFont.boldSystemFont(ofSize: 17)
        let h3Font = NSFont.boldSystemFont(ofSize: 15)
        let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        
        let defaultParagraphStyle = NSMutableParagraphStyle()
        defaultParagraphStyle.lineSpacing = 4
        defaultParagraphStyle.lineBreakMode = .byWordWrapping
        
        let attrString = NSMutableAttributedString(string: text, attributes: [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: defaultParagraphStyle
        ])
        
        let patterns = [
            ("^### +(.*)$", h3Font, 4),
            ("^## +(.*)$", h2Font, 3)
        ]
        for (pattern, font, lengthToRemove) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) {
                let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: attrString.length))
                for match in matches.reversed() {
                    let fullRange = match.range
                    let textRange = match.range(at: 1)
                    attrString.addAttributes([.font: font, .foregroundColor: NSColor.labelColor], range: textRange)
                    attrString.replaceCharacters(in: NSRange(location: fullRange.location, length: lengthToRemove), with: "")
                }
            }
        }

        if let regex = try? NSRegularExpression(pattern: "^ {1,4}[*\\-] +(.*)$", options: .anchorsMatchLines) {
            let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: attrString.length))
            
            let nestedBulletPara = NSMutableParagraphStyle()
            nestedBulletPara.lineSpacing = 4
            nestedBulletPara.firstLineHeadIndent = 20
            nestedBulletPara.headIndent = 36
            nestedBulletPara.tabStops = [NSTextTab(textAlignment: .left, location: 36, options: [:])]
            nestedBulletPara.lineBreakMode = .byWordWrapping
            
            for match in matches.reversed() {
                attrString.addAttribute(.paragraphStyle, value: nestedBulletPara, range: match.range)
                let prefixLength = match.range(at: 1).location - match.range.location
                attrString.replaceCharacters(in: NSRange(location: match.range.location, length: prefixLength), with: "◦\t")
            }
        }
        
        if let regex = try? NSRegularExpression(pattern: "^[*\\-] +(.*)$", options: .anchorsMatchLines) {
            let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: attrString.length))
            
            let mainBulletPara = NSMutableParagraphStyle()
            mainBulletPara.lineSpacing = 4
            mainBulletPara.firstLineHeadIndent = 0
            mainBulletPara.headIndent = 16
            mainBulletPara.tabStops = [NSTextTab(textAlignment: .left, location: 16, options: [:])]
            mainBulletPara.lineBreakMode = .byWordWrapping
            
            for match in matches.reversed() {
                attrString.addAttribute(.paragraphStyle, value: mainBulletPara, range: match.range)
                let prefixLength = match.range(at: 1).location - match.range.location
                attrString.replaceCharacters(in: NSRange(location: match.range.location, length: prefixLength), with: "•\t")
            }
        }

        if let regex = try? NSRegularExpression(pattern: "^(\\d{1,3})\\. +(.*)$", options: .anchorsMatchLines) {
            let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: attrString.length))
            
            let numberedPara = NSMutableParagraphStyle()
            numberedPara.lineSpacing = 4
            numberedPara.firstLineHeadIndent = 0
            numberedPara.headIndent = 20
            numberedPara.tabStops = [NSTextTab(textAlignment: .left, location: 20, options: [:])]
            numberedPara.lineBreakMode = .byWordWrapping
            
            for match in matches.reversed() {
                attrString.addAttribute(.paragraphStyle, value: numberedPara, range: match.range)
                let number = (attrString.string as NSString).substring(with: match.range(at: 1))
                let prefixLength = match.range(at: 2).location - match.range.location
                attrString.replaceCharacters(in: NSRange(location: match.range.location, length: prefixLength), with: "\(number).\t")
            }
        }

        if let regex = try? NSRegularExpression(pattern: "`([^`]+?)`") {
            let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: attrString.length))
            for match in matches.reversed() {
                attrString.addAttributes([
                    .font: codeFont,
                    .backgroundColor: NSColor(white: 0.5, alpha: 0.15)
                ], range: match.range(at: 1))
                attrString.replaceCharacters(in: NSRange(location: match.range(at: 1).upperBound, length: 1), with: "")
                attrString.replaceCharacters(in: NSRange(location: match.range(at: 1).lowerBound - 1, length: 1), with: "")
            }
        }

        if let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)") {
            let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: attrString.length))
            for match in matches.reversed() {
                let labelRange = match.range(at: 1)
                let urlRange = match.range(at: 2)
                let urlString = (attrString.string as NSString).substring(with: urlRange)
                
                if let url = URL(string: urlString) {
                    attrString.addAttributes([
                        .link: url,
                        .foregroundColor: NSColor.linkColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ], range: labelRange)
                }
                attrString.replaceCharacters(in: NSRange(location: labelRange.upperBound, length: match.range.upperBound - labelRange.upperBound), with: "")
                attrString.replaceCharacters(in: NSRange(location: labelRange.lowerBound - 1, length: 1), with: "")
            }
        }
        
        if let regex = try? NSRegularExpression(pattern: "\\*\\*(.*?)\\*\\*") {
            let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: attrString.length))
            for match in matches.reversed() {
                attrString.addAttributes([.font: boldFont, .foregroundColor: NSColor.labelColor], range: match.range(at: 1))
                attrString.replaceCharacters(in: NSRange(location: match.range(at: 1).upperBound, length: 2), with: "")
                attrString.replaceCharacters(in: NSRange(location: match.range(at: 1).lowerBound - 2, length: 2), with: "")
            }
        }
        
        if let regex = try? NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.*?)(?<!\\*)\\*(?!\\*)") {
            let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: attrString.length))
            for match in matches.reversed() {
                attrString.addAttributes([.font: italicFont], range: match.range(at: 1))
                attrString.replaceCharacters(in: NSRange(location: match.range(at: 1).upperBound, length: 1), with: "")
                attrString.replaceCharacters(in: NSRange(location: match.range(at: 1).lowerBound - 1, length: 1), with: "")
            }
        }
        
        if let regex = try? NSRegularExpression(pattern: "^---$", options: .anchorsMatchLines) {
            let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: attrString.length))
            for match in matches.reversed() {
                attrString.replaceCharacters(in: match.range, with: "───────────────")
            }
        }

        if !releaseNotesDetailsBlocks.isEmpty,
           let regex = try? NSRegularExpression(pattern: "@@DETAILS:([0-9A-Fa-f\\-]+)@@") {
            let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: attrString.length))
            for match in matches.reversed() {
                let id = (attrString.string as NSString).substring(with: match.range(at: 1))
                guard let block = releaseNotesDetailsBlocks[id] else { continue }
                let isOpen = releaseNotesOpenDetailsIDs.contains(id)
                
                let replacement = NSMutableAttributedString()
                let arrow = isOpen ? "▼ " : "▶ "
                let summaryPara = NSMutableParagraphStyle()
                summaryPara.lineSpacing = 4
                
                let summaryPlain = sanitizeSummaryText(block.summary)
                let summaryAttr = NSMutableAttributedString(string: arrow + summaryPlain, attributes: [
                    .font: boldFont,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: summaryPara,
                    .link: URL(string: "hellomac-details://\(id)")!,
                    .cursor: NSCursor.pointingHand
                ])

                replacement.append(summaryAttr)
                
                if isOpen {
                    replacement.append(NSAttributedString(string: "\n"))
                    let innerAttr = parseMarkdown(block.content)
                    replacement.append(innerAttr)
                }
                
                attrString.replaceCharacters(in: match.range, with: replacement)
            }
        }
        

        return attrString
    }

    // MARK: - NSTextViewDelegate (Release Notes links & details toggle)
    
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let urlString = (link as? URL)?.absoluteString ?? (link as? String) else { return false }
        
        if urlString.hasPrefix("hellomac-details://") {
            let id = String(urlString.dropFirst("hellomac-details://".count))
            let isOpening = !releaseNotesOpenDetailsIDs.contains(id)
            if isOpening {
                releaseNotesOpenDetailsIDs.insert(id)
            } else {
                releaseNotesOpenDetailsIDs.remove(id)
            }
            renderReleaseNotes(animated: true)
            
            if isOpening {
                let totalAnimationDelay: TimeInterval = 0.08 + 0.16 + 0.02
                DispatchQueue.main.asyncAfter(deadline: .now() + totalAnimationDelay) { [weak self] in
                    self?.scrollReleaseNotesToLink(withPrefix: "hellomac-details://\(id)")
                }
            }
            return true
        }
        
        if let url = URL(string: urlString), textView == releaseNotesTextView {
            NSWorkspace.shared.open(url)
            return true
        }
        
        return false
    }

    private func scrollReleaseNotesToLink(withPrefix prefix: String) {
        guard let textView = releaseNotesTextView,
              let textStorage = textView.textStorage,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView = textView.enclosingScrollView else { return }

        layoutManager.ensureLayout(for: textContainer)
        textView.sizeToFit()
        scrollView.layoutSubtreeIfNeeded()
        
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var foundRange: NSRange?
        
        textStorage.enumerateAttribute(.link, in: fullRange, options: []) { value, range, stop in
            let urlString = (value as? URL)?.absoluteString ?? (value as? String)
            if let urlString, urlString.hasPrefix(prefix) {
                foundRange = range
                stop.pointee = true
            }
        }
        
        guard let range = foundRange else { return }
        
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textView.textContainerInset.width
        rect.origin.y += textView.textContainerInset.height
        rect.size.height += 80
        
        textView.scrollToVisible(rect)
    }
    
    private func showCategory(at index: Int, highlighting anchorView: NSView? = nil) {
        guard let contentScroll = contentScrollView,
              index >= 0, index < tabContentViews.count else { return }

        UserDefaults.standard.set(index, forKey: "SettingsLastSelectedCategory")

        let isAlreadyShowing = selectedCategoryIndex == index && currentContentView === tabContentViews[index]
        selectedCategoryIndex = index
        let newView = tabContentViews[index]
        let category = settingsCategories[index]

        sectionTitlePillLabel.stringValue = category.title
        sectionTitlePillIcon.image = SettingsIconBadge.loadSymbol(category.symbolName, fallback: "questionmark.circle")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        sectionTitlePillIcon.contentTintColor = AccessibilityManager.shared.adjustedColor(category.tintColor)
        updateSectionTitlePillAppearance()
        sectionTitlePill.superview?.addSubview(sectionTitlePill)

        if !isAlreadyShowing {
            let wrapper = FlippedView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            newView.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(newView)

            let topInset: CGFloat = 12 + SettingsWindowController.sectionTitlePillHeight + 14
            NSLayoutConstraint.activate([
                newView.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: topInset),
                newView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -12),
                newView.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                newView.widthAnchor.constraint(equalTo: wrapper.widthAnchor)
            ])

            contentScroll.documentView = wrapper
            NSLayoutConstraint.activate([
                wrapper.widthAnchor.constraint(equalTo: contentScroll.contentView.widthAnchor),
                wrapper.heightAnchor.constraint(greaterThanOrEqualTo: contentScroll.contentView.heightAnchor),
            ])

            currentContentView = newView
            AccessibilityManager.shared.applyToViewTree(wrapper)
        }

        sidebarController?.selectRow(index)

        if index == 0 {
            resetUpdateStatusUI()
        }

        if let anchorView {
            scrollToAndHighlight(anchorView, in: contentScroll)
        }
    }

    private func scrollToAndHighlight(_ anchorView: NSView, in scrollView: NSScrollView) {
        scrollView.layoutSubtreeIfNeeded()
        let targetRect = anchorView.convert(anchorView.bounds, to: scrollView.contentView.documentView)
        anchorView.scrollToVisible(targetRect.insetBy(dx: 0, dy: -24))
        flashHighlight(on: anchorView)
    }

    private func flashHighlight(on view: NSView) {
        view.wantsLayer = true
        let highlightLayer = CALayer()
        highlightLayer.frame = view.bounds.insetBy(dx: -8, dy: -4)
        highlightLayer.cornerRadius = 6
        highlightLayer.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.35).cgColor
        highlightLayer.zPosition = -1
        view.layer?.addSublayer(highlightLayer)

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        fadeOut.duration = 0.9
        fadeOut.beginTime = CACurrentMediaTime() + 0.3
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        highlightLayer.add(fadeOut, forKey: "fadeOut")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            highlightLayer.removeFromSuperlayer()
        }
    }

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

    func showInfoCategory() {
        guard let index = settingsCategories.firstIndex(where: { $0.symbolName == "info.circle.fill" }) else {
            return
        }
        showCategory(at: index)
    }

    func showGroupsCategory() {
        guard let index = settingsCategories.firstIndex(where: { $0.symbolName == "person.3.fill" }) else {
            return
        }
        showCategory(at: index)
    }

    func showSpeedDialCategory() {
        guard let index = settingsCategories.firstIndex(where: { $0.symbolName == "bolt.fill" }) else {
            return
        }
        showCategory(at: index)
    }

    func resetUpdateStatusUI() {
        guard updateStatusLabel != nil else { return }
        updateCheckSpinner.stopAnimation(nil)
        updateCheckSpinner.isHidden = true
        updateCheckingLabel.isHidden = true
        checkNowButton.isEnabled = true
        updateStatusLabel.stringValue = ""
        updateStatusCard.isHidden = true
        installUpdateButton.isHidden = true
        pendingDownloadURL = nil
    }

    private func styleUpdateStatusCard(symbolName: String, tint: NSColor) {
        updateStatusIconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        updateStatusIconView.contentTintColor = tint
        updateStatusLabel.textColor = tint
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateStatusCard.layer?.backgroundColor = tint.withAlphaComponent(0.14).cgColor
        CATransaction.commit()
    }

    @objc private func settingsSearchFieldChanged(_ sender: NSSearchField) {
        sidebarController?.applyFilter(sender.stringValue)
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

        updateStatusCard.isHidden = true
        installUpdateButton.isHidden = true
        checkNowButton.isEnabled = false
        updateCheckSpinner.isHidden = false
        updateCheckSpinner.startAnimation(nil)
        updateCheckingLabel.isHidden = false

        let checkStartTime = Date()
        let minimumLoadingDuration: TimeInterval = 0.6

        appDelegate.checkForUpdatesFromSettings { [weak self] result in
            guard let self = self else { return }

            let elapsed = Date().timeIntervalSince(checkStartTime)
            let remainingDelay = max(0, minimumLoadingDuration - elapsed)

            DispatchQueue.main.asyncAfter(deadline: .now() + remainingDelay) {
                guard self.selectedCategoryIndex == 0 else { return }
                self.updateCheckSpinner.stopAnimation(nil)
                self.updateCheckSpinner.isHidden = true
                self.updateCheckingLabel.isHidden = true
                self.checkNowButton.isEnabled = true

                switch result {
                case .upToDate:
                    self.pendingDownloadURL = nil
                    self.installUpdateButton.isHidden = true
                    self.styleUpdateStatusCard(symbolName: "checkmark.circle.fill", tint: .systemGreen)
                    self.updateStatusLabel.stringValue = L("up_to_date_text") + "\n" + L("up_to_date_thanks_text")
                    self.updateStatusCard.isHidden = false
                case .error:
                    self.pendingDownloadURL = nil
                    self.installUpdateButton.isHidden = true
                    self.styleUpdateStatusCard(symbolName: "exclamationmark.triangle.fill", tint: .systemRed)
                    self.updateStatusLabel.stringValue = L("update_error_text")
                    self.updateStatusCard.isHidden = false
                case .updateAvailable(let latestVersion, let downloadURL):
                    self.pendingDownloadURL = downloadURL
                    self.styleUpdateStatusCard(symbolName: "arrow.down.circle.fill", tint: .systemBlue)
                    self.updateStatusLabel.stringValue = L("update_text", latestVersion)
                    self.updateStatusCard.isHidden = false
                    self.installUpdateButton.isHidden = false
                }
            }
        }
    }

    @objc private func installUpdateTapped() {
        guard let downloadURL = pendingDownloadURL,
              let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appDelegate.beginUpdateFromSettings(downloadURL: downloadURL)
    }

    @objc private func toggleKeypadSound(_ sender: NSSwitch) {
        guard let key = sender.identifier?.rawValue else { return }
        UserDefaults.standard.set(sender.state == .on, forKey: key)
    }

    @objc private func toggleFeature(_ sender: NSSwitch) {
        if PrivacyMode.shared.isEnabled {
            sender.state = sender.state == .on ? .off : .on
            PrivacyMode.shared.showBlockedAlert()
            return
        }
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
            NotificationCenter.default.post(name: .speedDialSettingsDidChange, object: nil)
        } else if sender.identifier?.rawValue == "showContactHistoryInDetail" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hideContactHistoryInDetail")
        } else if sender.identifier?.rawValue == "showContactNotesInDetail" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hideContactNotesInDetail")
        } else if sender.identifier?.rawValue == "showMessagesButton" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hideMessagesButton")
        } else if sender.identifier?.rawValue == "showMenuBarIcon" {
            UserDefaults.standard.set(sender.state == .on, forKey: "showMenuBarIcon")
        } else if sender.identifier?.rawValue == "showMenuBarPlusButton" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hideMenuBarPlusButton")
        } else if sender.identifier?.rawValue == "showDetailReminderButton" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hideDetailReminderButton")
        } else if sender.identifier?.rawValue == "showGeneralReminderButton" {
            UserDefaults.standard.set(sender.state == .off, forKey: "hideGeneralReminderButton")
        }

        let contentAffectingKeys: Set<String> = [
            "showContactHistoryInDetail",
            "showContactNotesInDetail"
        ]
        let isContentAffecting = contentAffectingKeys.contains(sender.identifier?.rawValue ?? "")

        let needsHeavyRebuildKeys: Set<String> = [
            "showMessagesButton"
        ]
        let needsHeavyRebuild = needsHeavyRebuildKeys.contains(sender.identifier?.rawValue ?? "")

        if isContentAffecting {
            NotificationCenter.default.post(
                name: NSNotification.Name("UpdateUIVisibility"),
                object: nil,
                userInfo: ["needsFullRebuild": false, "detailOnly": true]
            )
        } else if needsHeavyRebuild {
            NotificationCenter.default.post(
                name: NSNotification.Name("UpdateUIVisibility"),
                object: nil,
                userInfo: ["needsFullRebuild": true]
            )
        } else {
            NotificationCenter.default.post(
                name: NSNotification.Name("UpdateUIVisibility"),
                object: nil,
                userInfo: ["needsFullRebuild": false]
            )
        }
    }
    
    @objc private func toggleAccessibilityFeature(_ sender: NSSwitch) {
        guard let key = sender.identifier?.rawValue else { return }
        let isOn = sender.state == .on
        UserDefaults.standard.set(isOn, forKey: key)
        NotificationCenter.default.post(name: .accessibilitySettingsDidChange, object: nil)
    }

    @objc private func textSizeStepChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        if index == 0 {
            AccessibilityManager.shared.isIncreaseTextSizeEnabled = false
        } else {
            AccessibilityManager.shared.textSizeStep = index + 1
            AccessibilityManager.shared.isIncreaseTextSizeEnabled = true
        }
    }

    @objc private func uiScaleStepChanged(_ sender: NSPopUpButton) {
        AccessibilityManager.shared.uiScaleStep = sender.indexOfSelectedItem
    }

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        AccessibilityManager.shared.colorAdjustmentTheme = A11yColorAdjustmentTheme(rawValue: sender.indexOfSelectedItem) ?? .dark
    }

    @objc private func timeZoneOptionChanged(_ sender: NSPopUpButton) {
        let option = TimeZoneOption(rawValue: sender.indexOfSelectedItem) ?? .system
        UserDefaults.standard.set(option.rawValue, forKey: TimeZoneOption.defaultsKey)
        customTimeZoneRow?.isHidden = option != .custom
        NotificationCenter.default.post(name: .appTimeZoneDidChange, object: nil)
    }

    @objc private func customTimeZoneChanged(_ sender: NSPopUpButton) {
        guard let identifier = sender.titleOfSelectedItem else { return }
        UserDefaults.standard.set(identifier, forKey: TimeZoneOption.customIdentifierKey)
        NotificationCenter.default.post(name: .appTimeZoneDidChange, object: nil)
    }

    @objc private func resetAccessibilityTapped() {
        let alert = NSAlert()
        AccessibilityManager.shared.applyAccessibility(to: alert)
        alert.alertStyle = .warning
        alert.messageText = L("a11y_reset_btn")
        alert.addButton(withTitle: L("ok"))
        alert.addButton(withTitle: L("cancel_btn"))

        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            AccessibilityManager.shared.resetAllToDefaults()
            self?.refreshAccessibilityUI()
        }

        if let appWindow = self.window {
            alert.beginSheetModal(for: appWindow, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    private func refreshAccessibilityUI() {
        for sw in a11ySwitches {
            guard let key = sw.identifier?.rawValue else { continue }
            sw.state = UserDefaults.standard.bool(forKey: key) ? .on : .off
        }
        let a11y = AccessibilityManager.shared
        a11yTextSizePopup?.selectItem(at: a11y.isIncreaseTextSizeEnabled ? max(1, a11y.textSizeStep - 1) : 0)
        a11yUIScalePopup?.selectItem(at: a11y.uiScaleStep)
        themePopup?.selectItem(at: a11y.colorAdjustmentTheme.rawValue)
    }

    @objc private func toggleSearchFeature(_ sender: NSSwitch) {
        if PrivacyMode.shared.isEnabled {
            sender.state = sender.state == .on ? .off : .on
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        guard let key = sender.identifier?.rawValue else { return }
        UserDefaults.standard.set(sender.state == .off, forKey: key)

        NotificationCenter.default.post(
            name: NSNotification.Name("UpdateUIVisibility"),
            object: nil,
            userInfo: ["needsFullRebuild": false]
        )
    }

    // MARK: - Ομάδες Επαφών

    @objc private func toggleGroupsEnabled(_ sender: NSSwitch) {
        if PrivacyMode.shared.isEnabled {
            sender.state = sender.state == .on ? .off : .on
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        ContactGroupStore.shared.isEnabled = sender.state == .on
        refreshGroupsManageEnabledState()
    }
    private func refreshGroupsManageEnabledState() {
        let enabled = ContactGroupStore.shared.isEnabled
        groupsManageContainer?.alphaValue = enabled ? 1.0 : 0.4
        newGroupNameField?.isEnabled = enabled
        groupsListStack?.subviews.forEach { $0.isHidden = !enabled ? false : $0.isHidden }
    }

    @objc private func addGroupTapped() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        guard let field = newGroupNameField else { return }
        groupsErrorLabel?.isHidden = true
        let sanitized = ContactGroup.sanitizedName(field.stringValue)
        guard !sanitized.isEmpty else { return }
        if ContactGroupStore.shared.addGroup(name: sanitized) == nil {
            groupsErrorLabel?.stringValue = L("groups_duplicate_name")
            groupsErrorLabel?.isHidden = false
            return
        }
        field.stringValue = ""
        refreshGroupsListUI()
    }
    private func refreshGroupsListUI() {
        guard let stack = groupsListStack else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let groups = ContactGroupStore.shared.sortedGroups
        groupsEmptyLabel?.isHidden = !groups.isEmpty
        let privacyModeActive = PrivacyMode.shared.isEnabled
        for group in groups {
            let displayName = privacyModeActive ? PrivacyMode.shared.maskedText(group.name) : nil
            let row = GroupSettingsRowView(group: group, displayName: displayName, target: self, renameAction: #selector(renameGroupTapped(_:)), deleteAction: #selector(deleteGroupTapped(_:)))
            row.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    @objc private func renameGroupTapped(_ sender: GroupSettingsRowView) {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        guard let groupID = sender.groupID, let group = ContactGroupStore.shared.group(withID: groupID) else { return }

        let alert = NSAlert()
        alert.messageText = L("groups_rename_prompt_title")
        alert.addButton(withTitle: L("save_btn"))
        alert.addButton(withTitle: L("cancel_btn"))

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = group.name
        input.placeholderString = L("groups_add_placeholder")
        alert.accessoryView = input
        AccessibilityManager.shared.applyAccessibility(to: alert)

        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let sanitized = ContactGroup.sanitizedName(input.stringValue)
            guard !sanitized.isEmpty else { return }
            ContactGroupStore.shared.renameGroup(id: groupID, to: sanitized)
            self?.refreshGroupsListUI()
        }

        if let win = window {
            alert.beginSheetModal(for: win, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    @objc private func deleteGroupTapped(_ sender: GroupSettingsRowView) {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        guard let groupID = sender.groupID, let group = ContactGroupStore.shared.group(withID: groupID) else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("groups_delete_confirm_title", group.name)
        alert.informativeText = L("groups_delete_confirm_text")
        alert.addButton(withTitle: L("groups_delete_confirm_btn"))
        alert.addButton(withTitle: L("cancel_btn"))
        AccessibilityManager.shared.applyAccessibility(to: alert)

        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            ContactGroupStore.shared.deleteGroup(id: groupID)
            self?.refreshGroupsListUI()
        }

        if let win = window {
            alert.beginSheetModal(for: win, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    @objc private func historyAutoDeleteChanged(_ sender: NSPopUpButton) {
        if PrivacyMode.shared.isEnabled {
            let savedIndex = UserDefaults.standard.integer(forKey: HistoryAutoDeleteInterval.defaultsKey)
            sender.selectItem(at: savedIndex)
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        UserDefaults.standard.set(sender.indexOfSelectedItem, forKey: HistoryAutoDeleteInterval.defaultsKey)
        HistoryStore.shared.purgeExpiredRecords()
    }

    @objc private func openServicesKeyboardSettingsTapped() {
        let modernURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")
        let legacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts")

        if let url = modernURL, NSWorkspace.shared.open(url) {
            return
        }
        if let url = legacyURL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openReleasesOnGitHub() {
        if let url = URL(string: "https://github.com/Konstantinos2106/HelloMac/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleContactsSyncEnabled(_ sender: NSSwitch) {
        let turningOn = sender.state == .on

        if !turningOn {
            ContactsSyncManager.shared.isFeatureEnabled = false
            refreshContactsSyncUI()
            return
        }

        let status = ContactsSyncManager.shared.authorizationStatus

        switch status {
        case .authorized:
            ContactsSyncManager.shared.isFeatureEnabled = true
            refreshContactsSyncUI()
            (NSApp.delegate as? AppDelegate)?.syncWithSystemContacts()

        case .notDetermined:
            sender.state = .off
            ContactsSyncManager.shared.requestAccess { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        ContactsSyncManager.shared.isFeatureEnabled = true
                        self?.refreshContactsSyncUI()
                        (NSApp.delegate as? AppDelegate)?.syncWithSystemContacts()
                    } else {
                        ContactsSyncManager.shared.isFeatureEnabled = false
                        self?.refreshContactsSyncUI()
                    }
                }
            }

        case .denied, .restricted:
            sender.state = .off
            ContactsSyncManager.shared.isFeatureEnabled = false
            refreshContactsSyncUI()

            let alert = NSAlert()
            AccessibilityManager.shared.applyAccessibility(to: alert)
            alert.messageText = L("contacts_sync_denied_title")
            alert.informativeText = L("contacts_sync_denied_text")
            alert.addButton(withTitle: L("contacts_sync_open_settings_btn"))
            alert.addButton(withTitle: L("cancel_btn"))

            let handle: (NSApplication.ModalResponse) -> Void = { response in
                if response == .alertFirstButtonReturn {
                    ContactsSyncManager.shared.openSystemPrivacySettings()
                }
            }

            if let appWindow = self.window {
                alert.beginSheetModal(for: appWindow, completionHandler: handle)
            } else {
                handle(alert.runModal())
            }

        @unknown default:
            sender.state = .off
            ContactsSyncManager.shared.isFeatureEnabled = false
            refreshContactsSyncUI()
        }
    }

    @objc private func toggleContactsAutoSync(_ sender: NSSwitch) {
        if PrivacyMode.shared.isEnabled {
            sender.state = sender.state == .on ? .off : .on
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        ContactsSyncManager.shared.isAutoSyncEnabled = sender.state == .on
        refreshContactsSyncUI()
    }

    @objc private func toggleCallRemindersEnabled(_ sender: NSSwitch) {
        if PrivacyMode.shared.isEnabled {
            sender.state = sender.state == .on ? .off : .on
            PrivacyMode.shared.showBlockedAlert()
            return
        }

        let turningOn = sender.state == .on

        if !turningOn {
            ReminderManager.shared.setEnabledByUser(false)
            NotificationCenter.default.post(name: NSNotification.Name("UpdateUIVisibility"), object: nil, userInfo: ["needsFullRebuild": false])
            return
        }

        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    ReminderManager.shared.setEnabledByUser(true)
                    NotificationCenter.default.post(name: NSNotification.Name("UpdateUIVisibility"), object: nil, userInfo: ["needsFullRebuild": false])

                case .notDetermined:
                    sender.state = .off
                    ReminderManager.shared.requestAuthorization { granted in
                        DispatchQueue.main.async {
                            ReminderManager.shared.setEnabledByUser(granted)
                            self.callRemindersSwitch?.state = granted ? .on : .off
                            NotificationCenter.default.post(name: NSNotification.Name("UpdateUIVisibility"), object: nil, userInfo: ["needsFullRebuild": false])
                        }
                    }

                case .denied:
                    sender.state = .off
                    ReminderManager.shared.setEnabledByUser(false)
                    NotificationCenter.default.post(name: NSNotification.Name("UpdateUIVisibility"), object: nil, userInfo: ["needsFullRebuild": false])

                    let alert = NSAlert()
                    AccessibilityManager.shared.applyAccessibility(to: alert)
                    alert.messageText = L("reminders_permission_lost_title")
                    alert.informativeText = L("reminders_permission_lost_text")
                    alert.addButton(withTitle: L("contacts_sync_open_settings_btn"))
                    alert.addButton(withTitle: L("cancel_btn"))

                    let handle: (NSApplication.ModalResponse) -> Void = { response in
                        if response == .alertFirstButtonReturn {
                            ReminderManager.shared.openSystemNotificationSettings()
                        }
                    }

                    if let appWindow = self.window {
                        alert.beginSheetModal(for: appWindow, completionHandler: handle)
                    } else {
                        handle(alert.runModal())
                    }

                @unknown default:
                    sender.state = .off
                    ReminderManager.shared.setEnabledByUser(false)
                    NotificationCenter.default.post(name: NSNotification.Name("UpdateUIVisibility"), object: nil, userInfo: ["needsFullRebuild": false])
                }
            }
        }
    }

    @objc private func syncContactsNowTapped() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        (NSApp.delegate as? AppDelegate)?.syncWithSystemContacts()
    }

    @objc private func refreshContactsSyncUI() {
        guard contactsSyncEnabledSwitch != nil else { return }

        let enabled = ContactsSyncManager.shared.isFeatureEnabled
        contactsSyncEnabledSwitch.state = enabled ? .on : .off

        contactsAutoSyncSwitch.state = ContactsSyncManager.shared.isAutoSyncEnabled ? .on : .off
        contactsAutoSyncRow.isHidden = !enabled
        contactsSyncStatusRow.isHidden = !enabled
        contactsSyncNowButton.isEnabled = enabled

        if enabled {
            contactsLastSyncLabel.stringValue = "\(L("contacts_sync_last_sync_label")): \(ContactsSyncManager.shared.lastSyncDisplayText)"
        } else {
            contactsLastSyncLabel.stringValue = ""
        }
    }

    @objc private func refreshCallRemindersUI() {
        guard callRemindersSwitch != nil else { return }
        let isEnabled = ReminderManager.shared.isEnabled
        callRemindersSwitch.state = isEnabled ? .on : .off
        
        keepReminderHistorySwitch?.isEnabled = isEnabled
        keepReminderHistorySwitch?.state = ReminderHistoryStore.shared.keepHistoryEnabled ? .on : .off
        
        detailReminderSwitch?.isEnabled = isEnabled
        generalReminderSwitch?.isEnabled = isEnabled
    }

    @objc private func toggleKeepReminderHistory(_ sender: NSSwitch) {
        if PrivacyMode.shared.isEnabled {
            sender.state = sender.state == .on ? .off : .on
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        ReminderHistoryStore.shared.keepHistoryEnabled = sender.state == .on
    }

    @objc private func factoryResetFirstConfirmTapped() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }

        let alert = NSAlert()
        AccessibilityManager.shared.applyAccessibility(to: alert)
        alert.alertStyle = .warning
        alert.messageText = L("factory_reset_confirm1_title")
        alert.informativeText = L("factory_reset_confirm1_text")
        alert.addButton(withTitle: L("factory_reset_confirm1_continue_btn"))
        alert.addButton(withTitle: L("cancel_btn"))

        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.showFactoryResetFinalConfirmation()
            }
        }

        if let appWindow = self.window {
            alert.beginSheetModal(for: appWindow, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    private func showFactoryResetFinalConfirmation() {
        let countdownSeconds = 5
        var remaining = countdownSeconds

        let alert = NSAlert()
        AccessibilityManager.shared.applyAccessibility(to: alert)
        alert.alertStyle = .critical
        alert.messageText = L("factory_reset_confirm2_title")

        func updateText() {
            let waitText = String(format: L("factory_reset_confirm2_wait_text"), remaining)
            alert.informativeText = "\(L("factory_reset_confirm2_text"))\n\n\(waitText)"
        }
        updateText()

        let resetButton = alert.addButton(withTitle: L("factory_reset_confirm2_final_btn"))
        alert.addButton(withTitle: L("cancel_btn"))
        resetButton.hasDestructiveAction = true
        resetButton.isEnabled = false

        factoryResetCountdownTimer?.invalidate()
        factoryResetCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            remaining -= 1
            if remaining <= 0 {
                resetButton.isEnabled = true
                alert.informativeText = L("factory_reset_confirm2_text")
                timer.invalidate()
            } else {
                updateText()
            }
        }

        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            self?.factoryResetCountdownTimer?.invalidate()
            self?.factoryResetCountdownTimer = nil
            if response == .alertFirstButtonReturn {
                self?.performFactoryReset()
            }
        }

        if let appWindow = self.window {
            alert.beginSheetModal(for: appWindow, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    private func performFactoryReset() {
        ContactsSyncManager.shared.factoryReset()
        refreshContactsSyncUI()

        let doneAlert = NSAlert()
        AccessibilityManager.shared.applyAccessibility(to: doneAlert)
        doneAlert.alertStyle = .informational
        doneAlert.messageText = L("factory_reset_done_title")
        doneAlert.informativeText = L("factory_reset_done_text")
        doneAlert.addButton(withTitle: L("ok"))
        if let appWindow = self.window {
            doneAlert.beginSheetModal(for: appWindow, completionHandler: nil)
        } else {
            doneAlert.runModal()
        }
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        if let tf = obj.object as? NSTextField, tf.tag >= 1, tf.tag <= 9 {
            if PrivacyMode.shared.isEnabled {
                tf.window?.makeFirstResponder(nil)
                PrivacyMode.shared.showBlockedAlert()
                return
            }
            speedDialFieldsActivelyEditing.insert(tf.tag)
            let savedValue = UserDefaults.standard.string(forKey: "SpeedDial_\(tf.tag)") ?? ""
            tf.stringValue = savedValue
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        if let searchField = obj.object as? NSSearchField, searchField === sidebarSearchField {
            sidebarController?.applyFilter(searchField.stringValue)
            return
        }

        if let tf = obj.object as? NSTextField, tf === newGroupNameField {
            if tf.stringValue.count > ContactGroup.nameCharacterLimit {
                tf.stringValue = String(tf.stringValue.prefix(ContactGroup.nameCharacterLimit))
            }
            groupsErrorLabel?.isHidden = true
            return
        }

        if let tf = obj.object as? NSTextField, tf.tag >= 1, tf.tag <= 9 {
            if PrivacyMode.shared.isEnabled {
                return
            }
            guard speedDialFieldsActivelyEditing.contains(tf.tag) else { return }

            let allowedCharacters = CharacterSet(charactersIn: "+0123456789")
            let currentText = tf.stringValue
            let filteredText = currentText.unicodeScalars.filter { allowedCharacters.contains($0) }
            let newText = String(String.UnicodeScalarView(filteredText))
            if currentText != newText {
                tf.stringValue = newText
            }

            if tf.stringValue.count > 20 {
                tf.stringValue = String(tf.stringValue.prefix(20))
            }
        
            UserDefaults.standard.set(tf.stringValue, forKey: "SpeedDial_\(tf.tag)")
        }
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        if let tf = obj.object as? NSTextField, tf.tag >= 1, tf.tag <= 9 {
            if PrivacyMode.shared.isEnabled {
                speedDialFieldsActivelyEditing.remove(tf.tag)
                privacyModeChangedRefreshSpeedDial()
                return
            }
            guard speedDialFieldsActivelyEditing.contains(tf.tag) else { return }
            speedDialFieldsActivelyEditing.remove(tf.tag)

            let allowedCharacters = CharacterSet(charactersIn: "+0123456789")
            let savedValue = String(String.UnicodeScalarView(tf.stringValue.unicodeScalars.filter { allowedCharacters.contains($0) }))
            if tf.stringValue != savedValue {
                tf.stringValue = savedValue
            }
            UserDefaults.standard.set(savedValue, forKey: "SpeedDial_\(tf.tag)")
            NotificationCenter.default.post(name: .speedDialSettingsDidChange, object: nil)
            
            if let contact = ContactStore.shared.contacts.first(where: { $0.phone.sanitizedForCall == savedValue.sanitizedForCall && !savedValue.isEmpty }) {
                tf.stringValue = contact.fullName
                tf.toolTip = contact.phone
            } else {
                tf.toolTip = savedValue.isEmpty ? nil : savedValue
            }
        }
    }

    @objc private func showContactPicker(_ sender: NSButton) {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }

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
            NotificationCenter.default.post(name: .speedDialSettingsDidChange, object: nil)
            
            tf.window?.makeFirstResponder(nil)
        }
    }
}