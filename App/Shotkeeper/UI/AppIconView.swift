import AppKit
import ShotkeeperCore
import SwiftUI

/// The app icon (spec PR 4 "App icon", option A) as a vector view: an indigo squircle with a faint lighter top half,
/// four white viewfinder corners and a white sparkle. Geometry: core `IconGeometry.appIcon` paths, the same ones
/// `IconSVG` writes to `design/icon/AppIcon.svg` and the AppIcon asset catalog (`scripts/make-icons.sh`). This view has
/// no transparent margin; the asset does (Apple's icon grid). Setup shows it at 72 pt.
struct AppIconView: View {
    var size: CGFloat = 72

    var body: some View {
        let geometry = IconGeometry.appIcon
        let squircle = IconPathShape(elements: geometry.backgroundPath)
        ZStack {
            squircle.fill(Color(nsColor: NSColor(srgbHex: IconGeometry.backgroundRGB)))
            VStack(spacing: 0) {
                Color.white.opacity(IconGeometry.topHighlightOpacity).frame(height: size / 2)
                Spacer(minLength: 0)
            }
            IconPathShape(elements: geometry.viewfinderPath)
                .stroke(.white, style: StrokeStyle(lineWidth: geometry.cornerStroke * size, lineCap: .round, lineJoin: .round))
            IconPathShape(elements: geometry.sparklePath()).fill(.white)
        }
        .frame(width: size, height: size)
        .clipShape(squircle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shotkeeper")
        .accessibilityAddTraits(.isImage)
    }
}

/// The menu bar glyph as a vector view in the current foreground style (outline corners + filled sparkle), for
/// places that show "this is the menu bar icon" (setup step 5). The status item itself uses `MenuBarGlyph.image`.
struct MenuBarGlyphView: View {
    var size: CGFloat = 18

    var body: some View {
        let geometry = IconGeometry.menuBarGlyph
        ZStack {
            IconPathShape(elements: geometry.viewfinderPath)
                .stroke(style: StrokeStyle(lineWidth: max(1, geometry.cornerStroke * size), lineCap: .round, lineJoin: .round))
            IconPathShape(elements: geometry.sparklePath())
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shotkeeper menu bar icon")
        .accessibilityAddTraits(.isImage)
    }
}

/// A core `IconPathElement` path (unit square, y down) scaled to the rect.
struct IconPathShape: Shape {
    let elements: [IconPathElement]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for element in elements {
            switch element {
            case .move(let p): path.move(to: rect.point(p))
            case .line(let p): path.addLine(to: rect.point(p))
            case .curve(let p, let c1, let c2): path.addCurve(to: rect.point(p), control1: rect.point(c1), control2: rect.point(c2))
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}

extension CGRect {
    /// A unit-square `IconPoint` (y down) in this rect's coordinates (SwiftUI: y down).
    func point(_ point: IconPoint) -> CGPoint {
        CGPoint(x: minX + CGFloat(point.x) * width, y: minY + CGFloat(point.y) * height)
    }
}
