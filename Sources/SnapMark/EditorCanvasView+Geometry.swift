import AppKit

extension EditorCanvasView {
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
        let availableWidth = max(1, viewportSize.width - contentPadding * 2 - fitBorderInset)
        let availableHeight = max(1, viewportSize.height - contentPadding * 2 - fitBorderInset)
        let scale = min(1, availableWidth / imageSize.width, availableHeight / imageSize.height)
        return min(Self.maximumZoomScale, max(Self.minimumZoomScale, scale))
    }

    func fitInZoomScale(for viewportSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        let availableWidth = max(1, viewportSize.width - fitBorderInset)
        let availableHeight = max(1, viewportSize.height - fitBorderInset)
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

    var previewAnnotation: Annotation? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        var annotation = Annotation(tool: currentTool, start: start, end: current)
        annotation.color = annotationColor
        applyCurrentAnnotationModes(to: &annotation)
        if currentTool == .pen {
            annotation.points = finalizedDragPoints(endingAt: current)
            annotation.lineWidth = penSize.lineWidth
            return annotation
        }

        if currentTool == .arrow {
            normalizeMinimumArrowLength(&annotation)
        } else if currentTool == .rectangle {
            normalizeShapeAnnotation(&annotation)
        } else {
            normalizeMinimumSize(&annotation)
        }
        if currentTool == .text {
            annotation.text = L10n.text(.textDefault)
        }
        return annotation
    }

    func finalizedDragPoints(endingAt end: CGPoint) -> [CGPoint] {
        var points = dragPoints
        if points.last.map({ $0 != end }) ?? true {
            points.append(end)
        }
        return points
    }

    var canvasRect: CGRect {
        let size = CGSize(width: imageSize.width * zoomScale, height: imageSize.height * zoomScale)
        return CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    func resizeForCurrentZoom() {
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

    func imagePoint(from viewPoint: CGPoint, clampsOutOfBounds: Bool = false) -> CGPoint? {
        let rect = canvasRect
        guard zoomScale > 0, clampsOutOfBounds || rect.contains(viewPoint) else { return nil }
        return clamped(
            CGPoint(
                x: (viewPoint.x - rect.minX) / zoomScale,
                y: (viewPoint.y - rect.minY) / zoomScale
            )
        )
    }

    func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0, min(imageSize.width, point.x)),
            y: max(0, min(imageSize.height, point.y))
        )
    }

    var imageBounds: CGRect {
        CGRect(origin: .zero, size: imageSize)
    }
}
