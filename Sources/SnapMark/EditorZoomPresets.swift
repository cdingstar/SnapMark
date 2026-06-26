import AppKit

enum ZoomPresetMode: CaseIterable {
    case actualSize
    case bestFit
    case fitIn

    var title: String {
        switch self {
        case .actualSize:
            return L10n.text(.zoomModeActualSize)
        case .bestFit:
            return L10n.text(.zoomModeBestFit)
        case .fitIn:
            return L10n.text(.zoomModeFitIn)
        }
    }

    func scale(for canvasView: EditorCanvasView, viewportSize: CGSize) -> CGFloat {
        switch self {
        case .actualSize:
            return 1
        case .bestFit:
            return canvasView.bestFitZoomScale(for: viewportSize)
        case .fitIn:
            return canvasView.fitInZoomScale(for: viewportSize)
        }
    }
}

struct ZoomPresetOption {
    let mode: ZoomPresetMode
    let scale: CGFloat

    var title: String {
        mode.title
    }
}

enum EditorNumberFormatter {
    static func imageSize(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) x \(Int(size.height.rounded())) px"
    }

    static func zoom(_ scale: CGFloat) -> String {
        "\(Int((scale * 100).rounded()))%"
    }
}
