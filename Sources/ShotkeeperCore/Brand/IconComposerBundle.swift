import Foundation

/// The macOS 26 layered app icon (`App/Shotkeeper/AppIcon.icon`, an Icon Composer package) generated from
/// `IconGeometry`: the indigo document fill as the background, then the viewfinder corners and the sparkle (front) as
/// two groups, so the system can light them separately and derive the dark, clear and tinted looks.
///
/// Format facts and sources: `docs/research/icon-composer.md`. In short: a folder with `icon.json` and an `Assets/`
/// folder of layer images (SVG preferred, Apple docs); up to four groups, drawn back to front in array order; the
/// background is the document-level `fill`; the first group is the front-most. Apple does not document the `icon.json` schema, so every key used here is
/// one that Icon Composer itself wrote in Apple's "Landmarks: Building an app with Liquid Glass" sample
/// (`Landmarks App Icon.icon/icon.json`). Settings we do not choose are left out, so Icon Composer's defaults apply.
public enum IconComposerBundle {
    /// Layer canvas: Icon Composer's 1024 × 1024 for iPhone, iPad and Mac (Apple docs). The canvas is the whole icon
    /// shape (the system applies the mask), so unlike `IconSVG.appIcon` there is no transparent margin.
    public static let canvas = 1024.0

    static let cornersImage = "1-corners.svg"
    static let sparkleImage = "2-sparkle.svg"

    /// Every file of the package: path inside `AppIcon.icon/` → contents. `scripts/make-icons.sh` writes them.
    public static func files(_ geometry: IconGeometry = .appIcon) -> [(path: String, contents: String)] {
        [
            ("icon.json", iconJSON()),
            ("Assets/\(cornersImage)", cornersSVG(geometry)),
            ("Assets/\(sparkleImage)", sparkleSVG(geometry)),
        ]
    }

    /// `icon.json` in Icon Composer's own formatting (2-space indent, `"key" : value`, keys sorted), so a re-save in
    /// Icon Composer gives a small diff.
    static func iconJSON() -> String {
        func layerGroup(name: String, image: String) -> JSON {
            .object([
                ("layers", .array([.object([
                    ("image-name", .string(image)),
                    ("name", .string(name)),
                ])])),
            ])
        }
        let document = JSON.object([
            ("fill", .object([("solid", .string(srgb(IconGeometry.backgroundRGB)))])),
            // Front first (the sidebar's top-to-bottom order; research note "Group order"): the sparkle in front,
            // the corners behind. Names number back to front, as Apple's docs suggest.
            ("groups", .array([
                layerGroup(name: "2-sparkle", image: sparkleImage),
                layerGroup(name: "1-corners", image: cornersImage),
            ])),
            // "squares" : "shared" = one design for iOS and macOS (as in the Landmarks sample); no watchOS circle.
            ("supported-platforms", .object([("squares", .string("shared"))])),
        ])
        return document.render(indent: "") + "\n"
    }

    static func cornersSVG(_ geometry: IconGeometry) -> String {
        layerSVG(title: "1-corners", body: """
          <path d="\(IconSVG.pathData(geometry.viewfinderPath, place))" fill="none" stroke="#FFFFFF" \
        stroke-width="\(IconSVG.number(geometry.cornerStroke * canvas))" stroke-linecap="round" stroke-linejoin="round"/>
        """)
    }

    static func sparkleSVG(_ geometry: IconGeometry) -> String {
        layerSVG(title: "2-sparkle", body: """
          <path d="\(IconSVG.pathData(geometry.sparklePath(), place))" fill="#FFFFFF"/>
        """)
    }

    private static func place(_ p: IconPoint) -> IconPoint { IconPoint(p.x * canvas, p.y * canvas) }

    private static func layerSVG(title: String, body: String) -> String {
        let side = IconSVG.number(canvas)
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(side)" height="\(side)" viewBox="0 0 \(side) \(side)">
          <title>\(title)</title>
        \(body)
        </svg>

        """
    }

    /// Icon Composer's color string, e.g. `srgb:0.34510,0.33725,0.83922,1.00000` (Landmarks sample).
    static func srgb(_ rgb: UInt32) -> String {
        let channels = [(rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF].map { String(format: "%.5f", Double($0) / 255) }
        return "srgb:" + (channels + ["1.00000"]).joined(separator: ",")
    }
}

/// A minimal ordered JSON value, rendered the way Icon Composer writes `icon.json`.
enum JSON {
    case string(String)
    case array([JSON])
    case object([(String, JSON)])

    func render(indent: String) -> String {
        let inner = indent + "  "
        switch self {
        case .string(let value):
            return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        case .array(let items):
            return "[\n" + items.map { inner + $0.render(indent: inner) }.joined(separator: ",\n") + "\n\(indent)]"
        case .object(let pairs):
            let sorted = pairs.sorted { $0.0 < $1.0 }
            return "{\n" + sorted.map { "\(inner)\"\($0.0)\" : \($0.1.render(indent: inner))" }.joined(separator: ",\n")
                + "\n\(indent)}"
        }
    }
}
