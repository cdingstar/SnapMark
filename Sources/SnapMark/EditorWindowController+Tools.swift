import AppKit

extension EditorWindowController {
    @objc func changeTool(_ sender: NSSegmentedControl) {
        guard let tool = AnnotationTool(rawValue: sender.selectedSegment) else { return }
        let previousTool = canvasView.currentTool
        canvasView.applyActiveAnnotation()
        if tool == previousTool {
            switch tool {
            case .arrow:
                cycleArrowMode()
            case .rectangle:
                cycleShapeMode()
            case .mosaic:
                cycleMosaicMode()
            case .pen:
                cyclePenSize()
            case .hand:
                cycleHandMode()
            case .text, .magnifier:
                break
            }
        } else if tool == .hand {
            canvasView.handMode = .selection
        }
        canvasView.currentTool = tool
        updateToolOptions()
    }

    @objc func choosePenSize(_ sender: NSMenuItem) {
        guard let size = PenSize(rawValue: sender.tag) else { return }
        canvasView.applyActiveAnnotation()
        canvasView.penSize = size
        canvasView.currentTool = .pen
        toolControl?.selectedSegment = AnnotationTool.pen.rawValue
        updatePenSegmentImage()
        updatePenSegmentTooltip()
        updateToolOptions()
    }

    func updateToolOptions() {
        annotationColorControl?.isEnabled = true
        updateShapeSegmentImage()
        updateShapeSegmentTooltip()
        updateArrowSegmentImage()
        updateArrowSegmentTooltip()
        updateTextSegmentTooltip()
        updateMosaicSegmentImage()
        updateMosaicSegmentTooltip()
        updateMagnifierSegmentTooltip()
        updatePenSegmentImage()
        updatePenSegmentTooltip()
        updateHandSegmentImage()
        updateHandSegmentTooltip()
        updatePenSizeMenuState()
    }

    func makePenSizeMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.text(.penSizeMenu))
        menu.delegate = self
        for size in PenSize.allCases {
            let item = NSMenuItem(title: L10n.format(.penSizeMenuItemFormat, size.title), action: #selector(choosePenSize), keyEquivalent: "")
            item.target = self
            item.tag = size.rawValue
            item.image = EditorToolbarImages.penStrokeImage(for: size, size: CGSize(width: 34, height: 16))
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

    func updatePenSegmentImage() {
        toolControl?.setImage(EditorToolbarImages.penStrokeImage(for: canvasView.penSize), forSegment: AnnotationTool.pen.rawValue)
    }

    func updatePenSegmentTooltip() {
        toolControl?.setToolTip(penTooltipText(), forSegment: AnnotationTool.pen.rawValue)
    }

    func updatePenSizeMenuState() {
        refreshPenSizeMenuLanguage()
        penSizeMenu?.items.forEach { item in
            item.state = item.tag == canvasView.penSize.rawValue ? .on : .off
        }
    }

    func refreshPenSizeMenuLanguage() {
        penSizeMenu?.title = L10n.text(.penSizeMenu)
        penSizeMenu?.items.forEach { item in
            guard let size = PenSize(rawValue: item.tag) else { return }
            item.title = L10n.format(.penSizeMenuItemFormat, size.title)
        }
    }

    func cyclePenSize() {
        let sizes = PenSize.allCases
        guard let index = sizes.firstIndex(of: canvasView.penSize) else { return }
        canvasView.penSize = sizes[(index + 1) % sizes.count]
        updatePenSegmentImage()
        updatePenSegmentTooltip()
        updatePenSizeMenuState()
    }

    func updateShapeSegmentImage() {
        toolControl?.setImage(EditorToolbarImages.shapeToolImage(for: canvasView.shapeMode), forSegment: AnnotationTool.rectangle.rawValue)
    }

    func updateShapeSegmentTooltip() {
        toolControl?.setToolTip(shapeTooltipText(), forSegment: AnnotationTool.rectangle.rawValue)
    }

    func cycleShapeMode() {
        let modes = ShapeMode.allCases
        guard let index = modes.firstIndex(of: canvasView.shapeMode) else { return }
        canvasView.shapeMode = modes[(index + 1) % modes.count]
        updateShapeSegmentImage()
        updateShapeSegmentTooltip()
    }

    func updateArrowSegmentImage() {
        toolControl?.setImage(EditorToolbarImages.arrowToolImage(for: canvasView.arrowMode), forSegment: AnnotationTool.arrow.rawValue)
    }

    func updateArrowSegmentTooltip() {
        toolControl?.setToolTip(arrowTooltipText(), forSegment: AnnotationTool.arrow.rawValue)
    }

    func cycleArrowMode() {
        let modes = ArrowMode.allCases
        guard let index = modes.firstIndex(of: canvasView.arrowMode) else { return }
        canvasView.arrowMode = modes[(index + 1) % modes.count]
        updateArrowSegmentImage()
        updateArrowSegmentTooltip()
    }

    func updateMosaicSegmentImage() {
        toolControl?.setImage(EditorToolbarImages.mosaicToolImage(for: canvasView.mosaicMode), forSegment: AnnotationTool.mosaic.rawValue)
    }

    func updateMosaicSegmentTooltip() {
        toolControl?.setToolTip(mosaicTooltipText(), forSegment: AnnotationTool.mosaic.rawValue)
    }

    func cycleMosaicMode() {
        let modes = MosaicMode.allCases
        guard let index = modes.firstIndex(of: canvasView.mosaicMode) else { return }
        canvasView.mosaicMode = modes[(index + 1) % modes.count]
        updateMosaicSegmentImage()
        updateMosaicSegmentTooltip()
    }

    func updateHandSegmentImage() {
        toolControl?.setImage(EditorToolbarImages.handToolImage(for: canvasView.handMode), forSegment: AnnotationTool.hand.rawValue)
    }

    func updateHandSegmentTooltip() {
        toolControl?.setToolTip(handTooltipText(), forSegment: AnnotationTool.hand.rawValue)
    }

    func cycleHandMode() {
        let modes = HandMode.allCases
        guard let index = modes.firstIndex(of: canvasView.handMode) else { return }
        canvasView.handMode = modes[(index + 1) % modes.count]
        updateHandSegmentImage()
        updateHandSegmentTooltip()
    }

    func configureToolTips(for control: NSSegmentedControl) {
        control.setToolTip(arrowTooltipText(), forSegment: AnnotationTool.arrow.rawValue)
        control.setToolTip(shapeTooltipText(), forSegment: AnnotationTool.rectangle.rawValue)
        control.setToolTip(L10n.text(.toolTextTooltip), forSegment: AnnotationTool.text.rawValue)
        control.setToolTip(mosaicTooltipText(), forSegment: AnnotationTool.mosaic.rawValue)
        control.setToolTip(L10n.text(.toolMagnifierTooltip), forSegment: AnnotationTool.magnifier.rawValue)
        control.setToolTip(penTooltipText(), forSegment: AnnotationTool.pen.rawValue)
        control.setToolTip(handTooltipText(), forSegment: AnnotationTool.hand.rawValue)
    }

    func configureToolTips() {
        guard let toolControl else { return }
        configureToolTips(for: toolControl)
    }

    func updateTextSegmentTooltip() {
        toolControl?.setToolTip(L10n.text(.toolTextTooltip), forSegment: AnnotationTool.text.rawValue)
    }

    func updateMagnifierSegmentTooltip() {
        toolControl?.setToolTip(L10n.text(.toolMagnifierTooltip), forSegment: AnnotationTool.magnifier.rawValue)
    }

    func penTooltipText() -> String {
        L10n.format(.penTooltipFormat, canvasView.penSize.title, tooltipModeList(PenSize.allCases.map(\.title)))
    }

    func shapeTooltipText() -> String {
        L10n.format(.shapeTooltipFormat, canvasView.shapeMode.title, tooltipModeList(ShapeMode.allCases.map(\.title)))
    }

    func arrowTooltipText() -> String {
        L10n.format(.arrowTooltipFormat, canvasView.arrowMode.title, tooltipModeList(ArrowMode.allCases.map(\.title)))
    }

    func mosaicTooltipText() -> String {
        L10n.format(.mosaicTooltipFormat, canvasView.mosaicMode.title, tooltipModeList(MosaicMode.allCases.map(\.title)))
    }

    func handTooltipText() -> String {
        L10n.format(.handTooltipFormat, canvasView.handMode.title, tooltipModeList(HandMode.allCases.map(\.title)))
    }

    func tooltipModeList(_ titles: [String]) -> String {
        titles.joined(separator: L10n.text(.tooltipListSeparator))
    }
}
