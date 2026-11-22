import AppKit
import ShotkeeperCore

/// The menu bar glyph: the PR 4 app icon's shape as a template image (outline viewfinder corners + a filled
/// 4-point sparkle), drawn as vectors so it is sharp at every scale. Same geometry as `AppIconView`.
enum MenuBarGlyph {
    enum Variant {
        case normal
        /// Larger sparkle: the frames of the short pulse after a rename.
        case pulse
    }

    /// 18×18 pt template image (menu bar size).
    static func image(_ variant: Variant = .normal, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            draw(in: rect, sparkleScale: variant == .pulse ? 1.35 : 1)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Shotkeeper"
        return image
    }

    /// Core `IconGeometry.menuBarGlyph` paths (the app icon's shape, with the corners pushed out and a heavier stroke
    /// for 18 pt; also exported as `design/icon/MenuBarGlyph.svg`), drawn in AppKit coordinates (y up).
    static func draw(in rect: NSRect, sparkleScale: CGFloat) {
        let geometry = IconGeometry.menuBarGlyph
        let side = min(rect.width, rect.height)
        let corners = bezierPath(geometry.viewfinderPath, in: rect, side: side)
        corners.lineWidth = max(1, side * CGFloat(geometry.cornerStroke))
        corners.lineCapStyle = .round
        corners.lineJoinStyle = .round
        corners.stroke()
        bezierPath(geometry.sparklePath(scale: Double(sparkleScale)), in: rect, side: side).fill()
    }

    /// A unit-square core path (y down) as an `NSBezierPath` in `rect` (y up).
    private static func bezierPath(_ elements: [IconPathElement], in rect: NSRect, side: CGFloat) -> NSBezierPath {
        func point(_ p: IconPoint) -> NSPoint {
            NSPoint(x: rect.minX + CGFloat(p.x) * side, y: rect.minY + side - CGFloat(p.y) * side)
        }
        let path = NSBezierPath()
        for element in elements {
            switch element {
            case .move(let p): path.move(to: point(p))
            case .line(let p): path.line(to: point(p))
            case .curve(let p, let c1, let c2): path.curve(to: point(p), controlPoint1: point(c1), controlPoint2: point(c2))
            case .close: path.close()
            }
        }
        return path
    }
}
