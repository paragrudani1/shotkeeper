import Foundation

/// One rename/move the app made.
public struct UndoRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    /// Absolute path before the change.
    public var from: String
    /// Absolute path after the change.
    public var to: String

    public init(id: UUID = UUID(), timestamp: Date, from: String, to: String) {
        self.id = id
        self.timestamp = timestamp
        self.from = from
        self.to = to
    }
}

public enum UndoError: Error, Equatable, Sendable {
    case nothingToUndo
    case notFound(UUID)
    case alreadyUndone(UUID)
    /// The file is no longer where we put it (the user moved or deleted it).
    case fileNotAtDestination(String)
    /// Something now exists at the original path; we will not replace it.
    case originalPathOccupied(String)
}

/// Append-only JSONL log of renames/moves. One line per event:
///   `{"kind":"move","id":…,"timestamp":…,"from":…,"to":…}` and, after an undo, `{"kind":"undo","id":…,"timestamp":…}`.
/// Survives restarts; unreadable lines (e.g. a truncated last line after a crash) are skipped. Thread-safe.
public final class UndoLog: @unchecked Sendable {
    public let fileURL: URL
    private let organizer: FileOrganizer
    private let lock = NSLock()

    public init(fileURL: URL, organizer: FileOrganizer = FileOrganizer()) {
        self.fileURL = fileURL
        self.organizer = organizer
    }

    @discardableResult
    public func append(from: URL, to: URL, at timestamp: Date = Date()) throws -> UndoRecord {
        let record = UndoRecord(timestamp: timestamp, from: from.standardizedFileURL.path, to: to.standardizedFileURL.path)
        try lock.withLock { try write(Line(kind: .move, id: record.id, timestamp: timestamp, from: record.from, to: record.to)) }
        return record
    }

    /// Moves that have not been undone, oldest first.
    public func records() throws -> [UndoRecord] {
        try lock.withLock { try state().active }
    }

    /// Puts the file back at `from`. Only when it is still at `to` and nothing exists at `from`.
    /// Returns the record so the caller can update the index (`to` → `from`).
    @discardableResult
    public func undo(id: UUID, at timestamp: Date = Date()) throws -> UndoRecord {
        try lock.withLock {
            let state = try state()
            if state.undone.contains(id) { throw UndoError.alreadyUndone(id) }
            guard let record = state.active.first(where: { $0.id == id }) else { throw UndoError.notFound(id) }
            try revert(record, moves: state.moves, at: timestamp)
            return record
        }
    }

    @discardableResult
    public func undoLast(at timestamp: Date = Date()) throws -> UndoRecord {
        try lock.withLock {
            let state = try state()
            guard let record = state.active.last else { throw UndoError.nothingToUndo }
            try revert(record, moves: state.moves, at: timestamp)
            return record
        }
    }

    // MARK: - Private

    private struct Line: Codable {
        enum Kind: String, Codable { case move, undo }
        var kind: Kind
        var id: UUID
        var timestamp: Date
        var from: String?
        var to: String?
    }

    private func revert(_ record: UndoRecord, moves: [UndoRecord], at timestamp: Date) throws {
        // A later move put another file at the same path (ours was deleted or moved away in between): the file
        // there now is not the one this record moved, so it must not be "put back".
        if let position = moves.firstIndex(where: { $0.id == record.id }),
           moves[(position + 1)...].contains(where: { $0.to == record.to }) {
            throw UndoError.fileNotAtDestination(record.to)
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: record.to) else { throw UndoError.fileNotAtDestination(record.to) }
        guard !fm.fileExists(atPath: record.from) else { throw UndoError.originalPathOccupied(record.from) }
        do {
            try organizer.move(URL(fileURLWithPath: record.to), to: URL(fileURLWithPath: record.from))
        } catch FileOrganizerError.destinationExists {
            throw UndoError.originalPathOccupied(record.from)  // appeared between the check and the rename
        }
        try write(Line(kind: .undo, id: record.id, timestamp: timestamp, from: nil, to: nil))
    }

    /// `moves`: every move in log order (undone ones included); `active`: those not undone.
    private func state() throws -> (active: [UndoRecord], undone: Set<UUID>, moves: [UndoRecord]) {
        guard let data = FileManager.default.contents(atPath: fileURL.path) else { return ([], [], []) }
        let decoder = Self.decoder
        var moves: [UndoRecord] = []
        var undone = Set<UUID>()
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let entry = try? decoder.decode(Line.self, from: Data(line)) else { continue }
            switch entry.kind {
            case .move:
                if let from = entry.from, let to = entry.to {
                    moves.append(UndoRecord(id: entry.id, timestamp: entry.timestamp, from: from, to: to))
                }
            case .undo:
                undone.insert(entry.id)
            }
        }
        return (moves.filter { !undone.contains($0.id) }, undone, moves)
    }

    private func write(_ line: Line) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: fileURL.path) { _ = fm.createFile(atPath: fileURL.path, contents: nil) }
        let handle = try FileHandle(forUpdating: fileURL)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        var data = Data()
        if end > 0 {
            // A crash may have left a partial last line; start ours on a fresh line so it stays readable.
            try handle.seek(toOffset: end - 1)
            if try handle.read(upToCount: 1) != Data([UInt8(ascii: "\n")]) { data.append(UInt8(ascii: "\n")) }
            try handle.seekToEnd()
        }
        data.append(try Self.encoder.encode(line))
        data.append(UInt8(ascii: "\n"))
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
