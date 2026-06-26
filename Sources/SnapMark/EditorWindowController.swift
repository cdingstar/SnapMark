import AppKit

final class EditorWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private static let minimumToolbarWindowWidth: CGFloat = 1210
    private static let minimumWindowHeight: CGFloat = 360
    private static let imageSizeToolbarWidth: CGFloat = 220
    private static let toolsToolbarWidth: CGFloat = 354
    private static let colorToolbarWidth: CGFloat = 48
    private static let eraserSizeToolbarWidth: CGFloat = 84
    private static let dragCopyToolbarWidth: CGFloat = 28

    var onClose: (() -> Void)?

    private let scrollView = NSScrollView()
    private let canvasView: EditorCanvasView
    private let saveURL: URL
    private var autosaveWorkItem: DispatchWorkItem?
    private var shouldSaveOnClose = true
    private let imagePixelSize: CGSize
    private let imageSizeLabel = NSTextField(labelWithString: "")
    private let zoomInfoLabel = NSTextField(labelWithString: "")
    private var toolControl: NSSegmentedControl?
    private var annotationColorWell: NSColorWell?
    private var eraserSizeControl: NSSegmentedControl?
    private var zoomSlider: NSSlider?

    init(image: NSImage) {
        imagePixelSize = image.snapMarkPixelSize
        canvasView = EditorCanvasView(image: image)
        saveURL = AutoSaveStore.newCaptureURL()

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = canvasView

        let contentSize = EditorWindowController.preferredWindowSize(for: imagePixelSize)
        canvasView.updateViewportSize(contentSize)
        canvasView.setZoomScale(canvasView.fitZoomScale(for: contentSize))

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SnapMark"
        window.minSize = Self.minimumWindowSize()
        window.contentView = scrollView

        super.init(window: window)

        window.delegate = self
        setupToolbar()
        updateZoomUI()
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        updateCanvasViewport()
        canvasView.scrollToVisible(canvasView.canvasCenterRect)
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
        let maxWidth = min(1240, visibleFrame.width - 80)
        let maxHeight = min(820, visibleFrame.height - 120)
        let minimumWidth = min(Self.minimumToolbarWindowWidth, maxWidth)
        return CGSize(
            width: max(minimumWidth, min(maxWidth, imageSize.width + 20)),
            height: max(Self.minimumWindowHeight, min(maxHeight, imageSize.height + 80))
        )
    }

    private static func minimumWindowSize() -> CGSize {
        let visibleWidth = NSScreen.main?.visibleFrame.width ?? 1280
        let width = min(Self.minimumToolbarWindowWidth, max(560, visibleWidth - 80))
        return CGSize(width: width, height: Self.minimumWindowHeight)
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "SnapMarkToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .small
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
        if #available(macOS 11.0, *) {
            window?.toolbarStyle = .unifiedCompact
        }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .imageSize,
            .flexibleSpace,
            .tools,
            .color,
            .eraserSize,
            .fitZoom,
            .undo,
            .copy,
            .save,
            .dragCopy
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .imageSize:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "尺寸"
            item.paletteLabel = "尺寸"
            item.toolTip = "截图尺寸"
            zoomInfoLabel.stringValue = Self.formatZoom(canvasView.zoomScale)
            zoomInfoLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            zoomInfoLabel.textColor = .secondaryLabelColor
            zoomInfoLabel.alignment = .left
            zoomInfoLabel.setContentHuggingPriority(.required, for: .horizontal)
            zoomInfoLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

            imageSizeLabel.stringValue = Self.formatImageSize(imagePixelSize)
            imageSizeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            imageSizeLabel.textColor = .tertiaryLabelColor
            imageSizeLabel.alignment = .left

            let slider = NSSlider(
                value: Double(canvasView.zoomScale),
                minValue: Double(EditorCanvasView.minimumZoomScale),
                maxValue: Double(EditorCanvasView.maximumZoomScale),
                target: self,
                action: #selector(changeZoom)
            )
            slider.controlSize = .small
            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.widthAnchor.constraint(equalToConstant: 104).isActive = true

            let infoStack = NSStackView(views: [zoomInfoLabel, imageSizeLabel])
            infoStack.orientation = .vertical
            infoStack.alignment = .leading
            infoStack.spacing = 0

            let stack = NSStackView(views: [infoStack, slider])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            item.view = stack
            lockToolbarItem(item, width: Self.imageSizeToolbarWidth)
            zoomSlider = slider
            return item

        case .tools:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "工具"

            let control = NSSegmentedControl(
                labels: AnnotationTool.allCases.map(\.title),
                trackingMode: .selectOne,
                target: self,
                action: #selector(changeTool)
            )
            control.controlSize = .small
            control.segmentStyle = .texturedRounded
            control.selectedSegment = canvasView.currentTool.rawValue
            control.setWidth(52, forSegment: AnnotationTool.arrow.rawValue)
            control.setWidth(52, forSegment: AnnotationTool.rectangle.rawValue)
            control.setWidth(48, forSegment: AnnotationTool.text.rawValue)
            control.setWidth(62, forSegment: AnnotationTool.mosaic.rawValue)
            control.setWidth(62, forSegment: AnnotationTool.magnifier.rawValue)
            control.setWidth(68, forSegment: AnnotationTool.eraser.rawValue)
            item.view = control
            lockToolbarItem(item, width: Self.toolsToolbarWidth)
            toolControl = control
            updateToolOptions()
            return item

        case .color:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "颜色"
            item.paletteLabel = "颜色"
            item.toolTip = "新标注颜色"

            let colorWell = NSColorWell(frame: CGRect(x: 0, y: 0, width: 34, height: 22))
            colorWell.color = canvasView.annotationColor
            colorWell.target = self
            colorWell.action = #selector(changeAnnotationColor)
            colorWell.controlSize = .small
            item.view = colorWell
            lockToolbarItem(item, width: Self.colorToolbarWidth)
            annotationColorWell = colorWell
            return item

        case .eraserSize:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "擦除大小"
            item.paletteLabel = "擦除大小"
            item.toolTip = "擦除大小"

            let control = NSSegmentedControl(
                labels: EraserSize.allCases.map(\.title),
                trackingMode: .selectOne,
                target: self,
                action: #selector(changeEraserSize)
            )
            control.controlSize = .small
            control.segmentStyle = .texturedRounded
            control.selectedSegment = canvasView.eraserSize.rawValue
            EraserSize.allCases.forEach { size in
                control.setWidth(24, forSegment: size.rawValue)
            }
            item.view = control
            lockToolbarItem(item, width: Self.eraserSizeToolbarWidth)
            eraserSizeControl = control
            updateToolOptions()
            return item

        case .fitZoom:
            return toolbarButton(
                identifier: itemIdentifier,
                label: "适应",
                symbolName: "arrow.up.left.and.arrow.down.right",
                action: #selector(fitZoom)
            )

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
            item.paletteLabel = "拖拽复制"
            item.toolTip = "拖拽复制"
            let button = DragExportButton(title: "", target: nil, action: nil)
            button.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "拖拽复制")
            button.imagePosition = .imageOnly
            button.bezelStyle = .texturedRounded
            button.controlSize = .small
            button.toolTip = "拖拽复制"
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
            button.imageProvider = { [weak self] in self?.canvasView.renderedImage() }
            item.view = button
            lockToolbarItem(item, width: Self.dragCopyToolbarWidth)
            return item

        default:
            return nil
        }
    }

    @objc private func changeTool(_ sender: NSSegmentedControl) {
        guard let tool = AnnotationTool(rawValue: sender.selectedSegment) else { return }
        canvasView.currentTool = tool
        updateToolOptions()
    }

    @objc private func changeAnnotationColor(_ sender: NSColorWell) {
        canvasView.annotationColor = sender.color
    }

    @objc private func changeEraserSize(_ sender: NSSegmentedControl) {
        guard let size = EraserSize(rawValue: sender.selectedSegment) else { return }
        canvasView.eraserSize = size
    }

    @objc private func fitZoom() {
        updateCanvasViewport()
        canvasView.setZoomScale(canvasView.fitZoomScale(for: scrollView.contentView.bounds.size))
        updateZoomUI()
        canvasView.scrollToVisible(canvasView.canvasCenterRect)
    }

    @objc private func changeZoom(_ sender: NSSlider) {
        updateCanvasViewport()
        canvasView.setZoomScale(CGFloat(sender.doubleValue))
        updateZoomUI()
        canvasView.scrollToVisible(canvasView.canvasCenterRect)
    }

    @objc private func scrollViewBoundsDidChange(_ notification: Notification) {
        updateCanvasViewport()
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

    private func updateCanvasViewport() {
        canvasView.updateViewportSize(scrollView.contentView.bounds.size)
    }

    private func updateZoomUI() {
        zoomSlider?.doubleValue = Double(canvasView.zoomScale)
        zoomInfoLabel.stringValue = Self.formatZoom(canvasView.zoomScale)
    }

    private func updateToolOptions() {
        eraserSizeControl?.isEnabled = canvasView.currentTool == .eraser
        annotationColorWell?.isEnabled = canvasView.currentTool != .eraser
    }

    private static func formatImageSize(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) x \(Int(size.height.rounded())) px"
    }

    private static func formatZoom(_ scale: CGFloat) -> String {
        "\(Int((scale * 100).rounded()))%"
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

    private func lockToolbarItem(_ item: NSToolbarItem, width: CGFloat) {
        guard let view = item.view else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
    }
}

private extension NSToolbarItem.Identifier {
    static let imageSize = NSToolbarItem.Identifier("SnapMark.ImageSize")
    static let tools = NSToolbarItem.Identifier("SnapMark.Tools")
    static let color = NSToolbarItem.Identifier("SnapMark.Color")
    static let eraserSize = NSToolbarItem.Identifier("SnapMark.EraserSize")
    static let fitZoom = NSToolbarItem.Identifier("SnapMark.FitZoom")
    static let undo = NSToolbarItem.Identifier("SnapMark.Undo")
    static let copy = NSToolbarItem.Identifier("SnapMark.Copy")
    static let save = NSToolbarItem.Identifier("SnapMark.Save")
    static let dragCopy = NSToolbarItem.Identifier("SnapMark.DragCopy")
}
