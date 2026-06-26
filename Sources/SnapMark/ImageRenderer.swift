import AppKit

enum ImageRenderer {
    static func render(baseImage: NSImage, annotations: [Annotation]) -> NSImage {
        let size = baseImage.snapMarkPixelSize
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: max(1, Int(size.width.rounded())),
                pixelsHigh: max(1, Int(size.height.rounded())),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            return baseImage
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        let canvasRect = CGRect(origin: .zero, size: size)
        NSColor.clear.setFill()
        canvasRect.fill()
        baseImage.draw(in: canvasRect, from: .zero, operation: .copy, fraction: 1)
        draw(annotations: annotations, over: baseImage, canvasRect: canvasRect)

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    static func draw(annotations: [Annotation], over baseImage: NSImage, canvasRect: CGRect, isPreview: Bool = false) {
        for annotation in annotations {
            switch annotation.tool {
            case .arrow:
                drawArrow(annotation, isPreview: isPreview)
            case .rectangle:
                drawRectangle(annotation, isPreview: isPreview)
            case .text:
                drawText(annotation, isPreview: isPreview)
            case .mosaic:
                drawMosaic(annotation, over: baseImage, canvasRect: canvasRect, isPreview: isPreview)
            case .magnifier:
                drawMagnifier(annotation, over: baseImage, canvasRect: canvasRect, isPreview: isPreview)
            case .pen:
                drawPen(annotation, isPreview: isPreview)
            case .hand:
                drawImagePatch(annotation, isPreview: isPreview)
            }
        }
    }

    private static func drawArrow(_ annotation: Annotation, isPreview: Bool) {
        switch annotation.arrowMode {
        case .solid:
            drawSolidArrow(annotation, isPreview: isPreview)
        case .notched:
            drawNotchedArrow(annotation, isPreview: isPreview)
        case .line:
            drawArrowLine(annotation, isPreview: isPreview)
        }
    }

    private static func drawArrowLine(_ annotation: Annotation, isPreview: Bool) {
        let path = NSBezierPath()
        path.move(to: annotation.start)
        path.line(to: annotation.end)
        path.lineWidth = annotation.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        annotationColor(annotation, alphaMultiplier: isPreview ? 0.55 : 1).setStroke()
        path.stroke()
    }

    private static func drawSolidArrow(_ annotation: Annotation, isPreview: Bool) {
        guard let metrics = arrowMetrics(for: annotation) else { return }

        let alpha: CGFloat = isPreview ? 0.55 : 1
        let lineWidth = max(1, annotation.lineWidth)
        let headLength = min(max(18, lineWidth * 4), max(8, metrics.length * 0.45))
        let headHalfWidth = max(7, lineWidth * 1.8)
        let shaftEnd = CGPoint(
            x: annotation.end.x - metrics.unit.x * headLength * 0.62,
            y: annotation.end.y - metrics.unit.y * headLength * 0.62
        )

        let shaft = NSBezierPath()
        shaft.move(to: annotation.start)
        shaft.line(to: shaftEnd)
        shaft.lineWidth = lineWidth
        shaft.lineCapStyle = .round
        shaft.lineJoinStyle = .round
        annotationColor(annotation, alphaMultiplier: alpha).setStroke()
        shaft.stroke()

        let baseCenter = CGPoint(
            x: annotation.end.x - metrics.unit.x * headLength,
            y: annotation.end.y - metrics.unit.y * headLength
        )

        let head = NSBezierPath()
        head.move(to: annotation.end)
        head.line(to: CGPoint(
            x: baseCenter.x + metrics.perpendicular.x * headHalfWidth,
            y: baseCenter.y + metrics.perpendicular.y * headHalfWidth
        ))
        head.line(to: CGPoint(
            x: baseCenter.x - metrics.perpendicular.x * headHalfWidth,
            y: baseCenter.y - metrics.perpendicular.y * headHalfWidth
        ))
        head.close()
        annotationColor(annotation, alphaMultiplier: alpha).setFill()
        head.fill()
    }

    private static func drawNotchedArrow(_ annotation: Annotation, isPreview: Bool) {
        guard let metrics = arrowMetrics(for: annotation) else { return }

        let alpha: CGFloat = isPreview ? 0.55 : 1
        let lineWidth = max(1, annotation.lineWidth)
        guard metrics.length > 14 else {
            drawArrowLine(annotation, isPreview: isPreview)
            return
        }

        let headLength = min(max(24, lineWidth * 5), metrics.length * 0.68)
        let headHalfWidth = max(9, lineWidth * 2.3)
        let tailHalfWidth = max(3, lineWidth * 0.85)
        let notchDepth = min(max(6, lineWidth * 1.5), headLength * 0.42)
        let headBase = CGPoint(
            x: annotation.end.x - metrics.unit.x * headLength,
            y: annotation.end.y - metrics.unit.y * headLength
        )
        let notch = CGPoint(
            x: annotation.start.x + metrics.unit.x * notchDepth,
            y: annotation.start.y + metrics.unit.y * notchDepth
        )

        let path = NSBezierPath()
        path.move(to: CGPoint(
            x: annotation.start.x + metrics.perpendicular.x * tailHalfWidth,
            y: annotation.start.y + metrics.perpendicular.y * tailHalfWidth
        ))
        path.line(to: CGPoint(
            x: headBase.x + metrics.perpendicular.x * headHalfWidth,
            y: headBase.y + metrics.perpendicular.y * headHalfWidth
        ))
        path.line(to: annotation.end)
        path.line(to: CGPoint(
            x: headBase.x - metrics.perpendicular.x * headHalfWidth,
            y: headBase.y - metrics.perpendicular.y * headHalfWidth
        ))
        path.line(to: CGPoint(
            x: annotation.start.x - metrics.perpendicular.x * tailHalfWidth,
            y: annotation.start.y - metrics.perpendicular.y * tailHalfWidth
        ))
        path.line(to: notch)
        path.close()

        annotationColor(annotation, alphaMultiplier: alpha).setFill()
        path.fill()
    }

    private static func arrowMetrics(for annotation: Annotation) -> (length: CGFloat, unit: CGPoint, perpendicular: CGPoint)? {
        let dx = annotation.end.x - annotation.start.x
        let dy = annotation.end.y - annotation.start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return nil }

        let unit = CGPoint(x: dx / length, y: dy / length)
        return (length, unit, CGPoint(x: -unit.y, y: unit.x))
    }

    private static func drawRectangle(_ annotation: Annotation, isPreview: Bool) {
        let path: NSBezierPath
        switch annotation.shapeMode {
        case .rectangle:
            path = NSBezierPath(rect: annotation.rect)
        case .circle:
            path = NSBezierPath(ovalIn: circleRect(for: annotation.rect))
        case .ellipse:
            path = NSBezierPath(ovalIn: annotation.rect)
        }
        path.lineWidth = annotation.lineWidth
        annotationColor(annotation, alphaMultiplier: isPreview ? 0.55 : 1).setStroke()
        path.stroke()
    }

    private static func circleRect(for rect: CGRect) -> CGRect {
        let side = min(rect.width, rect.height)
        return CGRect(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side
        )
    }

    private static func drawText(_ annotation: Annotation, isPreview: Bool) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: annotation.fontSize, weight: .semibold),
            .foregroundColor: annotationColor(annotation, alphaMultiplier: isPreview ? 0.55 : 1),
            .backgroundColor: NSColor.white.withAlphaComponent(isPreview ? 0.45 : 0.72),
            .paragraphStyle: paragraph
        ]

        let rect = annotation.rect.insetBy(dx: -2, dy: -2)
        annotation.text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }

    private static func drawMosaic(_ annotation: Annotation, over baseImage: NSImage, canvasRect: CGRect, isPreview: Bool) {
        let rect = annotation.rect.intersection(canvasRect)
        guard rect.width > 1, rect.height > 1 else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .none

        let blockSize: CGFloat = 12
        let smallSize = CGSize(
            width: max(1, floor(rect.width / blockSize)),
            height: max(1, floor(rect.height / blockSize))
        )

        let smallImage = NSImage(size: smallSize)
        smallImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        baseImage.draw(
            in: CGRect(origin: .zero, size: smallSize),
            from: rect,
            operation: .copy,
            fraction: isPreview ? 0.7 : 1
        )
        smallImage.unlockFocus()

        smallImage.draw(
            in: rect,
            from: CGRect(origin: .zero, size: smallSize),
            operation: .copy,
            fraction: isPreview ? 0.7 : 1
        )

        if annotation.mosaicMode == .bordered {
            annotationColor(annotation, alphaMultiplier: isPreview ? 0.45 : 0.22).setStroke()
            let border = NSBezierPath(rect: rect)
            border.lineWidth = 2
            border.stroke()
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawMagnifier(_ annotation: Annotation, over baseImage: NSImage, canvasRect: CGRect, isPreview: Bool) {
        let lensRect = annotation.rect.intersection(canvasRect)
        guard lensRect.width > 12, lensRect.height > 12 else { return }

        let magnification: CGFloat = 2
        let sourceSize = CGSize(width: lensRect.width / magnification, height: lensRect.height / magnification)
        let sourceRect = CGRect(
            x: lensRect.midX - sourceSize.width / 2,
            y: lensRect.midY - sourceSize.height / 2,
            width: sourceSize.width,
            height: sourceSize.height
        ).intersection(canvasRect)

        NSGraphicsContext.saveGraphicsState()

        let clipPath = NSBezierPath(ovalIn: lensRect)
        clipPath.addClip()
        baseImage.draw(in: lensRect, from: sourceRect, operation: .copy, fraction: isPreview ? 0.72 : 1)

        NSGraphicsContext.restoreGraphicsState()

        let border = NSBezierPath(ovalIn: lensRect)
        border.lineWidth = max(3, annotation.lineWidth)
        annotationColor(annotation, alphaMultiplier: isPreview ? 0.55 : 1).setStroke()
        border.stroke()

        NSColor.white.withAlphaComponent(isPreview ? 0.35 : 0.75).setStroke()
        let inner = NSBezierPath(ovalIn: lensRect.insetBy(dx: 5, dy: 5))
        inner.lineWidth = 1.5
        inner.stroke()
    }

    private static func drawPen(_ annotation: Annotation, isPreview: Bool) {
        let points = annotation.points.isEmpty ? [annotation.start, annotation.end] : annotation.points
        guard let firstPoint = points.first else { return }

        let lineWidth = max(1, annotation.lineWidth)
        let isSinglePoint = points.count == 1 || (points.last.map { $0 == firstPoint } ?? false)
        annotationColor(annotation, alphaMultiplier: isPreview ? 0.55 : 1).setStroke()
        annotationColor(annotation, alphaMultiplier: isPreview ? 0.55 : 1).setFill()

        if isSinglePoint {
            let dotRect = CGRect(
                x: firstPoint.x - lineWidth / 2,
                y: firstPoint.y - lineWidth / 2,
                width: lineWidth,
                height: lineWidth
            )
            NSBezierPath(ovalIn: dotRect).fill()
            return
        }

        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: firstPoint)

        for point in points.dropFirst() {
            path.line(to: point)
        }

        path.stroke()
    }

    private static func drawImagePatch(_ annotation: Annotation, isPreview: Bool) {
        guard let imagePatch = annotation.imagePatch else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = annotation.rect.width >= imagePatch.size.width ? .none : .high
        imagePatch.draw(
            in: annotation.rect,
            from: CGRect(origin: .zero, size: imagePatch.size),
            operation: .copy,
            fraction: isPreview ? 0.72 : 1
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func annotationColor(_ annotation: Annotation, alphaMultiplier: CGFloat) -> NSColor {
        guard let color = annotation.color.usingColorSpace(.deviceRGB) else {
            return annotation.color.withAlphaComponent(clamped(annotation.color.alphaComponent * alphaMultiplier))
        }

        return color.withAlphaComponent(clamped(color.alphaComponent * alphaMultiplier))
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(1, max(0, value))
    }
}
