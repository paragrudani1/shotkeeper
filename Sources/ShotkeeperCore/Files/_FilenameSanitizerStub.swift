// TEMPORARY STUB: DELETE THIS FILE AT MERGE.
// The analyzers task owns the real `FilenameSanitizer` in `Sources/ShotkeeperCore/Analysis/`.
// This stub exists only so the files/index/pipeline branch builds on its own. It matches the agreed API exactly:
//   public enum FilenameSanitizer { public static func stem(from title: String, maxLength: Int = 80) -> String? }
// Core code outside Analysis/ must not rely on anything beyond that signature.
import Foundation

public enum FilenameSanitizer {
    /// Minimal placeholder: strips path separators/control characters, trims, truncates. Nil when nothing usable remains.
    public static func stem(from title: String, maxLength: Int = 80) -> String? {
        var scalars = String.UnicodeScalarView()
        for scalar in title.unicodeScalars {
            if scalar == "/" || scalar == ":" || scalar == "\\" { scalars.append("-") }
            else if CharacterSet.controlCharacters.contains(scalar) { scalars.append(" ") }
            else { scalars.append(scalar) }
        }
        var stem = String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while stem.hasPrefix(".") { stem.removeFirst() }
        stem = String(stem.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        return stem.isEmpty ? nil : stem
    }
}
