import Foundation

/// Cheap, stable identity for a screenshot file, used to skip files that were already processed.
///
/// Format: `v1:<size>:<mtime in ms>:<FNV-1a 64 of the first 64 KiB, hex>`.
/// Why not SHA-256: plain Foundation has no SHA-256 on Linux (CryptoKit is Apple-only) and core takes no dependencies.
/// Why this is enough: a screenshot is written once; size + modification time + the first 64 KiB (PNG header, IHDR,
/// first image rows) tell two screenshots apart in practice. Renames and same-volume moves keep the mtime, so a file
/// we renamed still matches its index row. Not a security hash: a collision only means a file is skipped as "already done".
public enum ContentFingerprint {
    public static let prefixLength = 64 * 1024

    public static func compute(for url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: prefixLength) ?? Data()
        return make(size: size, modificationTime: mtime, prefix: prefix)
    }

    public static func make(size: Int64, modificationTime: TimeInterval, prefix: Data) -> String {
        let millis = Int64((modificationTime * 1000).rounded())
        return "v1:\(size):\(millis):\(String(fnv1a64(prefix.prefix(prefixLength)), radix: 16))"
    }

    static func fnv1a64<D: DataProtocol>(_ bytes: D) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
