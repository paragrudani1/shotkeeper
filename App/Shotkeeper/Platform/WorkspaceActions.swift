import AppKit
import UniformTypeIdentifiers

/// Open / reveal / copy for a file, through Finder and the pasteboard. Used by the search panel's result actions
/// and the menu's Recent rows. Nothing here moves, renames or deletes a file (CODING_STANDARDS #1).
@MainActor
enum WorkspaceActions {
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// One pasteboard item with the image as PNG (the file's own bytes when it is a PNG) and its file URL, so image
    /// editors and chat apps paste the picture and Finder/Mail paste the file. False when the file cannot be read.
    @discardableResult
    static func copyImage(_ url: URL, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        let png: Data
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .png) == true {
            png = data
        } else if let rep = NSBitmapImageRep(data: data), let converted = rep.representation(using: .png, properties: [:]) {
            png = converted  // JPEG/HEIC/TIFF screenshots (a `defaults write com.apple.screencapture type` choice)
        } else {
            return false
        }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setString(url.absoluteString, forType: .fileURL)
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}
