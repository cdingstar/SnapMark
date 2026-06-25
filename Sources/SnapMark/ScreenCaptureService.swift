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
        let rect = ScreenCaptureRegion.fullScreenCoreGraphicsRect(for: NSScreen.screens)
        return capture(coreGraphicsRect: rect)
    }

    func capture(rect: CGRect) -> NSImage? {
        guard let region = ScreenCaptureRegion(appKitRect: rect) else { return nil }
        return capture(region: region)
    }

    func capture(region: ScreenCaptureRegion) -> NSImage? {
        guard region.isCapturable else { return nil }
        return capture(coreGraphicsRect: region.coreGraphicsRect, expectedPixelSize: region.pixelSize)
    }

    private func capture(coreGraphicsRect rect: CGRect, expectedPixelSize: CGSize? = nil) -> NSImage? {
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return nil }

        guard let cgImage = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: expectedPixelSize ?? CGSize(width: cgImage.width, height: cgImage.height)
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
