import Foundation

/// Names of stored secrets.
public struct CredentialKey: RawRepresentable, Hashable, Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Cloudflare API token with Workers AI Read + Edit.
    public static let cloudflareAPIToken = CredentialKey(rawValue: "cloudflare-api-token")
    /// Optional bearer token for a custom OpenAI-compatible endpoint.
    public static let customEndpointAPIKey = CredentialKey(rawValue: "custom-endpoint-api-key")
}

/// Where secrets live. The macOS app implements this with the Keychain; never log or persist values elsewhere.
public protocol CredentialStore: Sendable {
    func secret(for key: CredentialKey) throws -> String?
    func setSecret(_ value: String, for key: CredentialKey) throws
    func removeSecret(for key: CredentialKey) throws
}

/// For tests and previews.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private var values: [CredentialKey: String]
    private let lock = NSLock()

    public init(_ values: [CredentialKey: String] = [:]) { self.values = values }

    public func secret(for key: CredentialKey) throws -> String? { lock.withLock { values[key] } }
    public func setSecret(_ value: String, for key: CredentialKey) throws { lock.withLock { values[key] = value } }
    public func removeSecret(for key: CredentialKey) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}
