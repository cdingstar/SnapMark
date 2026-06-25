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
            }
        }
    }

    private static func drawArrow(_ annotation: Annotation, isPreview: Bool) {
        let path = NSBezierPath()
        path.move(to: annotation.start)
        path.line(to: annotation.end)
        path.lineWidth = annotation.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        annotation.color.withAlphaComponent(isPreview ? 0.55 : 1).setStroke()
        path.stroke()

        let angle = atan2(annotation.end.y - annotation.start.y, annotation.end.x - annotation.start.x)
        let headLength: CGFloat = 18
        let spread: CGFloat = .pi / 7

        let point1 = CGPoint(
            x: annotation.end.x - headLength * cos(angle - spread),
            y: annotation.end.y - headLength * sin(angle - spread)
        )
        let point2 = CGPoint(
            x: annotation.end.x - headLength * cos(angle + spread),
            y: annotation.end.y - headLength * sin(angle + spread)
        )

        let head = NSBezierPath()
        head.move(to: annotation.end)
        head.line(to: point1)
        head.move(to: annotation.end)
        head.line(to: point2)
        head.lineWidth = annotation.lineWidth
        head.lineCapStyle = .round
        head.stroke()
    }

    private static func drawRectangle(_ annotation: Annotation, isPreview: Bool) {
        let path = NSBezierPath(rect: annotation.rect)
        path.lineWidth = annotation.lineWidth
        annotation.color.withAlphaComponent(isPreview ? 0.55 : 1).setStroke()
        path.stroke()
    }

    private static func drawText(_ annotation: Annotation, isPreview: Bool) {
        let fontSize = max(18, min(44, annotation.rect.height * 0.65))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: annotation.color.withAlphaComponent(isPreview ? 0.55 : 1),
            .backgroundColor: NSColor.white.withAlphaComponent(isPreview ? 0.45 : 0.72)
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

        annotation.color.withAlphaComponent(isPreview ? 0.45 : 0.22).setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 2
        border.stroke()

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
        annotation.color.withAlphaComponent(isPreview ? 0.55 : 1).setStroke()
        border.stroke()

        NSColor.white.withAlphaComponent(isPreview ? 0.35 : 0.75).setStroke()
        let inner = NSBezierPath(ovalIn: lensRect.insetBy(dx: 5, dy: 5))
        inner.lineWidth = 1.5
        inner.stroke()
    }
}
