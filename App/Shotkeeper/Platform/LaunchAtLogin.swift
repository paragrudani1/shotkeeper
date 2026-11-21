import Foundation
import ServiceManagement

/// Login item for the app bundle itself (`SMAppService.mainApp`, macOS 13+).
@MainActor
enum LaunchAtLogin {
    enum Status: Equatable, Sendable {
        case enabled
        case disabled
        /// Registered, but the user must approve it in System Settings > General > Login Items.
        case requiresApproval
        /// The app is not in a location launchd can register (e.g. run from DerivedData or a DMG).
        case notFound

        init(_ status: SMAppService.Status) {
            switch status {
            case .enabled: self = .enabled
            case .requiresApproval: self = .requiresApproval
            case .notFound: self = .notFound
            case .notRegistered: self = .disabled
            @unknown default: self = .disabled
            }
        }
    }

    static var status: Status { Status(SMAppService.mainApp.status) }

    static var isEnabled: Bool { status == .enabled }

    static func register() throws {
        try SMAppService.mainApp.register()
    }

    static func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try register() } else { try unregister() }
    }

    /// Makes the login item match `enabled` without failing on a no-op: registers unless already enabled,
    /// unregisters only what is registered.
    static func apply(_ enabled: Bool) throws {
        switch (enabled, status) {
        case (true, .enabled), (false, .disabled), (false, .notFound): return
        case (true, _): try register()
        case (false, _): try unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
