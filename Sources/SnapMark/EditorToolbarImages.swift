import AppKit

enum EditorToolbarImages {
    static func toolImage(for tool: AnnotationTool) -> NSImage {
        switch tool {
        case .arrow:
            return arrowToolImage(for: .solid)
        case .rectangle:
            return shapeToolImage(for: .rectangle)
        case .text:
            return textToolImage()
        case .mosaic:
            return mosaicToolImage(for: .plain)
        case .magnifier:
            return NSImage(
                systemSymbolName: tool.symbolName,
                accessibilityDescription: tool.displayTitle
            ) ?? NSImage(size: CGSize(width: 16, height: 16))
        case .pen:
            return penStrokeImage(for: .medium)
        case .hand:
            return handToolImage(for: .selection)
        }
    }

    static func textToolImage() -> NSImage {
        NSImage(size: CGSize(width: 18, height: 18), flipped: false) { rect in
            let glyph = "T" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: NSColor.labelColor
            ]
            let glyphSize = glyph.size(withAttributes: attributes)
            glyph.draw(
                in: CGRect(
                    x: rect.midX - glyphSize.width / 2,
                    y: rect.midY - glyphSize.height / 2,
                    width: glyphSize.width,
                    height: glyphSize.height
                ),
                withAttributes: attributes
            )
            return true
        }
    }

    static func shapeToolImage(for mode: ShapeMode, size: CGSize = CGSize(width: 18, height: 18)) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let frame = rect.insetBy(dx: 3, dy: 4)
            let path: NSBezierPath
            switch mode {
            case .rectangle:
                path = NSBezierPath(rect: frame)
            case .circle:
                let side = min(frame.width, frame.height)
                path = NSBezierPath(ovalIn: CGRect(
                    x: frame.midX - side / 2,
                    y: frame.midY - side / 2,
                    width: side,
                    height: side
                ))
            case .ellipse:
                path = NSBezierPath(ovalIn: frame.insetBy(dx: 0, dy: 1.5))
            }
            path.lineWidth = 1.8
            NSColor.labelColor.setStroke()
            path.stroke()
            return true
        }
    }

    static func arrowToolImage(for mode: ArrowMode, size: CGSize = CGSize(width: 18, height: 18)) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let start = CGPoint(x: rect.minX + 3, y: rect.minY + 5)
            let end = CGPoint(x: rect.maxX - 3, y: rect.maxY - 5)
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = hypot(dx, dy)
            guard length > 0 else { return true }

            let unit = CGPoint(x: dx / length, y: dy / length)
            let perpendicular = CGPoint(x: -unit.y, y: unit.x)
            NSColor.labelColor.setStroke()
            NSColor.labelColor.setFill()

            switch mode {
            case .solid:
                let headLength: CGFloat = 6
                let headHalfWidth: CGFloat = 3.8
                let base = CGPoint(x: end.x - unit.x * headLength, y: end.y - unit.y * headLength)
                let shaft = NSBezierPath()
                shaft.lineWidth = 2
                shaft.lineCapStyle = .round
                shaft.move(to: start)
                shaft.line(to: CGPoint(x: base.x + unit.x * 1.4, y: base.y + unit.y * 1.4))
                shaft.stroke()

                let head = NSBezierPath()
                head.move(to: end)
                head.line(to: CGPoint(x: base.x + perpendicular.x * headHalfWidth, y: base.y + perpendicular.y * headHalfWidth))
                head.line(to: CGPoint(x: base.x - perpendicular.x * headHalfWidth, y: base.y - perpendicular.y * headHalfWidth))
                head.close()
                head.fill()
            case .notched:
                let headLength: CGFloat = 8
                let headHalfWidth: CGFloat = 4.5
                let tailHalfWidth: CGFloat = 1.8
                let notchDepth: CGFloat = 3.2
                let base = CGPoint(x: end.x - unit.x * headLength, y: end.y - unit.y * headLength)
                let notch = CGPoint(x: start.x + unit.x * notchDepth, y: start.y + unit.y * notchDepth)

                let path = NSBezierPath()
                path.move(to: CGPoint(x: start.x + perpendicular.x * tailHalfWidth, y: start.y + perpendicular.y * tailHalfWidth))
                path.line(to: CGPoint(x: base.x + perpendicular.x * headHalfWidth, y: base.y + perpendicular.y * headHalfWidth))
                path.line(to: end)
                path.line(to: CGPoint(x: base.x - perpendicular.x * headHalfWidth, y: base.y - perpendicular.y * headHalfWidth))
                path.line(to: CGPoint(x: start.x - perpendicular.x * tailHalfWidth, y: start.y - perpendicular.y * tailHalfWidth))
                path.line(to: notch)
                path.close()
                path.fill()
            case .line:
                let path = NSBezierPath()
                path.lineWidth = 2.2
                path.lineCapStyle = .round
                path.move(to: start)
                path.line(to: end)
                path.stroke()
            }
            return true
        }
    }

    static func mosaicToolImage(for mode: MosaicMode, size: CGSize = CGSize(width: 18, height: 18)) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let frame = rect.insetBy(dx: 3, dy: 3)
            let tileWidth = frame.width / 3
            let tileHeight = frame.height / 3

            for row in 0..<3 {
                for column in 0..<3 {
                    let isStrong = (row + column).isMultiple(of: 2)
                    NSColor.labelColor.withAlphaComponent(isStrong ? 0.88 : 0.25).setFill()
                    CGRect(
                        x: frame.minX + CGFloat(column) * tileWidth,
                        y: frame.minY + CGFloat(row) * tileHeight,
                        width: tileWidth,
                        height: tileHeight
                    ).fill()
                }
            }

            if mode == .bordered {
                let border = NSBezierPath(rect: frame)
                border.lineWidth = 1.6
                NSColor.labelColor.setStroke()
                border.stroke()
            }

            return true
        }
    }

    static func penStrokeImage(for penSize: PenSize, size: CGSize = CGSize(width: 18, height: 18)) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let lineWidth: CGFloat
            switch penSize {
            case .small:
                lineWidth = 2
            case .medium:
                lineWidth = 4
            case .large:
                lineWidth = 6
            }

            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.move(to: CGPoint(x: rect.minX + 3, y: rect.midY))
            path.line(to: CGPoint(x: rect.maxX - 3, y: rect.midY))
            NSColor.labelColor.setStroke()
            path.stroke()
            return true
        }
    }

    static func handToolImage(for mode: HandMode, size: CGSize = CGSize(width: 18, height: 18)) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            if let hand = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: mode.title) {
                hand.draw(in: rect.insetBy(dx: 3, dy: 3), from: .zero, operation: .sourceOver, fraction: 1)
            }

            guard mode == .selection else { return true }

            let frame = rect.insetBy(dx: 1.5, dy: 1.5)
            let path = NSBezierPath(roundedRect: frame, xRadius: 1.5, yRadius: 1.5)
            path.lineWidth = 1.2
            let dash: [CGFloat] = [2.2, 1.6]
            dash.withUnsafeBufferPointer { buffer in
                path.setLineDash(buffer.baseAddress, count: dash.count, phase: 0)
            }
            NSColor.labelColor.setStroke()
            path.stroke()
            return true
        }
    }
}
