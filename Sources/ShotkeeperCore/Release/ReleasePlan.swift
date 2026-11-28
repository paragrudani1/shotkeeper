import Foundation

/// What the release job needs for one tag: versions, file names and release notes (auto-update spec, "Core seam:
/// `ReleasePlan`"). The tag is the single source of truth; `make` fails with one log line before anything is built.
public struct ReleasePlan: Equatable, Sendable {
    /// `CFBundleShortVersionString`, e.g. "0.2.0".
    public var marketingVersion: String
    /// `CFBundleVersion`: MAJOR×10000 + MINOR×100 + PATCH, e.g. 200.
    public var buildNumber: Int
    /// The release tag, e.g. "v0.2.0".
    public var tag: String
    /// The zip uploaded to the GitHub Release, e.g. "Shotkeeper-0.2.0.zip".
    public var archiveName: String
    /// The GitHub Release title, e.g. "Shotkeeper 0.2.0".
    public var title: String
    /// The CHANGELOG.md section body, for the GitHub Release page.
    public var notesMarkdown: String
    /// The same notes rendered as an HTML fragment, for Sparkle's update window.
    public var notesHTML: String

    /// - Parameter previousTag: the latest published release's tag, or nil for the first release.
    public static func make(tag: String, previousTag: String?, changelog: String) throws(ReleasePlanError) -> ReleasePlan {
        let version = try ReleaseVersion(tag: tag)
        if let previousTag {
            let previous: ReleaseVersion
            do { previous = try ReleaseVersion(tag: previousTag) } catch { throw .previousRelease(error) }
            guard version > previous else { throw .notHigherThanPrevious(tag: tag, previous: previousTag) }
        }
        let notes = try Changelog.section(for: version.description, in: changelog)
        return ReleasePlan(marketingVersion: version.description, buildNumber: version.buildNumber, tag: tag,
                           archiveName: "Shotkeeper-\(version).zip", title: "Shotkeeper \(version)",
                           notesMarkdown: notes, notesHTML: ReleaseNotesHTML.render(notes))
    }

    /// The Markdown notes file, for `gh release create --notes-file`.
    public static let notesMarkdownFileName = "notes.md"

    /// The HTML notes file. `generate_appcast` pairs an archive with the release-notes file of the same name and
    /// another extension, trying `.html`, then `.txt`, `.md`, `.markdown` (Sparkle 2.10.1
    /// `generate_appcast/ArchiveItem.swift:419-446`, `releaseNotesPath`). So the zip's name with `.html`.
    public var notesHTMLFileName: String { (archiveName as NSString).deletingPathExtension + ".html" }

    /// File name → contents, for the CLI to write into its output folder. Both end with a newline.
    public var outputFiles: [String: String] {
        [Self.notesMarkdownFileName: notesMarkdown + "\n", notesHTMLFileName: notesHTML + "\n"]
    }

    /// `key=value` lines for `$GITHUB_OUTPUT`; file paths are under `directory`, where the CLI wrote `outputFiles`.
    public func githubOutput(directory: String) -> String {
        let folder = directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        return [
            ("version", marketingVersion),
            ("build_number", String(buildNumber)),
            ("tag", tag),
            ("archive_name", archiveName),
            ("title", title),
            ("notes_markdown_file", "\(folder)/\(Self.notesMarkdownFileName)"),
            ("notes_html_file", "\(folder)/\(notesHTMLFileName)"),
        ].map { "\($0)=\($1)\n" }.joined()
    }
}

/// Why a release can't go ahead; `message` is the one line the release log shows.
public enum ReleasePlanError: Error, Equatable, Sendable {
    case tagWithoutV(String)
    case notAVersionTag(String)
    case tagSuffix(String)
    case leadingZero(String)
    case minorOrPatchOver99(String)
    case majorTooLarge(String)
    case belowFirstVersion(String)
    /// The previous release's tag breaks one of the tag rules.
    indirect case previousRelease(ReleasePlanError)
    case notHigherThanPrevious(tag: String, previous: String)
    case noChangelogSection(String)
    case emptyChangelogSection(String)
    case duplicateChangelogSection(String)

    public var message: String {
        switch self {
        case .tagWithoutV(let tag): return "Tag \(tag) does not start with v (expected vMAJOR.MINOR.PATCH)"
        case .notAVersionTag(let tag): return "Tag \(tag) is not vMAJOR.MINOR.PATCH"
        case .tagSuffix(let tag): return "Tag \(tag) has a pre-release or build suffix; releases are vMAJOR.MINOR.PATCH only"
        case .leadingZero(let tag): return "Tag \(tag) has a leading zero"
        case .minorOrPatchOver99(let tag):
            return "Tag \(tag): minor and patch must be 0-99 (build number MAJOR×10000+MINOR×100+PATCH)"
        case .majorTooLarge(let tag): return "Tag \(tag): major version is too large"
        case .belowFirstVersion(let tag): return "Tag \(tag) is below v0.1.0, the first version a release may have"
        case .previousRelease(let error): return "Previous release: \(error.message)"
        case .notHigherThanPrevious(let tag, let previous): return "\(tag) is not higher than the previous release \(previous)"
        case .noChangelogSection(let version): return "CHANGELOG.md has no section for \(version)"
        case .emptyChangelogSection(let version): return "CHANGELOG.md section \(version) is empty"
        case .duplicateChangelogSection(let version): return "CHANGELOG.md has more than one section for \(version)"
        }
    }
}

struct ReleaseVersion: Comparable, CustomStringConvertible {
    var major: Int, minor: Int, patch: Int

    /// The largest major version whose build number still fits in an `Int` (spec "Build number" caps only minor
    /// and patch; this only stops an overflow).
    private static let maxMajor = (Int.max - 9_999) / 10_000

    /// Parses `vMAJOR.MINOR.PATCH` with the release constraints of the spec's "Build number" section.
    init(tag: String) throws(ReleasePlanError) {
        guard tag.hasPrefix("v") else { throw .tagWithoutV(tag) }
        let body = tag.dropFirst()
        guard !body.contains("-"), !body.contains("+") else { throw .tagSuffix(tag) }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { ("0"..."9").contains($0) } }) else {
            throw .notAVersionTag(tag)
        }
        guard parts.allSatisfy({ $0.count == 1 || !$0.hasPrefix("0") }) else { throw .leadingZero(tag) }
        guard let major = Int(parts[0]), major <= Self.maxMajor else { throw .majorTooLarge(tag) }
        guard parts[1].count <= 2, parts[2].count <= 2, let minor = Int(parts[1]), let patch = Int(parts[2]) else {
            throw .minorOrPatchOver99(tag)
        }
        (self.major, self.minor, self.patch) = (major, minor, patch)
        guard self >= ReleaseVersion(major: 0, minor: 1, patch: 0) else { throw .belowFirstVersion(tag) }
    }

    private init(major: Int, minor: Int, patch: Int) { (self.major, self.minor, self.patch) = (major, minor, patch) }

    var buildNumber: Int { major * 10_000 + minor * 100 + patch }
    var description: String { "\(major).\(minor).\(patch)" }

    static func < (a: ReleaseVersion, b: ReleaseVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
}

enum Changelog {
    /// The body of the `## <version> (<date>)` section, without surrounding blank lines.
    static func section(for version: String, in changelog: String) throws(ReleasePlanError) -> String {
        // "\r\n" is one Character in Swift, so split on "\n" alone would never see a Windows line ending.
        let lines = changelog.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let starts = lines.indices.filter { headingVersion(lines[$0]) == version }
        guard let start = starts.first else { throw .noChangelogSection(version) }
        guard starts.count == 1 else { throw .duplicateChangelogSection(version) }
        let rest = lines[(start + 1)...]
        let body = rest.prefix { headingVersion($0) == nil }
        let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .emptyChangelogSection(version) }
        return text
    }

    /// The version word of a level-2 heading (`## 0.2.0 (2026-11-28)` → "0.2.0"), or nil for any other line.
    private static func headingVersion(_ line: String) -> String? {
        guard line.hasPrefix("## ") else { return nil }
        return line.dropFirst(3).split(separator: " ").first.map(String.init) ?? ""
    }
}
