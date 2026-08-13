import AppKit
import CoreImage

extension Notification.Name {
    static let accessibilitySettingsDidChange = Notification.Name("AccessibilitySettingsDidChange")
}

let a11yUserPhotoIdentifier = NSUserInterfaceItemIdentifier("a11y-user-photo")

let a11ySelfManagedIdentifier = NSUserInterfaceItemIdentifier("a11y-self-managed")

enum A11yColorAdjustmentTheme: Int {
    case dark = 0
    case light = 1
    case auto = 2
}

final class AccessibilityManager {
    static let shared = AccessibilityManager()
    private init() {}

    // MARK: - Defaults keys

    private enum Key {
        static let highContrast = "a11yHighContrast"
        static let increaseTextSize = "a11yIncreaseTextSize"
        static let textSizeStep = "a11yTextSizeStep"
        static let boldText = "a11yBoldText"
        static let uiScale = "a11yUIScale"
        static let grayscale = "a11yGrayscale"
        static let lightMode = "a11yLightMode"
        static let appTheme = "a11yAppTheme"
        static let largerHitTargets = "a11yLargerHitTargets"
    }

    // MARK: - Public state (όλα false / 0 από προεπιλογή)

    var isHighContrastEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.highContrast) }
        set { UserDefaults.standard.set(newValue, forKey: Key.highContrast); notifyChange() }
    }

    var isIncreaseTextSizeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.increaseTextSize) }
        set { UserDefaults.standard.set(newValue, forKey: Key.increaseTextSize); notifyChange() }
    }

    var textSizeStep: Int {
        get {
            let raw = UserDefaults.standard.integer(forKey: Key.textSizeStep)
            return raw == 1 ? 2 : raw
        }
        set { UserDefaults.standard.set(max(0, min(4, newValue)), forKey: Key.textSizeStep); notifyChange() }
    }

    var isBoldTextEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.boldText) }
        set { UserDefaults.standard.set(newValue, forKey: Key.boldText); notifyChange() }
    }

    /// 0 = 100%, 1 = 110%, 2 = 120%, 3 = 130%
    var uiScaleStep: Int {
        get { UserDefaults.standard.integer(forKey: Key.uiScale) }
        set { UserDefaults.standard.set(max(0, min(3, newValue)), forKey: Key.uiScale); notifyChange() }
    }

    var isGrayscaleEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.grayscale) }
        set { UserDefaults.standard.set(newValue, forKey: Key.grayscale); notifyChange() }
    }

    var colorAdjustmentTheme: A11yColorAdjustmentTheme {
        get {
            let defaults = UserDefaults.standard

            if defaults.object(forKey: Key.appTheme) != nil {
                return A11yColorAdjustmentTheme(rawValue: defaults.integer(forKey: Key.appTheme)) ?? .auto
            }

            if defaults.object(forKey: Key.lightMode) != nil {
                return defaults.bool(forKey: Key.lightMode) ? .light : .dark
            }

            return .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Key.appTheme)
            notifyChange()
        }
    }

    var isEffectivelyColorInverted: Bool {
        switch colorAdjustmentTheme {
        case .dark: return false
        case .light: return true
        case .auto:
            return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        }
    }

    var isLargerHitTargetsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.largerHitTargets) }
        set { UserDefaults.standard.set(newValue, forKey: Key.largerHitTargets); notifyChange() }
    }

    var hasActiveColorAdjustments: Bool {
        isHighContrastEnabled || isGrayscaleEnabled || isEffectivelyColorInverted
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .accessibilitySettingsDidChange, object: nil)
    }

    // MARK: - Derived helpers: Κείμενο

    var extraFontPoints: CGFloat {
        guard isIncreaseTextSizeEnabled else { return 0 }
        return CGFloat(textSizeStep) * 2.0
    }

    func adjustedFont(baseSize: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let size = baseSize + extraFontPoints
        if isBoldTextEnabled {
            let boldWeight: NSFont.Weight = weight == .regular ? .semibold : .bold
            return NSFont.systemFont(ofSize: size, weight: boldWeight)
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    private func boldedFont(_ font: NSFont) -> NSFont {
        let traits = NSFontManager.shared.traits(of: font)
        if traits.contains(.boldFontMask) {
            return font
        }
        return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    // MARK: - Derived helpers: Μεγέθυνση διεπαφής

    var uiScaleFactor: CGFloat {
        return 1.0 + (CGFloat(uiScaleStep) * 0.1)
    }

    // MARK: - Derived helpers: Μεγαλύτερες περιοχές πατήματος

    var hitTargetInset: CGFloat {
        isLargerHitTargetsEnabled ? 6 : 0
    }

    // MARK: - Χρώμα / αντίθεση: NSColor μετασχηματισμοί

    var highContrastBorderWidth: CGFloat {
        isHighContrastEnabled ? 1.5 : 0
    }

    var highContrastBorderColor: CGColor {
        isEffectivelyColorInverted ? NSColor.black.cgColor : NSColor.white.cgColor
    }

    func adjustedColor(_ base: NSColor) -> NSColor {
        var color = base
        if isGrayscaleEnabled { color = color.desaturated() }
        return color
    }

    func adjustedBackgroundOrTextColor(_ base: NSColor) -> NSColor {
        var color = base
        if isGrayscaleEnabled { color = color.desaturated() }
        if isEffectivelyColorInverted { color = color.inverted() }
        return color
    }

    func desaturatedImage(_ image: NSImage) -> NSImage {
        guard isGrayscaleEnabled else { return image }
        guard let tiff = image.tiffRepresentation,
              let ciImage = CIImage(data: tiff) else { return image }
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage else { return image }
        let rep = NSCIImageRep(ciImage: output)
        let result = NSImage(size: image.size)
        result.addRepresentation(rep)
        return result
    }

    var preferredWindowAppearance: NSAppearance? {
        isEffectivelyColorInverted ? NSAppearance(named: .aqua) : NSAppearance(named: .darkAqua)
    }

    func applyPreferredAppearance(to window: NSWindow) {
        window.appearance = preferredWindowAppearance
    }

    func applyAccessibility(to alert: NSAlert) {
        alert.window.appearance = preferredWindowAppearance
        guard let contentView = alert.window.contentView else { return }
        applyToViewTree(contentView)
    }

    func applyHighContrastBorder(to view: NSView, cornerRadius: CGFloat = 4) {
        view.wantsLayer = true
        view.layer?.borderWidth = highContrastBorderWidth
        view.layer?.borderColor = highContrastBorderColor
        if isHighContrastEnabled {
            view.layer?.cornerRadius = max(view.layer?.cornerRadius ?? 0, cornerRadius)
        }
    }

    // MARK: - Γενικός περιπατητής view tree
    func applyToViewTree(_ root: NSView) {
        applyRecursive(root)
    }

    private func applyRecursive(_ view: NSView) {
        if view.identifier == a11yUserPhotoIdentifier {
            return
        }

        if view.identifier == a11ySelfManagedIdentifier {
            return
        }

        applyColorAdjustments(to: view)
        applyControlBorderIfNeeded(to: view)

        for sub in view.subviews {
            applyRecursive(sub)
        }
    }

    private func applyColorAdjustments(to view: NSView) {
        let bgTextActive = isGrayscaleEnabled || isEffectivelyColorInverted
        let tintActive = isGrayscaleEnabled

        switch view {
        case let textField as NSTextField:
            if textField.textColor?.isDynamicSystemColor != true {
                if !textField.a11yHasCapturedTextColor {
                    textField.a11yBaseTextColor = textField.textColor
                    textField.a11yHasCapturedTextColor = true
                }
                if let base = textField.a11yBaseTextColor {
                    textField.textColor = bgTextActive ? adjustedBackgroundOrTextColor(base) : base
                }
            }
            if !textField.a11yHasCapturedFont {
                textField.a11yBaseFont = textField.font
                textField.a11yHasCapturedFont = true
            }
            if let baseFont = textField.a11yBaseFont {
                textField.font = isBoldTextEnabled ? boldedFont(baseFont) : baseFont
            }
        case let button as NSButton:
            if !button.a11yHasCapturedTintColor {
                button.a11yBaseTintColor = button.contentTintColor
                button.a11yHasCapturedTintColor = true
            }
            if let base = button.a11yBaseTintColor {
                button.contentTintColor = tintActive ? adjustedColor(base) : base
            }
        case let imageView as NSImageView:
            if !imageView.a11yHasCapturedTintColor {
                imageView.a11yBaseTintColor = imageView.contentTintColor
                imageView.a11yHasCapturedTintColor = true
            }
            if let base = imageView.a11yBaseTintColor {
                imageView.contentTintColor = tintActive ? adjustedColor(base) : base
            }
        case let textView as NSTextView:
            if textView.isRichText {
                break
            }
            if !textView.a11yHasCapturedTextColor {
                textView.a11yBaseTextColor = textView.textColor
                textView.a11yHasCapturedTextColor = true
            }
            if let base = textView.a11yBaseTextColor {
                textView.textColor = bgTextActive ? adjustedBackgroundOrTextColor(base) : base
            }
            if !textView.a11yHasCapturedFont {
                textView.a11yBaseFont = textView.font
                textView.a11yHasCapturedFont = true
            }
            if let baseFont = textView.a11yBaseFont {
                textView.font = isBoldTextEnabled ? boldedFont(baseFont) : baseFont
            }
        default:
            break
        }
        let isButtonLikeBackground = view is NSControl
        let layerBgActive = isButtonLikeBackground ? tintActive : bgTextActive
        if view.wantsLayer, let layer = view.layer {
            if !view.a11yHasCapturedBackgroundColor {
                view.a11yBaseBackgroundColor = layer.backgroundColor.flatMap { NSColor(cgColor: $0) }
                view.a11yHasCapturedBackgroundColor = true
            }
            if let base = view.a11yBaseBackgroundColor, (base.usingColorSpace(.deviceRGB)?.alphaComponent ?? 1) > 0.001 {
                layer.backgroundColor = layerBgActive
                    ? (isButtonLikeBackground ? adjustedColor(base) : adjustedBackgroundOrTextColor(base)).cgColor
                    : base.cgColor
            }
        }

        if let window = view.window, view === window.contentView {
            if !window.a11yHasCapturedBackgroundColor {
                window.a11yBaseBackgroundColor = window.backgroundColor
                window.a11yHasCapturedBackgroundColor = true
            }
            if let base = window.a11yBaseBackgroundColor {
                window.backgroundColor = bgTextActive ? adjustedBackgroundOrTextColor(base) : base
            }
        }

        if let searchOrTextField = view as? NSTextField, searchOrTextField.isBezeled || view is NSSearchField {

            if searchOrTextField.backgroundColor?.isDynamicSystemColor == true {
            } else {
                if !searchOrTextField.a11yHasCapturedFieldBackgroundColor {
                    searchOrTextField.a11yBaseFieldBackgroundColor = searchOrTextField.backgroundColor
                    searchOrTextField.a11yHasCapturedFieldBackgroundColor = true
                }
                if let base = searchOrTextField.a11yBaseFieldBackgroundColor {
                    searchOrTextField.backgroundColor = bgTextActive ? adjustedBackgroundOrTextColor(base) : base
                }
            }
        }
    }

    private func applyControlBorderIfNeeded(to view: NSView) {
        let isControl = view is NSButton || view is NSSwitch || view is NSTextField
            || view is NSSearchField || view is NSPopUpButton || view is NSComboBox
        guard isControl else { return }
        if let textField = view as? NSTextField, !textField.isEditable && !textField.isSelectable {
            return
        }
        applyHighContrastBorder(to: view, cornerRadius: min(6, view.bounds.height / 2))
    }

    // MARK: - Παρακολούθηση για ένα view (βοηθητικό για views χωρίς δικό τους observer)

    @discardableResult
    func observeAndApply(to view: NSView) -> NSObjectProtocol {
        applyToViewTree(view)
        return NotificationCenter.default.addObserver(forName: .accessibilitySettingsDidChange, object: nil, queue: .main) { [weak view] _ in
            guard let view = view else { return }
            self.applyToViewTree(view)
        }
    }

    // MARK: - Reset

    func resetAllToDefaults() {
        let defaults = UserDefaults.standard
        [Key.highContrast, Key.increaseTextSize, Key.boldText,
         Key.grayscale, Key.lightMode, Key.appTheme, Key.largerHitTargets].forEach {
            defaults.removeObject(forKey: $0)
        }
        defaults.removeObject(forKey: Key.textSizeStep)
        defaults.removeObject(forKey: Key.uiScale)
        notifyChange()
    }
}

private var a11yBaseTextColorKey: UInt8 = 0
private var a11yHasCapturedTextColorKey: UInt8 = 0
private var a11yBaseTintColorKey: UInt8 = 0
private var a11yHasCapturedTintColorKey: UInt8 = 0
private var a11yBaseBackgroundColorKey: UInt8 = 0
private var a11yHasCapturedBackgroundColorKey: UInt8 = 0
private var a11yBaseFieldBackgroundColorKey: UInt8 = 0
private var a11yHasCapturedFieldBackgroundColorKey: UInt8 = 0
private var a11yBaseFontKey: UInt8 = 0
private var a11yHasCapturedFontKey: UInt8 = 0

private extension NSTextField {
    var a11yBaseTextColor: NSColor? {
        get { objc_getAssociatedObject(self, &a11yBaseTextColorKey) as? NSColor }
        set { objc_setAssociatedObject(self, &a11yBaseTextColorKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    var a11yHasCapturedTextColor: Bool {
        get { (objc_getAssociatedObject(self, &a11yHasCapturedTextColorKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &a11yHasCapturedTextColorKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    var a11yBaseFieldBackgroundColor: NSColor? {
        get { objc_getAssociatedObject(self, &a11yBaseFieldBackgroundColorKey) as? NSColor }
        set { objc_setAssociatedObject(self, &a11yBaseFieldBackgroundColorKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    var a11yHasCapturedFieldBackgroundColor: Bool {
        get { (objc_getAssociatedObject(self, &a11yHasCapturedFieldBackgroundColorKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &a11yHasCapturedFieldBackgroundColorKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    var a11yBaseFont: NSFont? {
        get { objc_getAssociatedObject(self, &a11yBaseFontKey) as? NSFont }
        set { objc_setAssociatedObject(self, &a11yBaseFontKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    var a11yHasCapturedFont: Bool {
        get { (objc_getAssociatedObject(self, &a11yHasCapturedFontKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &a11yHasCapturedFontKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}

private extension NSTextView {
    var a11yBaseTextColor: NSColor? {
        get { objc_getAssociatedObject(self, &a11yBaseTextColorKey) as? NSColor }
        set { objc_setAssociatedObject(self, &a11yBaseTextColorKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    var a11yHasCapturedTextColor: Bool {
        get { (objc_getAssociatedObject(self, &a11yHasCapturedTextColorKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &a11yHasCapturedTextColorKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    var a11yBaseFont: NSFont? {
        get { objc_getAssociatedObject(self, &a11yBaseFontKey) as? NSFont }
        set { objc_setAssociatedObject(self, &a11yBaseFontKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    var a11yHasCapturedFont: Bool {
        get { (objc_getAssociatedObject(self, &a11yHasCapturedFontKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &a11yHasCapturedFontKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}

private extension NSButton {
    var a11yBaseTintColor: NSColor? {
        get { objc_getAssociatedObject(self, &a11yBaseTintColorKey) as? NSColor }
        set { objc_setAssociatedObject(self, &a11yBaseTintColorKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    var a11yHasCapturedTintColor: Bool {
        get { (objc_getAssociatedObject(self, &a11yHasCapturedTintColorKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &a11yHasCapturedTintColorKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}

private extension NSImageView {
    var a11yBaseTintColor: NSColor? {
        get { objc_getAssociatedObject(self, &a11yBaseTintColorKey) as? NSColor }
        set { objc_setAssociatedObject(self, &a11yBaseTintColorKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    var a11yHasCapturedTintColor: Bool {
        get { (objc_getAssociatedObject(self, &a11yHasCapturedTintColorKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &a11yHasCapturedTintColorKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}

extension NSView {
    var a11yBaseBackgroundColor: NSColor? {
        get { objc_getAssociatedObject(self, &a11yBaseBackgroundColorKey) as? NSColor }
        set { objc_setAssociatedObject(self, &a11yBaseBackgroundColorKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    var a11yHasCapturedBackgroundColor: Bool {
        get { (objc_getAssociatedObject(self, &a11yHasCapturedBackgroundColorKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &a11yHasCapturedBackgroundColorKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}

extension NSWindow {
    var a11yBaseBackgroundColor: NSColor? {
        get { objc_getAssociatedObject(self, &a11yBaseBackgroundColorKey) as? NSColor }
        set { objc_setAssociatedObject(self, &a11yBaseBackgroundColorKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    var a11yHasCapturedBackgroundColor: Bool {
        get { (objc_getAssociatedObject(self, &a11yHasCapturedBackgroundColorKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &a11yHasCapturedBackgroundColorKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
}

// MARK: - NSColor helpers για αντιστροφή/αποκορεσμό χωρίς CIFilter σε layer

extension NSColor {
    func inverted() -> NSColor {
        guard let rgb = usingColorSpace(.deviceRGB) else { return self }
        return NSColor(red: 1 - rgb.redComponent,
                        green: 1 - rgb.greenComponent,
                        blue: 1 - rgb.blueComponent,
                        alpha: rgb.alphaComponent)
    }

    func desaturated() -> NSColor {
        guard let rgb = usingColorSpace(.deviceRGB) else { return self }
        let gray = (rgb.redComponent * 0.299) + (rgb.greenComponent * 0.587) + (rgb.blueComponent * 0.114)
        return NSColor(white: gray, alpha: rgb.alphaComponent)
    }

    var isDynamicSystemColor: Bool {
        return self.type == .catalog
    }
}