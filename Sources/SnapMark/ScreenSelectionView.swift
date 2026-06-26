import AppKit
import CoreGraphics

final class ScreenSelectionView: NSView {
    var onRegionComplete: ((CGRect) -> Void)?
    var onWindowComplete: ((WindowTarget) -> Void)?
    var onCancel: (() -> Void)?

    private let magnifier: SelectionMagnifierRenderer
    private let windowTargets: [WindowTarget]
    private var trackingArea: NSTrackingArea?
    private var hoveredWindow: WindowTarget?
    private var pressedWindow: WindowTarget?
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var isDraggingSelection = false

    init(frame frameRect: NSRect, screenSnapshot: CGImage?, windowTargets: [WindowTarget]) {
        magnifier = SelectionMagnifierRenderer(screenSnapshot: screenSnapshot)
        self.windowTargets = windowTargets
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.24).setFill()
        bounds.fill()

        if !isDraggingSelection {
            drawHoveredWindow()
        }

        if let selectionRect {
            drawSelectionRect(selectionRect)
            drawSizeLabel(for: selectionRect)
        }

        if let currentPoint {
            magnifier.draw(at: currentPoint, in: bounds)
            if let window {
                SelectionCoordinateOverlay.draw(
                    currentPoint: currentPoint,
                    startPoint: isDraggingSelection ? startPoint : nil,
                    selectionRect: isDraggingSelection ? selectionRect : nil,
                    in: bounds,
                    window: window
                )
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))
        currentPoint = point
        hoveredWindow = windowTarget(at: point)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))
        startPoint = point
        currentPoint = point
        hoveredWindow = windowTarget(at: point)
        pressedWindow = hoveredWindow
        isDraggingSelection = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))
        currentPoint = point

        if let startPoint, hypot(point.x - startPoint.x, point.y - startPoint.y) >= 3 {
            isDraggingSelection = true
            hoveredWindow = nil
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))
        currentPoint = point

        if !isDraggingSelection, let target = pressedWindow ?? hoveredWindow {
            onWindowComplete?(target)
            return
        }

        guard let selectionRect, selectionRect.width >= 4, selectionRect.height >= 4 else {
            resetDragState()
            onCancel?()
            return
        }

        onRegionComplete?(selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancelFromKeyboard()
            return
        }

        super.keyDown(with: event)
    }

    func cancelFromKeyboard() {
        resetDragState()
        onCancel?()
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint, isDraggingSelection else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }

    private func resetDragState() {
        startPoint = nil
        pressedWindow = nil
        isDraggingSelection = false
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0, min(bounds.width, point.x)),
            y: max(0, min(bounds.height, point.y))
        )
    }

    private func windowTarget(at localPoint: CGPoint) -> WindowTarget? {
        guard let window else { return nil }
        let appKitPoint = window.convertToScreen(CGRect(origin: localPoint, size: .zero)).origin
        return WindowInspector.windowUnder(appKitPoint: appKitPoint, in: windowTargets)
    }

    private func localRect(for target: WindowTarget) -> CGRect? {
        guard let window else { return nil }
        let windowRect = window.convertFromScreen(target.appKitBounds)
        return convert(windowRect, from: nil)
    }

    private func drawHoveredWindow() {
        guard let hoveredWindow, let rect = localRect(for: hoveredWindow) else { return }
        let visibleRect = rect.intersection(bounds)
        guard !visibleRect.isNull, visibleRect.width > 0, visibleRect.height > 0 else { return }

        NSColor.systemBlue.withAlphaComponent(0.12).setFill()
        visibleRect.fill()

        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(rect: visibleRect)
        border.lineWidth = 3
        border.stroke()

        drawWindowLabel(hoveredWindow.ownerName, near: visibleRect)
    }

    private func drawSelectionRect(_ rect: CGRect) {
        NSColor.white.withAlphaComponent(0.18).setFill()
        rect.fill()

        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()
    }

    private func drawWindowLabel(_ title: String, near rect: CGRect) {
        let text = "\(title)  点击截取窗口 · 拖拽选择区域"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        drawLabel(text, attributes: attributes, preferredOrigin: CGPoint(x: rect.minX, y: rect.maxY + 8))
    }

    private func drawSizeLabel(for rect: CGRect) {
        let scale = max(1, window?.screen?.backingScaleFactor ?? 1)
        let text = "\(Int((rect.width * scale).rounded())) x \(Int((rect.height * scale).rounded())) px"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        drawLabel(text, attributes: attributes, preferredOrigin: CGPoint(x: rect.minX, y: rect.minY - 30))
    }

    private func drawLabel(_ text: String, attributes: [NSAttributedString.Key: Any], preferredOrigin: CGPoint) {
        let size = text.size(withAttributes: attributes)
        var labelRect = CGRect(
            x: preferredOrigin.x,
            y: preferredOrigin.y,
            width: size.width + 16,
            height: size.height + 8
        )

        if labelRect.maxX > bounds.maxX - 8 {
            labelRect.origin.x = max(8, bounds.maxX - labelRect.width - 8)
        }
        if labelRect.minX < 8 {
            labelRect.origin.x = 8
        }
        if labelRect.maxY > bounds.maxY - 8 {
            labelRect.origin.y = bounds.maxY - labelRect.height - 8
        }
        if labelRect.minY < 8 {
            labelRect.origin.y = 8
        }

        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()
        text.draw(
            at: CGPoint(x: labelRect.minX + 8, y: labelRect.minY + 4),
            withAttributes: attributes
        )
    }
}
