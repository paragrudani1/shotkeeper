import Foundation

/// Reads the text of `pending` rows on this Mac, one at a time, newest first (spec "Text recognition: when it runs").
///
/// `ScreenshotProcessor` marks a row `pending` when its analysis succeeds; this runner then reads the original file at
/// the row's current path with the `TextRecognizer` and stores the text through the index's conditional write
/// (`ScreenshotIndex.setRecognizedText`). If the file changed during the read, the processor has saved the row again
/// as `pending` with a new hash, so the write is refused and the row is read again (story 45). The analysis and
/// `status` of the row are never touched, nothing is renamed, nothing is uploaded.
///
/// It takes no settings: Pause controls what is analysed and uploaded, not reading (spec decision 8), and rows
/// restored by Undo are read like any other.
///
/// Privacy: recognized text goes only into the index. It is never logged, and `text_error` holds a short reason
/// (`fileMissingReason`, or an error's domain and code), never text.
public actor TextRecognitionRunner {
    /// `text_error` for a row whose file is not at its indexed path.
    public static let fileMissingReason = "file missing"

    private let index: ScreenshotIndex
    private let recognizer: any TextRecognizer
    private var runTask: Task<Void, Never>?
    private var stopped = false
    private var isDraining = false

    public init(index: ScreenshotIndex, recognizer: any TextRecognizer) {
        self.index = index
        self.recognizer = recognizer
    }

    /// At launch: reads the rows still `pending` (from the last run too), then every row that becomes `pending`
    /// (woken by `ScreenshotIndex.changes()`), at utility priority. Does nothing while already started.
    public func start() {
        guard runTask == nil else { return }
        stopped = false
        let changes = index.changes() // subscribed before the first pass, so no change is missed
        runTask = Task(priority: .utility) { [weak self] in
            await self?.drain()
            for await _ in changes {
                guard let self, !Task.isCancelled else { return }
                await self.drain()
            }
        }
    }

    /// On quit: no new row is started. A read in progress finishes and is stored; rows still `pending` stay so in the
    /// index and are read after the next `start()`.
    public func stop() {
        stopped = true
        runTask?.cancel()
        runTask = nil
    }

    /// Reads `pending` rows, newest first, until none is left or `stop()` is called. Returns at once when a pass is
    /// already running (that pass looks for the next row after each one, so it also reads rows queued meanwhile).
    public func drain() async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }
        while !stopped, let row = try? index.newestPendingTextRow() {
            let result: TextRecognitionResult
            if !FileManager.default.fileExists(atPath: row.path) {
                result = .failed(reason: Self.fileMissingReason)
            } else {
                do {
                    result = RecognizedText.result(from: try await recognizer.recognize(URL(fileURLWithPath: row.path)))
                } catch {
                    result = .failed(reason: Self.failureReason(error))
                }
            }
            _ = try? index.setRecognizedText(result, recognizedBy: recognizer.recognizedBy, id: row.id,
                                             ifContentHash: row.contentHash)
        }
    }

    /// `text_error` for a recognizer error: its domain and code only. Never the error's description, which could
    /// quote recognized text (spec "Privacy").
    static func failureReason(_ error: Error) -> String {
        let error = error as NSError
        return "could not read the text (\(error.domain) \(error.code))"
    }
}
