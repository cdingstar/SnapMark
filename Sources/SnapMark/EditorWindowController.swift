import AppKit

final class EditorWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSMenuDelegate {
    private static let minimumToolbarWindowWidth: CGFloat = 1140
    private static let minimumWindowHeight: CGFloat = 360
    private static let imageSizeToolbarWidth: CGFloat = 256
    private static let toolsToolbarWidth: CGFloat = 260
    private static let colorToolbarWidth: CGFloat = 66
    private static let actionsToolbarWidth: CGFloat = 136
    private static let toolbarSeparatorWidth: CGFloat = 14
    static let zoomScaleTolerance: CGFloat = 0.0005

    var onClose: (() -> Void)?

    let scrollView = NSScrollView()
    let canvasView: EditorCanvasView
    let originalSaveURL: URL
    var editedSaveURL: URL?
    var autosaveWorkItem: DispatchWorkItem?
    var hasUserEdits = false
    var didReleaseWindowResources = false
    let imagePixelSize: CGSize
    var toolControl: NSSegmentedControl?
    var annotationColorControl: AnnotationColorPickerView?
    var penSizeMenu: NSMenu?
    var zoomInfoControl: ZoomInfoSliderView?
    var fitZoomButton: NSButton?
    private var shouldApplyInitialViewportFit = true
    var currentSaveURL: URL {
        editedSaveURL ?? originalSaveURL
    }

    init(image: NSImage) {
        imagePixelSize = image.snapMarkPixelSize
        canvasView = EditorCanvasView(image: image)
        originalSaveURL = AutoSaveStore.newCaptureURL()

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
            self?.handleAnnotationsChanged()
        }
        canvasView.onResetRequested = { [weak self] in
            self?.closeForExit()
        }
        try? AutoSaveStore.save(image, to: originalSaveURL)
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
        if shouldApplyInitialViewportFit {
            canvasView.setZoomScale(canvasView.fitZoomScale(for: scrollView.contentView.bounds.size))
            updateZoomUI()
            shouldApplyInitialViewportFit = false
        }
        canvasView.scrollToVisible(canvasView.canvasCenterRect)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
    }

    func windowWillClose(_ notification: Notification) {
        autosaveWorkItem?.cancel()
        autosaveWorkItem = nil
        saveEditedImageIfNeeded()
        releaseWindowResources()
        onClose?()
    }

    override func keyDown(with event: NSEvent) {
        if ExitShortcut.matches(event) {
            closeForExit()
            return
        }

        super.keyDown(with: event)
    }

    func closeForExit() {
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
        window?.titlebarAppearsTransparent = false
        if #available(macOS 11.0, *) {
            window?.toolbarStyle = .unifiedCompact
            window?.titlebarSeparatorStyle = .line
        }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .imageSize,
            .flexibleSpace,
            .toolbarGroupSeparatorOne,
            .tools,
            .toolbarGroupSeparatorTwo,
            .color,
            .toolbarGroupSeparatorThree,
            .actions
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .imageSize:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = L10n.text(.toolbarZoom)
            item.paletteLabel = L10n.text(.toolbarZoom)
            item.toolTip = L10n.text(.toolbarZoomTooltip)

            let zoomControl = ZoomInfoSliderView(
                value: canvasView.zoomScale,
                minValue: EditorCanvasView.minimumZoomScale,
                maxValue: EditorCanvasView.maximumZoomScale
            )
            zoomControl.translatesAutoresizingMaskIntoConstraints = false
            zoomControl.toolTip = L10n.text(.toolbarZoomTooltip)
            zoomControl.widthAnchor.constraint(equalToConstant: 210).isActive = true
            zoomControl.heightAnchor.constraint(equalToConstant: 28).isActive = true
            zoomControl.onZoomChanged = { [weak self] scale in
                self?.setZoomScaleFromSlider(scale)
            }

            let fitButton = NSButton(title: "", target: self, action: #selector(cycleZoomPreset))
            fitButton.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: L10n.text(.toolbarFit))
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
            item.view = toolbarGroupView(containing: stack)
            lockToolbarItem(item, width: Self.imageSizeToolbarWidth)
            zoomInfoControl = zoomControl
            fitZoomButton = fitButton
            updateZoomUI()
            updateFitZoomTooltip()
            return item

        case .tools:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = L10n.text(.toolbarTools)
            item.paletteLabel = L10n.text(.toolbarTools)
            item.toolTip = L10n.text(.toolbarToolsTooltip)

            let control = NSSegmentedControl(
                images: AnnotationTool.allCases.map { EditorToolbarImages.toolImage(for: $0) },
                trackingMode: .selectOne,
                target: self,
                action: #selector(changeTool)
            )
            control.controlSize = .small
            control.segmentStyle = .texturedRounded
            control.selectedSegment = canvasView.currentTool.rawValue
            control.setWidth(32, forSegment: AnnotationTool.arrow.rawValue)
            control.setWidth(32, forSegment: AnnotationTool.rectangle.rawValue)
            control.setWidth(32, forSegment: AnnotationTool.text.rawValue)
            control.setWidth(34, forSegment: AnnotationTool.mosaic.rawValue)
            control.setWidth(34, forSegment: AnnotationTool.magnifier.rawValue)
            control.setWidth(44, forSegment: AnnotationTool.pen.rawValue)
            control.setWidth(32, forSegment: AnnotationTool.hand.rawValue)
            configureToolTips(for: control)
            control.setMenu(makePenSizeMenu(), forSegment: AnnotationTool.pen.rawValue)
            control.setShowsMenuIndicator(true, forSegment: AnnotationTool.pen.rawValue)
            item.view = toolbarGroupView(containing: control)
            lockToolbarItem(item, width: Self.toolsToolbarWidth)
            toolControl = control
            updatePenSegmentImage()
            updatePenSegmentTooltip()
            updateToolOptions()
            return item

        case .color:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = L10n.text(.toolbarColor)
            item.paletteLabel = L10n.text(.toolbarColor)
            item.toolTip = L10n.text(.toolbarNewAnnotationColor)

            let colorControl = AnnotationColorPickerView(color: canvasView.annotationColor)
            colorControl.onColorChanged = { [weak self] color in
                self?.canvasView.annotationColor = color
            }
            item.view = toolbarGroupView(containing: colorControl, horizontalPadding: 5)
            lockToolbarItem(item, width: Self.colorToolbarWidth)
            annotationColorControl = colorControl
            return item

        case .actions:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = L10n.text(.toolbarActions)
            item.paletteLabel = L10n.text(.toolbarActions)
            item.toolTip = L10n.text(.toolbarActionsTooltip)

            let stack = NSStackView(views: [
                toolbarIconButton(role: .undo, symbolName: "arrow.uturn.backward", action: #selector(undo)),
                toolbarIconButton(role: .copy, symbolName: "doc.on.doc", action: #selector(copyImage)),
                toolbarIconButton(role: .save, symbolName: "square.and.arrow.down", action: #selector(saveImage)),
                toolbarIconButton(role: .share, symbolName: "square.and.arrow.up", action: #selector(shareImage(_:)))
            ])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 4
            stack.translatesAutoresizingMaskIntoConstraints = false
            item.view = toolbarGroupView(containing: stack)
            lockToolbarItem(item, width: Self.actionsToolbarWidth)
            return item

        case .toolbarGroupSeparatorOne, .toolbarGroupSeparatorTwo, .toolbarGroupSeparatorThree:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = ToolbarGroupSeparatorView()
            lockToolbarItem(item, width: Self.toolbarSeparatorWidth)
            return item

        default:
            return nil
        }
    }

    func applyLanguage() {
        window?.toolbar?.items.forEach { item in
            switch item.itemIdentifier {
            case .imageSize:
                item.label = L10n.text(.toolbarZoom)
                item.paletteLabel = L10n.text(.toolbarZoom)
                item.toolTip = L10n.text(.toolbarZoomTooltip)
                zoomInfoControl?.toolTip = L10n.text(.toolbarZoomTooltip)
            case .tools:
                item.label = L10n.text(.toolbarTools)
                item.paletteLabel = L10n.text(.toolbarTools)
                item.toolTip = L10n.text(.toolbarToolsTooltip)
            case .color:
                item.label = L10n.text(.toolbarColor)
                item.paletteLabel = L10n.text(.toolbarColor)
                item.toolTip = L10n.text(.toolbarNewAnnotationColor)
            case .actions:
                item.label = L10n.text(.toolbarActions)
                item.paletteLabel = L10n.text(.toolbarActions)
                item.toolTip = L10n.text(.toolbarActionsTooltip)
                refreshActionButtonToolTips(in: item.view)
            default:
                break
            }
        }
        annotationColorControl?.applyLanguage()
        configureToolTips()
        fitZoomButton?.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: L10n.text(.toolbarFit))
        refreshPenSizeMenuLanguage()
        updateToolOptions()
        updateZoomUI()
    }
}
