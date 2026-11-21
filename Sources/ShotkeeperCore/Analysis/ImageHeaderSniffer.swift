import Foundation

/// Reads MIME type and pixel size from PNG / JPEG / WebP headers without decoding (Foundation only, works on Linux).
/// The macOS app uses ImageIO instead; this serves the CLI and tests.
public enum ImageHeaderSniffer {
    public struct Info: Equatable, Sendable {
        public var mimeType: String
        public var width: Int
        public var height: Int
    }

    public static func sniff(_ data: Data) -> Info? {
        let b = [UInt8](data.prefix(64 * 1024))
        if let info = png(b) { return info }
        if let info = webp(b) { return info }
        if let info = jpeg(b) { return info }
        return nil
    }

    /// Wraps `data` as an `ImagePayload` when its format is recognised.
    public static func payload(for data: Data) -> ImagePayload? {
        guard let info = sniff(data) else { return nil }
        return ImagePayload(data: data, mimeType: info.mimeType, pixelWidth: info.width, pixelHeight: info.height)
    }

    private static func be32(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
    }
    private static func be16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) << 8 | Int(b[i + 1]) }
    private static func le16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
    private static func le24(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 }

    /// PNG: 8-byte signature, then the IHDR chunk with big-endian width/height at offsets 16/20.
    private static func png(_ b: [UInt8]) -> Info? {
        guard b.count >= 24, b[0..<8].elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
              b[12..<16].elementsEqual(Array("IHDR".utf8)) else { return nil }
        let w = be32(b, 16), h = be32(b, 20)
        return w > 0 && h > 0 ? Info(mimeType: "image/png", width: w, height: h) : nil
    }

    /// JPEG: walk segments from SOI to the first SOFn marker (C0–CF except C4, C8, CC).
    private static func jpeg(_ b: [UInt8]) -> Info? {
        guard b.count >= 4, b[0] == 0xFF, b[1] == 0xD8 else { return nil }
        var i = 2
        while i + 9 < b.count {
            guard b[i] == 0xFF else { return nil }
            let marker = b[i + 1]
            if marker == 0xFF { i += 1; continue }
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD7).contains(marker) { i += 2; continue }
            let length = be16(b, i + 2)
            if (0xC0...0xCF).contains(marker), marker != 0xC4, marker != 0xC8, marker != 0xCC {
                let h = be16(b, i + 5), w = be16(b, i + 7)
                return w > 0 && h > 0 ? Info(mimeType: "image/jpeg", width: w, height: h) : nil
            }
            guard length >= 2 else { return nil }
            i += 2 + length
        }
        return nil
    }

    /// WebP: RIFF....WEBP then a VP8X (extended), VP8L (lossless) or VP8 (lossy) chunk.
    private static func webp(_ b: [UInt8]) -> Info? {
        guard b.count >= 30, b[0..<4].elementsEqual(Array("RIFF".utf8)), b[8..<12].elementsEqual(Array("WEBP".utf8)) else {
            return nil
        }
        let chunk = String(decoding: b[12..<16], as: UTF8.self)
        var w = 0, h = 0
        switch chunk {
        case "VP8X":
            w = le24(b, 24) + 1
            h = le24(b, 27) + 1
        case "VP8L":
            guard b[20] == 0x2F else { return nil }
            let bits = Int(b[21]) | Int(b[22]) << 8 | Int(b[23]) << 16 | Int(b[24]) << 24
            w = (bits & 0x3FFF) + 1
            h = ((bits >> 14) & 0x3FFF) + 1
        case "VP8 ":
            guard b[23] == 0x9D, b[24] == 0x01, b[25] == 0x2A else { return nil }
            w = le16(b, 26) & 0x3FFF
            h = le16(b, 28) & 0x3FFF
        default:
            return nil
        }
        return w > 0 && h > 0 ? Info(mimeType: "image/webp", width: w, height: h) : nil
    }
}
