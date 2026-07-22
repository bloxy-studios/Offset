//
//  SettingsModels.swift
//  OffsetKit
//
//  Settings model types. Names/signatures per docs/00-SPINE.md §4 — verbatim,
//  plus `AppSettings.dismissedExplainerIDs` adopted via spine §8 (07 amendment).
//

import Foundation

/// Pro-editable session hours & killzone windows. Spine §4.
///
/// `killzoneWindows` values are labeled tuples, which Codable cannot synthesize —
/// custom Codable encodes each window as `{ "open": …, "close": … }` and keys both
/// dictionaries by raw value (docs/03-SESSION-ENGINE.md §2d note; owned here per 02).
nonisolated public struct ConventionSettings: Codable, Sendable {
    public var sessionOverrides: [MarketID: [TradingSegment]]   // empty = canonical defaults
    public var killzoneWindows: [KillzoneID: (open: WallClockTime, close: WallClockTime)]

    public init(
        sessionOverrides: [MarketID: [TradingSegment]] = [:],
        killzoneWindows: [KillzoneID: (open: WallClockTime, close: WallClockTime)] = [:]
    ) {
        self.sessionOverrides = sessionOverrides
        self.killzoneWindows = killzoneWindows
    }

    private nonisolated enum CodingKeys: String, CodingKey {
        case sessionOverrides, killzoneWindows
    }

    private nonisolated struct Window: Codable, Sendable {
        var open: WallClockTime
        var close: WallClockTime
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let rawOverrides = try container.decode([String: [TradingSegment]].self, forKey: .sessionOverrides)
        var overrides: [MarketID: [TradingSegment]] = [:]
        overrides.reserveCapacity(rawOverrides.count)
        for (key, segments) in rawOverrides {
            guard let market = MarketID(rawValue: key) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .sessionOverrides, in: container,
                    debugDescription: "Unknown MarketID '\(key)'"
                )
            }
            overrides[market] = segments
        }
        self.sessionOverrides = overrides

        let rawWindows = try container.decode([String: Window].self, forKey: .killzoneWindows)
        var windows: [KillzoneID: (open: WallClockTime, close: WallClockTime)] = [:]
        windows.reserveCapacity(rawWindows.count)
        for (key, window) in rawWindows {
            guard let killzone = KillzoneID(rawValue: key) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .killzoneWindows, in: container,
                    debugDescription: "Unknown KillzoneID '\(key)'"
                )
            }
            windows[killzone] = (open: window.open, close: window.close)
        }
        self.killzoneWindows = windows
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        var rawOverrides: [String: [TradingSegment]] = [:]
        rawOverrides.reserveCapacity(sessionOverrides.count)
        for (market, segments) in sessionOverrides {
            rawOverrides[market.rawValue] = segments
        }
        try container.encode(rawOverrides, forKey: .sessionOverrides)

        var rawWindows: [String: Window] = [:]
        rawWindows.reserveCapacity(killzoneWindows.count)
        for (killzone, window) in killzoneWindows {
            rawWindows[killzone.rawValue] = Window(open: window.open, close: window.close)
        }
        try container.encode(rawWindows, forKey: .killzoneWindows)
    }
}

nonisolated public enum TimeDisplayMode: String, Codable, Sendable {
    case local, market, both
}

nonisolated public struct AppSettings: Codable, Sendable {
    public var traderLevel: TraderLevel                 // default .beginner
    public var enabledMarkets: Set<MarketID>            // default: all seven
    public var alertRules: [AlertRule]                  // default set: 04 §2.1 R1–R20 (only R1–R4 enabled)
    public var econCurrencies: Set<String>              // default ["USD","GBP","EUR","JPY","AUD"]
    public var briefingTime: WallClockTime              // default 07:30 (device-local)
    public var conventions: ConventionSettings
    public var timeDisplayMode: TimeDisplayMode         // default .both
    public var liveActivityEnabled: Bool                // default true
    public var dismissedExplainerIDs: [String]          // spine §8 (07 amendment)

    public init(
        traderLevel: TraderLevel = .beginner,
        enabledMarkets: Set<MarketID> = Set(MarketID.allCases),
        alertRules: [AlertRule] = AlertRule.defaultRules(),
        econCurrencies: Set<String> = ["USD", "GBP", "EUR", "JPY", "AUD"],
        briefingTime: WallClockTime = WallClockTime(hour: 7, minute: 30),
        conventions: ConventionSettings = ConventionSettings(),
        timeDisplayMode: TimeDisplayMode = .both,
        liveActivityEnabled: Bool = true,
        dismissedExplainerIDs: [String] = []
    ) {
        self.traderLevel = traderLevel
        self.enabledMarkets = enabledMarkets
        self.alertRules = alertRules
        self.econCurrencies = econCurrencies
        self.briefingTime = briefingTime
        self.conventions = conventions
        self.timeDisplayMode = timeDisplayMode
        self.liveActivityEnabled = liveActivityEnabled
        self.dismissedExplainerIDs = dismissedExplainerIDs
    }
}
