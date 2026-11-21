import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum FileOrganizerError: Error, Equatable, Sendable {
    case sourceMissing(String)
    /// The stem is not a usable filename (empty, contains "/", hidden, too long). Sanitizing is `FilenameSanitizer`'s job.
    case invalidStem(String)
    /// Only from `move(_:to:)`: something already exists at the destination.
    case destinationExists(String)
    case tooManyCollisions(String)
    /// Cross-volume copy did not match the source size; the copy was removed and the source left in place.
    case copyVerificationFailed(String)
    case io(operation: String, path: String, errno: Int32)
}

/// Renames a screenshot to `<stem>.<original ext>` in place, or moves it into another folder. Never overwrites and
/// never deletes a user file: every rename is a no-replace rename (see `NoReplaceRename`); on a name collision it
/// retries with "Title 2.png", "Title 3.png", …. Across volumes it copies into a hidden temp file in the destination
/// folder, no-replace-renames that, verifies the size, and only then removes the source.
public struct FileOrganizer: Sendable {
    /// Highest collision suffix tried before giving up.
    public var maxCollisionSuffix: Int = 9999

    /// Returns 0 or an errno. Injected in tests (e.g. to force EXDEV).
    let renameNoReplace: @Sendable (String, String) -> Int32

    public init() { self.renameNoReplace = NoReplaceRename.rename }
    init(renameNoReplace: @escaping @Sendable (String, String) -> Int32) { self.renameNoReplace = renameNoReplace }

    /// Renames and/or moves `source`. `stem == nil` keeps the current name; `folder == nil` keeps the current folder.
    /// Returns the final URL (unchanged `source` when there was nothing to do).
    public func organize(_ source: URL, stem: String?, into folder: URL?) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { throw FileOrganizerError.sourceMissing(source.path) }
        let ext = source.pathExtension
        let baseStem = stem ?? source.deletingPathExtension().lastPathComponent
        if let stem { try Self.validate(stem: stem, ext: ext) }
        let sourceDir = source.deletingLastPathComponent().standardizedFileURL
        let destDir = (folder ?? sourceDir).standardizedFileURL
        if destDir.path != sourceDir.path {
            do { try fm.createDirectory(at: destDir, withIntermediateDirectories: true) }
            catch { throw FileOrganizerError.io(operation: "createDirectory", path: destDir.path, errno: EIO) }
        }
        let candidates = (1...max(1, maxCollisionSuffix)).lazy.map {
            destDir.appendingPathComponent(Self.filename(stem: baseStem, ext: ext, suffix: $0))
        }
        if let placed = try place(source, candidates: candidates) { return placed }
        throw FileOrganizerError.tooManyCollisions(destDir.appendingPathComponent(Self.filename(stem: baseStem, ext: ext, suffix: 1)).path)
    }

    /// Moves `source` to exactly `destination` (no suffixing). Throws `.destinationExists` if anything is there.
    /// Used by `UndoLog` to put a file back.
    public func move(_ source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { throw FileOrganizerError.sourceMissing(source.path) }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard try place(source, candidates: [destination.standardizedFileURL]) != nil else {
            throw FileOrganizerError.destinationExists(destination.path)
        }
    }

    /// "Title.png" for suffix 1, else "Title 2.png", "Title 3.png", ….
    public static func filename(stem: String, ext: String, suffix: Int) -> String {
        let base = suffix <= 1 ? stem : "\(stem) \(suffix)"
        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    static func validate(stem: String, ext: String) throws {
        let longest = filename(stem: stem, ext: ext, suffix: 9999)
        if stem.trimmingCharacters(in: .whitespaces).isEmpty || stem.contains("/") || stem.contains("\0")
            || stem.hasPrefix(".") || longest.utf8.count > 255 {
            throw FileOrganizerError.invalidStem(stem)
        }
    }

    /// Tries each candidate with a no-replace rename. Returns nil when every candidate was taken.
    private func place<C: Sequence>(_ source: URL, candidates: C) throws -> URL? where C.Element == URL {
        let source = source.standardizedFileURL
        var moving = source.path
        var tempCopy: URL?
        defer { if let tempCopy { try? FileManager.default.removeItem(at: tempCopy) } }  // only ever our own temp file

        for candidate in candidates {
            if candidate.path == source.path { return source }  // already has this name
            while true {
                let result = renameNoReplace(moving, candidate.path)
                if result == 0 {
                    if tempCopy != nil {
                        tempCopy = nil  // it now lives at `candidate`
                        try finishCrossVolumeMove(source: source, copy: candidate)
                    }
                    return candidate
                }
                if result == EEXIST || result == ENOTEMPTY { break }  // taken: next candidate
                if result == EXDEV, tempCopy == nil {
                    let temp = candidate.deletingLastPathComponent()
                        .appendingPathComponent(".shotkeeper-\(UUID().uuidString).tmp")
                    do { try FileManager.default.copyItem(at: source, to: temp) }
                    catch { throw FileOrganizerError.io(operation: "copy", path: temp.path, errno: EIO) }
                    tempCopy = temp
                    moving = temp.path
                    continue  // retry the same candidate with the local copy
                }
                throw FileOrganizerError.io(operation: "rename", path: candidate.path, errno: result)
            }
        }
        return nil
    }

    private func finishCrossVolumeMove(source: URL, copy: URL) throws {
        guard let sourceSize = Self.size(of: source), Self.size(of: copy) == sourceSize else {
            try? FileManager.default.removeItem(at: copy)  // our incomplete copy; the source is untouched
            throw FileOrganizerError.copyVerificationFailed(copy.path)
        }
        // If removing the source fails, the file exists in both places: nothing is lost.
        try? FileManager.default.removeItem(at: source)
    }

    static func size(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }
}
