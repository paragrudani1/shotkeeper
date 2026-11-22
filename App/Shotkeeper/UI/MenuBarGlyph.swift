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

    /// Core `IconGeometry.menuBarGlyph` (the app icon's shape, with the corners pushed out and a heavier stroke for
    /// 18 pt), drawn in AppKit coordinates (y up).
    static func draw(in rect: NSRect, sparkleScale: CGFloat) {
        let geometry = IconGeometry.menuBarGlyph
        let side = min(rect.width, rect.height)
        func point(_ p: IconPoint) -> NSPoint {
            NSPoint(x: rect.minX + CGFloat(p.x) * side, y: rect.minY + side - CGFloat(p.y) * side)
        }
        let corners = NSBezierPath()
        corners.lineWidth = max(1, side * CGFloat(geometry.cornerStroke))
        corners.lineCapStyle = .round
        corners.lineJoinStyle = .round
        for corner in geometry.viewfinderCorners {
            corners.move(to: point(corner[0]))
            for next in corner.dropFirst() { corners.line(to: point(next)) }
        }
        corners.stroke()

        let (tips, controls) = geometry.sparkle(scale: Double(sparkleScale))
        let sparkle = NSBezierPath()
        sparkle.move(to: point(tips[0]))
        for index in 0..<4 {
            let control = point(controls[index])
            sparkle.curve(to: point(tips[(index + 1) % 4]), controlPoint1: control, controlPoint2: control)
        }
        sparkle.close()
        sparkle.fill()
    }
}
