//
//  EngineTestSupport.swift
//  OffsetKitTests
//
//  Shared fixtures for the docs/03 §7 engine suite. Fixture hygiene per 03 §7:
//  expected instants are explicit Unix epochs (generated from IANA tzdata),
//  never built through the device calendar — the suite passes in any device zone.
//

import Foundation
import Testing
@testable import OffsetKit

/// Engine over the shipped seed JSONs (03 §7 conventions: fixture SeedData = bundled data).
func makeEngine() throws -> SessionScheduleEngine {
    SessionScheduleEngine(seed: try SessionScheduleEngine.loadBundledSeed())
}

func epochDate(_ seconds: Int) -> Date {
    Date(timeIntervalSince1970: TimeInterval(seconds))
}

func utcInterval(_ startEpoch: Int, _ endEpoch: Int) -> DateInterval {
    DateInterval(start: epochDate(startEpoch), end: epochDate(endEpoch))
}

func zonedCalendar(_ identifier: String) throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: identifier))
    return calendar
}

/// AppSettings defaults (spine §4) — all seven markets enabled, Beginner,
/// default rule set (04 §2.1: R1–R4 enabled, killzone rules disabled).
func defaultSettings() -> AppSettings {
    AppSettings()
}

func proSettings() -> AppSettings {
    var settings = AppSettings()
    settings.traderLevel = .pro
    return settings
}

extension Collection<MarketEvent> {
    func event(withID id: String) -> MarketEvent? {
        first { $0.id == id }
    }
}
