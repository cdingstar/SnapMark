import AppKit

struct SelectionCoordinateOverlay {
    static func draw(
        currentPoint: CGPoint,
        startPoint: CGPoint?,
        selectionRect: CGRect?,
        in bounds: CGRect,
        window: NSWindow
    ) {
        guard let screen = window.screen else { return }

        let current = coordinateInfo(for: currentPoint, window: window, screen: screen)
        var lines = [
            "zoom 5x / source 41px",
            "cursor local \(format(current.localPoint)) screen \(format(current.screenPoint)) capture \(format(current.capturePoint)) px \(format(current.pixelPoint))"
        ]

        if let startPoint, let selectionRect {
            let start = coordinateInfo(for: startPoint, window: window, screen: screen)
            lines = [
                "zoom 5x / source 41px",
                "start  local \(format(start.localPoint)) screen \(format(start.screenPoint)) capture \(format(start.capturePoint)) px \(format(start.pixelPoint))",
                "end    local \(format(current.localPoint)) screen \(format(current.screenPoint)) capture \(format(current.capturePoint)) px \(format(current.pixelPoint))"
            ]

            let screenRect = window.convertToScreen(selectionRect)
            if let region = ScreenCaptureRegion(appKitRect: screenRect, screen: screen) {
                lines.append("region capture \(format(region.coreGraphicsRect.origin)) \(format(region.coreGraphicsRect.size)) pixels \(format(region.pixelSize))")
            }
        }

        drawMultilineLabel(
            lines.joined(separator: "\n"),
            preferredOrigin: CGPoint(x: currentPoint.x + 18, y: currentPoint.y + 18),
            in: bounds
        )
    }

    private static func coordinateInfo(for localPoint: CGPoint, window: NSWindow, screen: NSScreen) -> SelectionCoordinateInfo {
        let screenPoint = window.convertToScreen(CGRect(origin: localPoint, size: .zero)).origin
        return SelectionCoordinateInfo(
            localPoint: localPoint,
            screenPoint: screenPoint,
            capturePoint: ScreenCaptureRegion.coreGraphicsPoint(from: screenPoint, on: screen),
            pixelPoint: ScreenCaptureRegion.backingPixelPoint(from: screenPoint, on: screen)
        )
    }

    private static func format(_ point: CGPoint) -> String {
        "(\(Int(point.x.rounded())),\(Int(point.y.rounded())))"
    }

    private static func format(_ size: CGSize) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    private static func drawMultilineLabel(_ text: String, preferredOrigin: CGPoint, in bounds: CGRect) {
        let maxWidth = min(bounds.width - 16, 640)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let textRect = NSString(string: text).boundingRect(
            with: CGSize(width: maxWidth - 16, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        var labelRect = CGRect(
            x: preferredOrigin.x,
            y: preferredOrigin.y,
            width: min(maxWidth, ceil(textRect.width) + 16),
            height: ceil(textRect.height) + 12
        )

        if labelRect.maxX > bounds.maxX - 8 {
            labelRect.origin.x = max(8, bounds.maxX - labelRect.width - 8)
        }
        if labelRect.maxY > bounds.maxY - 8 {
            labelRect.origin.y = max(8, preferredOrigin.y - labelRect.height - 36)
        }
        if labelRect.minX < 8 {
            labelRect.origin.x = 8
        }
        if labelRect.minY < 8 {
            labelRect.origin.y = 8
        }

        NSColor.black.withAlphaComponent(0.74).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()
        NSString(string: text).draw(
            with: labelRect.insetBy(dx: 8, dy: 6),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
    }
}

private struct SelectionCoordinateInfo {
    let localPoint: CGPoint
    let screenPoint: CGPoint
    let capturePoint: CGPoint
    let pixelPoint: CGPoint
}
