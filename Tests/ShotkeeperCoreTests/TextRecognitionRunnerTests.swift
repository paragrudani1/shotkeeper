import XCTest
@testable import ShotkeeperCore

/// Seam 3 (spec "Testing Decisions"): `TextRecognitionRunner` with a stub `TextRecognizer` over a real in-memory index.
final class TextRecognitionRunnerTests: XCTestCase {
    var dir: TempDir!
    var index: ScreenshotIndex!

    override func setUpWithError() throws {
        dir = try TempDir()
        index = try ScreenshotIndex.inMemory()
    }

    override func tearDown() { dir = nil }

    /// A `done` row whose text is queued, for a real file in the temp folder.
    @discardableResult
    private func pendingRow(_ name: String, takenAt seconds: TimeInterval = 1_800_000_000,
                            _ configure: (inout IndexedScreenshot) -> Void = { _ in }) throws -> IndexedScreenshot {
        let url = try dir.file(name, contents: "png bytes of \(name)")
        var row = IndexedScreenshot.testRow(url.path) {
            $0.textStatus = .pending
            $0.capturedAt = Date(timeIntervalSince1970: seconds)
        }
        configure(&row)
        row.id = try index.save(row)
        return row
    }

    private func runner(_ recognizer: StubTextRecognizer) -> TextRecognitionRunner {
        TextRecognitionRunner(index: index, recognizer: recognizer)
    }

    func testAPendingRowGetsItsTextAndIsDone() async throws {
        let row = try pendingRow("a.png")
        let recognizer = StubTextRecognizer([.success([line("Invoice 2026-0417")])])

        await runner(recognizer).drain()

        let after = try XCTUnwrap(index.lookup(byPath: row.path))
        XCTAssertEqual(after.textStatus, .done)
        XCTAssertEqual(after.recognizedText, "Invoice 2026-0417")
        XCTAssertEqual(after.textRecognizedBy, StubTextRecognizer.id)
        XCTAssertNil(after.textError)
    }

    func testAnImageWithoutTextOrOnlyBlankLinesIsNone() async throws {
        let empty = try pendingRow("empty.png", takenAt: 2)
        let blank = try pendingRow("blank.png", takenAt: 1)
        let recognizer = StubTextRecognizer([.success([]), .success([line("   "), line("\t", top: 0.5)])])

        await runner(recognizer).drain()

        for path in [empty.path, blank.path] {
            let after = try XCTUnwrap(index.lookup(byPath: path))
            XCTAssertEqual(after.textStatus, .noText, path)
            XCTAssertNil(after.recognizedText, path)
            XCTAssertEqual(after.textRecognizedBy, StubTextRecognizer.id, path)
        }
    }

    func testWhitespaceOnlyLinesAreDropped() async throws {
        let row = try pendingRow("a.png")
        let recognizer = StubTextRecognizer([.success([line("Total", top: 0.1), line("  ", top: 0.2),
                                                       line("42.00 EUR", top: 0.3)])])

        await runner(recognizer).drain()

        XCTAssertEqual(try index.lookup(byPath: row.path)?.recognizedText, "Total\n42.00 EUR")
    }

    func testLinesAreStoredTopToBottomThenLeftToRight() async throws {
        let row = try pendingRow("receipt.png")
        // Vision's order is not reading order. "Total" and "42.00" share a baseline but their boxes differ a little in
        // top and height (a different font size): they still count as one row, read left to right.
        let recognizer = StubTextRecognizer([.success([
            line("42.00", top: 0.501, left: 0.7, height: 0.022),
            line("Thank you", top: 0.8, left: 0.3),
            line("ACME Store", top: 0.05, left: 0.3),
            line("Total", top: 0.5, left: 0.1, height: 0.02),
            line("Coffee", top: 0.3, left: 0.1),
            line("3.50", top: 0.299, left: 0.7),
        ])])

        await runner(recognizer).drain()

        XCTAssertEqual(try index.lookup(byPath: row.path)?.recognizedText,
                       "ACME Store\nCoffee\n3.50\nTotal\n42.00\nThank you")
    }

    func testCloseButSeparateRowsKeepTheirOrder() async throws {
        let row = try pendingRow("code.png")
        // Two lines of code, 0.025 apart with 0.02 tall boxes: separate rows, so the left one below stays below.
        let recognizer = StubTextRecognizer([.success([
            line("  return total", top: 0.125, left: 0.05),
            line("let total = items.count + 1", top: 0.1, left: 0.1),
        ])])

        await runner(recognizer).drain()

        XCTAssertEqual(try index.lookup(byPath: row.path)?.recognizedText,
                       "let total = items.count + 1\n  return total")
    }

    /// `count` lines of 999 characters, top to bottom, each starting with its number.
    private func longLines(_ count: Int) -> [RecognizedLine] {
        (0..<count).map { i in
            let text = String(format: "%04d", i) + String(repeating: "x", count: 995)
            return line(text, top: Double(i) / Double(count + 1), height: 0.5 / Double(count + 1))
        }
    }

    func testTextLongerThan100000CharactersIsCutAtALineAndMarked() async throws {
        let row = try pendingRow("huge.png")
        // 100 lines of 999 characters + 99 line breaks = 99,999 characters fit; the 101st line would not.
        let lines = longLines(150)
        let recognizer = StubTextRecognizer([.success(lines)])

        await runner(recognizer).drain()

        let stored = try XCTUnwrap(index.lookup(byPath: row.path)?.recognizedText)
        var storedLines = stored.components(separatedBy: "\n")
        XCTAssertEqual(storedLines.popLast(), "[Text cut here: longer than 100,000 characters]")
        XCTAssertEqual(storedLines, lines.prefix(100).map(\.text))
        XCTAssertEqual(try index.lookup(byPath: row.path)?.textStatus, .done)
    }

    func testTextOfExactly100000CharactersIsKeptWhole() async throws {
        let row = try pendingRow("full.png")
        // 99 lines of 999 + 99 line breaks + one line of 1,000 = 100,000 characters.
        var lines = longLines(99)
        lines.append(line(String(repeating: "y", count: 1000), top: 0.999, height: 0.0005))
        let recognizer = StubTextRecognizer([.success(lines)])

        await runner(recognizer).drain()

        let stored = try XCTUnwrap(index.lookup(byPath: row.path)?.recognizedText)
        XCTAssertEqual(stored.count, 100_000)
        XCTAssertEqual(stored.components(separatedBy: "\n"), lines.map(\.text))
    }

    func testASingleLineLongerThanTheCapKeepsItsFirst100000Characters() async throws {
        let row = try pendingRow("one-line.png")
        let recognizer = StubTextRecognizer([.success([line(String(repeating: "z", count: 100_500))])])

        await runner(recognizer).drain()

        let stored = try XCTUnwrap(index.lookup(byPath: row.path)?.recognizedText)
        XCTAssertEqual(stored, String(repeating: "z", count: 100_000) + "\n[Text cut here: longer than 100,000 characters]")
    }

    // MARK: Failures

    func testARecognizerErrorFailsTheRowWithAShortReasonThatHoldsNoText() async throws {
        let visionError = try pendingRow("vision.png", takenAt: 2)
        let swiftError = try pendingRow("swift.png", takenAt: 1)
        // Errors whose descriptions carry recognized text: none of it may reach `text_error`.
        let recognizer = StubTextRecognizer([
            .failure(NSError(domain: "com.apple.Vision", code: 9,
                             userInfo: [NSLocalizedDescriptionKey: "stopped after IBAN DE89 3704 0044"])),
            .failure(LeakyError(partialText: "IBAN DE89 3704 0044")),
        ])

        await runner(recognizer).drain()

        let after = try XCTUnwrap(index.lookup(byPath: visionError.path))
        XCTAssertEqual(after.textStatus, .failed)
        XCTAssertNil(after.recognizedText)
        XCTAssertEqual(after.textRecognizedBy, StubTextRecognizer.id)
        XCTAssertEqual(after.textError, "could not read the text (com.apple.Vision 9)")
        let swiftReason = try XCTUnwrap(index.lookup(byPath: swiftError.path)?.textError)
        XCTAssertTrue(swiftReason.hasPrefix("could not read the text ("), swiftReason)
        XCTAssertFalse(swiftReason.contains("IBAN"), swiftReason)
    }

    func testAFileMissingAtItsPathFailsWithFileMissingWithoutReadingIt() async throws {
        let row = try pendingRow("gone.png")
        try FileManager.default.removeItem(atPath: row.path)
        let recognizer = StubTextRecognizer([.success([line("never")])])

        await runner(recognizer).drain()

        let after = try XCTUnwrap(index.lookup(byPath: row.path))
        XCTAssertEqual(after.textStatus, .failed)
        XCTAssertEqual(after.textError, "file missing")
        XCTAssertNil(after.recognizedText)
        XCTAssertEqual(recognizer.reads.get, [])
    }

    func testOneFailedRowDoesNotStopTheOthers() async throws {
        let newer = try pendingRow("newer.png", takenAt: 2)
        let older = try pendingRow("older.png", takenAt: 1)
        let recognizer = StubTextRecognizer([.failure(LeakyError(partialText: "x")), .success([line("Older text")])])

        await runner(recognizer).drain()

        XCTAssertEqual(try index.lookup(byPath: newer.path)?.textStatus, .failed)
        XCTAssertEqual(try index.lookup(byPath: older.path)?.recognizedText, "Older text")
    }

    // MARK: Which rows, in which order, at which path

    func testRowsAreReadNewestFirstOneAtATime() async throws {
        let middle = try pendingRow("middle.png", takenAt: 200)
        let oldest = try pendingRow("oldest.png", takenAt: 100)
        let newest = try pendingRow("newest.png", takenAt: 300)
        let notRequested = try pendingRow("not-requested.png", takenAt: 400) { $0.textStatus = nil }
        let recognizer = StubTextRecognizer([.success([line("text")])])

        await runner(recognizer).drain()

        XCTAssertEqual(recognizer.reads.get.map(\.path), [newest.path, middle.path, oldest.path])
        XCTAssertNil(try index.lookup(byPath: notRequested.path)?.textStatus)
    }

    func testTheFileIsReadAtTheRowsCurrentPath() async throws {
        let row = try pendingRow("Screenshot 1.png")
        let renamed = dir.url.appendingPathComponent("Invoice From Acme.png")
        try FileManager.default.moveItem(atPath: row.path, toPath: renamed.path)
        try index.updatePath(from: row.path, to: renamed.path)
        let recognizer = StubTextRecognizer([.success([line("Invoice")])])

        await runner(recognizer).drain()

        XCTAssertEqual(recognizer.reads.get.map(\.path), [renamed.path])
        XCTAssertEqual(try index.lookup(byPath: renamed.path)?.recognizedText, "Invoice")
    }

    func testTheRowsAnalysisAndStatusAreUntouched() async throws {
        let before = try pendingRow("a.png") {
            $0.title = "Invoice From Acme"
            $0.tags = ["invoice"]
            $0.keyText = "Total 42.00"
            $0.description = "An invoice"
            $0.note = "kept name: no title"
            $0.processedAt = Date(timeIntervalSince1970: 1_800_000_100)
        }
        let recognizer = StubTextRecognizer([.success([line("Total 42.00 EUR")])])

        await runner(recognizer).drain()

        var after = try XCTUnwrap(index.lookup(byPath: before.path))
        XCTAssertEqual(after.recognizedText, "Total 42.00 EUR")
        XCTAssertEqual(after.keyText, "Total 42.00", "the model's key_text is kept separately")
        after.recognizedText = nil
        after.textStatus = .pending
        after.textRecognizedBy = nil
        XCTAssertEqual(after, before)
    }

    func testARowRestoredByUndoIsReadLikeAnyOtherAndStaysWhereItIs() async throws {
        let row = try pendingRow("Screenshot 2026-01-13 at 10.22.11.png") { $0.restoredByUndo = true }
        let recognizer = StubTextRecognizer([.success([line("Meeting notes")])])

        await runner(recognizer).drain()

        let after = try XCTUnwrap(index.lookup(byPath: row.path))
        XCTAssertEqual(after.recognizedText, "Meeting notes")
        XCTAssertTrue(after.restoredByUndo)
        XCTAssertEqual(try dir.names(), ["Screenshot 2026-01-13 at 10.22.11.png"])
    }

    func testContentChangedDuringTheReadDropsTheLateResultAndReadsTheRowAgain() async throws {
        let row = try pendingRow("a.png")
        let index = self.index!
        let recognizer = StubTextRecognizer([.success([line("Old picture")]), .success([line("New picture")])])
        // While the first read runs, the file is replaced and the processor saves the row again as `pending`.
        recognizer.onRead.set { url in
            guard recognizer.reads.get.count == 1 else { return }
            try Data("new png bytes".utf8).write(to: url)
            var resaved = row
            resaved.contentHash = "h-new"
            resaved.title = "New title"
            try index.save(resaved)
        }

        await runner(recognizer).drain()

        let after = try XCTUnwrap(index.lookup(byPath: row.path))
        XCTAssertEqual(after.recognizedText, "New picture")
        XCTAssertEqual(after.textStatus, .done)
        XCTAssertEqual(after.contentHash, "h-new")
        XCTAssertEqual(recognizer.reads.get.map(\.path), [row.path, row.path])
    }

    // MARK: Running: launch, change feed, quit

    /// Polls `condition` every 10 ms; fails the test naming `what` after `seconds` instead of hanging.
    private func eventually(_ what: String, seconds: Double = 10, file: StaticString = #filePath, line: UInt = #line,
                            _ condition: () throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while try !condition() {
            guard Date() < deadline else {
                return XCTFail("timed out after \(seconds) s waiting for \(what)", file: file, line: line)
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testStartReadsRowsLeftPendingByTheLastRun() async throws {
        let row = try pendingRow("from-last-launch.png")
        let runner = runner(StubTextRecognizer([.success([line("Left over")])]))

        await runner.start()

        try await eventually("the pending row to be read at launch") {
            try index.lookup(byPath: row.path)?.textStatus == .done
        }
        await runner.stop()
    }

    func testStartedRunnerReadsRowsThatBecomePendingLater() async throws {
        let runner = runner(StubTextRecognizer([.success([line("Fresh")])]))
        await runner.start()

        let row = try pendingRow("new.png")

        try await eventually("the new row to be read") { try index.lookup(byPath: row.path)?.recognizedText == "Fresh" }
        await runner.stop()
    }

    func testStopEndsReadingAfterTheCurrentRow() async throws {
        let first = try pendingRow("first.png", takenAt: 2)
        let second = try pendingRow("second.png", takenAt: 1)
        let recognizer = StubTextRecognizer([.success([line("text")])])
        let runner = runner(recognizer)
        // Quit arrives while the first row is being read.
        recognizer.whileReading.set { await runner.stop() }

        await runner.start()

        try await eventually("the first row to be read") { try index.lookup(byPath: first.path)?.textStatus == .done }
        recognizer.whileReading.set(nil)
        try index.save(index.lookup(byPath: second.path)!) // a change that would wake a running runner
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(try index.lookup(byPath: second.path)?.textStatus, .pending, "stays pending for the next launch")
        XCTAssertEqual(recognizer.reads.get.map(\.path), [first.path])
    }

    func testAStoppedRunnerStartsAgain() async throws {
        let runner = runner(StubTextRecognizer([.success([line("Again")])]))
        await runner.start()
        await runner.stop()
        let row = try pendingRow("a.png")

        await runner.start()

        try await eventually("the row to be read after a restart") {
            try index.lookup(byPath: row.path)?.textStatus == .done
        }
        await runner.stop()
    }
}

/// A recognizer error that (wrongly) carries recognized text in its description.
struct LeakyError: Error, CustomStringConvertible {
    let partialText: String
    var description: String { "failed after reading \(partialText)" }
}

// MARK: - Stub recognizer

/// Returns queued results in order (the last one repeats) and records every file it was asked to read. `onRead` runs
/// inside the read, before the result is returned (to change the row "during" the read).
final class StubTextRecognizer: TextRecognizer, @unchecked Sendable {
    static let id = "stub-recognizer-v1"
    let recognizedBy = StubTextRecognizer.id
    private let results: Locked<[Result<[RecognizedLine], Error>]>
    let reads = Locked<[URL]>([])
    let onRead = Locked<(@Sendable (URL) throws -> Void)?>(nil)
    /// Awaited inside the read, after `onRead` (e.g. to stop the runner mid-read).
    let whileReading = Locked<(@Sendable () async -> Void)?>(nil)

    init(_ results: [Result<[RecognizedLine], Error>]) { self.results = Locked(results) }

    func recognize(_ url: URL) async throws -> [RecognizedLine] {
        reads.mutate { $0.append(url) }
        try onRead.get?(url)
        await whileReading.get?()
        return try results.mutate { $0.count > 1 ? $0.removeFirst() : $0[0] }.get()
    }
}

/// One recognized line. `top` is the distance from the image's top edge (0…1); Vision's boxes have their origin at the
/// bottom left, so the box's `y` is `1 - top - height`.
func line(_ text: String, top: Double = 0.1, left: Double = 0.1, height: Double = 0.02, width: Double = 0.3,
          confidence: Double = 0.9) -> RecognizedLine {
    RecognizedLine(text: text, confidence: confidence,
                   boundingBox: NormalizedBox(x: left, y: 1 - top - height, width: width, height: height))
}
