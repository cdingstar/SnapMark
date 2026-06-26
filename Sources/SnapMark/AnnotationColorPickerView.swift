import AppKit

final class AnnotationColorPickerView: NSControl {
    private enum Segment {
        case cycle
        case menu
    }

    var onColorChanged: ((NSColor) -> Void)?

    var color: NSColor {
        didSet {
            needsDisplay = true
        }
    }

    private var pressedSegment: Segment? {
        didSet {
            needsDisplay = true
        }
    }
    private var colorPopover: NSPopover?

    init(color: NSColor) {
        self.color = color
        super.init(frame: CGRect(origin: .zero, size: Self.defaultSize))
        applyLanguage()
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        Self.defaultSize
    }

    func applyLanguage() {
        toolTip = L10n.text(.toolbarNewAnnotationColor)
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let location = convert(event.locationInWindow, from: nil)
        let segment = segment(at: location)
        pressedSegment = segment

        switch segment {
        case .cycle:
            cyclePresetColor()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.pressedSegment = nil
            }
        case .menu:
            showCompactColorPicker()
            pressedSegment = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)

        if isEnabled {
            NSColor.controlBackgroundColor.setFill()
        } else {
            NSColor.controlBackgroundColor.withAlphaComponent(0.45).setFill()
        }
        backgroundPath.fill()

        if let pressedSegment {
            NSGraphicsContext.saveGraphicsState()
            backgroundPath.addClip()
            NSColor.selectedControlColor.withAlphaComponent(0.20).setFill()
            NSBezierPath(rect: rectFor(segment: pressedSegment).insetBy(dx: 0, dy: 0.5)).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        NSColor.separatorColor.setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()

        let dividerX = splitX
        let divider = NSBezierPath()
        divider.move(to: CGPoint(x: dividerX, y: rect.minY + 3))
        divider.line(to: CGPoint(x: dividerX, y: rect.maxY - 3))
        divider.lineWidth = 1
        divider.stroke()

        drawSwatch(in: rectFor(segment: .cycle))
        drawArrow(in: rectFor(segment: .menu))
    }

    private static let defaultSize = CGSize(width: 52, height: 24)

    private var splitX: CGFloat {
        floor(bounds.width * 2 / 3)
    }

    private func segment(at point: CGPoint) -> Segment {
        point.x < splitX ? .cycle : .menu
    }

    private func rectFor(segment: Segment) -> CGRect {
        switch segment {
        case .cycle:
            return CGRect(x: bounds.minX, y: bounds.minY, width: splitX, height: bounds.height)
        case .menu:
            return CGRect(x: splitX, y: bounds.minY, width: bounds.width - splitX, height: bounds.height)
        }
    }

    private func cyclePresetColor() {
        let presets = AnnotationColorPalette.presets
        let currentIndex = presets.firstIndex { AnnotationColorPalette.colorsMatch($0.color, color) }
        let nextIndex = currentIndex.map { ($0 + 1) % presets.count } ?? 0
        setColor(presets[nextIndex].color)
    }

    private func showCompactColorPicker() {
        colorPopover?.close()

        let controller = CompactColorPickerViewController(color: color)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = CGSize(width: 252, height: 318)
        popover.contentViewController = controller
        controller.onColorSelected = { [weak self, weak popover] color, closes in
            self?.setColor(color)
            if closes {
                popover?.performClose(nil)
            }
        }
        colorPopover = popover
        popover.show(relativeTo: rectFor(segment: .menu), of: self, preferredEdge: .maxY)
    }

    private func setColor(_ newColor: NSColor) {
        color = newColor
        onColorChanged?(newColor)
    }

    private func drawSwatch(in rect: CGRect) {
        let swatchSize = CGSize(width: 15, height: 15)
        let swatchRect = CGRect(
            x: rect.midX - swatchSize.width / 2,
            y: rect.midY - swatchSize.height / 2,
            width: swatchSize.width,
            height: swatchSize.height
        )
        AnnotationColorPalette.swatchImage(for: color, size: swatchSize).draw(in: swatchRect)
    }

    private func drawArrow(in rect: CGRect) {
        let arrowWidth: CGFloat = 7
        let arrowHeight: CGFloat = 4
        let arrowRect = CGRect(
            x: rect.midX - arrowWidth / 2,
            y: rect.midY - arrowHeight / 2,
            width: arrowWidth,
            height: arrowHeight
        )

        let path = NSBezierPath()
        path.move(to: CGPoint(x: arrowRect.minX, y: arrowRect.maxY))
        path.line(to: CGPoint(x: arrowRect.midX, y: arrowRect.minY))
        path.line(to: CGPoint(x: arrowRect.maxX, y: arrowRect.maxY))
        path.close()

        (isEnabled ? NSColor.secondaryLabelColor : NSColor.disabledControlTextColor).setFill()
        path.fill()
    }

}
