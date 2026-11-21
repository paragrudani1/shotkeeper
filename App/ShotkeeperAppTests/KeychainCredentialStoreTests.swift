import ShotkeeperCore
import XCTest
@testable import Shotkeeper

final class KeychainCredentialStoreTests: XCTestCase {
    /// A per-run service so tests never touch the real app's items and never collide between runs.
    private let store = KeychainCredentialStore(service: "dev.shotkeeper.Shotkeeper.tests.\(UUID().uuidString)")
    private let key = CredentialKey.cloudflareAPIToken
    private let other = CredentialKey(rawValue: "other")

    override func tearDown() {
        try? store.removeSecret(for: key)
        super.tearDown()
    }

    func testDefaultServiceIsTheBundleIdentifier() {
        XCTAssertEqual(KeychainCredentialStore().service, "dev.shotkeeper.Shotkeeper")
    }

    func testSetGetUpdateDelete() throws {
        try skipIfKeychainUnavailable { try store.setSecret("first-value", for: key) }
        XCTAssertEqual(try store.secret(for: key), "first-value")

        try store.setSecret("second-value", for: key)
        XCTAssertEqual(try store.secret(for: key), "second-value")

        try store.removeSecret(for: key)
        XCTAssertNil(try store.secret(for: key))
        // Deleting again is not an error.
        XCTAssertNoThrow(try store.removeSecret(for: key))
    }

    func testMissingKeyReturnsNil() throws {
        let value = try skipIfKeychainUnavailable { try store.secret(for: CredentialKey(rawValue: "never-set-\(UUID().uuidString)")) }
        XCTAssertNil(value)
    }

    func testKeysAreIndependent() throws {
        try skipIfKeychainUnavailable { try store.setSecret("a", for: key) }
        defer { try? store.removeSecret(for: other) }
        try store.setSecret("b", for: other)
        XCTAssertEqual(try store.secret(for: key), "a")
        XCTAssertEqual(try store.secret(for: other), "b")
    }

    /// CI runners may have no unlocked login keychain; that is an environment limit, not a bug in the store.
    @discardableResult
    private func skipIfKeychainUnavailable<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as KeychainError where error.isKeychainUnavailable {
            throw XCTSkip("Keychain unavailable in this environment (\(error)); KeychainCredentialStore not exercised.")
        }
    }
}
