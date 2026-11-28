import Foundation

/// Whether the organized folder can take subfolders right now (Settings shows why not; design §4, "Organized folder
/// missing or unreadable"). New screenshots still follow the pipeline's fallback either way.
public enum OrganizedFolderStatus: Equatable, Sendable {
    case ok
    /// Nothing there, or something that is not a folder.
    case missing
    /// A folder Shotkeeper may not read (permissions, or macOS privacy).
    case unreadable

    public static func check(_ folder: URL, fileManager: FileManager = .default) -> OrganizedFolderStatus {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .missing
        }
        return fileManager.isReadableFile(atPath: folder.path) ? .ok : .unreadable
    }
}

/// The words of Settings › General's "Sort into subfolders" rows (design §4). The app lays them out.
public enum SubfolderSettingsText {
    public static let pickerTitle = "Sort into subfolders"
    public static let exampleTitle = "Example"
    /// Story 20, said where the user would worry about it.
    public static let leftAlone = "Screenshots already there stay where they are."

    public static func title(for rule: SubfolderRule) -> String {
        switch rule {
        case .off: return "Off"
        case .byType: return "By type"
        case .bySource: return "By app or site"
        case .byTypeThenSource: return "By type, then app or site"
        }
    }

    /// "Screenshots › Receipts › Invoice from Acme.png": the organized folder's name, the rule's folders for a receipt
    /// from Mail (from the real router), and the file name in the current style. Nil when the rule is off.
    public static func example(rule: SubfolderRule, folderName: String, style: FilenameStyle, renameEnabled: Bool,
                               capturedAt: Date, timeZone: TimeZone) -> String? {
        guard rule != .off else { return nil }
        let folders = rule.relativeFolder(contentType: .receipt, source: "Mail") { _ in [] }
        let stem = renameEnabled
            ? style.stem(from: "Invoice from Acme", capturedAt: capturedAt, timeZone: timeZone) ?? "Invoice from Acme"
            : screenshotName(capturedAt, timeZone: timeZone)
        return ([folderName] + folders + ["\(stem).png"]).joined(separator: " › ")
    }

    /// What the rule does with the edge cases, under the example.
    public static func note(for rule: SubfolderRule) -> String? {
        switch rule {
        case .off:
            return nil
        case .byType:
            let names = ContentType.allCases.map(SubfolderRule.typeFolderName)
            return "Folders: \(names.dropLast().joined(separator: ", ")) and \(names.last!)."
        case .bySource:
            return "One folder per app or site. Screenshots from an unknown app go to Other."
        case .byTypeThenSource:
            return "Screenshots from an unknown app stay in the type folder."
        }
    }

    /// Replaces the example when the organized folder can't take subfolders; nil when it can.
    public static func warning(_ status: OrganizedFolderStatus, folderName: String) -> String? {
        switch status {
        case .ok: return nil
        case .missing: return "Can't find “\(folderName)”. Choose the organized folder again above."
        case .unreadable:
            return "Shotkeeper can't open “\(folderName)”. Allow access in Finder (Get Info › Sharing & Permissions), "
                + "or choose another folder."
        }
    }

    /// The macOS name a screenshot keeps when renaming is off: "Screenshot 2026-11-21 at 16.24.00".
    private static func screenshotName(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "Screenshot %04d-%02d-%02d at %02d.%02d.%02d",
                      c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }
}
