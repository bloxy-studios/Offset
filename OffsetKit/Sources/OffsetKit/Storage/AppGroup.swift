//
//  AppGroup.swift
//  OffsetKit
//
//  The App Group shared by the app and the widget extension (spine §2 Storage).
//  Identifier root `com.bloxy-studios` per DECISIONS "Setup facts (M0)" —
//  supersedes the docs' `dev.offsetapp` placeholder everywhere. Case-sensitive.
//

import Foundation

/// OSLog subsystem for OffsetKit components (02 §8; docs' `dev.offsetapp.offset`
/// mirrored to the real identifier root).
nonisolated let offsetLogSubsystem = "com.bloxy-studios.Offset"

nonisolated public enum AppGroup {

    public static let identifier = "group.com.bloxy-studios.Offset"

    /// App Group UserDefaults. Falls back to `.standard` when the entitlement is
    /// unavailable (e.g. SPM test runners) so OffsetKit never crashes; production
    /// targets always carry the App Group entitlement (M0 setup facts).
    public static var userDefaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// Shared container URL (SwiftData store home); nil without the entitlement.
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
