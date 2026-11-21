import Foundation

/// Progress for `hf download`. Two sources, because neither is guaranteed:
/// - the tqdm bar the CLI prints ("Fetching 12 files:  42%|████▏ | 5/12 [...]"), when its output reaches the pipe;
/// - bytes on disk in the target folder vs. the catalog's expected size (works regardless of output format).
enum DownloadProgress {
    /// Last "Fetching N files: NN%" percentage in `text`, as 0...1. Per-file bars are ignored: they restart at 0
    /// for every file and would make the bar jump backwards.
    static func fetchingFraction(in text: String) -> Double? {
        var result: Double?
        // tqdm redraws with \r; treat \r and \n alike.
        for segment in text.split(whereSeparator: { $0 == "\r" || $0 == "\n" }) where segment.contains("Fetching") {
            if let percent = lastPercent(in: segment) { result = percent / 100 }
        }
        return result
    }

    static func lastPercent(in text: Substring) -> Double? {
        var found: Double?
        var index = text.startIndex
        while let percentIndex = text[index...].firstIndex(of: "%") {
            var start = percentIndex
            while start > text.startIndex, text[text.index(before: start)].isASCII,
                  text[text.index(before: start)].isNumber || text[text.index(before: start)] == "." {
                start = text.index(before: start)
            }
            if start < percentIndex, let value = Double(text[start..<percentIndex]), (0...100).contains(value) {
                found = value
            }
            index = text.index(after: percentIndex)
        }
        return found
    }

    /// Total size of regular files under `directory` (including `.incomplete` partials).
    static func bytesOnDisk(in directory: URL, fileManager: FileManager = .default) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }

    /// Combined estimate, capped at 0.99 until the command exits successfully.
    static func estimate(parsed: Double?, bytesOnDisk: Int64, expectedGB: Double) -> Double {
        let expected = expectedGB * 1_000_000_000
        let fromDisk = expected > 0 ? Double(bytesOnDisk) / expected : 0
        return min(0.99, max(parsed ?? 0, fromDisk, 0))
    }
}
