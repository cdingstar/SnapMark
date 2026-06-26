import AppKit

final class ZoomInfoSliderView: NSView {
    let slider: NSSlider
    var onZoomChanged: ((CGFloat) -> Void)?

    private let zoomLabel = NSTextField(labelWithString: "")
    private let imageSizeLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?

    init(value: CGFloat, minValue: CGFloat, maxValue: CGFloat) {
        slider = NSSlider(
            value: Double(value),
            minValue: Double(minValue),
            maxValue: Double(maxValue),
            target: nil,
            action: nil
        )
        super.init(frame: .zero)
        buildView()
        setSliderVisible(false, animated: false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        setSliderVisible(true, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        setSliderVisible(false, animated: true)
    }

    func update(zoomText: String, imageSizeText: String, zoomScale: CGFloat) {
        zoomLabel.stringValue = zoomText
        imageSizeLabel.stringValue = imageSizeText
        slider.doubleValue = Double(zoomScale)
    }

    private func buildView() {
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.86).cgColor

        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        zoomLabel.textColor = .labelColor
        zoomLabel.alignment = .left
        zoomLabel.lineBreakMode = .byTruncatingTail
        zoomLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        imageSizeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        imageSizeLabel.textColor = .secondaryLabelColor
        imageSizeLabel.alignment = .right
        imageSizeLabel.lineBreakMode = .byTruncatingMiddle
        imageSizeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let infoRow = NSStackView(views: [zoomLabel, spacer, imageSizeLabel])
        infoRow.orientation = .horizontal
        infoRow.alignment = .centerY
        infoRow.spacing = 6
        infoRow.translatesAutoresizingMaskIntoConstraints = false

        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.controlSize = .small
        slider.alphaValue = 0.04
        slider.translatesAutoresizingMaskIntoConstraints = false

        addSubview(infoRow)
        addSubview(slider)

        NSLayoutConstraint.activate([
            infoRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            infoRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            infoRow.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1),

            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 7)
        ])
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        onZoomChanged?(CGFloat(sender.doubleValue))
    }

    private func setSliderVisible(_ visible: Bool, animated: Bool) {
        let updates = {
            self.slider.alphaValue = visible ? 0.92 : 0.04
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                self.slider.animator().alphaValue = visible ? 0.92 : 0.04
            }
        } else {
            updates()
        }
    }
}
