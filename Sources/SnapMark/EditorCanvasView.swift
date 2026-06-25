import AppKit

final class EditorCanvasView: NSView {
    let baseImage: NSImage
    var onAnnotationsChanged: (() -> Void)?
    var onResetRequested: (() -> Void)?

    var currentTool: AnnotationTool = .arrow {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }

    private(set) var annotations: [Annotation] = [] {
        didSet {
            needsDisplay = true
            onAnnotationsChanged?()
        }
    }

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    init(image: NSImage) {
        baseImage = image
        let size = image.snapMarkPixelSize
        super.init(frame: CGRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setFrameSize(size)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()

        let canvasRect = CGRect(origin: .zero, size: baseImage.snapMarkPixelSize)
        baseImage.draw(in: canvasRect, from: .zero, operation: .copy, fraction: 1)
        ImageRenderer.draw(annotations: annotations, over: baseImage, canvasRect: canvasRect)

        if let preview = previewAnnotation {
            ImageRenderer.draw(annotations: [preview], over: baseImage, canvasRect: canvasRect, isPreview: true)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = clamped(convert(event.locationInWindow, from: nil))
        dragStart = point
        dragCurrent = point
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = clamped(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart else { return }

        let end = clamped(convert(event.locationInWindow, from: nil))
        dragStart = nil
        dragCurrent = nil

        var annotation = Annotation(tool: currentTool, start: start, end: end)
        normalizeMinimumSize(&annotation)

        if currentTool == .text {
            guard let text = promptForText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                needsDisplay = true
                return
            }
            annotation.text = text
            annotation.lineWidth = 0
        }

        annotations.append(annotation)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onResetRequested?()
            return
        }

        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            undoLastAnnotation()
            return
        }

        super.keyDown(with: event)
    }

    func undoLastAnnotation() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
    }

    func renderedImage() -> NSImage {
        ImageRenderer.render(baseImage: baseImage, annotations: annotations)
    }

    private var previewAnnotation: Annotation? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        var annotation = Annotation(tool: currentTool, start: start, end: current)
        normalizeMinimumSize(&annotation)
        if currentTool == .text {
            annotation.text = "Text"
        }
        return annotation
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0, min(bounds.width, point.x)),
            y: max(0, min(bounds.height, point.y))
        )
    }

    private func normalizeMinimumSize(_ annotation: inout Annotation) {
        let minimum: CGFloat = annotation.tool == .text ? 32 : 8
        if annotation.rect.width >= minimum, annotation.rect.height >= minimum {
            return
        }

        annotation.end = CGPoint(
            x: annotation.start.x + max(minimum, annotation.rect.width),
            y: annotation.start.y + max(minimum, annotation.rect.height)
        )
    }

    private func promptForText() -> String? {
        let alert = NSAlert()
        alert.messageText = "添加文字"
        alert.informativeText = "输入要放到截图上的文字。"
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")

        let textField = NSTextField(frame: CGRect(x: 0, y: 0, width: 280, height: 24))
        textField.placeholderString = "标注文字"
        alert.accessoryView = textField

        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? textField.stringValue : nil
    }
}
