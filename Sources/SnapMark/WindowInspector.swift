import AppKit
import CoreGraphics

struct WindowTarget: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let appKitBounds: CGRect

    static func == (lhs: WindowTarget, rhs: WindowTarget) -> Bool {
        lhs.windowID == rhs.windowID
    }
}

enum WindowInspector {
    static func visibleWindowTargets(excludingOwnerNames excludedNames: Set<String>) -> [WindowTarget] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return list.compactMap { info in
            guard
                let windowIDNumber = info[kCGWindowNumber as String] as? NSNumber,
                let ownerPIDNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
                let ownerName = info[kCGWindowOwnerName as String] as? String,
                !excludedNames.contains(ownerName),
                let layerNumber = info[kCGWindowLayer as String] as? NSNumber,
                layerNumber.intValue == 0,
                let bounds = bounds(from: info[kCGWindowBounds as String]),
                bounds.width >= 24,
                bounds.height >= 24
            else {
                return nil
            }

            if let alphaNumber = info[kCGWindowAlpha as String] as? NSNumber, alphaNumber.doubleValue <= 0.01 {
                return nil
            }

            return WindowTarget(
                windowID: CGWindowID(windowIDNumber.uint32Value),
                ownerPID: ownerPIDNumber.int32Value,
                ownerName: ownerName,
                appKitBounds: appKitRect(fromCoreGraphicsBounds: bounds)
            )
        }
    }

    static func windowUnder(appKitPoint: CGPoint, in targets: [WindowTarget]) -> WindowTarget? {
        targets.first { $0.appKitBounds.contains(appKitPoint) }
    }

    private static func bounds(from value: Any?) -> CGRect? {
        guard let dictionary = value as? NSDictionary else { return nil }

        var rect = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(dictionary, &rect) else {
            return nil
        }
        return rect
    }

    private static func appKitRect(fromCoreGraphicsBounds bounds: CGRect) -> CGRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return bounds }

        var bestRect = CGRect(
            x: bounds.minX,
            y: screens[0].frame.maxY - bounds.maxY,
            width: bounds.width,
            height: bounds.height
        )
        var bestArea: CGFloat = -1

        for screen in screens {
            let candidate = CGRect(
                x: bounds.minX,
                y: screen.frame.maxY - bounds.maxY,
                width: bounds.width,
                height: bounds.height
            )
            let intersection = candidate.intersection(screen.frame)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                bestRect = candidate
            }
        }

        return bestRect
    }
}
