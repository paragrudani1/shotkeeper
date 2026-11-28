import AppKit
import ShotkeeperCore
import SwiftUI
import XCTest
@testable import Shotkeeper

/// Renders UI states to PNGs (light and dark) so agents without a Mac can look at them. CI uploads the folder as
/// the `Shotkeeper-ui-snapshots` artifact. See docs/wiki/macos-ci.md ("UI snapshots").
///
/// One file per screen (`ToastSnapshots.swift`, `MenuSnapshots.swift`, `SearchSnapshots.swift`, `SetupSnapshots.swift`,
/// `SettingsSnapshots.swift`), each with its catalog, its fixtures (`extension Fixtures`) and one test. To add a
/// state: add ONE line to that screen's `all`, e.g.
///     UISnapshot("search-empty") { SearchView(...) },
/// A new screen gets its own file and one line in `UISnapshotCatalog.all`.
@MainActor
enum UISnapshotCatalog {
    static var all: [UISnapshot] {
        ToastSnapshots.all + MenuSnapshots.all + SearchSnapshots.all + SetupSnapshots.all + SettingsSnapshots.all
    }

    /// `SHOTKEEPER_SNAPSHOT_DIR` (CI passes it as `TEST_RUNNER_SHOTKEEPER_SNAPSHOT_DIR`), else /tmp.
    static var outputDirectory: URL {
        let path = ProcessInfo.processInfo.environment["SHOTKEEPER_SNAPSHOT_DIR"] ?? "/tmp/shotkeeper-ui-snapshots"
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

struct UISnapshot {
    let name: String
    let make: @MainActor () -> AnyView

    init<V: View>(_ name: String, @ViewBuilder _ make: @escaping @MainActor () -> V) {
        self.name = name
        self.make = { AnyView(make()) }
    }
}

/// Writes each snapshot in light and dark mode to `UISnapshotCatalog.outputDirectory` as `<name>-light.png` and
/// `<name>-dark.png`, and fails for an image that looks blank.
@MainActor
enum UISnapshotWriter {
    static func write(_ snapshots: [UISnapshot], file: StaticString = #filePath, line: UInt = #line) throws {
        let directory = UISnapshotCatalog.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [String] = []
        for snapshot in snapshots {
            let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
            for (suffix, appearance) in appearances {
                let rep = try SnapshotRenderer.render(snapshot.make(), appearance: appearance)
                XCTAssertGreaterThan(SnapshotRenderer.distinctColors(in: rep), 8, "\(snapshot.name)-\(suffix) looks blank",
                                     file: file, line: line)
                let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]), file: file, line: line)
                let url = directory.appendingPathComponent("\(snapshot.name)-\(suffix).png")
                try data.write(to: url)
                written.append(url.lastPathComponent)
            }
        }
        print("UI snapshots: wrote \(written.count) PNGs to \(directory.path)")
    }
}

@MainActor
final class UISnapshotCatalogTests: XCTestCase {
    /// Two screens using one name would overwrite each other's PNGs in the artifact.
    func testSnapshotNamesAreUnique() {
        let names = UISnapshotCatalog.all.map(\.name)
        let repeated = Dictionary(grouping: names, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        XCTAssertEqual(repeated, [])
        XCTAssertGreaterThan(names.count, 0)
    }
}

@MainActor
enum SnapshotRenderer {
    /// Hosts `view` in an offscreen window with `appearance`, on a neutral desktop-like backdrop, and draws it at 2×.
    static func render(_ view: AnyView, appearance: NSAppearance.Name, scale: CGFloat = 2) throws -> NSBitmapImageRep {
        let isDark = appearance == .darkAqua
        let framed = view
            .shadow(color: .black.opacity(isDark ? 0.5 : 0.22), radius: 14, y: 6)
            .padding(28)
            .background(LinearGradient(colors: isDark ? [Color(white: 0.16), Color(white: 0.24)]
                                                      : [Color(red: 0.80, green: 0.84, blue: 0.90),
                                                         Color(red: 0.90, green: 0.88, blue: 0.92)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .environment(\.colorScheme, isDark ? .dark : .light)
            .environment(\.thumbnailSource, FakeThumbnails.source)
        let hosting = NSHostingView(rootView: framed)
        hosting.appearance = NSAppearance(named: appearance)
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))  // let SwiftUI finish its first update
        hosting.layoutSubtreeIfNeeded()

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else {
            throw NSError(domain: "SnapshotRenderer", code: 1)
        }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.close()
        return rep
    }

    /// Rough "is anything drawn" check on a sample grid.
    static func distinctColors(in rep: NSBitmapImageRep) -> Int {
        var colors = Set<UInt32>()
        let step = max(1, min(rep.pixelsWide, rep.pixelsHigh) / 40)
        for x in stride(from: 0, to: rep.pixelsWide, by: step) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: step) {
                var pixel = [Int](repeating: 0, count: 4)
                rep.getPixel(&pixel, atX: x, y: y)
                colors.insert(UInt32(pixel[0]) << 24 | UInt32(pixel[1]) << 16 | UInt32(pixel[2]) << 8 | UInt32(pixel[3]))
            }
        }
        return colors.count
    }
}

/// Generated "screenshot" thumbnails: a colored app header and text lines, color picked from the path.
enum FakeThumbnails {
    static let source = ThumbnailSource(cached: { path, side in image(for: path, side: side) },
                                        load: { path, side, _ in image(for: path, side: side) })

    /// Square for thumbnails; landscape (16:10) for large previews (side > 100), like a real screenshot.
    @MainActor
    static func image(for path: String, side: CGFloat) -> NSImage? {
        guard !path.isEmpty else { return nil }
        let hues: [CGFloat] = [0.58, 0.08, 0.36, 0.75, 0.95]
        let hue = hues[path.unicodeScalars.reduce(0) { $0 + Int($1.value) } % hues.count]  // stable across runs
        let size = side > 100 ? NSSize(width: 320, height: 200) : NSSize(width: 120, height: 120)
        return NSImage(size: size, flipped: true) { rect in
            let unit = rect.height / 120
            NSColor.white.setFill()
            rect.fill()
            NSColor(calibratedHue: hue, saturation: 0.55, brightness: 0.85, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: rect.width, height: 26 * unit).fill()
            NSColor(white: 0.75, alpha: 1).setFill()
            for (row, width) in [0.8, 0.6, 0.9, 0.5, 0.7].enumerated() {
                NSBezierPath(roundedRect: NSRect(x: 10 * unit, y: (38 + CGFloat(row) * 15) * unit,
                                                 width: (rect.width - 20 * unit) * width, height: 7 * unit),
                             xRadius: 3 * unit, yRadius: 3 * unit).fill()
            }
            return true
        }
    }
}

@MainActor
enum Fixtures {
    /// 2026-11-21 16:24 UTC.
    static let now = Date(timeIntervalSince1970: 1_795_278_240)
    static let time: TimeLabel = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return TimeLabel(calendar: calendar, locale: Locale(identifier: "en_US"))
    }()
    static let account = "0123456789abcdef0123456789abcdef"
}
