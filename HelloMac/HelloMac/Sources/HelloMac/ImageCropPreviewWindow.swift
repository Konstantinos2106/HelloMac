import AppKit
import ImageIO
import CoreGraphics

enum ImageOrientationFix {
    static func normalizedImage(contentsOf url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return NSImage(contentsOf: url)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        guard let orientation = CGImagePropertyOrientation(rawValue: rawOrientation), orientation != .up else {
            let size = NSSize(width: cgImage.width, height: cgImage.height)
            return NSImage(cgImage: cgImage, size: size)
        }

        guard let ciImage = CIImage(cgImage: cgImage).oriented(orientation) as CIImage? else {
            return NSImage(contentsOf: url)
        }

        let context = CIContext()
        let extent = ciImage.extent
        guard let outputCG = context.createCGImage(ciImage, from: extent) else {
            return NSImage(contentsOf: url)
        }

        let size = NSSize(width: outputCG.width, height: outputCG.height)
        return NSImage(cgImage: outputCG, size: size)
    }
}
class ImageCropView: NSView {
    private let image: NSImage
    private let imageAspectSize: NSSize

    private var zoom: CGFloat = 1.0
    private var minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 4.0

    private var offset: CGPoint = .zero

    private var lastDragPoint: NSPoint?

    var onChange: (() -> Void)?

    private var cropDiameter: CGFloat {
        min(bounds.width, bounds.height)
    }

    init(image: NSImage) {
        self.image = image
        self.imageAspectSize = image.size
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor

        addGestureRecognizer(NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:))))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        recalculateMinZoom()
    }

    private func recalculateMinZoom() {
        guard imageAspectSize.width > 0, imageAspectSize.height > 0, cropDiameter > 0 else { return }
        let scaleToCoverW = cropDiameter / imageAspectSize.width
        let scaleToCoverH = cropDiameter / imageAspectSize.height
        let newMinZoom = max(scaleToCoverW, scaleToCoverH)
        let wasAtMin = abs(zoom - minZoom) < 0.0001 || zoom < minZoom
        minZoom = newMinZoom
        if wasAtMin {
            zoom = minZoom
            offset = .zero
        } else {
            zoom = max(zoom, minZoom)
        }
        clampOffset()
    }

    // MARK: - Drawing
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.08, alpha: 1).setFill()
        bounds.fill()

        let drawSize = NSSize(width: imageAspectSize.width * zoom, height: imageAspectSize.height * zoom)
        let center = NSPoint(x: bounds.midX + offset.x, y: bounds.midY + offset.y)
        let drawRect = NSRect(
            x: center.x - drawSize.width / 2,
            y: center.y - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        NSGraphicsContext.saveGraphicsState()
        let flip = NSAffineTransform()
        flip.translateX(by: 0, yBy: drawRect.midY)
        flip.scaleX(by: 1, yBy: -1)
        flip.translateX(by: 0, yBy: -drawRect.midY)
        flip.concat()
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        let path = NSBezierPath(rect: bounds)
        let circleRect = cropRect()
        let circlePath = NSBezierPath(ovalIn: circleRect)
        path.append(circlePath)
        path.windingRule = .evenOdd
        NSColor(white: 0.02, alpha: 0.78).setFill()
        path.fill()

        let ring = NSBezierPath(ovalIn: circleRect.insetBy(dx: 0.75, dy: 0.75))
        ring.lineWidth = 1.5
        NSColor.white.withAlphaComponent(0.9).setStroke()
        ring.stroke()
    }

    private func cropRect() -> NSRect {
        let d = cropDiameter
        return NSRect(x: bounds.midX - d / 2, y: bounds.midY - d / 2, width: d, height: d)
    }

    private func clampOffset() {
        let drawSize = NSSize(width: imageAspectSize.width * zoom, height: imageAspectSize.height * zoom)
        let maxOffsetX = max(0, (drawSize.width - cropDiameter) / 2)
        let maxOffsetY = max(0, (drawSize.height - cropDiameter) / 2)
        offset.x = min(max(offset.x, -maxOffsetX), maxOffsetX)
        offset.y = min(max(offset.y, -maxOffsetY), maxOffsetY)
    }

    // MARK: - Interaction
    override func mouseDown(with event: NSEvent) {
        lastDragPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = lastDragPoint else { return }
        let current = event.locationInWindow
        offset.x += (current.x - last.x)
        offset.y -= (current.y - last.y)
        lastDragPoint = current
        clampOffset()
        needsDisplay = true
        onChange?()
    }

    override func mouseUp(with event: NSEvent) {
        lastDragPoint = nil
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        applyZoomDelta(delta * 0.01)
    }

    @objc private func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
        applyZoomDelta(gesture.magnification)
        gesture.magnification = 0
    }

    private func applyZoomDelta(_ delta: CGFloat) {
        setZoom(zoom * (1 + delta))
    }

    func setZoom(_ newZoom: CGFloat) {
        zoom = min(max(newZoom, minZoom), maxZoom)
        clampOffset()
        needsDisplay = true
        onChange?()
    }

    var currentZoom: CGFloat { zoom }
    var zoomRange: ClosedRange<CGFloat> { minZoom...maxZoom }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    // MARK: - Export
    func exportCroppedImage(outputSize: CGFloat = 500) -> NSImage {
        let d = cropDiameter
        let scaleFactor = outputSize / d

        let drawSize = NSSize(width: imageAspectSize.width * zoom * scaleFactor,
                               height: imageAspectSize.height * zoom * scaleFactor)

        let center = NSPoint(x: outputSize / 2 + offset.x * scaleFactor,
                              y: outputSize / 2 - offset.y * scaleFactor)
        let drawRect = NSRect(
            x: center.x - drawSize.width / 2,
            y: center.y - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        let output = NSImage(size: NSSize(width: outputSize, height: outputSize))
        output.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: outputSize, height: outputSize).fill()

        let clipPath = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: outputSize, height: outputSize))
        clipPath.addClip()

        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        output.unlockFocus()
        return output
    }
}

class ImageCropWindowController: NSWindowController {
    private let cropView: ImageCropView
    private var zoomSlider: NSSlider!
    private var onComplete: ((NSImage?) -> Void)?

    private static let canvasDiameter: CGFloat = 280

    convenience init(image: NSImage) {
        let panelWidth: CGFloat = 360
        let panelHeight: CGFloat = 460

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = AccessibilityManager.shared.preferredWindowAppearance
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear

        self.init(window: window, image: image)
        setupUI()
    }

    private init(window: NSWindow, image: NSImage) {
        self.cropView = ImageCropView(image: image)
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        let backgroundEffect = NSVisualEffectView()
        backgroundEffect.material = .underWindowBackground
        backgroundEffect.blendingMode = .behindWindow
        backgroundEffect.state = .active
        backgroundEffect.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backgroundEffect)
        NSLayoutConstraint.activate([
            backgroundEffect.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundEffect.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            backgroundEffect.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundEffect.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        let titleLabel = NSTextField(labelWithString: L("crop_photo_title"))
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: L("crop_photo_subtitle"))
        subtitleLabel.font = NSFont.systemFont(ofSize: 11.5)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)

        let canvasContainer = NSView()
        canvasContainer.wantsLayer = true
        canvasContainer.layer?.shadowColor = NSColor.black.cgColor
        canvasContainer.layer?.shadowOpacity = 0.45
        canvasContainer.layer?.shadowRadius = 14
        canvasContainer.layer?.shadowOffset = CGSize(width: 0, height: -2)
        canvasContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(canvasContainer)

        cropView.wantsLayer = true
        cropView.layer?.cornerRadius = Self.canvasDiameter / 2
        cropView.layer?.masksToBounds = true
        cropView.layer?.borderWidth = 1
        cropView.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        cropView.translatesAutoresizingMaskIntoConstraints = false
        cropView.onChange = { [weak self] in self?.syncSliderToZoom() }
        canvasContainer.addSubview(cropView)

        let zoomOutIcon = NSImageView(image: NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: nil) ?? NSImage())
        zoomOutIcon.contentTintColor = .secondaryLabelColor
        zoomOutIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        zoomOutIcon.translatesAutoresizingMaskIntoConstraints = false

        let zoomInIcon = NSImageView(image: NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: nil) ?? NSImage())
        zoomInIcon.contentTintColor = .secondaryLabelColor
        zoomInIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        zoomInIcon.translatesAutoresizingMaskIntoConstraints = false

        zoomSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: self, action: #selector(sliderChanged(_:)))
        zoomSlider.isContinuous = true
        zoomSlider.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(zoomSlider)
        contentView.addSubview(zoomOutIcon)
        contentView.addSubview(zoomInIcon)

        let cancelButton = NSButton(title: L("cancel_btn"), target: self, action: #selector(cancelTapped))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1B}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cancelButton)

        let useButton = NSButton(title: L("use_photo_btn"), target: self, action: #selector(useTapped))
        useButton.bezelStyle = .rounded
        useButton.keyEquivalent = "\r"
        useButton.contentTintColor = NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
        useButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(useButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            subtitleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            canvasContainer.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            canvasContainer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            canvasContainer.widthAnchor.constraint(equalToConstant: Self.canvasDiameter),
            canvasContainer.heightAnchor.constraint(equalToConstant: Self.canvasDiameter),

            cropView.topAnchor.constraint(equalTo: canvasContainer.topAnchor),
            cropView.leadingAnchor.constraint(equalTo: canvasContainer.leadingAnchor),
            cropView.trailingAnchor.constraint(equalTo: canvasContainer.trailingAnchor),
            cropView.bottomAnchor.constraint(equalTo: canvasContainer.bottomAnchor),

            zoomOutIcon.topAnchor.constraint(equalTo: canvasContainer.bottomAnchor, constant: 24),
            zoomOutIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            zoomOutIcon.widthAnchor.constraint(equalToConstant: 16),

            zoomInIcon.centerYAnchor.constraint(equalTo: zoomOutIcon.centerYAnchor),
            zoomInIcon.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            zoomInIcon.widthAnchor.constraint(equalToConstant: 16),

            zoomSlider.centerYAnchor.constraint(equalTo: zoomOutIcon.centerYAnchor),
            zoomSlider.leadingAnchor.constraint(equalTo: zoomOutIcon.trailingAnchor, constant: 10),
            zoomSlider.trailingAnchor.constraint(equalTo: zoomInIcon.leadingAnchor, constant: -10),

            useButton.topAnchor.constraint(equalTo: zoomSlider.bottomAnchor, constant: 26),
            useButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            useButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            useButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),

            cancelButton.centerYAnchor.constraint(equalTo: useButton.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: useButton.leadingAnchor, constant: -8),
        ])

        DispatchQueue.main.async { [weak self] in
            self?.syncSliderToZoom()
        }
    }

    private func syncSliderToZoom() {
        let range = cropView.zoomRange
        zoomSlider.minValue = Double(range.lowerBound)
        zoomSlider.maxValue = Double(range.upperBound)
        zoomSlider.doubleValue = Double(cropView.currentZoom)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        cropView.setZoom(CGFloat(sender.doubleValue))
    }

    @objc private func cancelTapped() {
        finish(with: nil)
    }

    @objc private func useTapped() {
        finish(with: cropView.exportCroppedImage())
    }

    private func finish(with image: NSImage?) {
        guard let sheetWindow = window, let parent = sheetWindow.sheetParent else {
            onComplete?(image)
            return
        }
        parent.endSheet(sheetWindow)
        onComplete?(image)
    }

    func present(on parentWindow: NSWindow, completion: @escaping (NSImage?) -> Void) {
        self.onComplete = completion
        guard let sheetWindow = window else { return }
        parentWindow.beginSheet(sheetWindow, completionHandler: nil)
    }
}

// MARK: - Μεγέθυνση φωτογραφίας επαφής
private class EscClosablePanel: NSPanel {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

class ImagePreviewWindowController: NSWindowController, NSWindowDelegate {

    convenience init(image: NSImage) {
        let maxDimension: CGFloat = 480
        let imageSize = image.size
        let aspect = imageSize.width > 0 && imageSize.height > 0 ? imageSize.width / imageSize.height : 1
        var displayWidth = maxDimension
        var displayHeight = maxDimension
        if aspect >= 1 {
            displayHeight = maxDimension / aspect
        } else {
            displayWidth = maxDimension * aspect
        }
        displayWidth = max(displayWidth, 260)
        displayHeight = max(displayHeight, 260)

        let extraChrome: CGFloat = 56
        let panelWidth = displayWidth + 40
        let panelHeight = displayHeight + extraChrome

        let window = EscClosablePanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.appearance = AccessibilityManager.shared.preferredWindowAppearance
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        self.init(window: window)
        window.delegate = self
        window.onCancel = { [weak self] in
            self?.closeTapped()
        }
        setupUI(image: image, displayWidth: displayWidth, displayHeight: displayHeight)
    }

    override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func present(on parentWindow: NSWindow) {
        guard let sheetWindow = window else { return }
        parentWindow.beginSheet(sheetWindow, completionHandler: nil)
    }

    private func setupUI(image: NSImage, displayWidth: CGFloat, displayHeight: CGFloat) {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor

        let blurView = NSVisualEffectView()
        blurView.material = .underWindowBackground
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(blurView)

        let closeConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let closeImg = NSImage(systemSymbolName: "xmark", accessibilityDescription: L("close_btn"))?.withSymbolConfiguration(closeConfig)
        let closeButton = NSButton(image: closeImg ?? NSImage(), target: self, action: #selector(closeTapped))
        closeButton.bezelStyle = .regularSquare
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(closeButton)

        let circleDiameter = min(displayWidth, displayHeight)

        let imageContainer = NSView()
        imageContainer.wantsLayer = true
        imageContainer.layer?.shadowColor = NSColor.black.cgColor
        imageContainer.layer?.shadowOpacity = 0.5
        imageContainer.layer?.shadowRadius = 18
        imageContainer.layer?.shadowOffset = CGSize(width: 0, height: -2)
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageContainer)

        var imageRect = NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
        let cgImage = image.cgImage(forProposedRect: &imageRect, context: nil, hints: [.interpolation: NSImageInterpolation.high])

        let imageLayer = CALayer()
        imageLayer.contents = cgImage
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.magnificationFilter = .trilinear
        imageLayer.minificationFilter = .trilinear
        imageLayer.cornerRadius = circleDiameter / 2
        imageLayer.cornerCurve = .circular
        imageLayer.masksToBounds = true
        imageLayer.backgroundColor = NSColor.clear.cgColor

        let imageHostView = NSView()
        imageHostView.wantsLayer = true
        imageHostView.layer?.backgroundColor = NSColor.clear.cgColor
        imageHostView.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.addSubview(imageHostView)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),

            blurView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: contentView.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            imageContainer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageContainer.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            imageContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
            imageContainer.widthAnchor.constraint(equalToConstant: circleDiameter),
            imageContainer.heightAnchor.constraint(equalToConstant: circleDiameter),

            imageHostView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            imageHostView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            imageHostView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            imageHostView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),
        ])

        imageLayer.frame = CGRect(x: 0, y: 0, width: circleDiameter, height: circleDiameter)
        imageHostView.layer?.addSublayer(imageLayer)
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2.0
    }

    @objc private func closeTapped() {
        guard let sheetWindow = window, let parent = sheetWindow.sheetParent else {
            window?.close()
            return
        }
        parent.endSheet(sheetWindow)
    }
}
