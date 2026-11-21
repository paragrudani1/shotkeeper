import AppKit
import SwiftUI

/// Brand colors (docs/specs/ui-polish-2026-11.md, "Global style"). Indigo is only for brand moments (toast label,
/// countdown bar, primary buttons in our own panels); everything else uses semantic system colors.
enum Brand {
    /// Fills and strokes: light #5856D6, dark #5E5CE6 (systemIndigo).
    static let indigoNSColor = NSColor(name: "ShotkeeperIndigo") { appearance in
        appearance.isDark ? NSColor(srgbHex: 0x5E5CE6) : NSColor(srgbHex: 0x5856D6)
    }

    /// Indigo text. Light: #4644C0 (spec; 6.2:1 on light materials). Dark: #A5A4FF, not in the spec: both spec
    /// indigos are below 3.3:1 on dark materials, and the spec requires 4.5:1 for text (this one is 5.1–7.4:1).
    static let indigoTextNSColor = NSColor(name: "ShotkeeperIndigoText") { appearance in
        appearance.isDark ? NSColor(srgbHex: 0xA5A4FF) : NSColor(srgbHex: 0x4644C0)
    }

    /// Error text (setup's failed Test Connection): systemRed is 3.6:1 on white, below the spec's 4.5:1.
    /// Light #C4281C (5.7:1 on white, 4.8:1 on #ECECEC), dark #FF7B72 (6.6:1 on #1E1E1E, 5.1:1 on #323232).
    static let errorTextNSColor = NSColor(name: "ShotkeeperErrorText") { appearance in
        appearance.isDark ? NSColor(srgbHex: 0xFF7B72) : NSColor(srgbHex: 0xC4281C)
    }

    /// Orange text on a light orange fill (setup's "Experimental" badge, local model note): light #8A4600
    /// (6.1:1 on its fill), dark #FFB340 (6.0:1).
    static let warningTextNSColor = NSColor(name: "ShotkeeperWarningText") { appearance in
        appearance.isDark ? NSColor(srgbHex: 0xFFB340) : NSColor(srgbHex: 0x8A4600)
    }

    static var indigo: Color { Color(nsColor: indigoNSColor) }
    static var warningText: Color { Color(nsColor: warningTextNSColor) }
    static var errorText: Color { Color(nsColor: errorTextNSColor) }
    static var indigoText: Color { Color(nsColor: indigoTextNSColor) }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

extension NSColor {
    convenience init(srgbHex hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Primary button in our own panels: indigo fill, white text (5.1–5.7:1). `large` is the window size (setup).
struct BrandPrimaryButtonStyle: ButtonStyle {
    var large = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 13 : 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 16 : 10)
            .frame(minWidth: large ? 84 : nil)
            .frame(height: large ? 28 : 24)
            .background(Brand.indigo.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 6))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Secondary button in our own panels: a light neutral fill that works on materials in light and dark mode.
struct PanelSecondaryButtonStyle: ButtonStyle {
    var large = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 13 : 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, large ? 16 : 10)
            .frame(minWidth: large ? 84 : nil)
            .frame(height: large ? 28 : 24)
            .background(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08)))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}
