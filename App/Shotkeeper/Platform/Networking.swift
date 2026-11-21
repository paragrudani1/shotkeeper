import Darwin
import Foundation

enum FreePortError: Error, Equatable {
    case posix(operation: String, errno: Int32)
}

/// Asks the kernel for an unused TCP port on 127.0.0.1 (bind to port 0, read it back, close).
/// There is an unavoidable race until the child binds it; callers retry on "address in use".
enum FreePort {
    static func find() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw FreePortError.posix(operation: "socket", errno: errno) }
        defer { close(fd) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { throw FreePortError.posix(operation: "bind", errno: errno) }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { throw FreePortError.posix(operation: "getsockname", errno: errno) }
        return UInt16(bigEndian: address.sin_port)
    }
}

enum HealthProbeError: Error, Equatable {
    /// Gave up; carries the last HTTP status seen (nil if nothing answered) and the last error description.
    case timedOut(lastStatus: Int?, lastError: String?)
}

/// Polls an HTTP URL until it answers 200 or the timeout passes (e.g. waiting for `mlx_lm.server` to load).
struct HealthProbe: Sendable {
    typealias StatusFetcher = @Sendable (URL) async throws -> Int

    let url: URL
    let timeout: Duration
    let interval: Duration
    private let fetchStatus: StatusFetcher

    init(url: URL, timeout: Duration = .seconds(120), interval: Duration = .milliseconds(500),
         fetchStatus: @escaping StatusFetcher = HealthProbe.urlSessionStatus) {
        self.url = url
        self.timeout = timeout
        self.interval = interval
        self.fetchStatus = fetchStatus
    }

    /// Returns once the URL answers 200; throws `HealthProbeError.timedOut` or `CancellationError`.
    func waitUntilHealthy() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var lastStatus: Int?
        var lastError: String?
        while true {
            try Task.checkCancellation()
            do {
                let status = try await fetchStatus(url)
                if status == 200 { return }
                lastStatus = status
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = String(describing: error)
            }
            if clock.now.advanced(by: interval) >= deadline {
                throw HealthProbeError.timedOut(lastStatus: lastStatus, lastError: lastError)
            }
            try await Task.sleep(for: interval)
        }
    }

    /// Default fetcher: a GET with a short per-request timeout, no caching, no cookies.
    static let urlSessionStatus: StatusFetcher = { url in
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        request.httpMethod = "GET"
        let (_, response) = try await probeSession.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? -1
    }

    private static let probeSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()
}

enum SystemInfo {
    static var physicalMemoryBytes: UInt64 { ProcessInfo.processInfo.physicalMemory }

    /// Physical RAM in GiB (e.g. 16.0 on a 16 GB Mac). Used by phase 2 to pick a model quantization.
    static var physicalMemoryGB: Double { Double(physicalMemoryBytes) / 1_073_741_824 }
}
