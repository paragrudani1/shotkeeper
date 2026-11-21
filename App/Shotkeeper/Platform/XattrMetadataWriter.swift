import Darwin
import Foundation
import ShotkeeperCore

enum XattrError: Error, Equatable {
    case posix(operation: String, attribute: String, errno: Int32)
}

/// Writes Finder tags and the Finder comment as extended attributes, with binary-plist payloads:
/// - `com.apple.metadata:_kMDItemUserTags`: array of strings ("Name" or "Name\n<color index>").
/// - `com.apple.metadata:kMDItemFinderComment`: string. Spotlight indexes it; Finder's Get Info panel reads
///   comments from `.DS_Store`, so it may not show there.
/// Payloads come from core's `FinderMetadata`; this type only does the raw `getxattr`/`setxattr`.
struct XattrMetadataWriter: FileMetadataWriter {
    static let tagsAttribute = FinderMetadata.tagsAttribute
    static let commentAttribute = FinderMetadata.commentAttribute

    // MARK: Raw attributes (the core protocol's shape)

    /// Current value of the attribute, or nil when it is not set.
    func readExtendedAttribute(_ name: String, of url: URL) throws -> Data? {
        try url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { throw XattrError.posix(operation: "getxattr", attribute: name, errno: EINVAL) }
            let size = getxattr(path, name, nil, 0, 0, 0)
            if size < 0 {
                if errno == ENOATTR { return nil }
                throw XattrError.posix(operation: "getxattr", attribute: name, errno: errno)
            }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, 0) }
            guard read >= 0 else { throw XattrError.posix(operation: "getxattr", attribute: name, errno: errno) }
            return data.prefix(read)
        }
    }

    func writeExtendedAttribute(_ name: String, data: Data, to url: URL) throws {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw XattrError.posix(operation: "setxattr", attribute: name, errno: EINVAL) }
            let result = data.withUnsafeBytes { setxattr(path, name, $0.baseAddress, data.count, 0, 0) }
            guard result == 0 else { throw XattrError.posix(operation: "setxattr", attribute: name, errno: errno) }
        }
    }

    func removeExtendedAttribute(_ name: String, from url: URL) throws {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw XattrError.posix(operation: "removexattr", attribute: name, errno: EINVAL) }
            if removexattr(path, name, 0) != 0, errno != ENOATTR {
                throw XattrError.posix(operation: "removexattr", attribute: name, errno: errno)
            }
        }
    }

    // MARK: Finder tags and comment

    /// Replaces the file's tags. An empty array removes the attribute.
    func setTags(_ tags: [String], for url: URL) throws {
        if tags.isEmpty {
            try removeExtendedAttribute(Self.tagsAttribute, from: url)
            return
        }
        try writeExtendedAttribute(Self.tagsAttribute, data: try FinderMetadata.tagsPayload(tags), to: url)
    }

    func tags(of url: URL) throws -> [String] {
        guard let data = try readExtendedAttribute(Self.tagsAttribute, of: url) else { return [] }
        return FinderMetadata.decodeTags(data) ?? []
    }

    /// Replaces the Finder comment. An empty string removes the attribute.
    func setFinderComment(_ comment: String, for url: URL) throws {
        if comment.isEmpty {
            try removeExtendedAttribute(Self.commentAttribute, from: url)
            return
        }
        try writeExtendedAttribute(Self.commentAttribute, data: try FinderMetadata.commentPayload(comment), to: url)
    }

    func finderComment(of url: URL) throws -> String? {
        guard let data = try readExtendedAttribute(Self.commentAttribute, of: url) else { return nil }
        return FinderMetadata.decodeComment(data)
    }
}
