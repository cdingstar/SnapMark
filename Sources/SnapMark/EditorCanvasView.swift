import AppKit

final class EditorCanvasView: NSView {
    static let minimumZoomScale: CGFloat = 0.03125
    static let maximumZoomScale: CGFloat = 8

    struct AnnotationHitCandidate {
        let index: Int
        let area: CGFloat
        let coveredRatio: CGFloat
    }

    let baseImage: NSImage
    var onAnnotationsChanged: (() -> Void)?
    var onResetRequested: (() -> Void)?
    var zoomScale: CGFloat = 1
    var penSize: PenSize = .medium
    var annotationColor: NSColor = .systemRed
    var shapeMode: ShapeMode = .rectangle
    var arrowMode: ArrowMode = .solid
    var mosaicMode: MosaicMode = .plain
    var handMode: HandMode = .selection {
        didSet {
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }

    var currentTool: AnnotationTool = .arrow {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }

    var annotations: [Annotation] = [] {
        didSet {
            needsDisplay = true
            onAnnotationsChanged?()
        }
    }

    var dragStart: CGPoint?
    var dragCurrent: CGPoint?
    var dragPoints: [CGPoint] = []
    var selectedAnnotationID: UUID?
    var annotationInteractionMode: AnnotationInteractionMode?
    var interactionStartPoint: CGPoint?
    var interactionOriginalAnnotation: Annotation?
    var viewportSize = CGSize(width: 560, height: 360)
    var panStartInWindow: CGPoint?
    var panStartBoundsOrigin: CGPoint?
    let imageSize: CGSize
    let contentPadding: CGFloat = 48
    let fitBorderInset: CGFloat = 2
    let checkerTileSize: CGFloat = 16

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

    override func resignFirstResponder() -> Bool {
        applyActiveAnnotation()
        return super.resignFirstResponder()
    }

    override func resetCursorRects() {
        if currentTool == .hand && handMode == .pan {
            addCursorRect(bounds, cursor: .openHand)
        } else {
            addCursorRect(canvasRect, cursor: .crosshair)
        }
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
        drawHandSelectionOverlay()

        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        if currentTool == .hand {
            if handMode == .pan {
                applyActiveAnnotation()
                beginPan(with: event)
                return
            }

            beginHandSelectionMouseDown(with: event)
            return
        }

        if event.modifierFlags.contains(.option) {
            applyActiveAnnotation()
            beginPan(with: event)
            return
        }

        window?.makeFirstResponder(self)
        guard let point = imagePoint(from: convert(event.locationInWindow, from: nil)) else {
            applyActiveAnnotation()
            return
        }
        if event.clickCount >= 2, editTextAnnotation(at: point) {
            return
        }
        if currentTool != .pen, beginAnnotationInteraction(at: point) {
            return
        }

        applyActiveAnnotation()
        dragStart = point
        dragCurrent = point
        dragPoints = [point]
    }

    override func mouseDragged(with event: NSEvent) {
        if panStartInWindow != nil || (event.modifierFlags.contains(.option) && !(currentTool == .hand && handMode == .selection)) {
            if panStartInWindow == nil {
                beginPan(with: event)
            }
            updatePan(with: event)
            return
        }

        if annotationInteractionMode != nil {
            guard let point = imagePoint(from: convert(event.locationInWindow, from: nil), clampsOutOfBounds: true) else { return }
            updateAnnotationInteraction(to: point)
            return
        }

        guard dragStart != nil, let point = imagePoint(from: convert(event.locationInWindow, from: nil), clampsOutOfBounds: true) else { return }
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

        let end = imagePoint(from: convert(event.locationInWindow, from: nil), clampsOutOfBounds: true) ?? start
        let points = finalizedDragPoints(endingAt: end)
        dragStart = nil
        dragCurrent = nil
        dragPoints.removeAll()

        if currentTool == .hand {
            if handMode == .selection {
                createImagePatchAnnotation(from: CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(start.x - end.x),
                    height: abs(start.y - end.y)
                ))
            }
            return
        }

        var annotation = Annotation(tool: currentTool, start: start, end: end)
        annotation.color = annotationColor
        applyCurrentAnnotationModes(to: &annotation)
        switch currentTool {
        case .pen:
            annotation.points = points
            annotation.lineWidth = penSize.lineWidth
        case .arrow:
            normalizeMinimumArrowLength(&annotation)
        case .rectangle:
            normalizeShapeAnnotation(&annotation)
        case .text, .mosaic, .magnifier:
            normalizeMinimumSize(&annotation)
        case .hand:
            return
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
        applyActiveAnnotation()
        beginPan(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        updatePan(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        endPan()
    }

    override func otherMouseDown(with event: NSEvent) {
        applyActiveAnnotation()
        beginPan(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        updatePan(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        endPan()
    }

    override func keyDown(with event: NSEvent) {
        if ExitShortcut.matches(event) {
            onResetRequested?()
            return
        }

        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            undoLastAnnotation()
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 {
            deleteSelectedAnnotation()
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

    func deleteSelectedAnnotation() {
        guard
            let selectedAnnotationID,
            let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID && $0.isDeletableElement })
        else { return }

        annotations.remove(at: index)
        self.selectedAnnotationID = nil
        annotationInteractionMode = nil
        interactionStartPoint = nil
        interactionOriginalAnnotation = nil
    }

    func applyActiveAnnotation() {
        guard selectedAnnotationID != nil || annotationInteractionMode != nil else { return }
        selectedAnnotationID = nil
        annotationInteractionMode = nil
        interactionStartPoint = nil
        interactionOriginalAnnotation = nil
        needsDisplay = true
    }

    func renderedImage() -> NSImage {
        ImageRenderer.render(baseImage: baseImage, annotations: annotations)
    }
}
