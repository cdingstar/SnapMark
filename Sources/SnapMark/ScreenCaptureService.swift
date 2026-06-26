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
        return capture(
            coreGraphicsRect: region.captureRequestRect,
            expectedPixelSize: region.pixelSize,
            cropRect: region.captureCropRect
        )
    }

    private func capture(coreGraphicsRect rect: CGRect, expectedPixelSize: CGSize? = nil, cropRect: CGRect? = nil) -> NSImage? {
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return nil }

        guard let cgImage = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            return nil
        }

        let outputImage = croppedImage(from: cgImage, cropRect: cropRect) ?? cgImage
        return NSImage(
            cgImage: outputImage,
            size: expectedPixelSize ?? CGSize(width: outputImage.width, height: outputImage.height)
        )
    }

    private func croppedImage(from image: CGImage, cropRect: CGRect?) -> CGImage? {
        guard let cropRect else { return nil }
        let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let boundedRect = cropRect.integral.intersection(imageRect)
        guard !boundedRect.isNull, boundedRect.width > 0, boundedRect.height > 0 else { return nil }
        return image.cropping(to: boundedRect)
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
