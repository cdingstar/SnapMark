import AppKit

enum AnnotationResizeHandle: CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case start
    case end
}

enum AnnotationInteractionMode {
    case move
    case resize(AnnotationResizeHandle)
}

extension AnnotationTool {
    var isTransformableElement: Bool {
        self != .pen
    }
}

extension Annotation {
    var isTransformableElement: Bool {
        tool.isTransformableElement
    }

    func contains(point: CGPoint, tolerance: CGFloat) -> Bool {
        guard isTransformableElement else { return false }

        switch tool {
        case .arrow:
            return distance(from: point, toSegmentStart: start, end: end) <= max(tolerance, lineWidth + 4)
                || resizeHandle(at: point, tolerance: tolerance) != nil
        case .magnifier:
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .rectangle, .text, .mosaic:
            return rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .pen:
            return false
        }
    }

    func resizeHandlePoints() -> [(AnnotationResizeHandle, CGPoint)] {
        guard isTransformableElement else { return [] }

        if tool == .arrow {
            return [(.start, start), (.end, end)]
        }

        let frame = rect
        return [
            (.topLeft, CGPoint(x: frame.minX, y: frame.maxY)),
            (.topRight, CGPoint(x: frame.maxX, y: frame.maxY)),
            (.bottomLeft, CGPoint(x: frame.minX, y: frame.minY)),
            (.bottomRight, CGPoint(x: frame.maxX, y: frame.minY))
        ]
    }

    func resizeHandle(at point: CGPoint, tolerance: CGFloat) -> AnnotationResizeHandle? {
        resizeHandlePoints().reversed().first { _, handlePoint in
            CGRect(
                x: handlePoint.x - tolerance,
                y: handlePoint.y - tolerance,
                width: tolerance * 2,
                height: tolerance * 2
            ).contains(point)
        }?.0
    }

    func moved(by delta: CGPoint, within imageSize: CGSize) -> Annotation {
        var clampedDelta = delta
        let frame = rect

        if frame.minX + clampedDelta.x < 0 {
            clampedDelta.x = -frame.minX
        }
        if frame.maxX + clampedDelta.x > imageSize.width {
            clampedDelta.x = imageSize.width - frame.maxX
        }
        if frame.minY + clampedDelta.y < 0 {
            clampedDelta.y = -frame.minY
        }
        if frame.maxY + clampedDelta.y > imageSize.height {
            clampedDelta.y = imageSize.height - frame.maxY
        }

        var moved = self
        moved.start = CGPoint(x: start.x + clampedDelta.x, y: start.y + clampedDelta.y)
        moved.end = CGPoint(x: end.x + clampedDelta.x, y: end.y + clampedDelta.y)
        moved.points = points.map { CGPoint(x: $0.x + clampedDelta.x, y: $0.y + clampedDelta.y) }
        return moved
    }

    func resized(handle: AnnotationResizeHandle, to point: CGPoint, within imageSize: CGSize, minimumSize: CGFloat) -> Annotation {
        let point = clamped(point, within: imageSize)
        if tool == .arrow {
            var resized = self
            switch handle {
            case .start:
                resized.start = point
            case .end:
                resized.end = point
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                break
            }
            return resized
        }

        let frame = rect
        var minX = frame.minX
        var maxX = frame.maxX
        var minY = frame.minY
        var maxY = frame.maxY

        switch handle {
        case .topLeft:
            minX = min(point.x, maxX - minimumSize)
            maxY = max(point.y, minY + minimumSize)
        case .topRight:
            maxX = max(point.x, minX + minimumSize)
            maxY = max(point.y, minY + minimumSize)
        case .bottomLeft:
            minX = min(point.x, maxX - minimumSize)
            minY = min(point.y, maxY - minimumSize)
        case .bottomRight:
            maxX = max(point.x, minX + minimumSize)
            minY = min(point.y, maxY - minimumSize)
        case .start, .end:
            break
        }

        minX = max(0, min(minX, imageSize.width - minimumSize))
        maxX = min(imageSize.width, max(maxX, minimumSize))
        minY = max(0, min(minY, imageSize.height - minimumSize))
        maxY = min(imageSize.height, max(maxY, minimumSize))

        if maxX - minX < minimumSize {
            maxX = min(imageSize.width, minX + minimumSize)
        }
        if maxY - minY < minimumSize {
            maxY = min(imageSize.height, minY + minimumSize)
        }

        var resized = self
        resized.start = CGPoint(x: minX, y: minY)
        resized.end = CGPoint(x: maxX, y: maxY)
        return resized
    }

    private func distance(from point: CGPoint, toSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private func clamped(_ point: CGPoint, within imageSize: CGSize) -> CGPoint {
        CGPoint(
            x: max(0, min(imageSize.width, point.x)),
            y: max(0, min(imageSize.height, point.y))
        )
    }
}
