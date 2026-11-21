import AppKit
import ShotkeeperCore
import SwiftUI

/// The app icon (spec PR 4 "App icon", option A) as a vector view: an indigo squircle with a faint lighter top half,
/// four white viewfinder corners and a white sparkle. Geometry: core `IconGeometry.appIcon`, shared with the menu
/// bar glyph and PR 4's SVG / asset catalog export. Setup shows it at 72 pt.
struct AppIconView: View {
    var size: CGFloat = 72

    var body: some View {
        let geometry = IconGeometry.appIcon
        let squircle = RoundedRectangle(cornerRadius: geometry.backgroundCornerRadius * size, style: .continuous)
        ZStack {
            squircle.fill(Color(nsColor: NSColor(srgbHex: IconGeometry.backgroundRGB)))
            VStack(spacing: 0) {
                Color.white.opacity(IconGeometry.topHighlightOpacity).frame(height: size / 2)
                Spacer(minLength: 0)
            }
            ViewfinderCornersShape(geometry: geometry)
                .stroke(.white, style: StrokeStyle(lineWidth: geometry.cornerStroke * size, lineCap: .round, lineJoin: .round))
            SparkleShape(geometry: geometry).fill(.white)
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
            ViewfinderCornersShape(geometry: geometry)
                .stroke(style: StrokeStyle(lineWidth: max(1, geometry.cornerStroke * size), lineCap: .round, lineJoin: .round))
            SparkleShape(geometry: geometry)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shotkeeper menu bar icon")
        .accessibilityAddTraits(.isImage)
    }
}

/// The four viewfinder corners of `IconGeometry`, scaled to the rect.
struct ViewfinderCornersShape: Shape {
    let geometry: IconGeometry

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for corner in geometry.viewfinderCorners {
            path.addLines(corner.map { rect.point($0) })
        }
        return path
    }
}

/// The 4-point sparkle of `IconGeometry` (concave sides), scaled to the rect.
struct SparkleShape: Shape {
    let geometry: IconGeometry
    var scale: Double = 1

    func path(in rect: CGRect) -> Path {
        let (tips, controls) = geometry.sparkle(scale: scale)
        var path = Path()
        path.move(to: rect.point(tips[0]))
        for index in 0..<4 {
            let control = rect.point(controls[index])
            path.addCurve(to: rect.point(tips[(index + 1) % 4]), control1: control, control2: control)
        }
        path.closeSubpath()
        return path
    }
}

extension CGRect {
    /// A unit-square `IconPoint` (y down) in this rect's coordinates (SwiftUI: y down).
    func point(_ point: IconPoint) -> CGPoint {
        CGPoint(x: minX + CGFloat(point.x) * width, y: minY + CGFloat(point.y) * height)
    }
}
