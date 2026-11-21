import Foundation

/// A point in a unit square (0…1), y pointing down.
public struct IconPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

/// The shape of the app icon and the menu bar glyph (spec PR 4, "App icon", option A): a squircle, four rounded
/// viewfinder corners and a 4-point sparkle in the center. Every length is a fraction of the icon's side, so the
/// SwiftUI view, the menu bar template image and PR 4's SVG/asset export draw the same thing.
public struct IconGeometry: Equatable, Sendable {
    /// Background squircle corner radius; 0 = no background (the template glyph).
    public var backgroundCornerRadius: Double
    /// From the edge to each viewfinder corner's vertex.
    public var cornerInset: Double
    /// Length of each arm of a viewfinder corner.
    public var cornerArm: Double
    /// Stroke width of the corners (round caps and joins).
    public var cornerStroke: Double
    /// Half the sparkle's width (tip to center).
    public var sparkleRadius: Double
    /// Where the concave sides bend: the control point's offset from the center along each diagonal, as a fraction
    /// of `sparkleRadius`.
    public var sparklePinch: Double

    public init(backgroundCornerRadius: Double, cornerInset: Double, cornerArm: Double, cornerStroke: Double,
                sparkleRadius: Double, sparklePinch: Double) {
        self.backgroundCornerRadius = backgroundCornerRadius
        self.cornerInset = cornerInset
        self.cornerArm = cornerArm
        self.cornerStroke = cornerStroke
        self.sparkleRadius = sparkleRadius
        self.sparklePinch = sparklePinch
    }

    /// The app icon: squircle radius ≈ 22.5%, corner stroke ≈ 5.6%, sparkle ≈ 27% of the size (spec PR 4).
    public static let appIcon = IconGeometry(backgroundCornerRadius: 0.225, cornerInset: 0.22, cornerArm: 0.16,
                                             cornerStroke: 0.056, sparkleRadius: 0.135, sparklePinch: 0.16)

    /// The 18 pt menu bar template: no background, the corners pushed out and drawn heavier so it reads like other
    /// menu bar glyphs (PR 1, `MenuBarGlyph`).
    public static let menuBarGlyph = IconGeometry(backgroundCornerRadius: 0, cornerInset: 0.1, cornerArm: 0.26,
                                                  cornerStroke: 0.085, sparkleRadius: 0.2, sparklePinch: 0.16)

    /// Icon fill #5856D6 (the spec's light indigo, in both appearances: an icon does not change with dark mode).
    public static let backgroundRGB: UInt32 = 0x5856D6
    /// White over the top half of the background.
    public static let topHighlightOpacity = 0.06

    /// Four 3-point polylines (arm end, vertex, arm end): top-left, top-right, bottom-right, bottom-left.
    public var viewfinderCorners: [[IconPoint]] {
        let near = cornerInset, far = 1 - cornerInset, arm = cornerArm
        return [
            [IconPoint(near, near + arm), IconPoint(near, near), IconPoint(near + arm, near)],
            [IconPoint(far - arm, near), IconPoint(far, near), IconPoint(far, near + arm)],
            [IconPoint(far, far - arm), IconPoint(far, far), IconPoint(far - arm, far)],
            [IconPoint(near + arm, far), IconPoint(near, far), IconPoint(near, far - arm)],
        ]
    }

    /// The sparkle's four tips (top, right, bottom, left) and, for each tip, the control point of the curve to the
    /// next tip (one quadratic control, or both cubic controls at the same point).
    /// - Parameter scale: the menu bar pulse draws it bigger.
    public func sparkle(scale: Double = 1) -> (tips: [IconPoint], controls: [IconPoint]) {
        let r = sparkleRadius * scale, p = r * sparklePinch, c = 0.5
        let tips = [IconPoint(c, c - r), IconPoint(c + r, c), IconPoint(c, c + r), IconPoint(c - r, c)]
        let controls = [IconPoint(c + p, c - p), IconPoint(c + p, c + p), IconPoint(c - p, c + p), IconPoint(c - p, c - p)]
        return (tips, controls)
    }
}
