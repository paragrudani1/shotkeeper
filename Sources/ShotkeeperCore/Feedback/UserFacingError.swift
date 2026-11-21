import Foundation

/// A short, readable problem for the UI (toast, menu). Never contains a raw `String(describing: error)`, a path
/// or a secret.
public struct UserFacingProblem: Error, Equatable, Sendable {
    /// Sentence fragment without a trailing period, e.g. "Cloudflare API token is not set".
    public var message: String
    /// True when the fix is in Settings (missing or rejected credentials, missing endpoint): the toast offers
    /// "Fix Settings…".
    public var needsSettings: Bool

    public init(message: String, needsSettings: Bool = false) {
        self.message = message
        self.needsSettings = needsSettings
    }

    /// The message on its own, capitalized and with a period: "The file is no longer there."
    public var sentence: String {
        guard let first = message.first else { return message }
        let text = first.uppercased() + message.dropFirst()
        return text.hasSuffix(".") ? text : text + "."
    }
}

/// Maps core errors to short UI text.
public enum UserFacingError {
    public static func problem(for error: any Error) -> UserFacingProblem {
        switch error {
        case let problem as UserFacingProblem: return problem
        case let error as SQLiteError: return UserFacingProblem(message: index(error))
        case let error as AnalyzerError: return analyzer(error)
        case let error as FileOrganizerError: return UserFacingProblem(message: organizer(error))
        case let error as UndoError: return UserFacingProblem(message: undo(error))
        case let error as ManualRenameError:
            switch error {
            case .unusableName: return UserFacingProblem(message: "that name cannot be used as a file name")
            }
        case let error as ImagePreparerError:
            switch error {
            case .unsupportedType: return UserFacingProblem(message: "this image type is not supported")
            case .unreadable: return UserFacingProblem(message: "the image could not be read")
            }
        default:
            return UserFacingProblem(message: "something went wrong")
        }
    }

    public static func message(for error: any Error) -> String { problem(for: error).message }

    /// Whether a processing error deserves a toast. Retryable errors (offline, rate limits, 5xx) do not: the queue
    /// retries them and the menu shows "Offline" meanwhile, so a toast per attempt would only be noise.
    public static func shouldNotify(_ error: any Error) -> Bool {
        if let error = error as? AnalyzerError { return !error.isRetryable }
        return true
    }

    private static func analyzer(_ error: AnalyzerError) -> UserFacingProblem {
        switch error {
        case .notConfigured(let reason):
            // Reasons come from the app's analyzer factory and are already short sentences ("Cloudflare API token is not set").
            return UserFacingProblem(message: reason, needsSettings: true)
        case .unauthorized:
            return UserFacingProblem(message: "the model backend rejected the token", needsSettings: true)
        case .unreachable:
            return UserFacingProblem(message: "the model backend is unreachable")
        case .rateLimited:
            return UserFacingProblem(message: "too many requests, trying again shortly")
        case .serverError(let status, _):
            return UserFacingProblem(message: "the model backend failed (HTTP \(status))")
        case .badRequest(let status, _):
            return UserFacingProblem(message: "the model backend rejected the image (HTTP \(status))")
        case .invalidResponse:
            return UserFacingProblem(message: "the model's answer could not be read")
        }
    }

    private static func organizer(_ error: FileOrganizerError) -> String {
        switch error {
        case .sourceMissing: return "the file is no longer there"
        case .invalidStem: return "that name cannot be used as a file name"
        case .destinationExists: return "a file with that name already exists"
        case .tooManyCollisions: return "too many files already have that name"
        case .copyVerificationFailed: return "the copy could not be verified, so the file was left in place"
        case .io(let operation, _, let errno): return "the file system refused the \(operation) (error \(errno))"
        }
    }

    /// SQLite result codes (https://www.sqlite.org/rescode.html). Extended codes carry the primary code in the low
    /// 8 bits. SQLite's own message is not shown: it can contain SQL or a path.
    private static func index(_ error: SQLiteError) -> String {
        switch error.code & 0xFF {
        case 3: return "Shotkeeper is not allowed to open the index file"                 // SQLITE_PERM
        case 5, 6: return "the index is busy, try again in a moment"                       // SQLITE_BUSY, SQLITE_LOCKED
        case 7: return "the Mac is out of memory"                                          // SQLITE_NOMEM
        case 8: return "the index file is read-only"                                       // SQLITE_READONLY
        case 10: return "the index file could not be read from disk"                       // SQLITE_IOERR
        case 11, 26: return "the index file is damaged"                                    // SQLITE_CORRUPT, SQLITE_NOTADB
        case 13: return "the disk is full"                                                 // SQLITE_FULL
        case 14: return "the index file could not be opened"                               // SQLITE_CANTOPEN
        case 23: return "Shotkeeper is not allowed to open the index file"                 // SQLITE_AUTH
        default: return "the index could not be read (SQLite error \(error.code))"
        }
    }

    private static func undo(_ error: UndoError) -> String {
        switch error {
        case .nothingToUndo: return "there is nothing to undo"
        case .notFound, .alreadyUndone: return "that rename was already undone"
        case .fileNotAtDestination: return "the file was moved or renamed since"
        case .originalPathOccupied: return "another file now has the original name"
        }
    }
}
