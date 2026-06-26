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
        let displayBounds = Self.coreGraphicsDisplayBounds(for: screen)
        let snappedCoreGraphicsRect = Self.pixelSnapped(
            Self.coreGraphicsRect(from: rawRect.standardized, on: screen),
            displayBounds: displayBounds,
            scale: backingScaleFactor
        )
        guard snappedCoreGraphicsRect.width > 0, snappedCoreGraphicsRect.height > 0 else { return nil }

        coreGraphicsRect = snappedCoreGraphicsRect
        appKitRect = Self.appKitRect(from: snappedCoreGraphicsRect, displayBounds: displayBounds, on: screen)
        pixelSize = Self.pixelSize(for: snappedCoreGraphicsRect, displayBounds: displayBounds, scale: backingScaleFactor)
    }

    var isCapturable: Bool {
        pixelSize.width >= 4 && pixelSize.height >= 4
    }

    static func fullScreenCoreGraphicsRect(for screens: [NSScreen]) -> CGRect {
        screens
            .map { coreGraphicsDisplayBounds(for: $0) }
            .reduce(CGRect.null) { $0.union($1) }
            .integral
    }

    static func coreGraphicsDisplayBounds(for screen: NSScreen) -> CGRect {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = screen.deviceDescription[key] as? NSNumber else {
            return screen.frame
        }
        return CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
    }

    static func coreGraphicsPoint(from appKitPoint: CGPoint, on screen: NSScreen) -> CGPoint {
        let screenFrame = screen.frame
        let displayBounds = coreGraphicsDisplayBounds(for: screen)
        return CGPoint(
            x: displayBounds.minX + (appKitPoint.x - screenFrame.minX),
            y: displayBounds.minY + (screenFrame.maxY - appKitPoint.y)
        )
    }

    static func backingPixelPoint(from appKitPoint: CGPoint, on screen: NSScreen) -> CGPoint {
        let capturePoint = coreGraphicsPoint(from: appKitPoint, on: screen)
        let displayBounds = coreGraphicsDisplayBounds(for: screen)
        let scale = max(1, screen.backingScaleFactor)
        return CGPoint(
            x: ((capturePoint.x - displayBounds.minX) * scale).rounded(),
            y: ((capturePoint.y - displayBounds.minY) * scale).rounded()
        )
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

    private static func pixelSnapped(_ rect: CGRect, displayBounds: CGRect, scale: CGFloat) -> CGRect {
        let minX = snappedCoordinate(rect.minX, origin: displayBounds.minX, scale: scale)
        let minY = snappedCoordinate(rect.minY, origin: displayBounds.minY, scale: scale)
        let maxX = snappedCoordinate(rect.maxX, origin: displayBounds.minX, scale: scale)
        let maxY = snappedCoordinate(rect.maxY, origin: displayBounds.minY, scale: scale)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func snappedCoordinate(_ value: CGFloat, origin: CGFloat, scale: CGFloat) -> CGFloat {
        origin + ((value - origin) * scale).rounded() / scale
    }

    private static func pixelSize(for rect: CGRect, displayBounds: CGRect, scale: CGFloat) -> CGSize {
        let minX = ((rect.minX - displayBounds.minX) * scale).rounded()
        let minY = ((rect.minY - displayBounds.minY) * scale).rounded()
        let maxX = ((rect.maxX - displayBounds.minX) * scale).rounded()
        let maxY = ((rect.maxY - displayBounds.minY) * scale).rounded()
        return CGSize(
            width: max(1, maxX - minX),
            height: max(1, maxY - minY)
        )
    }

    private static func coreGraphicsRect(from appKitRect: CGRect, on screen: NSScreen) -> CGRect {
        let origin = coreGraphicsPoint(
            from: CGPoint(x: appKitRect.minX, y: appKitRect.maxY),
            on: screen
        )
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: appKitRect.width,
            height: appKitRect.height
        )
    }

    private static func appKitRect(from coreGraphicsRect: CGRect, displayBounds: CGRect, on screen: NSScreen) -> CGRect {
        let screenFrame = screen.frame
        let minX = screenFrame.minX + (coreGraphicsRect.minX - displayBounds.minX)
        let maxX = screenFrame.minX + (coreGraphicsRect.maxX - displayBounds.minX)
        let minY = screenFrame.maxY - (coreGraphicsRect.maxY - displayBounds.minY)
        let maxY = screenFrame.maxY - (coreGraphicsRect.minY - displayBounds.minY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

}
