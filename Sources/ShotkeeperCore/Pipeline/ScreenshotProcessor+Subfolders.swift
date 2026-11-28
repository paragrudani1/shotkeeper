import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif  // strerror

/// Where the pipeline puts a screenshot: the organized folder, or a subfolder of it from `SubfolderRule` (wave 2
/// ticket 04). New screenshots (`process`) use this, and Analyze Again reuses it, so both follow today's settings.
///
/// Watching invariant (spec "Subfolders in the pipeline"; user story 19): subfolders are never watched or processed
/// again, because the watcher (`FolderWatcher`) and Process Existing (`ExistingScreenshotScanner`) see only the
/// watched folder's direct children, even when the organized folder sits inside it. A later recursive watch must
/// exclude the organized folder.
extension ScreenshotProcessor {
    /// The organized folder and the subfolder below it that a screenshot should go to.
    struct Destination: Equatable {
        var organizedFolder: URL
        /// `[]` = the organized folder itself.
        var subfolder: [String]
    }

    /// Where a rename/move left the file, and what the toast needs to know about it.
    struct Placement: Equatable {
        var url: URL
        var undoRecordID: UUID?
        /// The subfolder the file was moved into; empty when none was used.
        var sortedInto: [String] = []
        /// Every rename/move failed: the file kept its name and place (note "kept name: rename failed (…)").
        /// Analyze Again reports that as `TitleKeptReason.renameFailed`.
        var failed = false
    }

    /// The pipeline's move rule: nil when moving is off or no organized folder is set (the file stays in its folder);
    /// else the organized folder plus `settings.subfolderRule`'s folders for this analysis. Reads the existing
    /// subfolder names (read-only) so a folder is reused in any letter case or spelling of the source.
    func destination(for analysis: ScreenshotAnalysis, settings: AppSettings) -> Destination? {
        guard settings.moveEnabled, let root = settings.organizedFolder?.standardizedFileURL else { return nil }
        let rule = settings.subfolderRule
        let spelling = rule.usesSource ? folderSpelling(for: analysis.sourceAppOrSite) : nil
        let subfolder = rule.relativeFolder(contentType: analysis.contentType, source: spelling) { parent in
            Self.folderNames(in: Self.folder(root, parent))
        }
        return Destination(organizedFolder: root, subfolder: subfolder)
    }

    /// The spelling a new source folder is named from: `SourceFacet.displayName` (the most common spelling the index
    /// has for that source; ticket 03: never `SourceKey.rawValue`), or this screenshot's own spelling when the index
    /// has none yet.
    func folderSpelling(for raw: String?) -> String? {
        guard let raw, let key = SourceKey(raw) else { return nil }
        let known = (try? index.sources())?.first { $0.key == key }
        return (known ?? SourceFacet.merge([(raw: raw, count: 1)]).first)?.displayName
    }

    /// Renames and/or moves `url` through `FileOrganizer` (no-replace) and appends the undo record right after the
    /// move. Into the subfolder when there is one; when it can't be made or used, into the organized folder itself
    /// (noted "subfolder not created (…)"); when that fails too, the file keeps its name and place (noted).
    func place(_ url: URL, stem: String?, into destination: Destination?, notes: inout [String]) -> Placement {
        var placement = Placement(url: url)
        var folders: [(url: URL, subfolder: [String])] = []
        if let destination {
            if !destination.subfolder.isEmpty {
                do { folders.append((try makeSubfolder(destination), destination.subfolder)) }
                catch { notes.append("subfolder not created (\(error))") }
            }
            folders.append((destination.organizedFolder, []))
        }
        if folders.isEmpty, stem == nil { return placement }

        let finalURL: URL
        do {
            (finalURL, placement.sortedInto) = try organize(url, stem: stem, into: folders, notes: &notes)
        } catch {
            notes.append("kept name: rename failed (\(error))")
            placement.failed = true
            return placement
        }
        guard finalURL != url else {
            placement.sortedInto = []
            return placement
        }
        placement.url = finalURL
        do { placement.undoRecordID = try undoLog.append(from: url, to: finalURL, at: now()).id }
        catch { notes.append("undo record not written (\(error))") }
        return placement
    }

    /// Tries each folder in turn (the subfolder, then the organized folder); with no folder, renames in place.
    /// Returns where the file is and the subfolder it went into.
    private func organize(_ url: URL, stem: String?, into folders: [(url: URL, subfolder: [String])],
                          notes: inout [String]) throws -> (URL, [String]) {
        guard let last = folders.last else { return (try organizer.organize(url, stem: stem, into: nil), []) }
        for folder in folders.dropLast() {
            do { return (try organizer.organize(url, stem: stem, into: folder.url), folder.subfolder) }
            catch { notes.append("subfolder not used (\(error))") }
        }
        return (try organizer.organize(url, stem: stem, into: last.url), last.subfolder)
    }

    /// Creates the missing folders of `destination.subfolder` one level at a time, only below the organized folder.
    /// Throws when something that is not a folder (a file, a link) already has one of the names, or a folder can't be
    /// made; nothing is created then beyond the levels already made.
    private func makeSubfolder(_ destination: Destination) throws -> URL {
        let fm = FileManager.default
        var folder = destination.organizedFolder
        do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }  // as `organize` did before
        catch { throw SubfolderProblem.cannotCreate(folder.lastPathComponent, Self.reason(error)) }
        for name in destination.subfolder {
            folder = folder.appendingPathComponent(name, isDirectory: true)
            // Time of check to time of use: between this check (or the one after `createDirectory` below) and the
            // move, another process could swap the folder for a link. Nothing here can close that window without
            // `openat`/`renameatx_np` on directory descriptors. The move itself stays no-replace, so the file can't
            // overwrite anything; at worst it lands where the link points. Only a process running as the user can
            // do this, and it can move the file anyway.
            if Self.isRealFolder(folder) { continue }
            if Self.exists(folder) { throw SubfolderProblem.notAFolder(name) }
            do { try fm.createDirectory(at: folder, withIntermediateDirectories: false) }
            catch {
                if Self.isRealFolder(folder) { continue }  // made meanwhile
                throw SubfolderProblem.cannotCreate(name, Self.reason(error))
            }
        }
        return folder
    }

    static func folder(_ root: URL, _ components: [String]) -> URL {
        components.reduce(root) { $0.appendingPathComponent($1, isDirectory: true) }
    }

    /// Names of the real folders (not links, not hidden) directly inside `folder`; empty when it can't be read.
    static func folderNames(in folder: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") && isRealFolder(folder.appendingPathComponent($0)) }
    }

    /// A directory, not a symbolic link to one (`attributesOfItem` does not follow links), so a sorted file never
    /// leaves the organized folder.
    private static func isRealFolder(_ url: URL) -> Bool { itemType(url) == .typeDirectory }

    private static func exists(_ url: URL) -> Bool { itemType(url) != nil }

    private static func itemType(_ url: URL) -> FileAttributeType? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
    }

    private static func reason(_ error: Error) -> String {
        let nsError = error as NSError
        if let posix = nsError.userInfo[NSUnderlyingErrorKey] as? NSError, posix.domain == NSPOSIXErrorDomain {
            return String(cString: strerror(Int32(posix.code)))
        }
        return nsError.localizedDescription
    }
}

/// Why a subfolder could not be used; the text goes into the row's note ("subfolder not created (…)").
enum SubfolderProblem: Error, CustomStringConvertible {
    case notAFolder(String)
    case cannotCreate(String, String)

    var description: String {
        switch self {
        case .notAFolder(let name): return "“\(name)” is a file, not a folder"
        case .cannotCreate(let name, let reason): return "cannot create “\(name)”: \(reason)"
        }
    }
}
