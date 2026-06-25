import AppKit
import CoreGraphics

struct ScreenCaptureRegion: Equatable {
    let appKitRect: CGRect
    let coreGraphicsRect: CGRect
    let backingScaleFactor: CGFloat
    let pixelSize: CGSize

    init?(appKitRect rawRect: CGRect, screen preferredScreen: NSScreen? = nil) {
        guard !rawRect.isNull, rawRect.width > 0, rawRect.height > 0 else { return nil }
        guard let screen = preferredScreen ?? Self.bestScreen(for: rawRect) else { return nil }

        backingScaleFactor = max(1, screen.backingScaleFactor)
        appKitRect = Self.pixelAligned(rawRect.standardized, scale: backingScaleFactor)
        coreGraphicsRect = Self.coreGraphicsRect(from: appKitRect, on: screen)
        pixelSize = Self.pixelSize(for: appKitRect, scale: backingScaleFactor)
    }

    var isCapturable: Bool {
        pixelSize.width >= 4 && pixelSize.height >= 4
    }

    static func fullScreenCoreGraphicsRect(for screens: [NSScreen]) -> CGRect {
        screens
            .map { displayBounds(for: $0) }
            .reduce(CGRect.null) { $0.union($1) }
            .integral
    }

    private static func bestScreen(for rect: CGRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            intersectionArea(lhs.frame, rect) < intersectionArea(rhs.frame, rect)
        }
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private static func pixelAligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let minX = floor(rect.minX * scale) / scale
        let minY = floor(rect.minY * scale) / scale
        let maxX = ceil(rect.maxX * scale) / scale
        let maxY = ceil(rect.maxY * scale) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func pixelSize(for rect: CGRect, scale: CGFloat) -> CGSize {
        CGSize(
            width: max(1, (rect.width * scale).rounded()),
            height: max(1, (rect.height * scale).rounded())
        )
    }

    private static func coreGraphicsRect(from appKitRect: CGRect, on screen: NSScreen) -> CGRect {
        let screenFrame = screen.frame
        let displayBounds = displayBounds(for: screen)
        return CGRect(
            x: displayBounds.minX + (appKitRect.minX - screenFrame.minX),
            y: displayBounds.minY + (screenFrame.maxY - appKitRect.maxY),
            width: appKitRect.width,
            height: appKitRect.height
        )
    }

    private static func displayBounds(for screen: NSScreen) -> CGRect {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = screen.deviceDescription[key] as? NSNumber else {
            return screen.frame
        }
        return CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
    }
}
