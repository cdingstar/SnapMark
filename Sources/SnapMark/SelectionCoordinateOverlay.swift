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
        guard let startPoint, let selectionRect else { return }

        let screenRect = window.convertToScreen(selectionRect)
        guard let region = ScreenCaptureRegion(appKitRect: screenRect, screen: screen) else { return }

        let start = screenPoint(for: startPoint, window: window)
        let end = screenPoint(for: currentPoint, window: window)
        drawLabel(
            "\(format(start)) \(format(end))  \(format(region.pixelSize)) px",
            preferredOrigin: CGPoint(x: currentPoint.x + 18, y: currentPoint.y + 18),
            in: bounds
        )
    }

    private static func screenPoint(for localPoint: CGPoint, window: NSWindow) -> CGPoint {
        window.convertToScreen(CGRect(origin: localPoint, size: .zero)).origin
    }

    private static func format(_ point: CGPoint) -> String {
        "(\(Int(point.x.rounded())),\(Int(point.y.rounded())))"
    }

    private static func format(_ size: CGSize) -> String {
        "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    private static func drawLabel(_ text: String, preferredOrigin: CGPoint, in bounds: CGRect) {
        let maxWidth = min(bounds.width - 16, 420)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
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
