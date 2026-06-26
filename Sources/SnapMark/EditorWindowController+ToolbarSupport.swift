import AppKit

extension EditorWindowController {
    func toolbarGroupView(containing contentView: NSView, horizontalPadding: CGFloat = 6) -> NSView {
        ToolbarGroupContainerView(contentView: contentView, horizontalPadding: horizontalPadding)
    }

    func toolbarIconButton(role: ToolbarActionButtonRole, symbolName: String, action: Selector) -> NSButton {
        let title = role.localizedTitle
        let button = NSButton(title: "", target: self, action: action)
        button.identifier = role.viewIdentifier
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        button.imagePosition = .imageOnly
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.toolTip = role.localizedToolTip
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 24)
        ])
        return button
    }

    func refreshActionButtonToolTips(in rootView: NSView?) {
        guard let rootView else { return }
        for role in ToolbarActionButtonRole.allCases {
            rootView.descendant(with: role.viewIdentifier)?.toolTip = role.localizedToolTip
        }
    }

    func lockToolbarItem(_ item: NSToolbarItem, width: CGFloat) {
        guard let view = item.view else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
    }
}

extension NSToolbarItem.Identifier {
    static let imageSize = NSToolbarItem.Identifier("SnapMark.ImageSize")
    static let tools = NSToolbarItem.Identifier("SnapMark.Tools")
    static let color = NSToolbarItem.Identifier("SnapMark.Color")
    static let actions = NSToolbarItem.Identifier("SnapMark.Actions")
    static let toolbarGroupSeparatorOne = NSToolbarItem.Identifier("SnapMark.ToolbarGroupSeparator.One")
    static let toolbarGroupSeparatorTwo = NSToolbarItem.Identifier("SnapMark.ToolbarGroupSeparator.Two")
    static let toolbarGroupSeparatorThree = NSToolbarItem.Identifier("SnapMark.ToolbarGroupSeparator.Three")
}

enum ToolbarActionButtonRole: String, CaseIterable {
    case undo
    case copy
    case save
    case share

    var viewIdentifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("SnapMark.ActionButton.\(rawValue)")
    }

    var localizedTitle: String {
        switch self {
        case .undo:
            return L10n.text(.toolbarUndo)
        case .copy:
            return L10n.text(.toolbarCopy)
        case .save:
            return L10n.text(.toolbarSave)
        case .share:
            return L10n.text(.toolbarShare)
        }
    }

    var localizedToolTip: String {
        switch self {
        case .undo:
            return L10n.text(.toolbarUndoTooltip)
        case .copy:
            return L10n.text(.toolbarCopyTooltip)
        case .save:
            return L10n.text(.toolbarSaveTooltip)
        case .share:
            return L10n.text(.toolbarShareTooltip)
        }
    }
}

final class ToolbarGroupContainerView: NSView {
    private let contentView: NSView

    init(contentView: NSView, horizontalPadding: CGFloat) {
        self.contentView = contentView
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
            contentView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool {
        false
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 30)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 0.5, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        appearanceAwareFillColor.setFill()
        path.fill()
        appearanceAwareStrokeColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private var appearanceAwareFillColor: NSColor {
        isDarkAppearance ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.04)
    }

    private var appearanceAwareStrokeColor: NSColor {
        isDarkAppearance ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.10)
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

final class ToolbarGroupSeparatorView: NSView {
    override var isOpaque: Bool {
        false
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 14, height: 30)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.midX, y: 6))
        path.line(to: NSPoint(x: bounds.midX, y: bounds.maxY - 6))
        separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private var separatorColor: NSColor {
        isDarkAppearance ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.14)
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private extension NSView {
    func descendant(with identifier: NSUserInterfaceItemIdentifier) -> NSView? {
        if self.identifier == identifier {
            return self
        }

        for subview in subviews {
            if let match = subview.descendant(with: identifier) {
                return match
            }
        }

        return nil
    }
}
