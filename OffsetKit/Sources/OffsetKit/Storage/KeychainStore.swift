//
//  KeychainStore.swift
//  OffsetKit
//
//  Secrets pipeline per 02 §6: gitignored xcconfig → build settings → Info.plist
//  → read once at startup → Keychain (kSecAttrAccessibleAfterFirstUnlock).
//  Two accounts per key: a user-pasted override always wins over the
//  bundle-imported value (covers rotation without rebuilds and protects the
//  Settings paste-in from being clobbered by a stale bundle). Missing/blank keys
//  are legal — clients degrade (02 §6 step 4). Never log secret values.
//

import Foundation
import OSLog
import Security

nonisolated public struct KeychainStore: Sendable {

    public enum SecretKey: String, CaseIterable, Sendable {
        case finnhubAPIKey = "FINNHUB_API_KEY"
        case exaAPIKey = "EXA_API_KEY"
    }

    private let service: String
    private let logger = Logger(subsystem: offsetLogSubsystem, category: "refresh")

    public init(service: String = "com.bloxy-studios.Offset.secrets") {
        self.service = service
    }

    /// The effective value: user override first, then bundle-imported. Nil/blank → absent.
    public func string(for key: SecretKey) -> String? {
        if let user = read(account: key.rawValue + ".user"), !user.isEmpty { return user }
        if let bundle = read(account: key.rawValue + ".bundle"), !bundle.isEmpty { return bundle }
        return nil
    }

    /// Settings paste-in override (02 §6 alternative path). Nil or blank removes the override.
    public func setUserOverride(_ value: String?, for key: SecretKey) {
        write(value: value?.isEmpty == true ? nil : value, account: key.rawValue + ".user")
    }

    /// Startup bootstrap: import Info.plist substitutions into the Keychain.
    /// Rewrites the bundle-imported copy only when the bundle value changed
    /// (first launch or key rotation); never touches user overrides. Empty
    /// substitutions (keys absent at build) import nothing.
    public func bootstrap(from bundle: Bundle = .main) {
        for key in SecretKey.allCases {
            let bundleValue = (bundle.object(forInfoDictionaryKey: key.rawValue) as? String) ?? ""
            let account = key.rawValue + ".bundle"
            guard !bundleValue.isEmpty, !bundleValue.hasPrefix("$(") else { continue }
            if read(account: account) != bundleValue {
                write(value: bundleValue, account: account)
                logger.info("KeychainStore: imported \(key.rawValue, privacy: .public) from bundle")
            }
        }
    }

    // MARK: SecItem plumbing (generic passwords; internal for @testable access)

    func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(value: String?, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("KeychainStore: SecItemAdd failed (\(status)) for \(account, privacy: .public)")
        }
    }
}
