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
    private var selectedAnnotationID: UUID?
    private var movingAnnotationID: UUID?
    private var moveStartPoint: CGPoint?
    private var moveOriginalStart: CGPoint?
    private var moveOriginalEnd: CGPoint?
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

        drawSelectedTextBorder()

        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            beginPan(with: event)
            return
        }

        window?.makeFirstResponder(self)
        guard let point = imagePoint(from: convert(event.locationInWindow, from: nil)) else { return }
        if currentTool == .text, beginTextMove(at: point) {
            return
        }

        selectedAnnotationID = nil
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

        if movingAnnotationID != nil {
            guard let point = imagePoint(from: convert(event.locationInWindow, from: nil)) else { return }
            updateTextMove(to: point)
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

        if movingAnnotationID != nil {
            endTextMove()
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
            guard let options = promptForTextOptions() else {
                needsDisplay = true
                return
            }
            applyTextOptions(options, to: &annotation)
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

    private func promptForTextOptions() -> TextAnnotationOptions? {
        TextAnnotationDialogController().runModal()
    }

    private func applyTextOptions(_ options: TextAnnotationOptions, to annotation: inout Annotation) {
        annotation.text = options.text
        annotation.color = options.color
        annotation.fontSize = options.fontSize
        annotation.lineWidth = 0
        fitTextAnnotation(&annotation)
    }

    private func fitTextAnnotation(_ annotation: inout Annotation) {
        let maxTextWidth = max(1, min(imageSize.width, max(160, imageSize.width - annotation.rect.minX)))
        let fittedSize = TextAnnotationMetrics.fittedSize(
            for: annotation.text,
            fontSize: annotation.fontSize,
            maxWidth: maxTextWidth
        )
        let width = min(max(1, imageSize.width), max(annotation.rect.width, fittedSize.width))
        let height = min(max(1, imageSize.height), max(annotation.rect.height, fittedSize.height))
        let origin = CGPoint(
            x: min(max(0, annotation.rect.minX), max(0, imageSize.width - width)),
            y: min(max(0, annotation.rect.minY), max(0, imageSize.height - height))
        )
        annotation.start = origin
        annotation.end = CGPoint(x: origin.x + width, y: origin.y + height)
    }

    private func beginTextMove(at point: CGPoint) -> Bool {
        guard let index = textAnnotationIndex(at: point) else { return false }
        let annotation = annotations[index]
        selectedAnnotationID = annotation.id
        movingAnnotationID = annotation.id
        moveStartPoint = point
        moveOriginalStart = annotation.start
        moveOriginalEnd = annotation.end
        needsDisplay = true
        return true
    }

    private func updateTextMove(to point: CGPoint) {
        guard
            let movingAnnotationID,
            let index = annotations.firstIndex(where: { $0.id == movingAnnotationID }),
            let moveStartPoint,
            let moveOriginalStart,
            let moveOriginalEnd
        else { return }

        let originalRect = CGRect(
            x: min(moveOriginalStart.x, moveOriginalEnd.x),
            y: min(moveOriginalStart.y, moveOriginalEnd.y),
            width: abs(moveOriginalStart.x - moveOriginalEnd.x),
            height: abs(moveOriginalStart.y - moveOriginalEnd.y)
        )
        var delta = CGPoint(x: point.x - moveStartPoint.x, y: point.y - moveStartPoint.y)
        if originalRect.minX + delta.x < 0 {
            delta.x = -originalRect.minX
        }
        if originalRect.maxX + delta.x > imageSize.width {
            delta.x = imageSize.width - originalRect.maxX
        }
        if originalRect.minY + delta.y < 0 {
            delta.y = -originalRect.minY
        }
        if originalRect.maxY + delta.y > imageSize.height {
            delta.y = imageSize.height - originalRect.maxY
        }

        var annotation = annotations[index]
        annotation.start = CGPoint(x: moveOriginalStart.x + delta.x, y: moveOriginalStart.y + delta.y)
        annotation.end = CGPoint(x: moveOriginalEnd.x + delta.x, y: moveOriginalEnd.y + delta.y)
        annotations[index] = annotation
    }

    private func endTextMove() {
        movingAnnotationID = nil
        moveStartPoint = nil
        moveOriginalStart = nil
        moveOriginalEnd = nil
    }

    private func textAnnotationIndex(at point: CGPoint) -> Int? {
        annotations.indices.reversed().first { index in
            let annotation = annotations[index]
            return annotation.tool == .text && annotation.rect.insetBy(dx: -6, dy: -6).contains(point)
        }
    }

    private func drawSelectedTextBorder() {
        guard
            let selectedAnnotationID,
            let annotation = annotations.first(where: { $0.id == selectedAnnotationID && $0.tool == .text })
        else { return }

        let path = NSBezierPath(rect: annotation.rect.insetBy(dx: -4, dy: -4))
        path.lineWidth = max(1 / max(zoomScale, 1), 0.75)
        let dash: [CGFloat] = [4 / max(zoomScale, 1), 3 / max(zoomScale, 1)]
        dash.withUnsafeBufferPointer { buffer in
            path.setLineDash(buffer.baseAddress, count: dash.count, phase: 0)
        }
        NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
        path.stroke()
    }
}
