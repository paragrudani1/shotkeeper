import Foundation
@testable import ShotkeeperCore
import XCTest

final class IconPathTests: XCTestCase {
    private func points(_ path: [IconPathElement]) -> [IconPoint] {
        path.flatMap { element -> [IconPoint] in
            switch element {
            case .move(let p), .line(let p): return [p]
            case .curve(let p, let c1, let c2): return [c1, c2, p]
            case .close: return []
            }
        }
    }

    private func cubic(_ p0: IconPoint, _ c1: IconPoint, _ c2: IconPoint, _ p3: IconPoint, _ t: Double) -> IconPoint {
        let u = 1 - t
        func mix(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
            u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
        }
        return IconPoint(mix(p0.x, c1.x, c2.x, p3.x), mix(p0.y, c1.y, c2.y, p3.y))
    }

    func testSquircleIsAClosedSymmetricShapeInsideTheSquare() {
        let path = IconGeometry.appIcon.backgroundPath
        // move + 3 curves, then (line + 3 curves) × 3, then close.
        XCTAssertEqual(path.count, 1 + 3 + 3 * 4 + 1)
        guard case .move = path.first, path.last == .close else { return XCTFail("not a closed path") }
        let all = points(path)
        for p in all { XCTAssertTrue((0...1).contains(p.x) && (0...1).contains(p.y), "\(p)") }
        // Four-fold symmetry: rotating by 90° maps the set of points onto itself.
        func key(_ p: IconPoint) -> String { String(format: "%.9f,%.9f", p.x, p.y) }
        XCTAssertEqual(Set(all.map(key)), Set(all.map { key(IconPoint(1 - $0.y, $0.x)) }))
        XCTAssertEqual(IconGeometry.menuBarGlyph.backgroundPath, [], "the template glyph has no background")
    }

    func testSquircleCornerHasTheSpecRadiusAndMeetsTheEdgesSmoothly() {
        let r = IconGeometry.appIcon.backgroundCornerRadius
        let (start, curves) = ContinuousCorner.curves(radius: r)
        XCTAssertEqual(curves.count, 3)
        // The middle curve is the circular part: on the circle of radius r around (r, r), including its midpoint.
        let arcStart = curves[0].to, arc = curves[1]
        for t in [0, 0.25, 0.5, 0.75, 1] {
            let p = cubic(arcStart, arc.control1, arc.control2, arc.to, t)
            XCTAssertEqual(hypot(p.x - r, p.y - r), r, accuracy: r * 1e-3, "t = \(t)")
        }
        // Tangent continuity: the edge → transition handles lie on the edges, and each transition ends tangent to the
        // arc (its last handle, the joint and the arc's first handle are collinear).
        XCTAssertEqual(start.x, 0)
        XCTAssertEqual(curves[0].control1.x, 0)
        XCTAssertEqual(curves[0].control2.x, 0, accuracy: 1e-12)
        XCTAssertEqual(curves[2].control2.y, 0)
        let joint = arcStart, before = curves[0].control2, after = arc.control1
        let cross = (joint.x - before.x) * (after.y - joint.y) - (joint.y - before.y) * (after.x - joint.x)
        XCTAssertEqual(cross, 0, accuracy: 1e-12)
        // Mirror image across the diagonal.
        XCTAssertEqual(curves[2].to.x, start.y, accuracy: 1e-12)
        XCTAssertEqual(curves[2].control1.x, curves[0].control2.y, accuracy: 1e-12)
    }

    func testViewfinderAndSparklePathsReplayTheGeometry() {
        let geometry = IconGeometry.appIcon
        let corners = geometry.viewfinderCorners
        XCTAssertEqual(geometry.viewfinderPath, corners.flatMap { [.move($0[0]), .line($0[1]), .line($0[2])] })
        let (tips, controls) = geometry.sparkle(scale: 1.35)
        let sparkle = geometry.sparklePath(scale: 1.35)
        XCTAssertEqual(sparkle.first, .move(tips[0]))
        XCTAssertEqual(sparkle[2], .curve(tips[2], control1: controls[1], control2: controls[1]))
        XCTAssertEqual(sparkle.last, .close)
    }
}

final class IconSVGTests: XCTestCase {
    func testNumbersAreStable() {
        XCTAssertEqual(IconSVG.number(46.144), "46.144")
        XCTAssertEqual(IconSVG.number(100), "100")
        XCTAssertEqual(IconSVG.number(0.06), "0.06")
        XCTAssertEqual(IconSVG.number(-0.0001), "0")
        XCTAssertEqual(IconSVG.number(1.23456), "1.235")
    }

    func testAppIconFollowsTheGeometryAndTheSpec() {
        let svg = IconSVG.appIcon()
        let side = 824.0
        XCTAssertTrue(svg.contains(#"viewBox="0 0 1024 1024""#))
        XCTAssertTrue(svg.contains(##"fill="#5856D6""##))
        XCTAssertTrue(svg.contains(#"fill-opacity="0.06""#), "6% white top half")
        XCTAssertTrue(svg.contains(#"x="100" y="100" width="824" height="412""#), "the highlight is the top half")
        XCTAssertTrue(svg.contains(#"stroke-width="46.144""#), "corner stroke 5.6% of the icon")
        XCTAssertTrue(svg.contains(#"stroke-linecap="round""#))
        // The first viewfinder corner, placed on the 824 px body at a 100 px margin.
        let c = IconGeometry.appIcon.viewfinderCorners[0].map { IconPoint(100 + $0.x * side, 100 + $0.y * side) }
        XCTAssertTrue(svg.contains("M\(IconSVG.number(c[0].x)) \(IconSVG.number(c[0].y)) "
                                   + "L\(IconSVG.number(c[1].x)) \(IconSVG.number(c[1].y))"))
        // The sparkle's top tip: 27% wide, centered.
        XCTAssertTrue(svg.contains("M512 \(IconSVG.number(512 - 0.135 * side)) C"))
        // The squircle starts on the left edge, 1.528 radii below the top.
        XCTAssertTrue(svg.contains("M100 \(IconSVG.number(100 + 1.528 * 0.225 * side)) C"))
    }

    func testMenuBarGlyphIsABlackTemplate() {
        let svg = IconSVG.menuBarGlyph()
        XCTAssertTrue(svg.contains(#"viewBox="0 0 18 18""#))
        XCTAssertTrue(svg.contains(#"stroke-width="1.53""#), "8.5% of 18 pt")
        XCTAssertFalse(svg.contains("#5856D6"))
        XCTAssertFalse(svg.contains("#FFFFFF"), "template images are black on transparent")
    }

    /// `design/icon/*.svg` must be the current output: run `scripts/make-icons.sh` after changing `IconGeometry`.
    func testCommittedSVGsMatchTheGeometry() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let folder = root.appendingPathComponent("design/icon")
        for (name, expected) in [("AppIcon.svg", IconSVG.appIcon()), ("MenuBarGlyph.svg", IconSVG.menuBarGlyph())] {
            let committed = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
            XCTAssertEqual(committed, expected, "\(name) is stale: run scripts/make-icons.sh")
        }
    }
}

final class IconComposerBundleTests: XCTestCase {
    func testIconJSONHasTheBackgroundFillAndTwoGroupsFrontFirst() throws {
        let json = IconComposerBundle.iconJSON()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let fill = try XCTUnwrap(object["fill"] as? [String: Any])
        XCTAssertEqual(fill["solid"] as? String, "srgb:0.34510,0.33725,0.83922,1.00000", "#5856D6")
        let groups = try XCTUnwrap(object["groups"] as? [[String: Any]])
        let images = groups.map { (($0["layers"] as? [[String: Any]])?.map { $0["image-name"] as? String }) ?? [] }
        XCTAssertEqual(images, [["2-sparkle.svg"], ["1-corners.svg"]], "front first: sparkle, then corners")
        XCTAssertEqual((object["supported-platforms"] as? [String: String])?["squares"], "shared")
        XCTAssertTrue(json.contains(#""fill" : {"#), "Icon Composer's `\"key\" : value` formatting")
    }

    func testLayersAreTheCoreShapesOnTheFullCanvas() {
        let files = Dictionary(uniqueKeysWithValues: IconComposerBundle.files().map { ($0.path, $0.contents) })
        XCTAssertEqual(Set(files.keys), ["icon.json", "Assets/1-corners.svg", "Assets/2-sparkle.svg"])
        let geometry = IconGeometry.appIcon
        let place = { (p: IconPoint) in IconPoint(p.x * 1024, p.y * 1024) }
        let corners = files["Assets/1-corners.svg"] ?? ""
        XCTAssertTrue(corners.contains(IconSVG.pathData(geometry.viewfinderPath, place)))
        XCTAssertTrue(corners.contains(#"stroke-width="57.344""#), "5.6% of 1024")
        XCTAssertTrue(files["Assets/2-sparkle.svg"]?.contains(IconSVG.pathData(geometry.sparklePath(), place)) ?? false)
        XCTAssertFalse(corners.contains("5856D6"), "no background in the layers: the fill is the document's")
    }

    /// `App/Shotkeeper/AppIcon.icon` must be the current output, file for file: run `scripts/make-icons.sh`.
    func testCommittedIconComposerPackageMatchesTheGeometry() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let package = root.appendingPathComponent("App/Shotkeeper/AppIcon.icon")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: package, includingPropertiesForKeys: [.isRegularFileKey]))
        var committed: [String: String] = [:]
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            let relative = String(url.standardizedFileURL.path.dropFirst(package.standardizedFileURL.path.count + 1))
            committed[relative] = try String(contentsOf: url, encoding: .utf8)
        }
        let expected = Dictionary(uniqueKeysWithValues: IconComposerBundle.files().map { ($0.path, $0.contents) })
        XCTAssertEqual(Set(committed.keys), Set(expected.keys), "AppIcon.icon has extra or missing files")
        for (path, contents) in expected {
            XCTAssertEqual(committed[path], contents, "\(path) is stale: run scripts/make-icons.sh")
        }
    }
}
