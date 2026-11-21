import AppKit
@preconcurrency import QuickLookThumbnailing

/// QuickLook thumbnails for search rows, cached in memory by path + size.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    func cached(path: String, side: CGFloat) -> NSImage? {
        cache.object(forKey: Self.key(path, side))
    }

    func thumbnail(path: String, side: CGFloat, scale: CGFloat) async -> NSImage? {
        if let hit = cached(path: path, side: side) { return hit }
        guard let image = await Self.generate(url: URL(fileURLWithPath: path), side: side, scale: scale)?.image else {
            return nil
        }
        cache.setObject(image, forKey: Self.key(path, side))
        return image
    }

    private static func key(_ path: String, _ side: CGFloat) -> NSString { "\(Int(side))|\(path)" as NSString }

    /// Nonisolated on purpose: QuickLook calls the completion on its own queue, and a closure formed in a
    /// main-actor context would be inferred main-actor-isolated (a runtime isolation trap in Swift 6).
    nonisolated private static func generate(url: URL, side: CGFloat, scale: CGFloat) async -> ImageBox? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: scale,
                                                   representationTypes: .thumbnail)
        return await withCheckedContinuation { (continuation: CheckedContinuation<ImageBox?, Never>) in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation.map { ImageBox(image: $0.nsImage) })
            }
        }
    }

    /// NSImage is not Sendable; this one is created by QuickLook, handed over once, and only read afterwards.
    private struct ImageBox: @unchecked Sendable {
        let image: NSImage
    }
}
