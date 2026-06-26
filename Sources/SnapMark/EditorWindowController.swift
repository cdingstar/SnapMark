import AppKit

private enum ZoomPresetMode: CaseIterable {
    case current
    case actualSize
    case bestFit
    case fitIn

    var title: String {
        switch self {
        case .current:
            return "当前"
        case .actualSize:
            return "100%"
        case .bestFit:
            return "Best Fit"
        case .fitIn:
            return "Fit In"
        }
    }
}

final class EditorWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSMenuDelegate {
    private static let minimumToolbarWindowWidth: CGFloat = 1100
    private static let minimumWindowHeight: CGFloat = 360
    private static let imageSizeToolbarWidth: CGFloat = 256
    private static let toolsToolbarWidth: CGFloat = 366
    private static let colorToolbarWidth: CGFloat = 34
    private static let dragCopyToolbarWidth: CGFloat = 28

    var onClose: (() -> Void)?

    private let scrollView = NSScrollView()
    private let canvasView: EditorCanvasView
    private let saveURL: URL
    private var autosaveWorkItem: DispatchWorkItem?
    private var shouldSaveOnClose = true
    private let imagePixelSize: CGSize
    private var toolControl: NSSegmentedControl?
    private var annotationColorWell: NSColorWell?
    private var penSizeMenu: NSMenu?
    private var zoomInfoControl: ZoomInfoSliderView?
    private var fitZoomButton: NSButton?
    private var nextZoomPresetIndex = 1

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
            item.label = "缩放"
            item.paletteLabel = "缩放"
            item.toolTip = "缩放和截图尺寸"

            let zoomControl = ZoomInfoSliderView(
                value: canvasView.zoomScale,
                minValue: EditorCanvasView.minimumZoomScale,
                maxValue: EditorCanvasView.maximumZoomScale
            )
            zoomControl.translatesAutoresizingMaskIntoConstraints = false
            zoomControl.widthAnchor.constraint(equalToConstant: 210).isActive = true
            zoomControl.heightAnchor.constraint(equalToConstant: 28).isActive = true
            zoomControl.onZoomChanged = { [weak self] scale in
                self?.setZoomScaleFromSlider(scale)
            }

            let fitButton = NSButton(title: "", target: self, action: #selector(cycleZoomPreset))
            fitButton.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "适应")
            fitButton.imagePosition = .imageOnly
            fitButton.bezelStyle = .texturedRounded
            fitButton.controlSize = .small
            fitButton.translatesAutoresizingMaskIntoConstraints = false
            fitButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
            fitButton.heightAnchor.constraint(equalToConstant: 24).isActive = true

            let stack = NSStackView(views: [zoomControl, fitButton])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 6
            stack.translatesAutoresizingMaskIntoConstraints = false
            item.view = stack
            lockToolbarItem(item, width: Self.imageSizeToolbarWidth)
            zoomInfoControl = zoomControl
            fitZoomButton = fitButton
            updateZoomUI()
            updateFitZoomTooltip()
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
            control.setWidth(88, forSegment: AnnotationTool.pen.rawValue)
            control.setMenu(makePenSizeMenu(), forSegment: AnnotationTool.pen.rawValue)
            control.setShowsMenuIndicator(true, forSegment: AnnotationTool.pen.rawValue)
            item.view = control
            lockToolbarItem(item, width: Self.toolsToolbarWidth)
            toolControl = control
            updatePenSegmentTitle()
            updateToolOptions()
            return item

        case .color:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "颜色"
            item.paletteLabel = "颜色"
            item.toolTip = "新标注颜色"

            let colorWell = NSColorWell(frame: CGRect(x: 0, y: 0, width: 26, height: 22))
            colorWell.color = canvasView.annotationColor
            colorWell.target = self
            colorWell.action = #selector(changeAnnotationColor)
            colorWell.controlSize = .small
            item.view = colorWell
            lockToolbarItem(item, width: Self.colorToolbarWidth)
            annotationColorWell = colorWell
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
        if tool == .pen, canvasView.currentTool == .pen {
            cyclePenSize()
        }
        canvasView.currentTool = tool
        updateToolOptions()
    }

    @objc private func changeAnnotationColor(_ sender: NSColorWell) {
        canvasView.annotationColor = sender.color
    }

    @objc private func choosePenSize(_ sender: NSMenuItem) {
        guard let size = PenSize(rawValue: sender.tag) else { return }
        canvasView.penSize = size
        canvasView.currentTool = .pen
        toolControl?.selectedSegment = AnnotationTool.pen.rawValue
        updatePenSegmentTitle()
        updateToolOptions()
    }

    private func setZoomScaleFromSlider(_ scale: CGFloat) {
        updateCanvasViewport()
        canvasView.setZoomScale(scale)
        updateZoomUI()
        canvasView.scrollToVisible(canvasView.canvasCenterRect)
    }

    @objc private func cycleZoomPreset() {
        let modes = ZoomPresetMode.allCases
        let mode = modes[nextZoomPresetIndex % modes.count]
        applyZoomPreset(mode)
        nextZoomPresetIndex = (nextZoomPresetIndex + 1) % modes.count
        updateFitZoomTooltip()
    }

    private func applyZoomPreset(_ mode: ZoomPresetMode) {
        updateCanvasViewport()
        switch mode {
        case .current:
            break
        case .actualSize:
            canvasView.setZoomScale(1)
        case .bestFit:
            canvasView.setZoomScale(canvasView.bestFitZoomScale(for: scrollView.contentView.bounds.size))
        case .fitIn:
            canvasView.setZoomScale(canvasView.fitInZoomScale(for: scrollView.contentView.bounds.size))
        }
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
        zoomInfoControl?.update(
            zoomText: Self.formatZoom(canvasView.zoomScale),
            imageSizeText: Self.formatImageSize(imagePixelSize),
            zoomScale: canvasView.zoomScale
        )
    }

    private func updateToolOptions() {
        annotationColorWell?.isEnabled = true
        updatePenSegmentTitle()
        updatePenSizeMenuState()
    }

    private func makePenSizeMenu() -> NSMenu {
        let menu = NSMenu(title: "Pen 大小")
        menu.delegate = self
        for size in PenSize.allCases {
            let item = NSMenuItem(title: "Pen \(size.title)", action: #selector(choosePenSize), keyEquivalent: "")
            item.target = self
            item.tag = size.rawValue
            menu.addItem(item)
        }
        penSizeMenu = menu
        updatePenSizeMenuState()
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu == penSizeMenu {
            updatePenSizeMenuState()
        }
    }

    private func updatePenSegmentTitle() {
        toolControl?.setLabel("Pen \(canvasView.penSize.title)", forSegment: AnnotationTool.pen.rawValue)
    }

    private func updatePenSizeMenuState() {
        penSizeMenu?.items.forEach { item in
            item.state = item.tag == canvasView.penSize.rawValue ? .on : .off
        }
    }

    private func cyclePenSize() {
        let sizes = PenSize.allCases
        guard let index = sizes.firstIndex(of: canvasView.penSize) else { return }
        canvasView.penSize = sizes[(index + 1) % sizes.count]
        updatePenSegmentTitle()
        updatePenSizeMenuState()
    }

    private func updateFitZoomTooltip() {
        let modes = ZoomPresetMode.allCases
        let mode = modes[nextZoomPresetIndex % modes.count]
        fitZoomButton?.toolTip = "缩放模式：\(mode.title)"
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
    static let undo = NSToolbarItem.Identifier("SnapMark.Undo")
    static let copy = NSToolbarItem.Identifier("SnapMark.Copy")
    static let save = NSToolbarItem.Identifier("SnapMark.Save")
    static let dragCopy = NSToolbarItem.Identifier("SnapMark.DragCopy")
}
