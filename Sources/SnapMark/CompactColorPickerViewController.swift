import AppKit

final class CompactColorPickerViewController: NSViewController, NSTextFieldDelegate {
    var onColorSelected: ((NSColor, Bool) -> Void)?

    private var color: NSColor
    private let hexField = NSTextField()
    private let opacitySlider = NSSlider(value: 1, minValue: 0.15, maxValue: 1, target: nil, action: nil)
    private var presetButtons: [NSButton] = []
    private var paletteButtons: [NSButton] = []

    init(color: NSColor) {
        self.color = color
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView(frame: CGRect(x: 0, y: 0, width: 252, height: 318))
        buildContent()
        refreshControls()
    }

    private func buildContent() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            root.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12)
        ])

        root.addArrangedSubview(presetRow())
        root.addArrangedSubview(paletteGrid())
        root.addArrangedSubview(hexRow())
        root.addArrangedSubview(opacityRow())
    }

    private func presetRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7

        presetButtons = AnnotationColorPalette.presets.enumerated().map { index, preset in
            let button = NSButton(title: "", target: self, action: #selector(selectPresetColor(_:)))
            button.tag = index
            button.image = AnnotationColorPalette.swatchImage(for: preset.color, size: CGSize(width: 22, height: 22))
            button.imagePosition = .imageOnly
            button.bezelStyle = .texturedRounded
            button.toolTip = preset.title
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 34).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            row.addArrangedSubview(button)
            return button
        }

        return row
    }

    private func paletteGrid() -> NSView {
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 4

        let columns = 8
        paletteButtons.removeAll()
        let choices = AnnotationColorPalette.compactChoices
        for rowStart in stride(from: 0, to: choices.count, by: columns) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 4

            for index in rowStart..<min(rowStart + columns, choices.count) {
                let choice = choices[index]
                let button = NSButton(title: "", target: self, action: #selector(selectPaletteColor(_:)))
                button.tag = index
                button.image = AnnotationColorPalette.swatchImage(for: choice.color, size: CGSize(width: 18, height: 14))
                button.imagePosition = .imageOnly
                button.bezelStyle = .texturedRounded
                button.toolTip = choice.title
                button.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    button.widthAnchor.constraint(equalToConstant: 24),
                    button.heightAnchor.constraint(equalToConstant: 20)
                ])
                row.addArrangedSubview(button)
                paletteButtons.append(button)
            }

            grid.addArrangedSubview(row)
        }

        return grid
    }

    private func hexRow() -> NSView {
        let label = fieldLabel(L10n.text(.colorHex))
        hexField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        hexField.delegate = self
        hexField.target = self
        hexField.action = #selector(commitHexColor)
        hexField.translatesAutoresizingMaskIntoConstraints = false
        hexField.widthAnchor.constraint(equalToConstant: 96).isActive = true

        let row = NSStackView(views: [label, hexField])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func opacityRow() -> NSView {
        let label = fieldLabel(L10n.text(.colorOpacity))
        opacitySlider.target = self
        opacitySlider.action = #selector(changeOpacity)
        opacitySlider.controlSize = .small
        opacitySlider.translatesAutoresizingMaskIntoConstraints = false
        opacitySlider.widthAnchor.constraint(equalToConstant: 128).isActive = true

        let row = NSStackView(views: [label, opacitySlider])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func fieldLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 54).isActive = true
        return label
    }

    private func refreshControls() {
        hexField.stringValue = AnnotationColorPalette.hexString(for: color)
        opacitySlider.doubleValue = Double(color.usingColorSpace(.deviceRGB)?.alphaComponent ?? color.alphaComponent)
        let presets = AnnotationColorPalette.presets
        for (index, button) in presetButtons.enumerated() {
            guard presets.indices.contains(index) else { continue }
            let candidate = presets[index].color.withAlphaComponent(CGFloat(opacitySlider.doubleValue))
            button.state = AnnotationColorPalette.colorsMatch(candidate, color) ? .on : .off
        }

        let choices = AnnotationColorPalette.compactChoices
        for (index, button) in paletteButtons.enumerated() {
            guard choices.indices.contains(index) else { continue }
            let candidate = choices[index].color.withAlphaComponent(CGFloat(opacitySlider.doubleValue))
            button.state = AnnotationColorPalette.colorsMatch(candidate, color) ? .on : .off
        }
    }

    @objc private func selectPresetColor(_ sender: NSButton) {
        let presets = AnnotationColorPalette.presets
        guard presets.indices.contains(sender.tag) else { return }
        color = presets[sender.tag].color.withAlphaComponent(CGFloat(opacitySlider.doubleValue))
        refreshControls()
        onColorSelected?(color, true)
    }

    @objc private func selectPaletteColor(_ sender: NSButton) {
        let choices = AnnotationColorPalette.compactChoices
        guard choices.indices.contains(sender.tag) else { return }
        color = choices[sender.tag].color.withAlphaComponent(CGFloat(opacitySlider.doubleValue))
        refreshControls()
        onColorSelected?(color, true)
    }

    @objc private func commitHexColor() {
        guard let nextColor = AnnotationColorPalette.color(
            fromHex: hexField.stringValue,
            alpha: CGFloat(opacitySlider.doubleValue)
        ) else {
            NSSound.beep()
            refreshControls()
            return
        }

        color = nextColor
        refreshControls()
        onColorSelected?(color, true)
    }

    @objc private func changeOpacity() {
        color = color.withAlphaComponent(CGFloat(opacitySlider.doubleValue))
        refreshControls()
        onColorSelected?(color, false)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitHexColor()
    }
}
