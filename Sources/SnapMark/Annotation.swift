import AppKit

enum AnnotationTool: Int, CaseIterable {
    case arrow
    case rectangle
    case text
    case mosaic
    case magnifier
    case eraser

    var title: String {
        switch self {
        case .arrow:
            return "Arrow"
        case .rectangle:
            return "Rect"
        case .text:
            return "Text"
        case .mosaic:
            return "Mosaic"
        case .magnifier:
            return "Lens"
        case .eraser:
            return "Eraser"
        }
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
        case .eraser:
            return "eraser"
        }
    }
}

enum EraserSize: Int, CaseIterable {
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

struct Annotation: Identifiable {
    let id = UUID()
    var tool: AnnotationTool
    var start: CGPoint
    var end: CGPoint
    var text: String = ""
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    var fontSize: CGFloat = TextAnnotationMetrics.defaultFontSize
    var points: [CGPoint] = []

    var rect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
    }
}
