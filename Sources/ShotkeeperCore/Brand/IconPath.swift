import Foundation

/// One step of a vector path in the unit square (y down). The icon's shapes are built once here as paths; the SwiftUI
/// view, the AppKit menu bar glyph and the SVG export (`IconSVG`) only scale and replay them.
public enum IconPathElement: Equatable, Sendable {
    case move(IconPoint)
    case line(IconPoint)
    /// Cubic Bézier to the point.
    case curve(IconPoint, control1: IconPoint, control2: IconPoint)
    case close
}

extension IconGeometry {
    /// The background squircle: a rounded square with continuous ("squircle") corners of radius
    /// `backgroundCornerRadius`. Empty when the radius is 0 (the template glyph has no background).
    ///
    /// Each corner is line → transition curve → circular arc → transition curve → line, so the curvature eases in
    /// instead of jumping from 0 to 1/r like a plain rounded rectangle. The shape is our own choice, made to look like
    /// Apple's continuous corners (SwiftUI `RoundedRectangle(style: .continuous)`); see `ContinuousCorner`.
    public var backgroundPath: [IconPathElement] {
        let r = min(backgroundCornerRadius, 0.5 / ContinuousCorner.extent)
        guard r > 0 else { return [] }
        // Local corner coordinates (corner at the origin, from the incoming edge to the outgoing edge, clockwise on
        // screen) mapped to each of the four corners.
        let maps: [(IconPoint) -> IconPoint] = [
            { IconPoint($0.x, $0.y) },            // top-left: up the left edge, then along the top
            { IconPoint(1 - $0.y, $0.x) },        // top-right
            { IconPoint(1 - $0.x, 1 - $0.y) },    // bottom-right
            { IconPoint($0.y, 1 - $0.x) },        // bottom-left
        ]
        let corner = ContinuousCorner.curves(radius: r)
        var path: [IconPathElement] = []
        for (index, map) in maps.enumerated() {
            let start = map(corner.start)
            path.append(index == 0 ? .move(start) : .line(start))
            for curve in corner.curves {
                path.append(.curve(map(curve.to), control1: map(curve.control1), control2: map(curve.control2)))
            }
        }
        path.append(.close)
        return path
    }

    /// The four viewfinder corners as open polylines (stroke them with round caps and joins, width `cornerStroke`).
    public var viewfinderPath: [IconPathElement] {
        viewfinderCorners.flatMap { corner in [.move(corner[0])] + corner.dropFirst().map { .line($0) } }
    }

    /// The filled 4-point sparkle (concave sides); `scale` > 1 is the menu bar pulse frame.
    public func sparklePath(scale: Double = 1) -> [IconPathElement] {
        let (tips, controls) = sparkle(scale: scale)
        var path: [IconPathElement] = [.move(tips[0])]
        for index in 0..<4 {
            path.append(.curve(tips[(index + 1) % 4], control1: controls[index], control2: controls[index]))
        }
        path.append(.close)
        return path
    }
}

/// The continuous corner of `IconGeometry.backgroundPath`, in local coordinates: the corner vertex at the origin, the
/// incoming edge along x = 0 and the outgoing edge along y = 0 (both in units of the unit square).
enum ContinuousCorner {
    /// Where the corner starts and ends along each edge, in corner radii (a plain rounded rectangle would use 1).
    static let extent = 1.528
    /// The first control point of the transition curve, this many radii in from the start (along the edge).
    static let edgeHandle = 0.44
    /// The circular part of the corner covers 90° − 2 × this angle around the corner's circle center (r, r).
    static let arcStartDegrees = 21.7

    struct Curve: Equatable {
        var to: IconPoint
        var control1: IconPoint
        var control2: IconPoint
    }

    /// The start point on the incoming edge and three cubic curves (transition, arc, transition) to the outgoing edge.
    static func curves(radius r: Double) -> (start: IconPoint, curves: [Curve]) {
        let phi0 = arcStartDegrees * .pi / 180
        // The arc: points (r − r·cos φ, r − r·sin φ) for φ from phi0 to 90° − phi0.
        let a = IconPoint(r * (1 - cos(phi0)), r * (1 - sin(phi0)))
        let b = IconPoint(a.y, a.x)
        // Transition: starts on the edge, ends tangent to the arc. Its second control point is where the arc's
        // tangent at `a` crosses the edge, so the curve meets the arc without a kink.
        let tangentLength = (1 - cos(phi0)) / sin(phi0) * r
        let edgeControl = a.y + tangentLength * cos(phi0)
        let start = IconPoint(0, extent * r)
        let first = Curve(to: a, control1: IconPoint(0, (extent - edgeHandle) * r), control2: IconPoint(0, edgeControl))
        // A circular arc as one cubic: handle length 4/3·tan(Δ/4) radii along the tangents.
        let k = 4.0 / 3.0 * tan((Double.pi / 2 - 2 * phi0) / 4) * r
        let arc = Curve(to: b, control1: IconPoint(a.x + k * sin(phi0), a.y - k * cos(phi0)),
                        control2: IconPoint(b.x - k * cos(phi0), b.y + k * sin(phi0)))
        // The second transition mirrors the first across the diagonal.
        let last = Curve(to: IconPoint(extent * r, 0), control1: IconPoint(edgeControl, 0),
                         control2: IconPoint((extent - edgeHandle) * r, 0))
        return (start, [first, arc, last])
    }
}
