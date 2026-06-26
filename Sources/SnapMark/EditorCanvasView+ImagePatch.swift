import AppKit

extension EditorCanvasView {
    func beginHandSelectionMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let point = imagePoint(from: convert(event.locationInWindow, from: nil)) else {
            applyActiveAnnotation()
            return
        }

        if beginImagePatchInteraction(at: point, copiesPatch: event.modifierFlags.contains(.option)) {
            return
        }

        applyActiveAnnotation()
        dragStart = point
        dragCurrent = point
        dragPoints = [point]
    }

    func beginImagePatchInteraction(at point: CGPoint, copiesPatch: Bool) -> Bool {
        let tolerance = annotationHitTolerance
        if
            !copiesPatch,
            let selectedIndex = selectedAnnotationIndex(),
            annotations[selectedIndex].isImagePatch,
            let handle = annotations[selectedIndex].resizeHandle(at: point, tolerance: tolerance)
        {
            annotationInteractionMode = .resize(handle)
            interactionStartPoint = point
            interactionOriginalAnnotation = annotations[selectedIndex]
            return true
        }

        guard let index = imagePatchIndex(at: point) else { return false }
        if copiesPatch {
            var duplicate = annotations[index]
            duplicate.id = UUID()
            annotations.append(duplicate)
            guard let duplicateIndex = annotations.indices.last else { return true }
            selectedAnnotationID = annotations[duplicateIndex].id
            interactionOriginalAnnotation = annotations[duplicateIndex]
        } else {
            selectedAnnotationID = annotations[index].id
            interactionOriginalAnnotation = annotations[index]
        }

        interactionStartPoint = point
        annotationInteractionMode = .move
        needsDisplay = true
        return true
    }

    func imagePatchIndex(at point: CGPoint) -> Int? {
        let tolerance = annotationHitTolerance
        return annotations.indices.reversed().first { index in
            annotations[index].isImagePatch && annotations[index].contains(point: point, tolerance: tolerance)
        }
    }

    func createImagePatchAnnotation(from proposedRect: CGRect) {
        let rect = proposedRect.intersection(imageBounds)
        guard rect.width >= 2, rect.height >= 2, let imagePatch = imagePatch(from: rect) else {
            needsDisplay = true
            return
        }

        var annotation = Annotation(
            tool: .hand,
            start: rect.origin,
            end: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        annotation.imagePatch = imagePatch
        annotations.append(annotation)
        selectedAnnotationID = annotations.last?.id
    }

    func imagePatch(from rect: CGRect) -> NSImage? {
        let patchSize = CGSize(width: max(1, rect.width.rounded()), height: max(1, rect.height.rounded()))
        let sourceImage = renderedImage()
        let patch = NSImage(size: patchSize)
        patch.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        sourceImage.draw(
            in: CGRect(origin: .zero, size: patchSize),
            from: rect,
            operation: .copy,
            fraction: 1
        )
        patch.unlockFocus()
        return patch
    }
}
