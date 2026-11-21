import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Atomic "rename, but never replace an existing file". Returns 0 on success or an errno value
/// (EEXIST when the destination exists, EXDEV across volumes).
///
/// Order of strategies:
/// 1. Darwin `renamex_np(RENAME_EXCL)`; Linux `renameat2(RENAME_NOREPLACE)` resolved with `dlsym` (Swift's Glibc module
///    does not export it; glibc ≥ 2.28 has the symbol, `RENAME_NOREPLACE` is 1 in `linux/fs.h`).
/// 2. When the filesystem rejects the flag (EINVAL/ENOTSUP/ENOSYS): `link()` + `unlink()`; `link` fails with EEXIST
///    instead of replacing. A crash between the two calls leaves two names for one file, never a lost file.
/// 3. When hard links are unsupported (e.g. exFAT/SMB: EPERM/ENOTSUP): reserve the destination name with
///    `open(O_CREAT|O_EXCL)` (fails if anything is there), then `rename()` over our own empty placeholder.
enum NoReplaceRename {
    static func rename(_ from: String, _ to: String) -> Int32 {
        #if canImport(Darwin)
        if renamex_np(from, to, UInt32(RENAME_EXCL)) == 0 { return 0 }
        let e = errno
        guard e == EINVAL || e == ENOTSUP || e == ENOSYS else { return e }
        return linkThenUnlink(from, to)
        #else
        if let renameat2 = linuxRenameat2 {
            if renameat2(AT_FDCWD, from, AT_FDCWD, to, 1 /* RENAME_NOREPLACE */) == 0 { return 0 }
            let e = errno
            guard e == EINVAL || e == ENOSYS || e == ENOTSUP else { return e }
        }
        return linkThenUnlink(from, to)
        #endif
    }

    static func linkThenUnlink(_ from: String, _ to: String) -> Int32 {
        if link(from, to) != 0 {
            let e = errno
            if e == EPERM || e == ENOTSUP || e == EOPNOTSUPP { return reserveThenRename(from, to) }
            return e
        }
        if unlink(from) != 0 {
            let e = errno
            // Both names point at the same inode; dropping the new name leaves the file where it was.
            _ = unlink(to)
            return e
        }
        return 0
    }

    static func reserveThenRename(_ from: String, _ to: String) -> Int32 {
        let fd = open(to, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        if fd < 0 { return errno }
        _ = close(fd)
        #if canImport(Darwin)
        let renamed = Darwin.rename(from, to)
        #else
        let renamed = Glibc.rename(from, to)
        #endif
        if renamed != 0 {
            let e = errno
            _ = unlink(to)  // our own empty placeholder
            return e
        }
        return 0
    }

    #if !canImport(Darwin)
    private typealias Renameat2 = @convention(c) (Int32, UnsafePointer<CChar>, Int32, UnsafePointer<CChar>, UInt32) -> Int32
    private static let linuxRenameat2: Renameat2? = {
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "renameat2") else { return nil }
        return unsafeBitCast(symbol, to: Renameat2.self)
    }()
    #endif
}
