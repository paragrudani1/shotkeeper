import Foundation

/// Where macOS saves screenshots, from the `com.apple.screencapture` preferences domain
/// (`defaults write com.apple.screencapture location <path>` / `name <prefix>`).
struct ScreenshotLocation: Equatable, Sendable {
    static let preferencesDomain = "com.apple.screencapture"
    static let defaultNamePrefix = "Screenshot"

    /// Folder new screenshots land in.
    var folder: URL
    /// Filename prefix macOS uses ("Screenshot" unless the user changed `name`).
    var namePrefix: String

    /// Reads the live preferences. Not sandboxed, so another app's domain is readable.
    static func current(fileManager: FileManager = .default) -> ScreenshotLocation {
        let domain = preferencesDomain as CFString
        CFPreferencesAppSynchronize(domain)
        let location = CFPreferencesCopyAppValue("location" as CFString, domain) as? String
        let name = CFPreferencesCopyAppValue("name" as CFString, domain) as? String
        return resolve(location: location, name: name, home: fileManager.homeDirectoryForCurrentUser) { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// Pure resolution logic: expands `~` and `file://`, falls back to `~/Desktop` when the preference is
    /// missing, blank, or not an existing directory (macOS itself saves to the Desktop in that case).
    static func resolve(location: String?, name: String?, home: URL,
                        directoryExists: (URL) -> Bool) -> ScreenshotLocation {
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let prefix = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let namePrefix = (prefix?.isEmpty ?? true) ? defaultNamePrefix : prefix!

        guard let raw = location?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return ScreenshotLocation(folder: desktop, namePrefix: namePrefix)
        }
        let folder: URL
        if raw.hasPrefix("file://"), let url = URL(string: raw), url.isFileURL {
            folder = URL(fileURLWithPath: url.path, isDirectory: true)
        } else if raw == "~" {
            folder = home
        } else if raw.hasPrefix("~/") {
            folder = home.appendingPathComponent(String(raw.dropFirst(2)), isDirectory: true)
        } else if raw.hasPrefix("/") {
            folder = URL(fileURLWithPath: raw, isDirectory: true)
        } else {
            // Relative paths are not something macOS writes; treat as relative to home.
            folder = home.appendingPathComponent(raw, isDirectory: true)
        }
        let standardized = folder.standardizedFileURL
        guard directoryExists(standardized) else {
            return ScreenshotLocation(folder: desktop, namePrefix: namePrefix)
        }
        return ScreenshotLocation(folder: standardized, namePrefix: namePrefix)
    }
}
