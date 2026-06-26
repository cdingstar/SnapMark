import AppKit

final class ScreenSelectionWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if ExitShortcut.matches(event), let selectionView = contentView as? ScreenSelectionView {
            selectionView.cancelFromKeyboard()
            return
        }

        super.keyDown(with: event)
    }
}
