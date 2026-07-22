//
//  KeychainStoreTests.swift
//  OffsetTests
//
//  Keychain round-trip + precedence (02 §6). App-hosted on purpose: SecItem needs
//  the host app's keychain access; the unhosted SPM test runner cannot persist
//  generic passwords (found in M3 — see BUILDLOG).
//

import Foundation
import Testing
@testable import OffsetKit

@Suite("KeychainStore", .serialized)
struct KeychainStoreTests {

    @Test func userOverrideRoundTrip() {
        let store = KeychainStore(service: "com.bloxy-studios.Offset.tests.\(UUID().uuidString)")
        #expect(store.string(for: .exaAPIKey) == nil)

        store.setUserOverride("exa-test-key-123", for: .exaAPIKey)
        #expect(store.string(for: .exaAPIKey) == "exa-test-key-123")

        store.setUserOverride(nil, for: .exaAPIKey)
        #expect(store.string(for: .exaAPIKey) == nil)
    }

    @Test func userOverrideWinsOverBundleImport() {
        let store = KeychainStore(service: "com.bloxy-studios.Offset.tests.\(UUID().uuidString)")
        // Simulate a bundle import (internal write path), then a user override.
        store.write(value: "bundle-value", account: KeychainStore.SecretKey.finnhubAPIKey.rawValue + ".bundle")
        #expect(store.string(for: .finnhubAPIKey) == "bundle-value")

        store.setUserOverride("user-value", for: .finnhubAPIKey)
        #expect(store.string(for: .finnhubAPIKey) == "user-value")

        // Removing the override falls back to the bundle-imported value.
        store.setUserOverride(nil, for: .finnhubAPIKey)
        #expect(store.string(for: .finnhubAPIKey) == "bundle-value")
    }
}
