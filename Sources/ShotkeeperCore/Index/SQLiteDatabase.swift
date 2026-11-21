import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

public struct SQLiteError: Error, Equatable, Sendable, CustomStringConvertible {
    public var code: Int32
    public var message: String
    public var description: String { "SQLite error \(code): \(message)" }
}

/// A schema step: run `statements` to go from `version - 1` to `version`.
public struct SQLiteMigration: Sendable {
    public var version: Int32
    public var statements: [String]
    public init(version: Int32, statements: [String]) {
        self.version = version
        self.statements = statements
    }
}

/// Thin SQLite wrapper: one connection, prepared statements, transactions, `user_version` migrations, WAL.
/// Not thread-safe by itself; `ScreenshotIndex` serializes access with a lock.
final class SQLiteDatabase {
    private(set) var handle: OpaquePointer?

    /// `path` ":memory:" opens an in-memory database.
    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            handle = nil
            throw SQLiteError(code: rc, message: message)
        }
        sqlite3_busy_timeout(handle, 5000)
        if path != ":memory:" { _ = try? query("PRAGMA journal_mode=WAL") { _ in } }
        try execute("PRAGMA foreign_keys=ON")
    }

    deinit { sqlite3_close_v2(handle) }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &error)
        if rc != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? lastMessage
            sqlite3_free(error)
            throw SQLiteError(code: rc, message: message)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard rc == SQLITE_OK, let statement else { throw SQLiteError(code: rc, message: lastMessage) }
        return SQLiteStatement(statement, db: self)
    }

    /// Prepares, binds, and steps through every row.
    func query(_ sql: String, _ bindings: [SQLiteValue] = [], row: (SQLiteStatement) throws -> Void) throws {
        let statement = try prepare(sql)
        try statement.bind(bindings)
        while try statement.step() { try row(statement) }
    }

    func run(_ sql: String, _ bindings: [SQLiteValue] = []) throws {
        try query(sql, bindings) { _ in }
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    var userVersion: Int32 {
        get throws {
            var version: Int32 = 0
            try query("PRAGMA user_version") { version = $0.int32(0) }
            return version
        }
    }

    /// Applies every migration newer than `user_version`, each in its own transaction.
    func migrate(_ migrations: [SQLiteMigration]) throws {
        let current = try userVersion
        for migration in migrations.sorted(by: { $0.version < $1.version }) where migration.version > current {
            try transaction {
                for sql in migration.statements { try execute(sql) }
                try execute("PRAGMA user_version = \(migration.version)")
            }
        }
    }

    var changes: Int { Int(sqlite3_changes(handle)) }
    var lastMessage: String { handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no database" }
}

enum SQLiteValue {
    case null, int(Int64), double(Double), text(String)

    static func optional(_ s: String?) -> SQLiteValue { s.map { .text($0) } ?? .null }
    static func optional(_ d: Double?) -> SQLiteValue { d.map { .double($0) } ?? .null }
    static func optional(_ i: Int?) -> SQLiteValue { i.map { .int(Int64($0)) } ?? .null }
    static func optional(_ date: Date?) -> SQLiteValue { date.map { .double($0.timeIntervalSince1970) } ?? .null }
}

final class SQLiteStatement {
    private let statement: OpaquePointer
    private let db: SQLiteDatabase
    // SQLITE_TRANSIENT: SQLite copies the bound bytes.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(_ statement: OpaquePointer, db: SQLiteDatabase) {
        self.statement = statement
        self.db = db
    }

    deinit { sqlite3_finalize(statement) }

    func bind(_ values: [SQLiteValue]) throws {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let rc: Int32
            switch value {
            case .null: rc = sqlite3_bind_null(statement, index)
            case .int(let v): rc = sqlite3_bind_int64(statement, index, v)
            case .double(let v): rc = sqlite3_bind_double(statement, index, v)
            case .text(let v): rc = sqlite3_bind_text(statement, index, v, -1, Self.transient)
            }
            guard rc == SQLITE_OK else { throw SQLiteError(code: rc, message: db.lastMessage) }
        }
    }

    /// True when a row is available.
    func step() throws -> Bool {
        let rc = sqlite3_step(statement)
        switch rc {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw SQLiteError(code: rc, message: db.lastMessage)
        }
    }

    func isNull(_ column: Int32) -> Bool { sqlite3_column_type(statement, column) == SQLITE_NULL }
    func int32(_ column: Int32) -> Int32 { sqlite3_column_int(statement, column) }
    func int64(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
    func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
    func text(_ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }
    func optionalDouble(_ column: Int32) -> Double? { isNull(column) ? nil : double(column) }
    func optionalInt(_ column: Int32) -> Int? { isNull(column) ? nil : Int(int64(column)) }
    func optionalDate(_ column: Int32) -> Date? { optionalDouble(column).map(Date.init(timeIntervalSince1970:)) }
}
