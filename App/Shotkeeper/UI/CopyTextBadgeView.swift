import ShotkeeperCore
import SwiftUI

/// The Copy Text badge on the preview image (design §2 "The one bold choice", §4 "Preview: the Copy Text badge"):
/// bottom-right of the 220 pt image frame, inset 10 pt; a 26 pt capsule, black 72%, white 12 pt semibold, a leading
/// symbol, and on Copy Text the "⇧⌘C" keycap in white 60% at 11 pt. In dark mode a 0.5 pt white 18% edge keeps it
/// visible over dark screenshots (design §8). States and wording are core's `CopyTextBadge`.
///
/// Mouse clicks and the hover tooltip reach the badge through `FileDragView`, which lies over the image and is told the
/// badge's frame (`CopyTextBadgeFrameKey`) and help: a press on the badge never starts a drag or counts toward a
/// double-click. The SwiftUI button gives VoiceOver and Full Keyboard Access the same action.
struct CopyTextBadgeView: View {
    static let inset: CGFloat = 10
    static let height: CGFloat = 26

    let badge: CopyTextBadge
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                leading
                Text(badge.title)
                if let shortcut = badge.shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .padding(.leading, 2)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.leading, 9)
            .padding(.trailing, 10)
            .frame(height: Self.height)
            .background(Capsule().fill(Color.black.opacity(0.72)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.18 : 0), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(badge.help)
        .accessibilityLabel(badge.accessibilityLabel)
        .accessibilityHint(badge.accessibilityHint ?? "")
        .anchorPreference(key: CopyTextBadgeFrameKey.self, value: .bounds) { $0 }
    }

    @ViewBuilder private var leading: some View {
        switch badge {
        case .copyText:
            Image(systemName: "text.viewfinder")
        case .reading:
            // The native spinner at 12 pt (design §7), drawn light on the dark capsule.
            ProgressView().controlSize(.mini).frame(width: 12, height: 12).environment(\.colorScheme, .dark)
        case .readAgain:
            // White, like the problem pill's symbol: the overlay pill and badge are black 72% with white content (design §3).
            Image(systemName: "exclamationmark.triangle.fill")
        }
    }
}

/// The badge's bounds, read by the preview image to tell `FileDragView` where the badge is.
struct CopyTextBadgeFrameKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
