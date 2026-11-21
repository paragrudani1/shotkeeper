import AppKit
import SwiftUI

/// Where thumbnails come from. Live: QuickLook via `ThumbnailCache`. Snapshot tests inject generated images,
/// returned synchronously from `cached` so the first render already shows them.
struct ThumbnailSource: Sendable {
    var cached: @MainActor @Sendable (_ path: String, _ side: CGFloat) -> NSImage?
    var load: @MainActor @Sendable (_ path: String, _ side: CGFloat, _ scale: CGFloat) async -> NSImage?

    static let live = ThumbnailSource(
        cached: { path, side in ThumbnailCache.shared.cached(path: path, side: side) },
        load: { path, side, scale in await ThumbnailCache.shared.thumbnail(path: path, side: side, scale: scale) })
}

private struct ThumbnailSourceKey: EnvironmentKey {
    static let defaultValue = ThumbnailSource.live
}

extension EnvironmentValues {
    var thumbnailSource: ThumbnailSource {
        get { self[ThumbnailSourceKey.self] }
        set { self[ThumbnailSourceKey.self] = newValue }
    }
}

/// A square, rounded screenshot thumbnail with a thin border; a neutral placeholder until it loads.
struct ThumbnailView: View {
    let path: String
    let side: CGFloat
    let cornerRadius: CGFloat
    @Environment(\.thumbnailSource) private var source
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: NSImage?

    var body: some View {
        let image = loaded ?? source.cached(path, side)
        ZStack {
            Color.primary.opacity(0.06)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo").font(.system(size: side * 0.35)).foregroundStyle(.tertiary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .task(id: path) {
            guard loaded == nil, source.cached(path, side) == nil else { return }
            loaded = await source.load(path, side, displayScale)
        }
    }
}
