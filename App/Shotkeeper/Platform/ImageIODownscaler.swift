import CoreGraphics
import Foundation
import ImageIO
import ShotkeeperCore
import UniformTypeIdentifiers

enum ImageIODownscalerError: Error, Equatable {
    case unreadable(String)
    case thumbnailFailed(String)
    case encodeFailed(String)
}

/// Downscales a screenshot so its long side is at most `maxLongSide`, applying the EXIF orientation,
/// and encodes PNG (sharp text) unless the PNG exceeds `pngByteLimit`, in which case JPEG at `jpegQuality`.
struct ImageIODownscaler: ImagePreparer {
    let maxLongSide: Int
    let pngByteLimit: Int
    let jpegQuality: Double

    init(maxLongSide: Int = 1280, pngByteLimit: Int = 3_500_000, jpegQuality: Double = 0.85) {
        precondition(maxLongSide > 0, "maxLongSide must be positive")
        self.maxLongSide = maxLongSide
        self.pngByteLimit = pngByteLimit
        self.jpegQuality = jpegQuality
    }

    func prepare(_ url: URL) throws -> ImagePayload {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              CGImageSourceGetCount(source) > 0 else {
            throw ImageIODownscalerError.unreadable(url.lastPathComponent)
        }
        // Never upscale: clamp to the source's own long side.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let sourceWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let sourceHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let sourceLongSide = max(sourceWidth, sourceHeight)
        let targetLongSide = sourceLongSide > 0 ? min(maxLongSide, sourceLongSide) : maxLongSide

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // applies EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: targetLongSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw ImageIODownscalerError.thumbnailFailed(url.lastPathComponent)
        }

        let png = try Self.encode(image, type: .png, properties: nil)
        if png.count <= pngByteLimit {
            return ImagePayload(data: png, mimeType: "image/png", pixelWidth: image.width, pixelHeight: image.height)
        }
        let jpeg = try Self.encode(Self.flattenedOnWhite(image) ?? image, type: .jpeg,
                                   properties: [kCGImageDestinationLossyCompressionQuality: jpegQuality])
        return ImagePayload(data: jpeg, mimeType: "image/jpeg", pixelWidth: image.width, pixelHeight: image.height)
    }

    private static func encode(_ image: CGImage, type: UTType, properties: [CFString: Any]?) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw ImageIODownscalerError.encodeFailed(type.identifier)
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary?)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageIODownscalerError.encodeFailed(type.identifier)
        }
        return data as Data
    }

    /// JPEG has no alpha; window screenshots have transparent shadows that would otherwise turn black.
    private static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}

/// The pipeline's `ImagePreparer`: reads `maxImageLongSide` from the current settings for every screenshot, so a
/// change in Settings applies to the next one without rebuilding the processor.
struct SettingsDrivenImagePreparer: ImagePreparer {
    let settings: @Sendable () -> AppSettings

    func prepare(_ url: URL) throws -> ImagePayload {
        // Clairic caps one image at 4 MiB (CloudflareClairicAnalyzer.maxImageBytes); stay under it with margin.
        let longSide = max(64, settings().maxImageLongSide)
        return try ImageIODownscaler(maxLongSide: longSide, pngByteLimit: 3_500_000).prepare(url)
    }
}
