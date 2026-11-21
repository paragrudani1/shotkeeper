// shotkeeper-cli: run one live analyzer call from a terminal (Linux build box or a Mac).
//
// The image is sent exactly as read from disk: there is no downscaling here (ImageIO is macOS-only and the core stays
// Foundation-only). The macOS app downscales to `maxImageLongSide` first, so CLI costs are an upper bound; Clairic
// rejects images over 4 MiB. Credentials come from the environment and are never printed.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ShotkeeperCore

let usage = """
Usage:
  shotkeeper-cli analyze <image> [--backend clairic|local] [--endpoint URL] [--model NAME] [--raw PATH]

Backends:
  clairic (default)  Cloudflare Workers AI @cf/cloudflare/clairic.
                     Needs CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN in the environment.
  local              OpenAI-compatible /v1/chat/completions server (mlx_lm.server, LM Studio, llama-server, Ollama).
                     --endpoint defaults to http://127.0.0.1:8080, --model to mlx-community/Inkling-2-Mini-4bit.
                     Optional bearer token: SHOTKEEPER_LOCAL_API_KEY.

Options:
  --raw PATH         Save the raw model output as pretty JSON (for Clairic: the envelope's `result`), with the
                     account ID and token scrubbed, and print `usage` plus every field's value and confidence.

The image (PNG, JPEG or WebP) is sent as-is, without downscaling.
"""

struct CLIError: Error { let message: String }

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

struct Options {
    var imagePath = ""
    var backend = "clairic"
    var endpoint = "http://127.0.0.1:8080"
    var model = "mlx-community/Inkling-2-Mini-4bit"
    var rawPath: String?
}

func parse(_ args: [String]) throws -> Options {
    guard args.first == "analyze" else { throw CLIError(message: usage) }
    var o = Options()
    var i = 1
    func value(_ flag: String) throws -> String {
        i += 1
        guard i < args.count, !args[i].hasPrefix("--") else { throw CLIError(message: "\(flag) needs a value\n\n\(usage)") }
        return args[i]
    }
    while i < args.count {
        switch args[i] {
        case "--backend": o.backend = try value("--backend")
        case "--endpoint": o.endpoint = try value("--endpoint")
        case "--model": o.model = try value("--model")
        case "--raw": o.rawPath = try value("--raw")
        case "-h", "--help": throw CLIError(message: usage)
        case let a where a.hasPrefix("--"): throw CLIError(message: "Unknown option \(a)\n\n\(usage)")
        case let a:
            guard o.imagePath.isEmpty else { throw CLIError(message: "Only one image path is accepted\n\n\(usage)") }
            o.imagePath = a
        }
        i += 1
    }
    guard !o.imagePath.isEmpty else { throw CLIError(message: "Missing <image>\n\n\(usage)") }
    guard ["clairic", "local"].contains(o.backend) else { throw CLIError(message: "Unknown backend \(o.backend)\n\n\(usage)") }
    return o
}

/// Keeps the last response body so `--raw` can save exactly what the server returned.
final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    private let inner: any HTTPTransport
    private let lock = NSLock()
    private var body: Data?

    init(inner: any HTTPTransport = URLSessionTransport()) { self.inner = inner }

    var lastBody: Data? { lock.withLock { body } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await inner.send(request)
        lock.withLock { body = data }
        return (data, response)
    }
}

let recorder = RecordingTransport()

func makeAnalyzer(_ o: Options) throws -> any ScreenshotAnalyzer {
    let env = ProcessInfo.processInfo.environment
    switch o.backend {
    case "local":
        guard let url = URL(string: o.endpoint), url.scheme != nil else { throw CLIError(message: "Invalid --endpoint \(o.endpoint)") }
        return LocalOpenAICompatibleAnalyzer(configuration: .init(baseURL: url, model: o.model,
                                                                   apiKey: env["SHOTKEEPER_LOCAL_API_KEY"]),
                                             transport: recorder)
    default:
        let account = env["CLOUDFLARE_ACCOUNT_ID"] ?? ""
        let token = env["CLOUDFLARE_API_TOKEN"] ?? ""
        guard !account.isEmpty, !token.isEmpty else {
            throw CLIError(message: "Set CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN for the clairic backend.")
        }
        return CloudflareClairicAnalyzer(credentials: ClairicCredentials(accountID: account, apiToken: token),
                                         transport: recorder)
    }
}

func describe(_ error: AnalyzerError) -> String {
    switch error {
    case .unreachable(let m): return "unreachable: \(m)"
    case .rateLimited(let after): return "rate limited" + (after.map { ", retry after \($0)s" } ?? "")
    case .serverError(let s, let m): return "server error \(s): \(m)"
    case .unauthorized(let m): return "unauthorized: \(m)"
    case .badRequest(let s, let m): return s == 0 ? "rejected before sending: \(m)" : "bad request \(s): \(m)"
    case .invalidResponse(let m): return "invalid response: \(m)"
    case .notConfigured(let m): return "not configured: \(m)"
    }
}

/// Removes every configured secret from `text` (the response should never contain one; this is belt and braces).
func scrub(_ text: String) -> String {
    let env = ProcessInfo.processInfo.environment
    var out = text
    for key in ["CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_API_TOKEN", "SHOTKEEPER_LOCAL_API_KEY"] {
        if let secret = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), secret.count >= 4 {
            out = out.replacingOccurrences(of: secret, with: "<\(key)>")
        }
    }
    return out
}

func fmt(_ v: AnalysisJSON?) -> String {
    guard let v else { return "-" }
    if let d = v.doubleValue { return String(format: "%.4g", d) }
    if let data = try? v.encoded(), let s = String(data: data, encoding: .utf8) { return s }
    return "?"
}

/// Saves the raw output and prints usage and a per-field summary. Clairic: `result` of the REST envelope.
func saveRaw(_ body: Data, to path: String, backend: String) throws {
    var payload: Any = try JSONSerialization.jsonObject(with: body)
    if backend == "clairic", let root = payload as? [String: Any], let result = root["result"], !(result is NSNull) { payload = result }
    let pretty = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try Data((scrub(String(decoding: pretty, as: UTF8.self)) + "\n").utf8).write(to: URL(fileURLWithPath: path))
    print("Raw output saved to \(path)")
    guard backend == "clairic", let inner = try? AnalysisJSON.parse(pretty) else { return }
    if let usage = inner["usage"]?.objectValue {
        print("Usage: " + usage.keys.sorted().map { "\($0)=\(fmt(usage[$0]))" }.joined(separator: " "))
    }
    print("Truncated: \(fmt(inner["truncated"]))")
    for (name, a) in (inner["answers"]?.objectValue ?? [:]).sorted(by: { $0.key < $1.key }) {
        var parts = ["value=\(scrub(fmt(a["value"])))", "confidence=\(fmt(a["confidence"]))"]
        for key in ["confidences", "valid", "p_null", "p_nulls", "guess", "failure_reason"] where a[key] != nil {
            parts.append("\(key)=\(scrub(fmt(a[key])))")
        }
        print("  \(name): " + parts.joined(separator: " "))
    }
}

let options: Options
do { options = try parse(Array(CommandLine.arguments.dropFirst())) } catch {
    fail((error as? CLIError)?.message ?? "\(error)", code: 2)
}

let fileURL = URL(fileURLWithPath: options.imagePath)
guard let data = try? Data(contentsOf: fileURL) else { fail("Cannot read \(options.imagePath)") }
guard let image = ImageHeaderSniffer.payload(for: data) else { fail("\(options.imagePath) is not a PNG, JPEG or WebP image") }

let analyzer: any ScreenshotAnalyzer
do { analyzer = try makeAnalyzer(options) } catch {
    fail((error as? CLIError)?.message ?? "\(error)", code: 2)
}

let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
let context = AnalysisContext(originalFilename: fileURL.lastPathComponent,
                              capturedAt: attributes?[.modificationDate] as? Date ?? Date())

print("Image: \(fileURL.lastPathComponent) \(image.mimeType) \(image.pixelWidth)x\(image.pixelHeight), \(data.count) bytes (sent as-is)")
if options.backend == "clairic" {
    let tokens = ClairicFieldSchema.estimatedImageTokens(width: image.pixelWidth, height: image.pixelHeight)
    let total = ClairicFieldSchema.estimatedInputTokens(width: image.pixelWidth, height: image.pixelHeight)
    print("Estimated image tokens per copy: \(tokens) × \(ClairicFieldSchema.imageCopiesPerCall) copies"
          + " + \(ClairicFieldSchema.measuredSchemaTokens) schema ≈ \(total) input tokens")
}

let clock = ContinuousClock()
let start = clock.now
do {
    let analysis = try await analyzer.analyze(image, context: context)
    let elapsed = start.duration(to: clock.now)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(analysis), as: UTF8.self))
    let ext = fileURL.pathExtension.isEmpty ? "" : ".\(fileURL.pathExtension)"
    if let title = analysis.title {
        print("Proposed filename: \(title)\(ext) (title confidence \(String(format: "%.2f", analysis.titleConfidence)))")
    } else {
        print("Proposed filename: (none, keep \(fileURL.lastPathComponent))")
    }
    let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    print("Latency: \(Int(ms.rounded())) ms")
    print("Billed input tokens: \(analysis.billedInputTokens.map(String.init) ?? "n/a")")
    if let path = options.rawPath, let body = recorder.lastBody { try saveRaw(body, to: path, backend: options.backend) }
} catch let e as AnalyzerError {
    if let path = options.rawPath, let body = recorder.lastBody { try? saveRaw(body, to: path, backend: options.backend) }
    fail("Analysis failed (\(analyzer.backendID)): \(describe(e))")
} catch {
    fail("Analysis failed (\(analyzer.backendID)): \(error)")
}
