import Foundation

/// The pure rules that turn recognized lines into the text a row stores (spec "Text recognition: where it runs").
public enum RecognizedText {
    /// Safety cap on the stored text, in characters, so one row cannot bloat the index (spec decision 10).
    public static let maximumLength = 100_000
    /// The last line of text that was cut at `maximumLength`. The index has no "truncated" column, so the mark is in
    /// the text itself, where search, Copy Text and the user all see it.
    public static let truncationMarker = "[Text cut here: longer than 100,000 characters]"

    /// The text to store for `lines`: in reading order (`readingOrder(_:)`), whitespace-only lines dropped, the rest
    /// joined with "\n". Nothing left → `.noText`. Longer than `maximumLength`: only the whole lines that fit are kept
    /// (the first `maximumLength` characters when not even the first line fits), then `truncationMarker` on its own line.
    public static func result(from lines: [RecognizedLine]) -> TextRecognitionResult {
        let kept = readingOrder(lines).map(\.text).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !kept.isEmpty else { return .noText }
        var text = ""
        var length = 0 // text.count, kept as we go (String.count walks the whole string)
        for line in kept {
            let separator = text.isEmpty ? "" : "\n"
            let added = separator.count + line.count
            guard length + added <= maximumLength else {
                if text.isEmpty { text = String(line.prefix(maximumLength)) }
                return .text(text + "\n" + truncationMarker)
            }
            text += separator + line
            length += added
        }
        return .text(text)
    }

    /// Top to bottom, then left to right. Lines on the same baseline form one row: a line joins the row started by
    /// the highest line not yet placed when their vertical centres are less than half the smaller box height apart.
    static func readingOrder(_ lines: [RecognizedLine]) -> [RecognizedLine] {
        // Vision's origin is the bottom left, so a larger centre is higher up.
        func centre(_ line: RecognizedLine) -> Double { line.boundingBox.y + line.boundingBox.height / 2 }
        var rows: [[RecognizedLine]] = []
        for line in lines.sorted(by: { centre($0) > centre($1) }) {
            if let anchor = rows.last?.first,
               centre(anchor) - centre(line) < min(anchor.boundingBox.height, line.boundingBox.height) / 2 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.flatMap { $0.sorted { $0.boundingBox.x < $1.boundingBox.x } }
    }
}
