import AppKit

extension EditorCanvasView {
    func normalizeMinimumSize(_ annotation: inout Annotation) {
        let minimum: CGFloat = annotation.tool == .text ? 32 : 8
        if annotation.rect.width >= minimum, annotation.rect.height >= minimum {
            return
        }

        let dx = annotation.end.x - annotation.start.x
        let dy = annotation.end.y - annotation.start.y
        let xSign: CGFloat = dx < 0 ? -1 : 1
        let ySign: CGFloat = dy < 0 ? -1 : 1
        var end = annotation.end

        if abs(dx) < minimum {
            end.x = annotation.start.x + minimum * xSign
        }
        if abs(dy) < minimum {
            end.y = annotation.start.y + minimum * ySign
        }

        annotation.end = CGPoint(
            x: max(0, min(imageSize.width, end.x)),
            y: max(0, min(imageSize.height, end.y))
        )
    }

    func normalizeShapeAnnotation(_ annotation: inout Annotation) {
        if annotation.shapeMode == .circle {
            normalizeCircleAnnotation(&annotation)
            return
        }

        normalizeMinimumSize(&annotation)
    }

    func normalizeCircleAnnotation(_ annotation: inout Annotation) {
        let minimum: CGFloat = 8
        let dx = annotation.end.x - annotation.start.x
        let dy = annotation.end.y - annotation.start.y
        let xSign: CGFloat = dx < 0 ? -1 : 1
        let ySign: CGFloat = dy < 0 ? -1 : 1
        let maxX = xSign > 0 ? imageSize.width - annotation.start.x : annotation.start.x
        let maxY = ySign > 0 ? imageSize.height - annotation.start.y : annotation.start.y
        let requestedSide = max(minimum, abs(dx), abs(dy))
        let side = max(0, min(requestedSide, maxX, maxY))

        annotation.end = CGPoint(
            x: annotation.start.x + side * xSign,
            y: annotation.start.y + side * ySign
        )
    }

    func normalizeMinimumArrowLength(_ annotation: inout Annotation) {
        let minimum: CGFloat = 8
        let dx = annotation.end.x - annotation.start.x
        let dy = annotation.end.y - annotation.start.y
        let length = hypot(dx, dy)
        guard length < minimum else { return }

        if length > 0 {
            let scale = minimum / length
            annotation.end = CGPoint(
                x: annotation.start.x + dx * scale,
                y: annotation.start.y + dy * scale
            )
        } else {
            annotation.end = CGPoint(x: annotation.start.x + minimum, y: annotation.start.y)
        }
        annotation.end = clamped(annotation.end)
    }

    func applyCurrentAnnotationModes(to annotation: inout Annotation) {
        annotation.shapeMode = shapeMode
        annotation.arrowMode = arrowMode
        annotation.mosaicMode = mosaicMode
    }

    func promptForTextOptions(
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

    func applyTextOptions(_ options: TextAnnotationOptions, to annotation: inout Annotation) {
        annotation.text = options.text
        annotation.color = options.color
        annotation.fontSize = options.fontSize
        annotation.lineWidth = 0
        fitTextAnnotation(&annotation)
    }

    func fitTextAnnotation(_ annotation: inout Annotation) {
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

    func editTextAnnotation(at point: CGPoint) -> Bool {
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

    func beginAnnotationInteraction(at point: CGPoint) -> Bool {
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

    func updateAnnotationInteraction(to point: CGPoint) {
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

    func endAnnotationInteraction() {
        annotationInteractionMode = nil
        interactionStartPoint = nil
        interactionOriginalAnnotation = nil
    }

    func selectedAnnotationIndex() -> Int? {
        guard let selectedAnnotationID else { return nil }
        return annotations.firstIndex { $0.id == selectedAnnotationID }
    }

    func annotationIndex(at point: CGPoint) -> Int? {
        let tolerance = annotationHitTolerance
        let candidates = annotations.indices.compactMap { index -> AnnotationHitCandidate? in
            let annotation = annotations[index]
            guard annotation.contains(point: point, tolerance: tolerance) else { return nil }
            return AnnotationHitCandidate(
                index: index,
                area: selectionArea(for: annotation),
                coveredRatio: coveredRatio(forAnnotationAt: index)
            )
        }

        return candidates.sorted { lhs, rhs in
            if abs(lhs.area - rhs.area) > 0.5 {
                return lhs.area < rhs.area
            }
            if abs(lhs.coveredRatio - rhs.coveredRatio) > 0.01 {
                return lhs.coveredRatio > rhs.coveredRatio
            }
            return lhs.index > rhs.index
        }.first?.index
    }

    func textAnnotationIndex(at point: CGPoint) -> Int? {
        let tolerance = annotationHitTolerance
        return annotations.indices.reversed().first { index in
            let annotation = annotations[index]
            return annotation.tool == .text && annotation.contains(point: point, tolerance: tolerance)
        }
    }
}
