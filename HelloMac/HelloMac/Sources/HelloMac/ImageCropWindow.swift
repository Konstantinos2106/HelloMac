import AppKit
import ImageIO
import CoreGraphics

/// Custom view that renders an image inside a circular crop mask, letting the user
/// pan (drag) and zoom (scroll / pinch / slider) to frame their contact photo.
/// The darkened area outside the circle is purely visual — everything under
/// the circle is what gets exported.

/// Loads an image from disk and bakes its EXIF orientation into the actual
/// pixel data, returning an NSImage whose `.size` and raw bitmap agree.
///
/// Background: AppKit's NSImage/NSBitmapImageRep does NOT auto-rotate pixel
/// data to match the EXIF orientation tag the way UIImage on iOS does. For
/// some readers `.size` still reflects the *rotated* (visual) dimensions,
/// while `draw(in:from:...)` draws the *raw, unrotated* pixels. That mismatch
/// is exactly what produces a preview that looks rotated relative to what
/// the aspect-ratio math expects. Normalizing once at load time avoids the
/// problem everywhere downstream (crop preview, zoom math, export, save).
enum ImageOrientationFix {
    static func normalizedImage(contentsOf url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return NSImage(contentsOf: url)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        guard let orientation = CGImagePropertyOrientation(rawValue: rawOrientation), orientation != .up else {
            // No rotation/flip needed — use the pixel data as-is.
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

    /// 1.0 = image fits the crop circle exactly (shortest side). Larger = zoomed in.
    private var zoom: CGFloat = 1.0
    private var minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 4.0

    /// Offset of the image center from the view center, in view points.
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
        // The minimum zoom is whatever scale makes the image's shortest side
        // cover the crop circle's diameter exactly (i.e. "fill" behavior).
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

        // `image.draw(in:from:...)` always draws using the image's own
        // bottom-up bitmap coordinate system — it has no idea this view is
        // flipped (isFlipped == true). Left uncorrected, that mismatch makes
        // every photo render vertically mirrored relative to how the user
        // drags/zooms it, and any additional EXIF-derived rotation compounds
        // on top of that mirroring, producing the "rotated in some photos,
        // upside-down in others" behavior.
        //
        // `drawRect`'s position is already correct in this view's flipped
        // space — only the image's own pixel orientation needs correcting.
        // So instead of flipping the whole context (which would also move
        // drawRect to the wrong place), flip a local transform around the
        // vertical center of drawRect itself: this mirrors the image in
        // place without touching its position.
        NSGraphicsContext.saveGraphicsState()
        let flip = NSAffineTransform()
        flip.translateX(by: 0, yBy: drawRect.midY)
        flip.scaleX(by: 1, yBy: -1)
        flip.translateX(by: 0, yBy: -drawRect.midY)
        flip.concat()
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        // Dim everything outside the circular crop region.
        let path = NSBezierPath(rect: bounds)
        let circleRect = cropRect()
        let circlePath = NSBezierPath(ovalIn: circleRect)
        path.append(circlePath)
        path.windingRule = .evenOdd
        NSColor(white: 0.02, alpha: 0.78).setFill()
        path.fill()

        // Crisp ring around the crop circle.
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
        // `event.locationInWindow` is bottom-up window space, where moving
        // the mouse down gives a *negative* y delta. This view is flipped
        // (isFlipped == true), so in `offset`'s own coordinate space a
        // larger offset.y means further DOWN the screen. To make "drag
        // down" move the image down, offset.y must increase when the
        // mouse's bottom-up y decreases — hence the subtraction.
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

    /// Renders the current crop selection into a square NSImage at a fixed
    /// output resolution, ready to be handed to ContactImageStore.
    func exportCroppedImage(outputSize: CGFloat = 500) -> NSImage {
        let d = cropDiameter
        let scaleFactor = outputSize / d

        let drawSize = NSSize(width: imageAspectSize.width * zoom * scaleFactor,
                               height: imageAspectSize.height * zoom * scaleFactor)

        // `offset` is expressed in the crop view's flipped (top-down) space,
        // where +y means "image moved down on screen". lockFocus() below
        // gives us a bottom-up context (+y means up), so the y component
        // must be negated when converting between the two spaces.
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

/// Rounded, dark, modern sheet that hosts the crop view plus a zoom slider
/// and Cancel / Use Photo actions. Presented as a sheet over the Add/Edit
/// Contact window so it feels like a natural extension of that flow.
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
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false

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
        contentView.layer?.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1).cgColor

        let titleLabel = NSTextField(labelWithString: L("crop_photo_title"))
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: L("crop_photo_subtitle"))
        subtitleLabel.font = NSFont.systemFont(ofSize: 11.5)
        subtitleLabel.textColor = NSColor(white: 0.55, alpha: 1)
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)

        // Circular canvas container gives the crop view a soft shadow so it
        // reads as a distinct, elevated element rather than a plain square.
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
        zoomOutIcon.contentTintColor = NSColor(white: 0.6, alpha: 1)
        zoomOutIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        zoomOutIcon.translatesAutoresizingMaskIntoConstraints = false

        let zoomInIcon = NSImageView(image: NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: nil) ?? NSImage())
        zoomInIcon.contentTintColor = NSColor(white: 0.6, alpha: 1)
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

    /// Presents the cropper as a sheet on `parentWindow`. `completion` receives
    /// the cropped square NSImage, or nil if the user cancelled.
    func present(on parentWindow: NSWindow, completion: @escaping (NSImage?) -> Void) {
        self.onComplete = completion
        guard let sheetWindow = window else { return }
        parentWindow.beginSheet(sheetWindow, completionHandler: nil)
    }
}
