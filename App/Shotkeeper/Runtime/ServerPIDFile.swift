import Darwin
import Foundation

/// Records the managed server's pid **and its start time**, so a later launch can kill a server left over from a
/// crash without ever killing an unrelated process that reused the pid (the start time would differ).
struct ServerPIDFile: Sendable {
    struct Record: Codable, Equatable, Sendable {
        var pid: Int32
        /// Process start time in microseconds since 1970 (from `proc_pidinfo`).
        var startTime: UInt64
        var port: Int
    }

    let url: URL

    func write(_ record: Record) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
    }

    func read() -> Record? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)  // lint-allow: file-op (our PID file)
    }

    /// Kills the recorded process if it is still the same process (same start time), then removes the file.
    /// Returns true when something was killed.
    @discardableResult
    func killLeftover(gracePeriod: TimeInterval = 3) -> Bool {
        defer { remove() }
        guard let record = read(), record.pid > 1,
              let started = ProcessInfoReader.startTime(of: record.pid), started == record.startTime else { return false }
        kill(record.pid, SIGTERM)
        let deadline = Date().addingTimeInterval(gracePeriod)
        while ProcessInfoReader.startTime(of: record.pid) == record.startTime, Date() < deadline {
            usleep(50_000)
        }
        if ProcessInfoReader.startTime(of: record.pid) == record.startTime { kill(record.pid, SIGKILL) }
        return true
    }
}

enum ProcessInfoReader {
    /// Start time (µs since 1970) of a live process, or nil if there is no such process (or it is a zombie).
    static func startTime(of pid: Int32) -> UInt64? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let read = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard read == size else { return nil }
        if info.pbi_status == 5 { return nil } // SZOMB (sys/proc.h)
        return UInt64(info.pbi_start_tvsec) * 1_000_000 + UInt64(info.pbi_start_tvusec)
    }
}
