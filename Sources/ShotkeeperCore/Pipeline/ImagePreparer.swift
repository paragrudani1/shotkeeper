import Foundation

/// Turns a screenshot file into what the analyzer sends. The macOS app implements this with ImageIO
/// (downscale to `AppSettings.maxImageLongSide`, re-encode PNG/JPEG, read pixel size).
public protocol ImagePreparer: Sendable {
    func prepare(_ url: URL) throws -> ImagePayload
}

public enum ImagePreparerError: Error, Equatable, Sendable {
    case unsupportedType(String)
    case unreadable(String)
}

/// Reads the file as-is (no resizing). For Linux, the CLI, and tests. Pixel size is read from the PNG header when
/// possible, else reported as 0×0.
public struct PassthroughImagePreparer: ImagePreparer {
    public init() {}

    public func prepare(_ url: URL) throws -> ImagePayload {
        let mime: String
        switch url.pathExtension.lowercased() {
        case "png": mime = "image/png"
        case "jpg", "jpeg": mime = "image/jpeg"
        case "webp": mime = "image/webp"
        default: throw ImagePreparerError.unsupportedType(url.pathExtension)
        }
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw ImagePreparerError.unreadable(url.path)
        }
        let size = mime == "image/png" ? Self.pngSize(data) : nil
        return ImagePayload(data: data, mimeType: mime, pixelWidth: size?.0 ?? 0, pixelHeight: size?.1 ?? 0)
    }

    /// Width/height from the IHDR chunk (bytes 16–23, big-endian) of a PNG.
    static func pngSize(_ data: Data) -> (Int, Int)? {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let bytes = [UInt8](data.prefix(24))
        guard bytes.count == 24, Array(bytes[0..<8]) == signature else { return nil }
        func be32(_ offset: Int) -> Int { bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) } }
        return (be32(16), be32(20))
    }
}
