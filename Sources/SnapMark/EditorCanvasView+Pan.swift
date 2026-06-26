import AppKit

extension EditorCanvasView {
    func beginPan(with event: NSEvent) {
        guard let clipView = enclosingScrollView?.contentView else { return }
        panStartInWindow = event.locationInWindow
        panStartBoundsOrigin = clipView.bounds.origin
        NSCursor.openHand.set()
    }

    func updatePan(with event: NSEvent) {
        guard
            let clipView = enclosingScrollView?.contentView,
            let panStartInWindow,
            let panStartBoundsOrigin
        else { return }

        let delta = CGPoint(
            x: event.locationInWindow.x - panStartInWindow.x,
            y: event.locationInWindow.y - panStartInWindow.y
        )
        let maxOrigin = CGPoint(
            x: max(0, bounds.width - clipView.bounds.width),
            y: max(0, bounds.height - clipView.bounds.height)
        )
        let nextOrigin = CGPoint(
            x: max(0, min(maxOrigin.x, panStartBoundsOrigin.x - delta.x)),
            y: max(0, min(maxOrigin.y, panStartBoundsOrigin.y - delta.y))
        )

        clipView.scroll(to: nextOrigin)
        enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    func endPan() {
        panStartInWindow = nil
        panStartBoundsOrigin = nil
        if currentTool == .hand && handMode == .pan {
            NSCursor.openHand.set()
        } else if currentTool == .hand {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}
