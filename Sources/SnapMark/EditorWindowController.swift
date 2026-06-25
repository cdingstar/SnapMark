import AppKit

final class EditorWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    var onClose: (() -> Void)?

    private let canvasView: EditorCanvasView
    private let saveURL: URL
    private var autosaveWorkItem: DispatchWorkItem?
    private var shouldSaveOnClose = true
    private var toolControl: NSSegmentedControl?

    init(image: NSImage) {
        canvasView = EditorCanvasView(image: image)
        saveURL = AutoSaveStore.newCaptureURL()

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = canvasView

        let contentSize = EditorWindowController.preferredWindowSize(for: image.snapMarkPixelSize)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SnapMark"
        window.minSize = CGSize(width: 560, height: 360)
        window.contentView = scrollView

        super.init(window: window)

        window.delegate = self
        setupToolbar()
        canvasView.onAnnotationsChanged = { [weak self] in
            self?.scheduleAutosave()
        }
        canvasView.onResetRequested = { [weak self] in
            self?.resetAndClose()
        }
        try? AutoSaveStore.save(image, to: saveURL)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
    }

    func windowWillClose(_ notification: Notification) {
        autosaveWorkItem?.cancel()
        if shouldSaveOnClose {
            try? AutoSaveStore.save(canvasView.renderedImage(), to: saveURL)
        }
        onClose?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            resetAndClose()
            return
        }

        super.keyDown(with: event)
    }

    func resetAndClose() {
        autosaveWorkItem?.cancel()
        shouldSaveOnClose = false
        close()
    }

    private static func preferredWindowSize(for imageSize: CGSize) -> CGSize {
        let visibleFrame = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
        let maxWidth = min(1180, visibleFrame.width - 120)
        let maxHeight = min(820, visibleFrame.height - 120)
        return CGSize(
            width: max(560, min(maxWidth, imageSize.width + 20)),
            height: max(360, min(maxHeight, imageSize.height + 80))
        )
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "SnapMarkToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .tools,
            .flexibleSpace,
            .undo,
            .copy,
            .save,
            .dragCopy
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .tools:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "工具"

            let control = NSSegmentedControl(
                labels: AnnotationTool.allCases.map(\.title),
                trackingMode: .selectOne,
                target: self,
                action: #selector(changeTool)
            )
            control.segmentStyle = .texturedRounded
            control.selectedSegment = canvasView.currentTool.rawValue
            control.setWidth(78, forSegment: AnnotationTool.arrow.rawValue)
            control.setWidth(70, forSegment: AnnotationTool.rectangle.rawValue)
            control.setWidth(68, forSegment: AnnotationTool.text.rawValue)
            control.setWidth(86, forSegment: AnnotationTool.mosaic.rawValue)
            control.setWidth(70, forSegment: AnnotationTool.magnifier.rawValue)
            item.view = control
            toolControl = control
            return item

        case .undo:
            return toolbarButton(
                identifier: itemIdentifier,
                label: "撤销",
                symbolName: "arrow.uturn.backward",
                action: #selector(undo)
            )

        case .copy:
            return toolbarButton(
                identifier: itemIdentifier,
                label: "复制",
                symbolName: "doc.on.doc",
                action: #selector(copyImage)
            )

        case .save:
            return toolbarButton(
                identifier: itemIdentifier,
                label: "保存",
                symbolName: "square.and.arrow.down",
                action: #selector(saveImage)
            )

        case .dragCopy:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "拖拽复制"
            let button = DragExportButton(title: "拖拽复制", target: nil, action: nil)
            button.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "拖拽复制")
            button.imagePosition = .imageLeading
            button.bezelStyle = .texturedRounded
            button.imageProvider = { [weak self] in self?.canvasView.renderedImage() }
            item.view = button
            return item

        default:
            return nil
        }
    }

    @objc private func changeTool(_ sender: NSSegmentedControl) {
        guard let tool = AnnotationTool(rawValue: sender.selectedSegment) else { return }
        canvasView.currentTool = tool
    }

    @objc private func undo() {
        canvasView.undoLastAnnotation()
    }

    @objc private func copyImage() {
        guard let data = canvasView.renderedImage().pngData else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .png)
    }

    @objc private func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = saveURL.lastPathComponent
        panel.directoryURL = saveURL.deletingLastPathComponent()

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try AutoSaveStore.save(self.canvasView.renderedImage(), to: url)
            } catch {
                self.presentSaveError(error)
            }
        }
    }

    private func scheduleAutosave() {
        autosaveWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                try AutoSaveStore.save(self.canvasView.renderedImage(), to: self.saveURL)
            } catch {
                self.presentSaveError(error)
            }
        }
        autosaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: workItem)
    }

    private func presentSaveError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "保存失败"
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func toolbarButton(identifier: NSToolbarItem.Identifier, label: String, symbolName: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        item.target = self
        item.action = action
        return item
    }
}

private extension NSToolbarItem.Identifier {
    static let tools = NSToolbarItem.Identifier("SnapMark.Tools")
    static let undo = NSToolbarItem.Identifier("SnapMark.Undo")
    static let copy = NSToolbarItem.Identifier("SnapMark.Copy")
    static let save = NSToolbarItem.Identifier("SnapMark.Save")
    static let dragCopy = NSToolbarItem.Identifier("SnapMark.DragCopy")
}
