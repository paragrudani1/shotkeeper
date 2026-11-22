import Foundation

/// SVG sources of the app icon and the menu bar glyph, generated from `IconGeometry` (spec PR 4, "App icon").
/// `design/icon/*.svg` are this output (`shotkeeper-cli icon-svg`, run by `scripts/make-icons.sh`); a core test fails
/// when the committed files drift from it.
public enum IconSVG {
    /// The app icon canvas, in pixels.
    public static let appIconCanvas = 1024.0
    /// Transparent margin around the squircle on the canvas: Apple's macOS icon grid puts an 824 × 824 rounded square
    /// on a 1024 × 1024 canvas, so our icon sits at the same size as other apps in the Dock and Finder.
    public static let appIconMargin = 100.0
    /// The menu bar glyph's canvas (18 pt, `MenuBarGlyph.image`).
    public static let menuBarGlyphCanvas = 18.0

    /// The app icon for the asset catalog: indigo squircle, 6% white top half, white viewfinder corners and sparkle.
    public static func appIcon(_ geometry: IconGeometry = .appIcon) -> String {
        let side = appIconCanvas - 2 * appIconMargin
        let place = { (p: IconPoint) in IconPoint(appIconMargin + p.x * side, appIconMargin + p.y * side) }
        let squircle = pathData(geometry.backgroundPath, place)
        let fill = String(format: "#%06X", IconGeometry.backgroundRGB)
        let canvas = number(appIconCanvas)
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(canvas)" height="\(canvas)" viewBox="0 0 \(canvas) \(canvas)">
          <title>Shotkeeper app icon</title>
          <defs>
            <clipPath id="squircle"><path d="\(squircle)"/></clipPath>
          </defs>
          <path d="\(squircle)" fill="\(fill)"/>
          <rect x="\(number(appIconMargin))" y="\(number(appIconMargin))" width="\(number(side))" height="\(number(side / 2))" \
        fill="#FFFFFF" fill-opacity="\(number(IconGeometry.topHighlightOpacity))" clip-path="url(#squircle)"/>
          <path d="\(pathData(geometry.viewfinderPath, place))" fill="none" stroke="#FFFFFF" \
        stroke-width="\(number(geometry.cornerStroke * side))" stroke-linecap="round" stroke-linejoin="round"/>
          <path d="\(pathData(geometry.sparklePath(), place))" fill="#FFFFFF"/>
        </svg>

        """
    }

    /// The menu bar glyph as a template (black on transparent): outline corners + filled sparkle.
    public static func menuBarGlyph(_ geometry: IconGeometry = .menuBarGlyph) -> String {
        let side = menuBarGlyphCanvas
        let place = { (p: IconPoint) in IconPoint(p.x * side, p.y * side) }
        let canvas = number(side)
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(canvas)" height="\(canvas)" viewBox="0 0 \(canvas) \(canvas)">
          <title>Shotkeeper menu bar glyph (template)</title>
          <path d="\(pathData(geometry.viewfinderPath, place))" fill="none" stroke="#000000" \
        stroke-width="\(number(geometry.cornerStroke * side))" stroke-linecap="round" stroke-linejoin="round"/>
          <path d="\(pathData(geometry.sparklePath(), place))" fill="#000000"/>
        </svg>

        """
    }

    /// SVG path data (`M`, `L`, `C`, `Z`, absolute) for `elements`, each point passed through `place`.
    public static func pathData(_ elements: [IconPathElement], _ place: (IconPoint) -> IconPoint) -> String {
        func xy(_ point: IconPoint) -> String {
            let p = place(point)
            return "\(number(p.x)) \(number(p.y))"
        }
        return elements.map { element -> String in
            switch element {
            case .move(let p): return "M\(xy(p))"
            case .line(let p): return "L\(xy(p))"
            case .curve(let p, let c1, let c2): return "C\(xy(c1)) \(xy(c2)) \(xy(p))"
            case .close: return "Z"
            }
        }.joined(separator: " ")
    }

    /// At most 3 decimals, no trailing zeros, never "-0": stable text for the committed files.
    static func number(_ value: Double) -> String {
        var text = String(format: "%.3f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }
}
