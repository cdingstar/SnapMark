import AppKit

final class DragExportButton: NSButton, NSDraggingSource {
    var imageProvider: (() -> NSImage?)?

    override func mouseDragged(with event: NSEvent) {
        guard
            let image = imageProvider?(),
            let url = AutoSaveStore.writeTemporaryDragImage(image)
        else {
            return
        }

        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
