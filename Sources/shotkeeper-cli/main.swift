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
  shotkeeper-cli analyze <image> [--backend clairic|openrouter|local] [--endpoint URL] [--model NAME] [--raw PATH]
  shotkeeper-cli icon-svg app|glyph     Print the app icon or menu bar glyph SVG (core IconSVG) to stdout.
                                        scripts/make-icons.sh writes design/icon/ and the asset catalog from it.
  shotkeeper-cli icon-composer --list|<file>
                                        List the files of the macOS 26 AppIcon.icon package, or print one of them
                                        (core IconComposerBundle). scripts/make-icons.sh writes App/Shotkeeper/AppIcon.icon.

Backends:
  clairic (default)  Cloudflare Workers AI @cf/cloudflare/clairic.
                     Needs CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN in the environment.
  openrouter         Inkling 2 Mini through OpenRouter (https://openrouter.ai/api/v1/chat/completions), with reasoning
                     off, zero data retention and data_collection deny. Needs OPENROUTER_API_KEY in the environment.
                     --model defaults to thinkingmachines/inkling-2-mini. Prints usage tokens and cost (usage.cost).
  local              OpenAI-compatible /v1/chat/completions server (mlx_lm.server, LM Studio, llama-server, Ollama).
                     --endpoint defaults to http://127.0.0.1:8080, --model to mlx-community/Inkling-2-Mini-4bit.
                     Optional bearer token: SHOTKEEPER_LOCAL_API_KEY.

Options:
  --raw PATH         Save the raw model output as pretty JSON (for Clairic: the envelope's `result`; for OpenRouter
                     and local: the whole completion, or every completion when a repair call was made), with the
                     account ID, tokens and keys scrubbed, and print `usage` plus every field's value and confidence.

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
    var model: String?
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
    guard ["clairic", "openrouter", "local"].contains(o.backend) else { throw CLIError(message: "Unknown backend \(o.backend)\n\n\(usage)") }
    return o
}

/// Keeps every response body so `--raw` can save exactly what the server returned (OpenRouter and local backends
/// may make a second, repair call).
final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    private let inner: any HTTPTransport
    private let lock = NSLock()
    private var bodies: [Data] = []

    init(inner: any HTTPTransport = URLSessionTransport()) { self.inner = inner }

    var allBodies: [Data] { lock.withLock { bodies } }
    var lastBody: Data? { allBodies.last }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await inner.send(request)
        lock.withLock { bodies.append(data) }
        return (data, response)
    }
}

let recorder = RecordingTransport()

func makeAnalyzer(_ o: Options) throws -> any ScreenshotAnalyzer {
    let env = ProcessInfo.processInfo.environment
    switch o.backend {
    case "local":
        guard let url = URL(string: o.endpoint), url.scheme != nil else { throw CLIError(message: "Invalid --endpoint \(o.endpoint)") }
        return OpenAICompatibleAnalyzer(configuration: .init(baseURL: url, model: o.model ?? "mlx-community/Inkling-2-Mini-4bit",
                                                              apiKey: env["SHOTKEEPER_LOCAL_API_KEY"]),
                                        transport: recorder)
    case "openrouter":
        let key = env["OPENROUTER_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { throw CLIError(message: "Set OPENROUTER_API_KEY for the openrouter backend.") }
        return OpenAICompatibleAnalyzer(configuration: OpenRouterBackend.configuration(apiKey: key, model: o.model),
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
    case .accountState(let m): return "account: \(m)"
    }
}

/// Removes every configured secret from `text` (the response should never contain one; this is belt and braces).
func scrub(_ text: String) -> String {
    let env = ProcessInfo.processInfo.environment
    var out = text
    for key in ["CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_API_TOKEN", "SHOTKEEPER_LOCAL_API_KEY", "OPENROUTER_API_KEY"] {
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

/// Saves the raw output and prints usage and a per-field summary. Clairic: `result` of the REST envelope. Chat
/// backends: the completion, or an array of completions when a repair call was made.
func saveRaw(_ bodies: [Data], to path: String, backend: String) throws {
    guard let body = bodies.last else { return }
    var payload: Any = try JSONSerialization.jsonObject(with: body)
    if backend == "clairic", let root = payload as? [String: Any], let result = root["result"], !(result is NSNull) { payload = result }
    if backend != "clairic", bodies.count > 1 { payload = try bodies.map { try JSONSerialization.jsonObject(with: $0) } }
    let pretty = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try Data((scrub(String(decoding: pretty, as: UTF8.self)) + "\n").utf8).write(to: URL(fileURLWithPath: path))
    print("Raw output saved to \(path)")
    if backend != "clairic" { return }
    guard let inner = try? AnalysisJSON.parse(pretty) else { return }
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

/// Chat completions' `usage` (OpenRouter: prompt/completion/reasoning tokens and `cost` in USD credits;
/// docs/research/openrouter.md, "Usage and cost"), per call and summed, plus the serving provider and the title
/// rules' verdict.
func printChatUsage(_ bodies: [Data]) {
    var prompt = 0, completion = 0, reasoning = 0, cost = 0.0, hasCost = false
    for (i, body) in bodies.enumerated() {
        guard let root = try? AnalysisJSON.parse(body) else { continue }
        let usage = root["usage"]
        let p = usage?["prompt_tokens"]?.intValue ?? 0, c = usage?["completion_tokens"]?.intValue ?? 0
        let r = usage?["completion_tokens_details"]?["reasoning_tokens"]?.intValue ?? 0
        prompt += p; completion += c; reasoning += r
        if let value = usage?["cost"]?.doubleValue { cost += value; hasCost = true }
        let provider = root["provider"]?.stringValue.map { " provider=\($0)" } ?? ""
        let finish = root["choices"]?[0]?["finish_reason"]?.stringValue ?? "-"
        let logprobs = root["choices"]?[0]?["logprobs"]?["content"]?.arrayValue?.count
        print("Call \(i + 1): prompt_tokens=\(p) completion_tokens=\(c) reasoning_tokens=\(r)"
              + " cost=\(fmt(usage?["cost"])) finish_reason=\(finish) logprob_tokens=\(logprobs.map(String.init) ?? "none")\(provider)")
        if let content = root["choices"]?[0]?["message"]?["content"]?.stringValue,
           let object = try? AnalysisJSON.parse(content), let title = object["title"]?.stringValue {
            let problem = TitleRules.problem(with: title, sourceAppOrSite: object["source_app_or_site"]?.stringValue)
            print("  title rules: \(problem.map { "\($0)" } ?? "pass")")
        }
    }
    print("Usage total: prompt_tokens=\(prompt) completion_tokens=\(completion) reasoning_tokens=\(reasoning)"
          + (hasCost ? String(format: " cost=$%.8f", cost) : " cost=n/a"))
}

// `icon-svg`: no network, no credentials; stdout only (the script decides where the file goes).
if CommandLine.arguments.dropFirst().first == "icon-svg" {
    switch Array(CommandLine.arguments.dropFirst(2)) {
    case ["app"]: print(IconSVG.appIcon(), terminator: "")
    case ["glyph"]: print(IconSVG.menuBarGlyph(), terminator: "")
    default: fail(usage, code: 2)
    }
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "icon-composer" {
    let files = IconComposerBundle.files()
    let args = Array(CommandLine.arguments.dropFirst(2))
    guard args.count == 1 else { fail(usage, code: 2) }
    if args[0] == "--list" {
        print(files.map(\.path).joined(separator: "\n"))
    } else if let file = files.first(where: { $0.path == args[0] }) {
        print(file.contents, terminator: "")
    } else {
        fail("No such file: \(args[0])\n\n\(usage)", code: 2)
    }
    exit(0)
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
if options.backend == "openrouter" {
    print("Backend: OpenRouter \(options.model ?? OpenRouterBackend.defaultModel), reasoning \(fmt(OpenRouterBackend.reasoningOff)), "
          + "provider \(fmt(OpenRouterBackend.providerRouting(model: OpenRouterBackend.effectiveModel(options.model)))))")
}
if options.backend == "clairic" {
    let tokens = ClairicFieldSchema.estimatedImageTokens(width: image.pixelWidth, height: image.pixelHeight)
    let total = ClairicFieldSchema.estimatedInputTokens(width: image.pixelWidth, height: image.pixelHeight)
    print("Estimated image tokens per copy: \(tokens) × \(ClairicFieldSchema.imageCopiesPerCall) copies"
          + " + \(ClairicFieldSchema.measuredSchemaTokens) schema ≈ \(total) input tokens")
}

let clock = ContinuousClock()
let start = clock.now
do {
    let analysis = try await analyzer.analyze(image, context: context)  // lint-allow: analyze (developer CLI: only the file on its command line)
    let elapsed = start.duration(to: clock.now)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(analysis), as: UTF8.self))
    let ext = fileURL.pathExtension.isEmpty ? "" : ".\(fileURL.pathExtension)"
    // The app's rule with default settings (ScreenshotProcessor): rename only at title confidence >= 0.5, styled
    // with the default filename style (sentence case, no date).
    let defaults = AppSettings.defaults
    let confidence = String(format: "%.2f", analysis.titleConfidence)
    if let title = analysis.title, analysis.titleConfidence >= defaults.minTitleConfidence,
       let stem = defaults.filenameStyle.stem(from: title, capturedAt: context.capturedAt, timeZone: .current) {
        print("Proposed filename: \(stem)\(ext) (title confidence \(confidence))")
    } else if let title = analysis.title {
        print("Proposed filename: (keep \(fileURL.lastPathComponent): title \"\(title)\" confidence \(confidence) < "
              + "\(defaults.minTitleConfidence))")
    } else {
        print("Proposed filename: (keep \(fileURL.lastPathComponent): no usable title)")
    }
    let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    print("Latency: \(Int(ms.rounded())) ms")
    print("Billed input tokens: \(analysis.billedInputTokens.map(String.init) ?? "n/a")")
    if options.backend != "clairic" { printChatUsage(recorder.allBodies) }
    if let path = options.rawPath, !recorder.allBodies.isEmpty { try saveRaw(recorder.allBodies, to: path, backend: options.backend) }
} catch let e as AnalyzerError {
    if options.backend != "clairic" { printChatUsage(recorder.allBodies) }
    if let path = options.rawPath, !recorder.allBodies.isEmpty { try? saveRaw(recorder.allBodies, to: path, backend: options.backend) }
    fail(scrub("Analysis failed (\(analyzer.backendID)): \(describe(e))"))
} catch {
    fail(scrub("Analysis failed (\(analyzer.backendID)): \(error)"))
}
