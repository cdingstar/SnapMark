import AppKit

extension EditorCanvasView {
    func drawCheckerboard(in rect: CGRect) {
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

    func drawSelectedAnnotationOverlay() {
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

    func drawHandSelectionOverlay() {
        guard
            currentTool == .hand,
            handMode == .selection,
            annotationInteractionMode == nil,
            let start = dragStart,
            let current = dragCurrent
        else { return }

        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y)
        )
        guard rect.width > 0, rect.height > 0 else { return }

        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        rect.fill()

        let path = NSBezierPath(rect: rect)
        path.lineWidth = max(1 / zoomScaleSafe, 0.75)
        let dash: [CGFloat] = [5 / zoomScaleSafe, 3 / zoomScaleSafe]
        dash.withUnsafeBufferPointer { buffer in
            path.setLineDash(buffer.baseAddress, count: dash.count, phase: 0)
        }
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        path.stroke()
    }

    func drawResizeHandles(for annotation: Annotation) {
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

    var annotationHitTolerance: CGFloat {
        max(6 / zoomScaleSafe, 4)
    }

    var resizeHandleDisplaySize: CGFloat {
        max(8 / zoomScaleSafe, 5)
    }

    var zoomScaleSafe: CGFloat {
        max(zoomScale, 0.01)
    }

    func minimumTransformSize(for annotation: Annotation) -> CGFloat {
        annotation.tool == .text ? 32 : 8
    }

    func selectionArea(for annotation: Annotation) -> CGFloat {
        if annotation.tool == .arrow {
            let length = max(hypot(annotation.end.x - annotation.start.x, annotation.end.y - annotation.start.y), 1)
            let thickness = max(annotation.lineWidth, annotationHitTolerance * 2, 1)
            return length * thickness
        }

        let frame = selectionFrame(for: annotation)
        return max(frame.width, 1) * max(frame.height, 1)
    }

    func coveredRatio(forAnnotationAt index: Int) -> CGFloat {
        let frame = selectionFrame(for: annotations[index])
        let area = max(frame.width, 1) * max(frame.height, 1)
        let coveredArea = annotations.indices
            .filter { $0 > index && annotations[$0].isTransformableElement }
            .reduce(CGFloat.zero) { total, otherIndex in
                let intersection = frame.intersection(selectionFrame(for: annotations[otherIndex]))
                guard !intersection.isNull else { return total }
                return total + max(intersection.width, 0) * max(intersection.height, 0)
            }
        return min(1, coveredArea / area)
    }

    func selectionFrame(for annotation: Annotation) -> CGRect {
        if annotation.tool == .arrow {
            let minX = min(annotation.start.x, annotation.end.x)
            let minY = min(annotation.start.y, annotation.end.y)
            let width = max(abs(annotation.end.x - annotation.start.x), 1)
            let height = max(abs(annotation.end.y - annotation.start.y), 1)
            let thickness = max(annotation.lineWidth, annotationHitTolerance * 2, 1)
            return CGRect(x: minX, y: minY, width: width, height: height)
                .insetBy(dx: -thickness / 2, dy: -thickness / 2)
        }

        return annotation.rect
    }
}
