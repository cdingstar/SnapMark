import AppKit
import CoreGraphics

final class ScreenCaptureService {
    var hasScreenCaptureAccess: Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    func requestScreenCaptureAccess() -> Bool {
        if #available(macOS 10.15, *) {
            return CGRequestScreenCaptureAccess()
        }
        return true
    }

    func captureFullScreen() -> NSImage? {
        let rect = NSScreen.screens
            .map(\.frame)
            .reduce(CGRect.null) { $0.union($1) }

        return capture(rect: rect)
    }

    func capture(rect: CGRect) -> NSImage? {
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return nil }

        guard let cgImage = CGWindowListCreateImage(
            rect.integral,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: CGSize(width: cgImage.width, height: cgImage.height)
        )
    }

    func capture(windowID: CGWindowID, fallbackRect: CGRect) -> NSImage? {
        if let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) {
            return NSImage(
                cgImage: cgImage,
                size: CGSize(width: cgImage.width, height: cgImage.height)
            )
        }

        return capture(rect: fallbackRect)
    }
}
