import AppKit

struct TextAnnotationOptions {
    var text: String
    var color: NSColor
    var fontSize: CGFloat
}

enum TextAnnotationMetrics {
    static let defaultFontSize: CGFloat = 28
    static let minimumFontSize: CGFloat = 12
    static let maximumFontSize: CGFloat = 96

    static func fittedSize(for text: String, fontSize: CGFloat, maxWidth: CGFloat) -> CGSize {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sample = trimmed.isEmpty ? L10n.text(.textDefault) : trimmed
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
        let preferredWidth = min(maxWidth, max(fontSize * 8, min(fontSize * 18, CGFloat(sample.count) * fontSize * 0.62)))
        let bounds = (sample as NSString).boundingRect(
            with: CGSize(width: max(96, preferredWidth), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return CGSize(
            width: min(maxWidth, max(96, ceil(bounds.width + fontSize * 0.9))),
            height: max(fontSize * 1.35, ceil(bounds.height + fontSize * 0.75))
        )
    }
}

final class TextAnnotationDialogController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private let textView = NSTextView()
    private let colorWell = NSColorWell(frame: CGRect(x: 0, y: 0, width: 44, height: 26))
    private let fontSizeSlider = NSSlider(value: Double(TextAnnotationMetrics.defaultFontSize), minValue: Double(TextAnnotationMetrics.minimumFontSize), maxValue: Double(TextAnnotationMetrics.maximumFontSize), target: nil, action: nil)
    private let fontSizeLabel = NSTextField(labelWithString: "")
    private let previewLabel = NSTextField(labelWithString: "Aa")
    private var modalResponse: NSApplication.ModalResponse = .cancel
    private(set) var options: TextAnnotationOptions?

    init(
        defaultText: String = "",
        defaultColor: NSColor = .systemRed,
        defaultFontSize: CGFloat = TextAnnotationMetrics.defaultFontSize
    ) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 420, height: 286),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.textAnnotationTitle)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        colorWell.color = defaultColor
        fontSizeSlider.doubleValue = Double(defaultFontSize)
        buildContent()
        textView.string = defaultText
        updatePreview()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func runModal() -> TextAnnotationOptions? {
        guard let window else { return nil }
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        modalResponse = NSApp.runModal(for: window)
        window.orderOut(nil)
        return modalResponse == .OK ? options : nil
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.stopModal(withCode: .cancel)
    }

    func textDidChange(_ notification: Notification) {
        updatePreview()
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        let title = NSTextField(labelWithString: L10n.text(.addTextTitle))
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let textLabel = fieldLabel(L10n.text(.textContent))
        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 92).isActive = true
        scrollView.widthAnchor.constraint(equalToConstant: 380).isActive = true
        textView.font = .systemFont(ofSize: 14)
        textView.delegate = self
        textView.string = ""
        textView.isRichText = false
        textView.textContainerInset = CGSize(width: 8, height: 6)
        scrollView.documentView = textView

        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 18

        let colorStack = labeledControl(title: L10n.text(.textColor), control: colorWell)
        colorWell.target = self
        colorWell.action = #selector(colorChanged)

        fontSizeSlider.target = self
        fontSizeSlider.action = #selector(fontSizeChanged)
        fontSizeSlider.controlSize = .small
        fontSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        fontSizeSlider.widthAnchor.constraint(equalToConstant: 142).isActive = true
        fontSizeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        fontSizeLabel.alignment = .right
        fontSizeLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let sizeStack = NSStackView(views: [fontSizeSlider, fontSizeLabel])
        sizeStack.orientation = .horizontal
        sizeStack.alignment = .centerY
        sizeStack.spacing = 8

        controls.addArrangedSubview(colorStack)
        controls.addArrangedSubview(labeledControl(title: L10n.text(.textFontSize), control: sizeStack))

        previewLabel.isBezeled = false
        previewLabel.drawsBackground = true
        previewLabel.backgroundColor = .textBackgroundColor
        previewLabel.alignment = .center
        previewLabel.maximumNumberOfLines = 1
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.widthAnchor.constraint(equalToConstant: 96).isActive = true
        previewLabel.heightAnchor.constraint(equalToConstant: 42).isActive = true
        controls.addArrangedSubview(labeledControl(title: L10n.text(.textPreview), control: previewLabel))

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        let cancelButton = NSButton(title: L10n.text(.cancel), target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        let addButton = NSButton(title: L10n.text(.add), target: self, action: #selector(confirm))
        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "\r"
        buttons.addArrangedSubview(spacer)
        buttons.addArrangedSubview(cancelButton)
        buttons.addArrangedSubview(addButton)

        root.addArrangedSubview(title)
        root.addArrangedSubview(textLabel)
        root.addArrangedSubview(scrollView)
        root.addArrangedSubview(controls)
        root.addArrangedSubview(buttons)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    private func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func labeledControl(title: String, control: NSView) -> NSStackView {
        let stack = NSStackView(views: [fieldLabel(title), control])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        return stack
    }

    @objc private func colorChanged() {
        updatePreview()
    }

    @objc private func fontSizeChanged() {
        updatePreview()
    }

    @objc private func confirm() {
        let trimmed = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            NSSound.beep()
            return
        }

        options = TextAnnotationOptions(
            text: trimmed,
            color: colorWell.color,
            fontSize: CGFloat(fontSizeSlider.doubleValue.rounded())
        )
        modalResponse = .OK
        NSApp.stopModal(withCode: .OK)
    }

    @objc private func cancel() {
        modalResponse = .cancel
        NSApp.stopModal(withCode: .cancel)
    }

    private func updatePreview() {
        let fontSize = CGFloat(fontSizeSlider.doubleValue.rounded())
        fontSizeLabel.stringValue = "\(Int(fontSize)) px"
        previewLabel.font = .systemFont(ofSize: min(36, max(14, fontSize)), weight: .semibold)
        previewLabel.textColor = colorWell.color
        let trimmed = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        previewLabel.stringValue = trimmed.isEmpty ? "Aa" : String(trimmed.prefix(8))
    }
}
