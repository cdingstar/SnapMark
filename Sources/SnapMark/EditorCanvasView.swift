import AppKit

final class EditorCanvasView: NSView {
    static let minimumZoomScale: CGFloat = 0.125
    static let maximumZoomScale: CGFloat = 8

    let baseImage: NSImage
    var onAnnotationsChanged: (() -> Void)?
    var onResetRequested: (() -> Void)?
    private(set) var zoomScale: CGFloat = 1
    var eraserSize: EraserSize = .medium

    var currentTool: AnnotationTool = .arrow {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }

    private(set) var annotations: [Annotation] = [] {
        didSet {
            needsDisplay = true
            onAnnotationsChanged?()
        }
    }

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var dragPoints: [CGPoint] = []
    private var viewportSize = CGSize(width: 560, height: 360)
    private var panStartInWindow: CGPoint?
    private var panStartBoundsOrigin: CGPoint?
    private let imageSize: CGSize
    private let contentPadding: CGFloat = 48
    private let checkerTileSize: CGFloat = 16

    init(image: NSImage) {
        baseImage = image
        imageSize = image.snapMarkPixelSize
        super.init(frame: CGRect(origin: .zero, size: imageSize))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(canvasRect, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawCheckerboard(in: dirtyRect)

        let rect = canvasRect
        NSColor.black.withAlphaComponent(0.28).setStroke()
        NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5)).stroke()

        NSGraphicsContext.saveGraphicsState()
        if zoomScale >= 1 {
            NSGraphicsContext.current?.imageInterpolation = .none
        } else {
            NSGraphicsContext.current?.imageInterpolation = .high
        }

        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scale(by: zoomScale)
        transform.concat()

        let imageRect = CGRect(origin: .zero, size: imageSize)
        baseImage.draw(in: imageRect, from: .zero, operation: .copy, fraction: 1)
        ImageRenderer.draw(annotations: annotations, over: baseImage, canvasRect: imageRect)

        if let preview = previewAnnotation {
            ImageRenderer.draw(annotations: [preview], over: baseImage, canvasRect: imageRect, isPreview: true)
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            beginPan(with: event)
            return
        }

        window?.makeFirstResponder(self)
        guard let point = imagePoint(from: convert(event.locationInWindow, from: nil)) else { return }
        dragStart = point
        dragCurrent = point
        dragPoints = [point]
    }

    override func mouseDragged(with event: NSEvent) {
        if panStartInWindow != nil || event.modifierFlags.contains(.option) {
            if panStartInWindow == nil {
                beginPan(with: event)
            }
            updatePan(with: event)
            return
        }

        guard dragStart != nil, let point = imagePoint(from: convert(event.locationInWindow, from: nil)) else { return }
        dragCurrent = point
        if currentTool == .eraser {
            dragPoints.append(point)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if panStartInWindow != nil {
            endPan()
            return
        }

        guard let start = dragStart else { return }

        let end = imagePoint(from: convert(event.locationInWindow, from: nil)) ?? start
        let points = finalizedDragPoints(endingAt: end)
        dragStart = nil
        dragCurrent = nil
        dragPoints.removeAll()

        var annotation = Annotation(tool: currentTool, start: start, end: end)
        if currentTool == .eraser {
            annotation.points = points
            annotation.lineWidth = eraserSize.lineWidth
        } else {
            normalizeMinimumSize(&annotation)
        }

        if currentTool == .text {
            guard let text = promptForText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                needsDisplay = true
                return
            }
            annotation.text = text
            annotation.lineWidth = 0
        }

        annotations.append(annotation)
    }

    override func rightMouseDown(with event: NSEvent) {
        beginPan(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        updatePan(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        endPan()
    }

    override func otherMouseDown(with event: NSEvent) {
        beginPan(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        updatePan(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        endPan()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onResetRequested?()
            return
        }

        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            undoLastAnnotation()
            return
        }

        super.keyDown(with: event)
    }

    func undoLastAnnotation() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
    }

    func renderedImage() -> NSImage {
        ImageRenderer.render(baseImage: baseImage, annotations: annotations)
    }

    func updateViewportSize(_ size: CGSize) {
        viewportSize = CGSize(width: max(1, size.width), height: max(1, size.height))
        resizeForCurrentZoom()
    }

    func setZoomScale(_ scale: CGFloat) {
        zoomScale = min(Self.maximumZoomScale, max(Self.minimumZoomScale, scale))
        resizeForCurrentZoom()
        needsDisplay = true
    }

    func fitZoomScale(for viewportSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        let availableWidth = max(1, viewportSize.width - contentPadding * 2)
        let availableHeight = max(1, viewportSize.height - contentPadding * 2)
        let scale = min(1, availableWidth / imageSize.width, availableHeight / imageSize.height)
        return min(Self.maximumZoomScale, max(Self.minimumZoomScale, scale))
    }

    var canvasCenterRect: CGRect {
        CGRect(
            x: max(0, bounds.midX - viewportSize.width / 2),
            y: max(0, bounds.midY - viewportSize.height / 2),
            width: viewportSize.width,
            height: viewportSize.height
        )
    }

    private var previewAnnotation: Annotation? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        var annotation = Annotation(tool: currentTool, start: start, end: current)
        if currentTool == .eraser {
            annotation.points = finalizedDragPoints(endingAt: current)
            annotation.lineWidth = eraserSize.lineWidth
            return annotation
        }

        normalizeMinimumSize(&annotation)
        if currentTool == .text {
            annotation.text = "Text"
        }
        return annotation
    }

    private func finalizedDragPoints(endingAt end: CGPoint) -> [CGPoint] {
        var points = dragPoints
        if points.last.map({ $0 != end }) ?? true {
            points.append(end)
        }
        return points
    }

    private var canvasRect: CGRect {
        let size = CGSize(width: imageSize.width * zoomScale, height: imageSize.height * zoomScale)
        return CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func resizeForCurrentZoom() {
        let scaledSize = CGSize(width: imageSize.width * zoomScale, height: imageSize.height * zoomScale)
        let documentSize = CGSize(
            width: max(viewportSize.width, scaledSize.width + contentPadding * 2),
            height: max(viewportSize.height, scaledSize.height + contentPadding * 2)
        )
        if frame.size != documentSize {
            setFrameSize(documentSize)
        }
        window?.invalidateCursorRects(for: self)
    }

    private func imagePoint(from viewPoint: CGPoint) -> CGPoint? {
        let rect = canvasRect
        guard rect.contains(viewPoint), zoomScale > 0 else { return nil }
        return clamped(
            CGPoint(
                x: (viewPoint.x - rect.minX) / zoomScale,
                y: (viewPoint.y - rect.minY) / zoomScale
            )
        )
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0, min(imageSize.width, point.x)),
            y: max(0, min(imageSize.height, point.y))
        )
    }

    private func drawCheckerboard(in rect: CGRect) {
        NSColor(calibratedWhite: 0.76, alpha: 1).setFill()
        rect.fill()

        NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
        let minColumn = Int(floor(rect.minX / checkerTileSize))
        let maxColumn = Int(ceil(rect.maxX / checkerTileSize))
        let minRow = Int(floor(rect.minY / checkerTileSize))
        let maxRow = Int(ceil(rect.maxY / checkerTileSize))

        for column in minColumn...maxColumn {
            for row in minRow...maxRow where (column + row).isMultiple(of: 2) {
                CGRect(
                    x: CGFloat(column) * checkerTileSize,
                    y: CGFloat(row) * checkerTileSize,
                    width: checkerTileSize,
                    height: checkerTileSize
                ).fill()
            }
        }
    }

    private func beginPan(with event: NSEvent) {
        guard let clipView = enclosingScrollView?.contentView else { return }
        panStartInWindow = event.locationInWindow
        panStartBoundsOrigin = clipView.bounds.origin
        NSCursor.openHand.set()
    }

    private func updatePan(with event: NSEvent) {
        guard
            let clipView = enclosingScrollView?.contentView,
            let panStartInWindow,
            let panStartBoundsOrigin
        else { return }

        let delta = CGPoint(
            x: event.locationInWindow.x - panStartInWindow.x,
            y: event.locationInWindow.y - panStartInWindow.y
        )
        let maxOrigin = CGPoint(
            x: max(0, bounds.width - clipView.bounds.width),
            y: max(0, bounds.height - clipView.bounds.height)
        )
        let nextOrigin = CGPoint(
            x: max(0, min(maxOrigin.x, panStartBoundsOrigin.x - delta.x)),
            y: max(0, min(maxOrigin.y, panStartBoundsOrigin.y - delta.y))
        )

        clipView.scroll(to: nextOrigin)
        enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    private func endPan() {
        panStartInWindow = nil
        panStartBoundsOrigin = nil
        NSCursor.arrow.set()
    }

    private func normalizeMinimumSize(_ annotation: inout Annotation) {
        let minimum: CGFloat = annotation.tool == .text ? 32 : 8
        if annotation.rect.width >= minimum, annotation.rect.height >= minimum {
            return
        }

        annotation.end = CGPoint(
            x: annotation.start.x + max(minimum, annotation.rect.width),
            y: annotation.start.y + max(minimum, annotation.rect.height)
        )
    }

    private func promptForText() -> String? {
        let alert = NSAlert()
        alert.messageText = "添加文字"
        alert.informativeText = "输入要放到截图上的文字。"
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")

        let textField = NSTextField(frame: CGRect(x: 0, y: 0, width: 280, height: 24))
        textField.placeholderString = "标注文字"
        alert.accessoryView = textField

        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? textField.stringValue : nil
    }
}
