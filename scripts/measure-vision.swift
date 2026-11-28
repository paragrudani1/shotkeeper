// Measures Apple Vision text recognition settings on screenshots (ticket 05, spec "Vision settings to measure on a
// real Mac"). macOS only. It is not part of the Swift package or the app; CI type-checks it and runs it on generated
// sample images (.github/workflows/ci.yml, macos-app job).
//
//   xcrun swift scripts/measure-vision.swift <folder>          # sweep; <folder> holds the images and strings.txt
//   xcrun swift scripts/measure-vision.swift --make-sample <new folder>   # writes 2 synthetic images + strings.txt
//
// How to run it, and the strings.txt format: docs/research/vision-ocr-settings.md, "How to run (Parag)".
//
// Privacy: recognised text stays in memory. The tool prints and saves only pass/fail per expected string (by its line
// number in strings.txt), timings and memory. Nothing is uploaded.
//
// Request setup (ticket 04's `VisionTextRecognizer` must use the same, or the numbers do not apply):
//   VNImageRequestHandler(url: <original file>, options: [:]), one VNRecognizeTextRequest per image with
//   revision = VNRecognizeTextRequestRevision3, recognitionLevel, minimumTextHeight, usesLanguageCorrection,
//   automaticallyDetectsLanguage = true for .accurate (accurate only), recognitionLanguages left at the default,
//   topCandidates(1) per observation.
// Sources: docs/research/spotlight-shortcuts-ocr.md §3 [V1] [V3] [V4] [WV22];
//   https://developer.apple.com/documentation/vision/vnrecognizetextrequest
//   https://developer.apple.com/documentation/vision/recognizing-text-in-images

#if !os(macOS)
#error("measure-vision.swift runs on macOS only (it uses Apple Vision).")
#endif

import CoreGraphics
import CoreText
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

let toolVersion = "1"

// MARK: - Errors and output

struct ToolError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func progress(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

// MARK: - The grid (ticket 05)

enum Height {
    case fraction(Int)  // 1/n of the image height
    case pixelFloor(Int)  // n pixels, converted per image: n / pixelHeight

    var label: String {
        switch self {
        case .fraction(let n): return "1/\(n)"
        case .pixelFloor(let px): return "\(px)px"
        }
    }

    func minimumTextHeight(pixelHeight: Int) -> Float {
        switch self {
        case .fraction(let n): return 1 / Float(n)
        case .pixelFloor(let px): return min(1, Float(px) / Float(max(pixelHeight, 1)))
        }
    }
}

struct Combination {
    let level: VNRequestTextRecognitionLevel
    let height: Height
    let languageCorrection: Bool

    /// Automatic language detection is accurate-only [V1] [WV22]; the spec measures it on.
    var automaticLanguage: Bool { level == .accurate }
    var levelLabel: String { level == .accurate ? "accurate" : "fast" }
    /// Same shape as ticket 04's `text_recognized_by`.
    var id: String {
        "vision-r3-\(levelLabel)-h\(height.label)-lc\(languageCorrection ? 1 : 0)"
    }
}

let heights: [Height] = [.fraction(32), .fraction(64), .fraction(96), .fraction(128), .pixelFloor(10)]
let grid: [Combination] = [VNRequestTextRecognitionLevel.accurate, .fast].flatMap { level in
    heights.flatMap { height in
        [true, false].map { Combination(level: level, height: height, languageCorrection: $0) }
    }
}

// MARK: - Vision

func makeRequest(_ combination: Combination, pixelHeight: Int) -> VNRecognizeTextRequest {
    // [V1] VNRecognizeTextRequest properties; revision 3 and automaticallyDetectsLanguage need macOS 13 [V1].
    let request = VNRecognizeTextRequest()
    request.revision = VNRecognizeTextRequestRevision3
    request.recognitionLevel = combination.level
    request.minimumTextHeight = combination.height.minimumTextHeight(pixelHeight: pixelHeight)
    request.usesLanguageCorrection = combination.languageCorrection
    request.automaticallyDetectsLanguage = combination.automaticLanguage
    return request
}

/// Recognised lines, in Vision's order. Never printed.
func recognize(_ url: URL, _ combination: Combination, pixelHeight: Int) throws -> [String] {
    try autoreleasepool {
        let request = makeRequest(combination, pixelHeight: pixelHeight)
        let handler = VNImageRequestHandler(url: url, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}

// MARK: - Images and expected strings

struct Image {
    let url: URL
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int
}

let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff"]

func loadImages(in folder: URL) throws -> [Image] {
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        .filter { imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    return try names.map { name in
        let url = folder.appendingPathComponent(name)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw ToolError("Cannot read the size of \(name). Is it an image?") }
        return Image(url: url, name: name, pixelWidth: width, pixelHeight: height)
    }
}

struct Expected {
    let line: Int  // line number in strings.txt; the only way the output refers to the string
    let image: String
    let text: String
    let exact: Bool
}

/// `<image file name>: <text>` or `<image file name>: exact: <text>`; `#` lines and blank lines are ignored.
/// macOS file names cannot contain ":", so the first ":" ends the file name.
func parseStrings(_ contents: String, imageNames: Set<String>) throws -> [Expected] {
    var result: [Expected] = []
    for (index, raw) in contents.components(separatedBy: .newlines).enumerated() {
        let lineNumber = index + 1
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { continue }
        guard let colon = line.firstIndex(of: ":") else {
            throw ToolError("strings.txt line \(lineNumber): expected \"<image file name>: <text>\".")
        }
        let image = line[..<colon].trimmingCharacters(in: .whitespaces)
        var text = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        var exact = false
        if text.lowercased().hasPrefix("exact:") {
            exact = true
            text = String(text.dropFirst("exact:".count)).trimmingCharacters(in: .whitespaces)
        }
        guard imageNames.contains(image) else {
            throw ToolError("strings.txt line \(lineNumber): no image named \"\(image)\" in the folder.")
        }
        guard !text.isEmpty else { throw ToolError("strings.txt line \(lineNumber): the text is empty.") }
        result.append(Expected(line: lineNumber, image: image, text: text, exact: exact))
    }
    return result
}

func collapseWhitespace(_ s: String) -> String {
    s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// Plain strings: case-insensitive. `exact:` strings: same characters and case (runs of spaces count as one, since
/// Vision does not keep indentation). Searched in each line and in all lines joined by a space.
func isFound(_ expected: Expected, in lines: [String]) -> Bool {
    let needle = collapseWhitespace(expected.text)
    let haystacks = lines.map(collapseWhitespace) + [collapseWhitespace(lines.joined(separator: " "))]
    let options: String.CompareOptions = expected.exact ? [] : [.caseInsensitive]
    return haystacks.contains { $0.range(of: needle, options: options) != nil }
}

// MARK: - Memory

/// phys_footprint, the number Activity Monitor shows as "Memory".
func footprintBytes() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}

/// Samples the footprint every 5 ms on a background queue and keeps the highest value.
final class PeakSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: UInt64 = 0
    private let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))

    init() {
        timer.schedule(deadline: .now(), repeating: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.record() }
    }

    func start() { record(); timer.resume() }

    func stop() -> UInt64 {
        timer.cancel()
        record()
        lock.lock(); defer { lock.unlock() }
        return peak
    }

    private func record() {
        let now = footprintBytes()
        lock.lock(); peak = max(peak, now); lock.unlock()
    }
}

// MARK: - Sweep

struct Row {
    let combination: Combination
    let median: Double
    let slowest: Double
    let slowestImage: String
    let peakBytes: UInt64
    let addedBytes: UInt64
    let found: Int
    let exactFound: Int
    let missed: [Int]
    let errors: [String]
}

func seconds(_ start: UInt64, _ end: UInt64) -> Double { Double(end - start) / 1_000_000_000 }

func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let mid = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
}

func measure(_ combination: Combination, images: [Image], expected: [Expected]) -> Row {
    let baseline = footprintBytes()
    let sampler = PeakSampler()
    sampler.start()
    var times: [(Double, String)] = []
    var foundByLine: [Int: Bool] = [:]
    var errors: [String] = []
    for image in images {
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let lines = try recognize(image.url, combination, pixelHeight: image.pixelHeight)
            times.append((seconds(start, DispatchTime.now().uptimeNanoseconds), image.name))
            for item in expected where item.image == image.name {
                foundByLine[item.line] = isFound(item, in: lines)
            }
        } catch {
            errors.append("\(image.name): \(error.localizedDescription)")
        }
    }
    let peak = sampler.stop()
    let slowest = times.max { $0.0 < $1.0 }
    return Row(
        combination: combination,
        median: median(times.map(\.0)),
        slowest: slowest?.0 ?? 0,
        slowestImage: slowest?.1 ?? "-",
        peakBytes: peak,
        addedBytes: peak > baseline ? peak - baseline : 0,
        found: expected.filter { !$0.exact && foundByLine[$0.line] == true }.count,
        exactFound: expected.filter { $0.exact && foundByLine[$0.line] == true }.count,
        missed: expected.filter { foundByLine[$0.line] != true }.map(\.line),
        errors: errors
    )
}

// MARK: - Report

func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "unknown" }
    return String(cString: buffer)
}

func megabytes(_ bytes: UInt64) -> String { String(format: "%.0f", Double(bytes) / 1_048_576) }
func secondsText(_ value: Double) -> String { String(format: "%.3f", value) }

func report(rows: [Row], images: [Image], expected: [Expected], started: Date) -> String {
    let plain = expected.filter { !$0.exact }.count
    let exact = expected.count - plain
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withSpaceBetweenDateAndTime]
    formatter.timeZone = .current
    var out: [String] = []
    out.append("## Vision sweep (measure-vision.swift v\(toolVersion))")
    out.append("")
    out.append("- Run: \(formatter.string(from: started))")
    out.append("- Mac: \(sysctlString("hw.model")), \(sysctlString("machdep.cpu.brand_string")), "
        + "\(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB, "
        + "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    out.append("- Request: VNRecognizeTextRequest revision 3, VNImageRequestHandler(url:), one image at a time; "
        + "automatic language detection on for accurate (not available for fast)")
    out.append("- Images: \(images.count). Expected strings: \(plain) plain, \(exact) exact (code)")
    out.append("- Times include reading the file. Memory: peak = whole tool process; added = peak minus before the row")
    out.append("")
    out.append("| # | id | level | min height | lang. correction | median s | slowest s | slowest image | peak MB "
        + "| added MB | found (of \(plain)) | exact found (of \(exact)) | missed (strings.txt lines) | errors |")
    out.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for (index, row) in rows.enumerated() {
        let c = row.combination
        let missed = row.missed.isEmpty ? "-" : row.missed.map { "L\($0)" }.joined(separator: " ")
        out.append("| \(index + 1) | \(c.id) | \(c.levelLabel) | \(c.height.label) | \(c.languageCorrection ? "on" : "off") "
            + "| \(secondsText(row.median)) | \(secondsText(row.slowest)) | \(row.slowestImage) "
            + "| \(megabytes(row.peakBytes)) | \(megabytes(row.addedBytes)) | \(row.found) | \(row.exactFound) "
            + "| \(missed) | \(row.errors.count) |")
    }
    out.append("")
    out.append("### Images")
    out.append("")
    out.append("| image | pixels | expected strings (lines) |")
    out.append("|---|---|---|")
    for image in images {
        let lines = expected.filter { $0.image == image.name }.map { "L\($0.line)\($0.exact ? " exact" : "")" }
        out.append("| \(image.name) | \(image.pixelWidth)×\(image.pixelHeight) "
            + "| \(lines.isEmpty ? "-" : lines.joined(separator: ", ")) |")
    }
    let errors = rows.flatMap { row in row.errors.map { "- \(row.combination.id): \($0)" } }
    if !errors.isEmpty {
        out.append("")
        out.append("### Errors")
        out.append("")
        out.append(contentsOf: errors)
    }
    return out.joined(separator: "\n") + "\n"
}

// MARK: - Sample images (for CI and a first try)

func renderSample(to url: URL, width: Int, height: Int, texts: [(String, CGFloat, CGFloat, CGFloat, Bool)]) throws {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw ToolError("Cannot create a drawing context.") }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for (text, size, x, yFromTop, monospaced) in texts {
        let font = CTFontCreateWithName((monospaced ? "Menlo" : "Helvetica") as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = CGPoint(x: x, y: CGFloat(height) - yFromTop)
        CTLineDraw(line, context)
    }
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw ToolError("Cannot encode \(url.lastPathComponent).") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw ToolError("Cannot write \(url.lastPathComponent).") }
}

/// Creates a new folder (fails if it exists) with two synthetic screenshots and their strings.txt.
func makeSample(at folder: URL) throws {
    guard !FileManager.default.fileExists(atPath: folder.path) else {
        throw ToolError("\(folder.path) already exists; give a new folder name.")
    }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    // A Retina-sized "full screen" with a small title-bar name, and a small region with a timestamp.
    try renderSample(to: folder.appendingPathComponent("01-sample-full-screen.png"), width: 2880, height: 1800, texts: [
        ("report-final-v2.pdf", 26, 1300, 40, false),
        ("let total = items.count + 1", 30, 200, 400, true),
        ("Quarterly summary for the design team", 48, 200, 260, false),
    ])
    try renderSample(to: folder.appendingPathComponent("02-sample-region.png"), width: 640, height: 200, texts: [
        ("Sent 10:42 AM", 22, 40, 110, false),
    ])
    let strings = """
        # Sample strings for the two synthetic images.
        01-sample-full-screen.png: report-final-v2.pdf
        01-sample-full-screen.png: exact: let total = items.count + 1
        02-sample-region.png: 10:42 AM
        """
    try Data((strings + "\n").utf8).write(to: folder.appendingPathComponent("strings.txt"), options: .withoutOverwriting)
}

// MARK: - Main

func run(_ arguments: [String]) throws -> Int32 {
    if arguments.count == 2, arguments[0] == "--make-sample" {
        try makeSample(at: URL(fileURLWithPath: arguments[1]))
        progress("Wrote a sample folder at \(arguments[1]).")
        return 0
    }
    let check = arguments.contains("--check")
    let positional = arguments.filter { $0 != "--check" }
    guard positional.count == 1, !positional[0].hasPrefix("-") else {
        progress("Usage: xcrun swift scripts/measure-vision.swift <folder with screenshots and strings.txt>")
        progress("       xcrun swift scripts/measure-vision.swift --make-sample <new folder>")
        return 64
    }
    let folder = URL(fileURLWithPath: positional[0])
    let images = try loadImages(in: folder)
    guard !images.isEmpty else { throw ToolError("No .png/.jpg/.heic/.tiff images in \(folder.path).") }
    let stringsURL = folder.appendingPathComponent("strings.txt")
    guard let contents = try? String(contentsOf: stringsURL, encoding: .utf8) else {
        throw ToolError("Missing \(stringsURL.path). See docs/research/vision-ocr-settings.md for the format.")
    }
    let expected = try parseStrings(contents, imageNames: Set(images.map(\.name)))

    let started = Date()
    progress("\(images.count) images, \(expected.count) expected strings, \(grid.count) settings to try.")
    progress("Warming up Vision (not timed)...")
    for level in [VNRequestTextRecognitionLevel.accurate, .fast] {
        let warmUp = Combination(level: level, height: .fraction(32), languageCorrection: true)
        _ = try? recognize(images[0].url, warmUp, pixelHeight: images[0].pixelHeight)
    }
    var rows: [Row] = []
    for (index, combination) in grid.enumerated() {
        let rowStart = DispatchTime.now().uptimeNanoseconds
        let row = measure(combination, images: images, expected: expected)
        rows.append(row)
        progress("[\(index + 1)/\(grid.count)] \(combination.id): "
            + "\(String(format: "%.1f", seconds(rowStart, DispatchTime.now().uptimeNanoseconds))) s")
    }

    let text = report(rows: rows, images: images, expected: expected, started: started)
    print(text)
    let stamp = DateFormatter()
    stamp.dateFormat = "yyyy-MM-dd-HHmmss"
    let reportURL = folder.appendingPathComponent("vision-results-\(stamp.string(from: started)).md")
    try Data(text.utf8).write(to: reportURL, options: .withoutOverwriting)
    progress("Saved the table to \(reportURL.path)")

    let anyErrors = rows.contains { !$0.errors.isEmpty }
    let anyComplete = rows.contains { $0.missed.isEmpty && $0.errors.isEmpty }
    if !anyComplete {
        progress("Note: no setting found every string. Check strings.txt for typos (the table lists missed lines).")
    }
    return check && (anyErrors || !anyComplete) ? 1 : 0
}

do {
    exit(try run(Array(CommandLine.arguments.dropFirst())))
} catch {
    progress("Error: \(error)")
    exit(1)
}
