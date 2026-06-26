import AppKit

struct AnnotationPresetColor {
    let title: String
    let color: NSColor
}

enum AnnotationColorPalette {
    static var presets: [AnnotationPresetColor] {
        [
            AnnotationPresetColor(title: L10n.text(.colorRed), color: .systemRed),
            AnnotationPresetColor(title: L10n.text(.colorWhite), color: .white),
            AnnotationPresetColor(title: L10n.text(.colorBlue), color: .systemBlue),
            AnnotationPresetColor(title: L10n.text(.colorBlack), color: .black)
        ]
    }

    static var compactChoices: [AnnotationPresetColor] {
        [
            swatch("#000000"), swatch("#263238"), swatch("#455A64"), swatch("#607D8B"),
            swatch("#9E9E9E"), swatch("#BDBDBD"), swatch("#E0E0E0"), swatch("#FFFFFF"),
            swatch("#B71C1C"), swatch("#D50000"), swatch("#E53935"), swatch("#FF5252"),
            swatch("#F8BBD0"), swatch("#D81B60"), swatch("#880E4F"), swatch("#FF4081"),
            swatch("#E65100"), swatch("#EF6C00"), swatch("#FB8C00"), swatch("#FFB300"),
            swatch("#FDD835"), swatch("#F9A825"), swatch("#F57F17"), swatch("#795548"),
            swatch("#827717"), swatch("#AFB42B"), swatch("#C0CA33"), swatch("#8BC34A"),
            swatch("#7CB342"), swatch("#43A047"), swatch("#2E7D32"), swatch("#1B5E20"),
            swatch("#004D40"), swatch("#00695C"), swatch("#00897B"), swatch("#00ACC1"),
            swatch("#26C6DA"), swatch("#039BE5"), swatch("#0277BD"), swatch("#01579B"),
            swatch("#0D47A1"), swatch("#1565C0"), swatch("#1E88E5"), swatch("#42A5F5"),
            swatch("#90CAF9"), swatch("#5E35B1"), swatch("#3949AB"), swatch("#283593"),
            swatch("#311B92"), swatch("#4527A0"), swatch("#7E57C2"), swatch("#AB47BC"),
            swatch("#8E24AA"), swatch("#6A1B9A"), swatch("#4A148C"), swatch("#E1BEE7"),
            swatch("#3E2723"), swatch("#5D4037"), swatch("#8D6E63"), swatch("#A1887F"),
            swatch("#FFAB91"), swatch("#FFCC80"), swatch("#FFF59D"), swatch("#C8E6C9")
        ]
    }

    static func swatchImage(for color: NSColor, size: CGSize = CGSize(width: 14, height: 14)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = CGRect(origin: CGPoint(x: 1, y: 1), size: CGSize(width: size.width - 2, height: size.height - 2))
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        drawTransparencyBackground(in: rect)
        color.setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1
        path.stroke()

        return image
    }

    static func hexString(for color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return "#FF0000" }
        let red = Int((rgb.redComponent * 255).rounded())
        let green = Int((rgb.greenComponent * 255).rounded())
        let blue = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    static func color(fromHex text: String, alpha: CGFloat) -> NSColor? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }

        let red = CGFloat((value >> 16) & 0xff) / 255
        let green = CGFloat((value >> 8) & 0xff) / 255
        let blue = CGFloat(value & 0xff) / 255
        return NSColor(deviceRed: red, green: green, blue: blue, alpha: alpha)
    }

    static func colorsMatch(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        guard
            let left = lhs.usingColorSpace(.deviceRGB),
            let right = rhs.usingColorSpace(.deviceRGB)
        else {
            return lhs == rhs
        }

        let tolerance: CGFloat = 0.01
        return abs(left.redComponent - right.redComponent) <= tolerance
            && abs(left.greenComponent - right.greenComponent) <= tolerance
            && abs(left.blueComponent - right.blueComponent) <= tolerance
            && abs(left.alphaComponent - right.alphaComponent) <= tolerance
    }

    private static func swatch(_ hex: String) -> AnnotationPresetColor {
        AnnotationPresetColor(title: hex, color: color(fromHex: hex, alpha: 1) ?? .systemRed)
    }

    private static func drawTransparencyBackground(in rect: CGRect) {
        NSColor.white.setFill()
        rect.fill()

        NSColor(calibratedWhite: 0.78, alpha: 1).setFill()
        let tileSize = max(4, min(rect.width, rect.height) / 3)
        var row = 0
        var y = rect.minY
        while y < rect.maxY {
            var column = 0
            var x = rect.minX
            while x < rect.maxX {
                if (row + column).isMultiple(of: 2) {
                    CGRect(
                        x: x,
                        y: y,
                        width: min(tileSize, rect.maxX - x),
                        height: min(tileSize, rect.maxY - y)
                    ).fill()
                }
                column += 1
                x += tileSize
            }
            row += 1
            y += tileSize
        }
    }
}
