import AppKit
import CoreGraphics

struct SelectionMagnifierRenderer {
    let screenSnapshot: CGImage?
    let zoom: CGFloat = 5
    let sourcePixels = 41

    func draw(at point: CGPoint, in bounds: CGRect) {
        guard let screenSnapshot else { return }

        guard
            let geometry = SelectionMagnifierGeometry.make(
                focus: point,
                in: bounds,
                snapshotSize: CGSize(width: screenSnapshot.width, height: screenSnapshot.height),
                sourcePixels: sourcePixels,
                zoom: zoom
            ),
            let crop = screenSnapshot.cropping(to: geometry.cropRect)
        else {
            return
        }

        let lensSize = geometry.lensSize
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

        drawPixelGrid(in: lensRect, sourcePixels: geometry.gridPixels)
        drawCrosshair(in: lensRect, focusUnitPoint: geometry.focusUnitPoint)

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

    private func drawCrosshair(in rect: CGRect, focusUnitPoint: CGPoint) {
        let center = CGPoint(
            x: rect.minX + rect.width * focusUnitPoint.x,
            y: rect.minY + rect.height * focusUnitPoint.y
        )

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
