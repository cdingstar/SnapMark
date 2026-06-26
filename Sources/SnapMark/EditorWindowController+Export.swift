import AppKit
import UniformTypeIdentifiers

extension EditorWindowController {
    @objc func undo() {
        canvasView.undoLastAnnotation()
    }

    @objc func copyImage() {
        guard let data = canvasView.renderedImage().pngData else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .png)
    }

    @objc func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = currentSaveURL.lastPathComponent
        panel.directoryURL = currentSaveURL.deletingLastPathComponent()

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try AutoSaveStore.save(self.canvasView.renderedImage(), to: url)
            } catch {
                self.presentSaveError(error)
            }
        }
    }

    @objc func shareImage(_ sender: NSButton) {
        guard let url = AutoSaveStore.writeTemporaryImage(canvasView.renderedImage()) else {
            presentSaveError(CocoaError(.fileWriteUnknown))
            return
        }

        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    func handleAnnotationsChanged() {
        markUserEdits()
        scheduleAutosave()
    }

    func markUserEdits() {
        guard !hasUserEdits else { return }
        hasUserEdits = true
        editedSaveURL = AutoSaveStore.newCaptureURL()
    }

    func editedAutoSaveURL() -> URL {
        if let editedSaveURL {
            return editedSaveURL
        }

        let url = AutoSaveStore.newCaptureURL()
        editedSaveURL = url
        return url
    }

    func saveEditedImageIfNeeded() {
        guard hasUserEdits else { return }
        try? AutoSaveStore.save(canvasView.renderedImage(), to: editedAutoSaveURL())
    }

    func scheduleAutosave() {
        autosaveWorkItem?.cancel()
        let targetURL = editedAutoSaveURL()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                try AutoSaveStore.save(self.canvasView.renderedImage(), to: targetURL)
            } catch {
                self.presentSaveError(error)
            }
        }
        autosaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: workItem)
    }

    func releaseWindowResources() {
        guard !didReleaseWindowResources else { return }
        didReleaseWindowResources = true

        NotificationCenter.default.removeObserver(
            self,
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        canvasView.onAnnotationsChanged = nil
        canvasView.onResetRequested = nil
        scrollView.documentView = nil
        window?.toolbar = nil
        window?.delegate = nil
    }

    func presentSaveError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = L10n.text(.saveFailed)
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
