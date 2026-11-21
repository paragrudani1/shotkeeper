import AppKit

/// The menu bar glyph: the PR 4 app icon's shape as a template image (outline viewfinder corners + a filled
/// 4-point sparkle), drawn as vectors so it is sharp at every scale. The full app icon is PR 4.
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

    /// Geometry in proportions of the side, matching the icon spec (corner stroke ≈ 5.6% of the icon, sparkle
    /// ≈ 27%), adjusted for 18 pt: a slightly heavier stroke so it reads like other menu bar glyphs.
    static func draw(in rect: NSRect, sparkleScale: CGFloat) {
        let side = min(rect.width, rect.height)
        let inset = side * 0.1
        let frame = rect.insetBy(dx: inset, dy: inset)
        let arm = side * 0.26
        let corners = NSBezierPath()
        corners.lineWidth = max(1, side * 0.085)
        corners.lineCapStyle = .round
        corners.lineJoinStyle = .round
        // Bottom-left, top-left, top-right, bottom-right "L"s.
        corners.move(to: NSPoint(x: frame.minX, y: frame.minY + arm))
        corners.line(to: NSPoint(x: frame.minX, y: frame.minY))
        corners.line(to: NSPoint(x: frame.minX + arm, y: frame.minY))
        corners.move(to: NSPoint(x: frame.minX, y: frame.maxY - arm))
        corners.line(to: NSPoint(x: frame.minX, y: frame.maxY))
        corners.line(to: NSPoint(x: frame.minX + arm, y: frame.maxY))
        corners.move(to: NSPoint(x: frame.maxX - arm, y: frame.maxY))
        corners.line(to: NSPoint(x: frame.maxX, y: frame.maxY))
        corners.line(to: NSPoint(x: frame.maxX, y: frame.maxY - arm))
        corners.move(to: NSPoint(x: frame.maxX, y: frame.minY + arm))
        corners.line(to: NSPoint(x: frame.maxX, y: frame.minY))
        corners.line(to: NSPoint(x: frame.maxX - arm, y: frame.minY))
        corners.stroke()

        sparkle(center: NSPoint(x: rect.midX, y: rect.midY), radius: side * 0.2 * sparkleScale).fill()
    }

    /// A 4-point star with concave sides (quadratic curves through a point near the center).
    static func sparkle(center c: NSPoint, radius r: CGFloat) -> NSBezierPath {
        let pinch = r * 0.16
        let points = [NSPoint(x: c.x, y: c.y + r), NSPoint(x: c.x + r, y: c.y),
                      NSPoint(x: c.x, y: c.y - r), NSPoint(x: c.x - r, y: c.y)]
        let controls = [NSPoint(x: c.x + pinch, y: c.y + pinch), NSPoint(x: c.x + pinch, y: c.y - pinch),
                        NSPoint(x: c.x - pinch, y: c.y - pinch), NSPoint(x: c.x - pinch, y: c.y + pinch)]
        let path = NSBezierPath()
        path.move(to: points[0])
        for i in 0..<4 {
            let next = points[(i + 1) % 4]
            path.curve(to: next, controlPoint1: controls[i], controlPoint2: controls[i])
        }
        path.close()
        return path
    }
}
