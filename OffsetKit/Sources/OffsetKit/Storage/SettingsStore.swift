//
//  SettingsStore.swift
//  OffsetKit
//
//  App Group UserDefaults persistence for AppSettings, per 02 §4.1:
//  one JSON blob under "offset.settings.v-envelope" wrapped in a versioned
//  SettingsEnvelope; stepwise migrations; quarantine-and-reset on downgrade or
//  decode failure (never crash, never modal).
//

import Foundation
import OSLog

/// Current `SettingsEnvelope.schemaVersion` (02 PROPOSED ADDITIONS).
nonisolated public let settingsSchemaVersion = 1

/// Versioned wrapper persisted by `SettingsStore` (02 PROPOSED ADDITIONS).
nonisolated public struct SettingsEnvelope: Codable, Sendable {
    public var schemaVersion: Int
    public var settings: AppSettings

    public init(schemaVersion: Int, settings: AppSettings) {
        self.schemaVersion = schemaVersion
        self.settings = settings
    }
}

/// Thin nonisolated wrapper over App Group UserDefaults (02 §2 isolation table);
/// UserDefaults provides its own synchronization. Single writer: the app target.
///
/// `@unchecked Sendable`: the only stored reference is `UserDefaults`, which is
/// not `Sendable`-annotated in the SDK but is documented thread-safe ("The
/// UserDefaults class is thread-safe"); this wrapper is otherwise immutable.
/// Justification recorded in BUILDLOG (M3) per BUILD_PROMPT §5 hygiene rule.
nonisolated public struct SettingsStore: @unchecked Sendable {

    public static let envelopeKey = "offset.settings.v-envelope"
    public static let quarantineKey = "offset.settings.quarantine"

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: offsetLogSubsystem, category: "refresh")

    public init(defaults: UserDefaults = AppGroup.userDefaults) {
        self.defaults = defaults
    }

    /// True when a previous load quarantined an unreadable/newer blob and reset
    /// to defaults — Settings surfaces a one-line "Settings were reset" row (02 §4.1).
    public var wasReset: Bool {
        defaults.data(forKey: Self.quarantineKey) != nil
    }

    public func clearResetFlag() {
        defaults.removeObject(forKey: Self.quarantineKey)
    }

    /// Load settings, running the migration policy. First launch creates and
    /// persists the defaults (incl. the 04 §2 default AlertRule set).
    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: Self.envelopeKey) else {
            let fresh = AppSettings()
            save(fresh)
            logger.info("SettingsStore: first launch — defaults persisted (schema \(settingsSchemaVersion))")
            return fresh
        }
        // Probe the version first so an incompatible AppSettings shape can't
        // masquerade as corruption before we know which path applies.
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data) else {
            return quarantineAndReset(data, reason: "envelope undecodable")
        }
        if probe.schemaVersion > settingsSchemaVersion {
            return quarantineAndReset(data, reason: "downgrade from schema \(probe.schemaVersion)")
        }

        var blob = data
        if probe.schemaVersion < settingsSchemaVersion {
            do {
                blob = try Self.migrate(blob, from: probe.schemaVersion)
            } catch {
                return quarantineAndReset(data, reason: "migration failed: \(error)")
            }
        }
        guard let envelope = try? JSONDecoder().decode(SettingsEnvelope.self, from: blob) else {
            return quarantineAndReset(data, reason: "settings undecodable at schema \(settingsSchemaVersion)")
        }
        if probe.schemaVersion < settingsSchemaVersion {
            save(envelope.settings)                      // persist the migrated form
            logger.info("SettingsStore: migrated schema \(probe.schemaVersion) → \(settingsSchemaVersion)")
        }
        return envelope.settings
    }

    public func save(_ settings: AppSettings) {
        let envelope = SettingsEnvelope(schemaVersion: settingsSchemaVersion, settings: settings)
        guard let data = try? JSONEncoder().encode(envelope) else {
            logger.error("SettingsStore: encode failed — settings not persisted")
            return
        }
        defaults.set(data, forKey: Self.envelopeKey)
    }

    // MARK: Migration machinery (02 §4.1 policy)

    private nonisolated struct VersionProbe: Codable {
        let schemaVersion: Int
    }

    /// Stepwise raw-blob migrations `migrate1to2`, `migrate2to3`, … — pure
    /// functions, unit-tested. Empty while settingsSchemaVersion == 1 (stub).
    private static let migrations: [Int: @Sendable (Data) throws -> Data] = [:]

    nonisolated static func migrate(_ data: Data, from version: Int) throws -> Data {
        var blob = data
        var current = version
        while current < settingsSchemaVersion {
            guard let step = migrations[current] else {
                throw CocoaError(.coderInvalidValue)
            }
            blob = try step(blob)
            current += 1
        }
        return blob
    }

    private func quarantineAndReset(_ raw: Data, reason: String) -> AppSettings {
        defaults.set(raw, forKey: Self.quarantineKey)
        logger.error("SettingsStore: quarantined settings blob (\(reason, privacy: .public)); reset to defaults")
        let fresh = AppSettings()
        save(fresh)
        return fresh
    }
}
