import CoreGraphics

struct SelectionMagnifierGeometry {
    let cropRect: CGRect
    let focusUnitPoint: CGPoint
    let zoom: CGFloat

    var lensSize: CGFloat {
        cropRect.width * zoom
    }

    var gridPixels: Int {
        max(1, Int(cropRect.width.rounded()))
    }

    static func make(
        focus point: CGPoint,
        in bounds: CGRect,
        snapshotSize: CGSize,
        sourcePixels: Int,
        zoom: CGFloat
    ) -> SelectionMagnifierGeometry? {
        guard bounds.width > 0, bounds.height > 0, snapshotSize.width > 0, snapshotSize.height > 0 else {
            return nil
        }

        let snapshotWidth = floor(snapshotSize.width)
        let snapshotHeight = floor(snapshotSize.height)
        let cropWidth = min(CGFloat(sourcePixels), snapshotWidth)
        let cropHeight = min(CGFloat(sourcePixels), snapshotHeight)
        guard cropWidth >= 1, cropHeight >= 1 else { return nil }

        let scaleX = snapshotWidth / bounds.width
        let scaleY = snapshotHeight / bounds.height
        let focusX = clamped(floor(point.x * scaleX), lower: 0, upper: snapshotWidth - 1)
        let focusY = clamped(floor((bounds.height - point.y) * scaleY), lower: 0, upper: snapshotHeight - 1)
        let radius = CGFloat(sourcePixels / 2)
        let cropX = clamped(focusX - radius, lower: 0, upper: snapshotWidth - cropWidth)
        let cropY = clamped(focusY - radius, lower: 0, upper: snapshotHeight - cropHeight)
        let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight).integral

        let focusUnitPoint = CGPoint(
            x: (focusX - cropRect.minX + 0.5) / cropRect.width,
            y: 1 - ((focusY - cropRect.minY + 0.5) / cropRect.height)
        )

        return SelectionMagnifierGeometry(cropRect: cropRect, focusUnitPoint: focusUnitPoint, zoom: zoom)
    }

    private static func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        max(lower, min(upper, value))
    }
}
