//
//  ModelTests.swift
//  OffsetKitTests
//
//  M1 acceptance: WallClockTime Comparable behavior, plus coverage for the
//  hand-written Codable surfaces introduced in M1 (DayKey, ConventionSettings)
//  and the AppSettings spine defaults.
//

import Foundation
import Testing
@testable import OffsetKit

@Suite("WallClockTime")
struct WallClockTimeTests {

    @Test func comparableOrdersByHourThenMinute() {
        #expect(WallClockTime(hour: 7, minute: 0) < WallClockTime(hour: 7, minute: 1))
        #expect(WallClockTime(hour: 9, minute: 59) < WallClockTime(hour: 10, minute: 0))
        #expect(WallClockTime(hour: 0, minute: 0) < WallClockTime(hour: 23, minute: 59))
        #expect(!(WallClockTime(hour: 8, minute: 30) < WallClockTime(hour: 8, minute: 30)))
        #expect(WallClockTime(hour: 8, minute: 30) == WallClockTime(hour: 8, minute: 30))
        // Derived operators from Comparable.
        #expect(WallClockTime(hour: 16, minute: 0) > WallClockTime(hour: 9, minute: 30))
        #expect(WallClockTime(hour: 13, minute: 0) <= WallClockTime(hour: 13, minute: 0))
    }

    @Test func sortingIsChronological() {
        let times = [
            WallClockTime(hour: 16, minute: 0),
            WallClockTime(hour: 4, minute: 0),
            WallClockTime(hour: 9, minute: 30),
            WallClockTime(hour: 9, minute: 0),
        ]
        #expect(times.sorted() == [
            WallClockTime(hour: 4, minute: 0),
            WallClockTime(hour: 9, minute: 0),
            WallClockTime(hour: 9, minute: 30),
            WallClockTime(hour: 16, minute: 0),
        ])
        #expect(max(WallClockTime(hour: 8, minute: 0), WallClockTime(hour: 9, minute: 30)) == WallClockTime(hour: 9, minute: 30))
        #expect(min(WallClockTime(hour: 8, minute: 0), WallClockTime(hour: 9, minute: 30)) == WallClockTime(hour: 8, minute: 0))
    }

    @Test func codableRoundTrip() throws {
        let original = WallClockTime(hour: 9, minute: 30)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WallClockTime.self, from: data)
        #expect(decoded == original)
        // Decodes the seed-file object shape.
        let fromSeedShape = try JSONDecoder().decode(
            WallClockTime.self,
            from: Data(#"{ "hour": 16, "minute": 35 }"#.utf8)
        )
        #expect(fromSeedShape == WallClockTime(hour: 16, minute: 35))
    }
}

@Suite("DayKey")
struct DayKeyTests {

    @Test func codableUsesISODayString() throws {
        let decoded = try JSONDecoder().decode([DayKey].self, from: Data(#"["2026-11-27"]"#.utf8))
        #expect(decoded == [DayKey(year: 2026, month: 11, day: 27)])

        let encoded = try JSONEncoder().encode([DayKey(year: 2026, month: 1, day: 1)])
        #expect(String(decoding: encoded, as: UTF8.self) == #"["2026-01-01"]"#)
    }

    @Test func rejectsMalformedDayStrings() {
        for bad in [#"["2026-1-1"]"#, #"["2026/01/01"]"#, #"["garbage"]"#, #"["2026-13-01"]"#, #"["2026-00-40"]"#] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode([DayKey].self, from: Data(bad.utf8))
            }
        }
    }

    @Test func comparableIsLexicographicOnYMD() {
        #expect(DayKey(year: 2026, month: 12, day: 31) < DayKey(year: 2027, month: 1, day: 1))
        #expect(DayKey(year: 2026, month: 3, day: 8) < DayKey(year: 2026, month: 3, day: 9))
        #expect(DayKey(year: 2026, month: 9, day: 30) < DayKey(year: 2026, month: 10, day: 1))
        let sorted = [
            DayKey(year: 2027, month: 1, day: 1),
            DayKey(year: 2026, month: 12, day: 24),
            DayKey(year: 2026, month: 12, day: 25),
        ].sorted()
        #expect(sorted == [
            DayKey(year: 2026, month: 12, day: 24),
            DayKey(year: 2026, month: 12, day: 25),
            DayKey(year: 2027, month: 1, day: 1),
        ])
    }

    // The same instant is a different calendar day in different market zones —
    // DayKey must follow the calendar it is given, never the device zone.
    @Test func initFromDateUsesCalendarZone() throws {
        // 2026-03-09T03:30:00Z == Mar 8, 23:30 EDT == Mar 9, 12:30 JST.
        let instant = Date(timeIntervalSince1970: 1_773_027_000)

        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        #expect(DayKey(instant, in: newYork) == DayKey(year: 2026, month: 3, day: 8))

        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        #expect(DayKey(instant, in: tokyo) == DayKey(year: 2026, month: 3, day: 9))
    }
}

@Suite("ConventionSettings")
struct ConventionSettingsTests {

    @Test func codableRoundTripsWindowsAndOverrides() throws {
        var conventions = ConventionSettings()
        conventions.killzoneWindows[.london] = (
            open: WallClockTime(hour: 2, minute: 30),
            close: WallClockTime(hour: 5, minute: 15)
        )
        conventions.sessionOverrides[.fxLondon] = [
            TradingSegment(
                kind: .regular,
                open: WallClockTime(hour: 7, minute: 30),
                close: WallClockTime(hour: 16, minute: 30),
                weekdays: [2, 3, 4, 5, 6],
                wrapsMidnight: false
            )
        ]

        let data = try JSONEncoder().encode(conventions)
        let decoded = try JSONDecoder().decode(ConventionSettings.self, from: data)

        #expect(decoded.sessionOverrides.count == 1)
        let segment = try #require(decoded.sessionOverrides[.fxLondon]?.first)
        #expect(segment.kind == .regular)
        #expect(segment.open == WallClockTime(hour: 7, minute: 30))
        #expect(segment.close == WallClockTime(hour: 16, minute: 30))
        #expect(segment.weekdays == [2, 3, 4, 5, 6])
        #expect(!segment.wrapsMidnight)

        #expect(decoded.killzoneWindows.count == 1)
        let window = try #require(decoded.killzoneWindows[.london])
        #expect(window.open == WallClockTime(hour: 2, minute: 30))
        #expect(window.close == WallClockTime(hour: 5, minute: 15))
    }

    @Test func emptyDefaultsRoundTrip() throws {
        let data = try JSONEncoder().encode(ConventionSettings())
        let decoded = try JSONDecoder().decode(ConventionSettings.self, from: data)
        #expect(decoded.sessionOverrides.isEmpty)
        #expect(decoded.killzoneWindows.isEmpty)
    }

    @Test func rejectsUnknownIdentifierKeys() {
        let badMarket = Data(#"{"sessionOverrides":{"fxMars":[]},"killzoneWindows":{}}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ConventionSettings.self, from: badMarket)
        }
        let badKillzone = Data(#"{"sessionOverrides":{},"killzoneWindows":{"midnight":{"open":{"hour":0,"minute":0},"close":{"hour":1,"minute":0}}}}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ConventionSettings.self, from: badKillzone)
        }
    }
}

@Suite("AppSettings")
struct AppSettingsTests {

    @Test func defaultsMatchSpine() {
        let settings = AppSettings()
        #expect(settings.traderLevel == .beginner)
        #expect(settings.enabledMarkets == Set(MarketID.allCases))
        #expect(settings.alertRules.isEmpty)          // Beginner default rules land in M4 (04 §2)
        #expect(settings.econCurrencies == ["USD", "GBP", "EUR", "JPY", "AUD"])
        #expect(settings.briefingTime == WallClockTime(hour: 7, minute: 30))
        #expect(settings.timeDisplayMode == .both)
        #expect(settings.liveActivityEnabled)
        #expect(settings.dismissedExplainerIDs.isEmpty)
        #expect(settings.conventions.sessionOverrides.isEmpty)
        #expect(settings.conventions.killzoneWindows.isEmpty)
    }

    @Test func codableRoundTrip() throws {
        var settings = AppSettings()
        settings.traderLevel = .pro
        settings.enabledMarkets = [.fxLondon, .fxNewYork, .usEquities]
        settings.alertRules = [
            AlertRule(
                target: .market(.fxLondon, .regular),
                moments: [.atOpen, .before(minutes: 15)],
                style: .standard,
                enabled: true
            ),
            AlertRule(
                target: .econ(minImpact: .high),
                moments: [.before(minutes: 30)],
                style: .timeSensitive,
                enabled: false
            ),
        ]
        settings.timeDisplayMode = .market
        settings.dismissedExplainerIDs = ["overlap-explainer"]
        settings.conventions.killzoneWindows[.nyAM] = (
            open: WallClockTime(hour: 7, minute: 0),
            close: WallClockTime(hour: 10, minute: 0)
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.traderLevel == .pro)
        #expect(decoded.enabledMarkets == [.fxLondon, .fxNewYork, .usEquities])
        #expect(decoded.alertRules == settings.alertRules)
        #expect(decoded.econCurrencies == settings.econCurrencies)
        #expect(decoded.briefingTime == WallClockTime(hour: 7, minute: 30))
        #expect(decoded.timeDisplayMode == .market)
        #expect(decoded.liveActivityEnabled)
        #expect(decoded.dismissedExplainerIDs == ["overlap-explainer"])
        let window = try #require(decoded.conventions.killzoneWindows[.nyAM])
        #expect(window.open == WallClockTime(hour: 7, minute: 0))
        #expect(window.close == WallClockTime(hour: 10, minute: 0))
    }
}

@Suite("EconImpact")
struct EconImpactTests {

    @Test func comparableFollowsDeclarationOrder() {
        #expect(EconImpact.low < .medium)
        #expect(EconImpact.medium < .high)
        #expect(EconImpact.high < .holiday)
        #expect(!(EconImpact.high < .high))
        #expect(EconImpact.high >= .medium)
        #expect([EconImpact.high, .low, .medium].sorted() == [.low, .medium, .high])
    }
}
