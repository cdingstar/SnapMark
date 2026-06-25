import AppKit

enum AnnotationTool: Int, CaseIterable {
    case arrow
    case rectangle
    case text
    case mosaic
    case magnifier

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

    var rect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
    }
}
