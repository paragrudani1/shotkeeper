import Foundation

/// User rules that keep screenshots out of the pipeline, plus the "pause for N minutes" window.
/// Excluded or paused screenshots are not analyzed, renamed, or written to the index.
public struct ExcludeRules: Codable, Equatable, Sendable {
    public struct Rule: Codable, Equatable, Sendable, Hashable {
        public enum Kind: String, Codable, Sendable {
            /// Glob on the filename (`*`, `?`), case-insensitive, whole-name match. E.g. "*bank*.png".
            case filenameGlob
            /// Case-insensitive substring of the filename.
            case filenameContains
            /// Absolute folder path (or "~/…"); the file is excluded if it lives in it or any subfolder.
            case folder
        }
        public var kind: Kind
        public var pattern: String

        public init(_ kind: Kind, _ pattern: String) {
            self.kind = kind
            self.pattern = pattern
        }

        public func matches(_ url: URL) -> Bool {
            let name = url.lastPathComponent
            switch kind {
            case .filenameGlob:
                return !pattern.isEmpty && Glob.matches(pattern: pattern.lowercased(), name: name.lowercased())
            case .filenameContains:
                return !pattern.isEmpty && name.lowercased().contains(pattern.lowercased())
            case .folder:
                let folder = ExcludeRules.components(of: pattern)
                guard !folder.isEmpty else { return false }
                let parent = ExcludeRules.components(of: url.deletingLastPathComponent().path)
                return parent.count >= folder.count && Array(parent.prefix(folder.count)) == folder
            }
        }
    }

    /// Why a file is kept out of the pipeline.
    public enum Exclusion: Equatable, Sendable {
        case paused(until: Date)
        case rule(Rule)
    }

    public var rules: [Rule]
    /// Start of the current pause window ("pause 10 minutes"), if any.
    public var pausedFrom: Date?
    /// End of the current pause window. Screenshots captured, or processed, inside [pausedFrom, pausedUntil) are skipped.
    public var pausedUntil: Date?

    public init(rules: [Rule] = [], pausedFrom: Date? = nil, pausedUntil: Date? = nil) {
        self.rules = rules
        self.pausedFrom = pausedFrom
        self.pausedUntil = pausedUntil
    }

    public mutating func pause(for duration: TimeInterval, from now: Date) {
        pausedFrom = now
        pausedUntil = now.addingTimeInterval(duration)
    }

    public mutating func resume() {
        pausedFrom = nil
        pausedUntil = nil
    }

    /// True when `date` falls inside the pause window. With no `pausedFrom` (older settings) the window is open-ended to the past.
    public func isPaused(at date: Date) -> Bool {
        guard let until = pausedUntil, date < until else { return false }
        if let from = pausedFrom, date < from { return false }
        return true
    }

    /// The first reason to skip `url`, or nil. Checks the pause window against both capture time and now.
    public func exclusion(for url: URL, capturedAt: Date?, now: Date) -> Exclusion? {
        if let until = pausedUntil, isPaused(at: now) || capturedAt.map(isPaused(at:)) == true {
            return .paused(until: until)
        }
        if let rule = rules.first(where: { $0.matches(url) }) { return .rule(rule) }
        return nil
    }

    private static func components(of path: String) -> [String] {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.pathComponents.filter { $0 != "/" }
    }

    // Tolerate missing keys so new fields can be added later.
    private enum CodingKeys: String, CodingKey { case rules, pausedFrom, pausedUntil }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules = (try? c.decodeIfPresent([Rule].self, forKey: .rules)) ?? []
        pausedFrom = try? c.decodeIfPresent(Date.self, forKey: .pausedFrom)
        pausedUntil = try? c.decodeIfPresent(Date.self, forKey: .pausedUntil)
    }
}

/// Minimal glob: `*` (any run), `?` (one character). No brackets or escapes; every other character is literal.
enum Glob {
    static func matches(pattern: String, name: String) -> Bool {
        let p = Array(pattern), n = Array(name)
        var pi = 0, ni = 0, star = -1, mark = 0
        while ni < n.count {
            if pi < p.count, p[pi] == "?" || p[pi] == n[ni] {
                pi += 1; ni += 1
            } else if pi < p.count, p[pi] == "*" {
                star = pi; mark = ni; pi += 1
            } else if star >= 0 {
                pi = star + 1; mark += 1; ni = mark
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}
