import AppKit
import CoreGraphics

struct SelectionMagnifierRenderer {
    let screenSnapshot: CGImage?
    let zoom: CGFloat = 10
    let sourcePixels = 21

    func draw(at point: CGPoint, in bounds: CGRect) {
        guard let screenSnapshot else { return }

        let snapshotWidth = CGFloat(screenSnapshot.width)
        let snapshotHeight = CGFloat(screenSnapshot.height)
        guard bounds.width > 0, bounds.height > 0, snapshotWidth > 0, snapshotHeight > 0 else { return }

        let scaleX = snapshotWidth / bounds.width
        let scaleY = snapshotHeight / bounds.height
        let pixelX = point.x * scaleX
        let pixelY = (bounds.height - point.y) * scaleY
        let sourceSize = CGFloat(sourcePixels)
        let halfSource = sourceSize / 2
        let cropX = max(0, min(snapshotWidth - sourceSize, floor(pixelX - halfSource)))
        let cropY = max(0, min(snapshotHeight - sourceSize, floor(pixelY - halfSource)))
        let cropRect = CGRect(x: cropX, y: cropY, width: sourceSize, height: sourceSize).integral

        guard let crop = screenSnapshot.cropping(to: cropRect) else { return }

        let lensSize = sourceSize * zoom
        let lensRect = magnifierRect(near: point, size: lensSize, in: bounds)

        NSGraphicsContext.saveGraphicsState()
        drawBackground(for: lensRect)

        guard let context = NSGraphicsContext.current else {
            NSGraphicsContext.restoreGraphicsState()
            return
        }

        context.imageInterpolation = .none
        let image = NSImage(cgImage: crop, size: CGSize(width: crop.width, height: crop.height))
        image.draw(
            in: lensRect,
            from: CGRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )

        drawPixelGrid(in: lensRect, sourcePixels: sourcePixels)
        drawCrosshair(in: lensRect)

        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(rect: lensRect)
        border.lineWidth = 2
        border.stroke()

        NSGraphicsContext.restoreGraphicsState()
    }

    private func magnifierRect(near point: CGPoint, size: CGFloat, in bounds: CGRect) -> CGRect {
        let offset: CGFloat = 18
        let insetBounds = bounds.insetBy(dx: 8, dy: 8)
        let candidates = [
            CGPoint(x: point.x + offset, y: point.y - offset - size),
            CGPoint(x: point.x + offset, y: point.y + offset),
            CGPoint(x: point.x - offset - size, y: point.y - offset - size),
            CGPoint(x: point.x - offset - size, y: point.y + offset)
        ]

        for origin in candidates {
            let rect = CGRect(origin: origin, size: CGSize(width: size, height: size))
            if insetBounds.contains(rect) {
                return rect
            }
        }

        return CGRect(
            x: max(8, min(bounds.width - size - 8, point.x + offset)),
            y: max(8, min(bounds.height - size - 8, point.y - offset - size)),
            width: size,
            height: size
        )
    }

    private func drawBackground(for rect: CGRect) {
        NSColor.black.withAlphaComponent(0.34).setFill()
        NSBezierPath(rect: rect.offsetBy(dx: 3, dy: -3)).fill()

        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: rect.insetBy(dx: -2, dy: -2)).fill()
    }

    private func drawPixelGrid(in rect: CGRect, sourcePixels: Int) {
        guard sourcePixels > 0 else { return }

        let pixelSize = rect.width / CGFloat(sourcePixels)
        NSColor.black.withAlphaComponent(0.18).setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 0.5

        for index in 1..<sourcePixels {
            let offset = CGFloat(index) * pixelSize
            grid.move(to: CGPoint(x: rect.minX + offset, y: rect.minY))
            grid.line(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
            grid.move(to: CGPoint(x: rect.minX, y: rect.minY + offset))
            grid.line(to: CGPoint(x: rect.maxX, y: rect.minY + offset))
        }

        grid.stroke()
    }

    private func drawCrosshair(in rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY)

        let outline = NSBezierPath()
        outline.lineWidth = 3
        outline.move(to: CGPoint(x: center.x, y: rect.minY))
        outline.line(to: CGPoint(x: center.x, y: rect.maxY))
        outline.move(to: CGPoint(x: rect.minX, y: center.y))
        outline.line(to: CGPoint(x: rect.maxX, y: center.y))
        NSColor.white.withAlphaComponent(0.82).setStroke()
        outline.stroke()

        let crosshair = NSBezierPath()
        crosshair.lineWidth = 1
        crosshair.move(to: CGPoint(x: center.x, y: rect.minY))
        crosshair.line(to: CGPoint(x: center.x, y: rect.maxY))
        crosshair.move(to: CGPoint(x: rect.minX, y: center.y))
        crosshair.line(to: CGPoint(x: rect.maxX, y: center.y))
        NSColor.systemRed.setStroke()
        crosshair.stroke()

        NSColor.systemRed.withAlphaComponent(0.18).setFill()
        NSBezierPath(rect: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)).fill()
    }
}
