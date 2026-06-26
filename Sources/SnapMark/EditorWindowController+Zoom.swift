import AppKit

extension EditorWindowController {
    func setZoomScaleFromSlider(_ scale: CGFloat) {
        updateCanvasViewport()
        canvasView.setZoomScale(scale)
        updateZoomUI()
        canvasView.scrollToVisible(canvasView.canvasCenterRect)
    }

    @objc func cycleZoomPreset() {
        updateCanvasViewport()
        guard let option = nextZoomPresetOption(in: zoomPresetOptions()) else { return }
        canvasView.setZoomScale(option.scale)
        updateZoomUI()
        canvasView.scrollToVisible(canvasView.canvasCenterRect)
    }

    @objc func scrollViewBoundsDidChange(_ notification: Notification) {
        updateCanvasViewport()
        updateZoomUI()
    }

    func updateCanvasViewport() {
        canvasView.updateViewportSize(scrollView.contentView.bounds.size)
    }

    func updateZoomUI() {
        zoomInfoControl?.update(
            zoomText: zoomInfoText(for: canvasView.zoomScale),
            imageSizeText: EditorNumberFormatter.imageSize(imagePixelSize),
            zoomScale: canvasView.zoomScale
        )
        updateFitZoomTooltip()
    }

    func zoomPresetOptions() -> [ZoomPresetOption] {
        let viewportSize = scrollView.contentView.bounds.size
        return ZoomPresetMode.allCases.reduce(into: [ZoomPresetOption]()) { options, mode in
            let option = ZoomPresetOption(mode: mode, scale: mode.scale(for: canvasView, viewportSize: viewportSize))
            if !options.contains(where: { Self.zoomScalesMatch($0.scale, option.scale) }) {
                options.append(option)
            }
        }
    }

    func nextZoomPresetOption(in options: [ZoomPresetOption]) -> ZoomPresetOption? {
        guard !options.isEmpty else { return nil }

        if let currentIndex = options.firstIndex(where: { Self.zoomScalesMatch($0.scale, canvasView.zoomScale) }) {
            return options[(currentIndex + 1) % options.count]
        }

        return options.first { !Self.zoomScalesMatch($0.scale, canvasView.zoomScale) }
    }

    func updateFitZoomTooltip() {
        let options = zoomPresetOptions()
        let nextOption = nextZoomPresetOption(in: options)
        fitZoomButton?.isEnabled = nextOption != nil

        if let nextOption {
            fitZoomButton?.toolTip = L10n.format(
                .zoomModeNextTooltipFormat,
                zoomInfoText(for: canvasView.zoomScale),
                nextOption.title,
                EditorNumberFormatter.zoom(nextOption.scale)
            )
        } else {
            fitZoomButton?.toolTip = L10n.text(.zoomModeTooltip)
        }
    }

    func zoomInfoText(for scale: CGFloat) -> String {
        guard let option = zoomPresetOptions().first(where: { Self.zoomScalesMatch($0.scale, scale) }) else {
            return EditorNumberFormatter.zoom(scale)
        }

        return "\(EditorNumberFormatter.zoom(scale)) \(option.title)"
    }

    static func zoomScalesMatch(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) <= zoomScaleTolerance
    }
}
