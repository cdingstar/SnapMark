import AppKit

final class EditorCanvasView: NSView {
    static let minimumZoomScale: CGFloat = 0.125
    static let maximumZoomScale: CGFloat = 8

    let baseImage: NSImage
    var onAnnotationsChanged: (() -> Void)?
    var onResetRequested: (() -> Void)?
    private(set) var zoomScale: CGFloat = 1
    var penSize: PenSize = .medium
    var annotationColor: NSColor = .systemRed

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
    private var annotationInteractionMode: AnnotationInteractionMode?
    private var interactionStartPoint: CGPoint?
    private var interactionOriginalAnnotation: Annotation?
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

        drawSelectedAnnotationOverlay()

        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            beginPan(with: event)
            return
        }

        window?.makeFirstResponder(self)
        guard let point = imagePoint(from: convert(event.locationInWindow, from: nil)) else { return }
        if event.clickCount >= 2, editTextAnnotation(at: point) {
            return
        }
        if currentTool != .pen, beginAnnotationInteraction(at: point) {
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

        if annotationInteractionMode != nil {
            guard let point = imagePoint(from: convert(event.locationInWindow, from: nil)) else { return }
            updateAnnotationInteraction(to: point)
            return
        }

        guard dragStart != nil, let point = imagePoint(from: convert(event.locationInWindow, from: nil)) else { return }
        dragCurrent = point
        if currentTool == .pen {
            dragPoints.append(point)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if panStartInWindow != nil {
            endPan()
            return
        }

        if annotationInteractionMode != nil {
            endAnnotationInteraction()
            return
        }

        guard let start = dragStart else { return }

        let end = imagePoint(from: convert(event.locationInWindow, from: nil)) ?? start
        let points = finalizedDragPoints(endingAt: end)
        dragStart = nil
        dragCurrent = nil
        dragPoints.removeAll()

        var annotation = Annotation(tool: currentTool, start: start, end: end)
        annotation.color = annotationColor
        if currentTool == .pen {
            annotation.points = points
            annotation.lineWidth = penSize.lineWidth
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
        if selectedAnnotationID == annotations.last?.id {
            selectedAnnotationID = nil
        }
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
        bestFitZoomScale(for: viewportSize)
    }

    func bestFitZoomScale(for viewportSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        let availableWidth = max(1, viewportSize.width - contentPadding * 2)
        let availableHeight = max(1, viewportSize.height - contentPadding * 2)
        let scale = min(1, availableWidth / imageSize.width, availableHeight / imageSize.height)
        return min(Self.maximumZoomScale, max(Self.minimumZoomScale, scale))
    }

    func fitInZoomScale(for viewportSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        let availableWidth = max(1, viewportSize.width - contentPadding * 2)
        let availableHeight = max(1, viewportSize.height - contentPadding * 2)
        let scale = min(availableWidth / imageSize.width, availableHeight / imageSize.height)
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
        annotation.color = annotationColor
        if currentTool == .pen {
            annotation.points = finalizedDragPoints(endingAt: current)
            annotation.lineWidth = penSize.lineWidth
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

    private func promptForTextOptions(
        defaultText: String = "",
        defaultColor: NSColor? = nil,
        defaultFontSize: CGFloat = TextAnnotationMetrics.defaultFontSize
    ) -> TextAnnotationOptions? {
        TextAnnotationDialogController(
            defaultText: defaultText,
            defaultColor: defaultColor ?? annotationColor,
            defaultFontSize: defaultFontSize
        ).runModal()
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

    private func editTextAnnotation(at point: CGPoint) -> Bool {
        guard let index = textAnnotationIndex(at: point) else { return false }

        selectedAnnotationID = annotations[index].id
        guard let options = promptForTextOptions(
            defaultText: annotations[index].text,
            defaultColor: annotations[index].color,
            defaultFontSize: annotations[index].fontSize
        ) else {
            needsDisplay = true
            return true
        }

        var updated = annotations[index]
        applyTextOptions(options, to: &updated)
        annotations[index] = updated
        return true
    }

    private func beginAnnotationInteraction(at point: CGPoint) -> Bool {
        let tolerance = annotationHitTolerance
        if
            let selectedIndex = selectedAnnotationIndex(),
            let handle = annotations[selectedIndex].resizeHandle(at: point, tolerance: tolerance)
        {
            annotationInteractionMode = .resize(handle)
            interactionStartPoint = point
            interactionOriginalAnnotation = annotations[selectedIndex]
            return true
        }

        guard let index = annotationIndex(at: point) else { return false }
        let annotation = annotations[index]
        selectedAnnotationID = annotation.id
        interactionStartPoint = point
        interactionOriginalAnnotation = annotation
        if let handle = annotation.resizeHandle(at: point, tolerance: tolerance) {
            annotationInteractionMode = .resize(handle)
        } else {
            annotationInteractionMode = .move
        }
        needsDisplay = true
        return true
    }

    private func updateAnnotationInteraction(to point: CGPoint) {
        guard
            let selectedIndex = selectedAnnotationIndex(),
            let interactionStartPoint,
            let interactionOriginalAnnotation,
            let annotationInteractionMode
        else { return }

        switch annotationInteractionMode {
        case .move:
            let delta = CGPoint(x: point.x - interactionStartPoint.x, y: point.y - interactionStartPoint.y)
            annotations[selectedIndex] = interactionOriginalAnnotation.moved(by: delta, within: imageSize)
        case .resize(let handle):
            annotations[selectedIndex] = interactionOriginalAnnotation.resized(
                handle: handle,
                to: point,
                within: imageSize,
                minimumSize: minimumTransformSize(for: interactionOriginalAnnotation)
            )
        }
    }

    private func endAnnotationInteraction() {
        annotationInteractionMode = nil
        interactionStartPoint = nil
        interactionOriginalAnnotation = nil
    }

    private func selectedAnnotationIndex() -> Int? {
        guard let selectedAnnotationID else { return nil }
        return annotations.firstIndex { $0.id == selectedAnnotationID }
    }

    private func annotationIndex(at point: CGPoint) -> Int? {
        let tolerance = annotationHitTolerance
        return annotations.indices.reversed().first { index in
            annotations[index].contains(point: point, tolerance: tolerance)
        }
    }

    private func textAnnotationIndex(at point: CGPoint) -> Int? {
        let tolerance = annotationHitTolerance
        return annotations.indices.reversed().first { index in
            let annotation = annotations[index]
            return annotation.tool == .text && annotation.contains(point: point, tolerance: tolerance)
        }
    }

    private func drawSelectedAnnotationOverlay() {
        guard
            let selectedAnnotationID,
            let annotation = annotations.first(where: { $0.id == selectedAnnotationID && $0.isTransformableElement })
        else { return }

        let path: NSBezierPath
        if annotation.tool == .arrow {
            path = NSBezierPath()
            path.move(to: annotation.start)
            path.line(to: annotation.end)
        } else {
            path = NSBezierPath(rect: annotation.rect.insetBy(dx: -4 / zoomScaleSafe, dy: -4 / zoomScaleSafe))
        }
        path.lineWidth = max(1 / zoomScaleSafe, 0.75)
        let dash: [CGFloat] = [4 / zoomScaleSafe, 3 / zoomScaleSafe]
        dash.withUnsafeBufferPointer { buffer in
            path.setLineDash(buffer.baseAddress, count: dash.count, phase: 0)
        }
        NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
        path.stroke()

        drawResizeHandles(for: annotation)
    }

    private func drawResizeHandles(for annotation: Annotation) {
        let size = resizeHandleDisplaySize
        for (_, point) in annotation.resizeHandlePoints() {
            let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5 / zoomScaleSafe, yRadius: 1.5 / zoomScaleSafe).fill()
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(roundedRect: rect, xRadius: 1.5 / zoomScaleSafe, yRadius: 1.5 / zoomScaleSafe)
            outline.lineWidth = max(1 / zoomScaleSafe, 0.75)
            outline.stroke()
        }
    }

    private var annotationHitTolerance: CGFloat {
        max(6 / zoomScaleSafe, 4)
    }

    private var resizeHandleDisplaySize: CGFloat {
        max(8 / zoomScaleSafe, 5)
    }

    private var zoomScaleSafe: CGFloat {
        max(zoomScale, 0.01)
    }

    private func minimumTransformSize(for annotation: Annotation) -> CGFloat {
        annotation.tool == .text ? 32 : 8
    }
}
