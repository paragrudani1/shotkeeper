// THROWAWAY probe (2026-11-28). Never merge to main. See probe/ShotkeeperProbe/project.yml.
// API facts: docs/research/spotlight-shortcuts-ocr.md — AppIntent / AppShortcutsProvider [AI1] [AI2],
// IntentFile(fileURL:filename:type:) and removedOnCompletion [AI11], ReturnsValue [AI20], openAppWhenRun [AI16].
import AppIntents
import Foundation
import UniformTypeIdentifiers

enum ProbeError: Error, CustomLocalizedStringResourceConvertible {
    case missingResource

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .missingResource: "probe.png is missing from the app bundle."
        }
    }
}

/// Returns the bundled probe PNG, copied into a fresh temporary folder (never a user file).
struct FindProbeScreenshots: AppIntent {
    static let title: LocalizedStringResource = "Find Probe Screenshots"
    static let description = IntentDescription("Returns ShotkeeperProbe's bundled test image.")

    @Parameter(title: "Text")
    var text: String?

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        guard let source = Bundle.main.url(forResource: "probe", withExtension: "png") else {
            throw ProbeError.missingResource
        }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotkeeperProbe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let copy = folder.appendingPathComponent("probe.png")
        // copyItem fails if the destination exists; the folder is new, so nothing can be replaced.
        try FileManager.default.copyItem(at: source, to: copy)
        var file = IntentFile(fileURL: copy, filename: "probe.png", type: .png)
        // Explicit, so a run shows whether Shortcuts leaves a returned file in place [AI11].
        file.removedOnCompletion = false
        return .result(value: [file])
    }
}

/// Brings up the probe's panel; the app is launched first if it isn't running.
struct OpenProbePanel: AppIntent {
    static let title: LocalizedStringResource = "Open Probe Panel"
    static let description = IntentDescription("Shows ShotkeeperProbe's panel.")
    // Deprecated in macOS 26 in favor of supportedModes [AI16]; the probe targets 15, where this is the API.
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ProbePanel.shared.show()
        return .result()
    }
}

struct ProbeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenProbePanel(),
            phrases: ["Open the probe panel in \(.applicationName)"],
            shortTitle: "Open Probe Panel",
            systemImageName: "macwindow"
        )
    }
}
