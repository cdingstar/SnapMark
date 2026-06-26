import AppKit

enum AnnotationTool: Int, CaseIterable {
    case arrow
    case rectangle
    case text
    case mosaic
    case magnifier
    case pen
    case hand

    var title: String {
        switch self {
        case .arrow:
            return L10n.text(.toolArrow)
        case .rectangle:
            return L10n.text(.toolRectangle)
        case .text:
            return L10n.text(.toolText)
        case .mosaic:
            return L10n.text(.toolMosaic)
        case .magnifier:
            return L10n.text(.toolMagnifier)
        case .pen:
            return L10n.text(.toolPen)
        case .hand:
            return L10n.text(.toolHand)
        }
    }

    var displayTitle: String {
        title
    }

    var symbolName: String {
        switch self {
        case .arrow:
            return "arrow.up.right"
        case .rectangle:
            return "rectangle"
        case .text:
            return "textformat"
        case .mosaic:
            return "checkerboard.rectangle"
        case .magnifier:
            return "plus.magnifyingglass"
        case .pen:
            return "pen"
        case .hand:
            return "hand.raised"
        }
    }
}

enum PenSize: Int, CaseIterable {
    case small
    case medium
    case large

    var title: String {
        switch self {
        case .small:
            return "S"
        case .medium:
            return "M"
        case .large:
            return "L"
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .small:
            return 8
        case .medium:
            return 16
        case .large:
            return 32
        }
    }
}

enum ShapeMode: Int, CaseIterable {
    case rectangle
    case circle
    case ellipse

    var title: String {
        switch self {
        case .rectangle:
            return L10n.text(.shapeRectangle)
        case .circle:
            return L10n.text(.shapeCircle)
        case .ellipse:
            return L10n.text(.shapeEllipse)
        }
    }
}

enum ArrowMode: Int, CaseIterable {
    case solid
    case notched
    case line

    var title: String {
        switch self {
        case .solid:
            return L10n.text(.arrowSolid)
        case .notched:
            return L10n.text(.arrowNotched)
        case .line:
            return L10n.text(.arrowLine)
        }
    }
}

enum MosaicMode: Int, CaseIterable {
    case plain
    case bordered

    var title: String {
        switch self {
        case .plain:
            return L10n.text(.mosaicPlain)
        case .bordered:
            return L10n.text(.mosaicBordered)
        }
    }
}

enum HandMode: Int, CaseIterable {
    case selection
    case pan

    var title: String {
        switch self {
        case .selection:
            return L10n.text(.handSelection)
        case .pan:
            return L10n.text(.handPan)
        }
    }
}

struct Annotation: Identifiable {
    var id = UUID()
    var tool: AnnotationTool
    var start: CGPoint
    var end: CGPoint
    var text: String = ""
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    var fontSize: CGFloat = TextAnnotationMetrics.defaultFontSize
    var points: [CGPoint] = []
    var shapeMode: ShapeMode = .rectangle
    var arrowMode: ArrowMode = .solid
    var mosaicMode: MosaicMode = .plain
    var imagePatch: NSImage?

    var rect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
    }
}
