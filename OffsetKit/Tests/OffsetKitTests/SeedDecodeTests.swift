//
//  SeedDecodeTests.swift
//  OffsetKitTests
//
//  M1 acceptance: decode tests for the three bundled seed files (docs/03 §7 T1),
//  plus the Market catalog checks against the spine §3 table.
//

import Foundation
import Testing
@testable import OffsetKit

@Suite("Seed decode")
struct SeedDecodeTests {

    // T1 — sessions.json → 7 MarketRecords in MarketID.allCases order; usEquities has
    // 3 segments, lse 3, cmeEquity 2. holidays.json → usEquities: 10 full + 2 half in
    // 2026; lse: 8 full + 2 half in 2026; cme policy advisoryOnUSHolidays with 0 days;
    // validThrough == 2027-12-31 for all three. killzones.json → 5 records,
    // timeZoneID "America/New_York", asia wrapsMidnight true.
    @Test func decodesAllSeedFiles() throws {
        let sessions = try SessionsFile.loadBundled()
        #expect(sessions.version == 1)
        #expect(sessions.markets.map(\.id) == MarketID.allCases)
        let segmentCounts = Dictionary(uniqueKeysWithValues: sessions.markets.map { ($0.id, $0.segments.count) })
        #expect(segmentCounts[.usEquities] == 3)
        #expect(segmentCounts[.lse] == 3)
        #expect(segmentCounts[.cmeEquity] == 2)
        for fx in [MarketID.fxSydney, .fxTokyo, .fxLondon, .fxNewYork] {
            #expect(segmentCounts[fx] == 1)
        }

        let holidays = try HolidaysFile.loadBundled()
        #expect(holidays.version == 1)
        #expect(holidays.calendars.count == 3)

        let us = try #require(holidays.calendars.first { $0.marketIDs == [.usEquities] })
        #expect(us.policy == .exact)
        #expect(us.validThrough == DayKey(year: 2027, month: 12, day: 31))
        let us2026 = us.days.filter { $0.date.year == 2026 }
        #expect(us2026.count(where: { $0.closure == .full }) == 10)
        #expect(us2026.count(where: { $0.closure == .half }) == 2)

        let lse = try #require(holidays.calendars.first { $0.marketIDs == [.lse] })
        #expect(lse.policy == .exact)
        #expect(lse.validThrough == DayKey(year: 2027, month: 12, day: 31))
        let lse2026 = lse.days.filter { $0.date.year == 2026 }
        #expect(lse2026.count(where: { $0.closure == .full }) == 8)
        #expect(lse2026.count(where: { $0.closure == .half }) == 2)

        let cme = try #require(holidays.calendars.first { $0.marketIDs == [.cmeEquity] })
        #expect(cme.policy == .advisoryOnUSHolidays)
        #expect(cme.validThrough == DayKey(year: 2027, month: 12, day: 31))
        #expect(cme.days.isEmpty)

        let killzones = try KillzonesFile.loadBundled()
        #expect(killzones.version == 1)
        #expect(killzones.timeZoneID == "America/New_York")
        #expect(killzones.killzones.count == 5)
        #expect(killzones.killzones.map(\.id) == KillzoneID.allCases)
        let asia = try #require(killzones.killzones.first { $0.id == .asia })
        #expect(asia.wrapsMidnight)
        #expect(asia.open == WallClockTime(hour: 20, minute: 0))
        #expect(asia.close == WallClockTime(hour: 0, minute: 0))
        #expect(asia.weekdays == [1, 2, 3, 4, 5])
    }

    // M1 acceptance: Market catalog exposes all 7 markets with correct
    // zones/colors/symbols (spine §3 table, verbatim).
    @Test func marketCatalogMatchesSpine() throws {
        let markets = try SessionsFile.loadBundled().markets.map(\.market)
        #expect(markets.count == 7)

        // (id, name, short, kind, zone, colorToken, symbol) — spine §3
        let expected: [(MarketID, String, String, MarketKind, String, String, String)] = [
            (.fxSydney, "Sydney Session", "SYD", .forexSession, "Australia/Sydney", "sydneyAmber", "globe.asia.australia.fill"),
            (.fxTokyo, "Tokyo Session", "TYO", .forexSession, "Asia/Tokyo", "tokyoRose", "sunrise.fill"),
            (.fxLondon, "London Session", "LDN", .forexSession, "Europe/London", "londonBlue", "globe.europe.africa.fill"),
            (.fxNewYork, "New York Session", "NYC", .forexSession, "America/New_York", "newYorkGreen", "globe.americas.fill"),
            (.usEquities, "US Stocks (NYSE·Nasdaq)", "US", .equityExchange, "America/New_York", "usIndigo", "building.columns.fill"),
            (.lse, "London Stock Exchange", "LSE", .equityExchange, "Europe/London", "lseCyan", "building.2.fill"),
            (.cmeEquity, "CME Globex (Futures)", "CME", .futures, "America/Chicago", "cmeOrange", "chart.line.uptrend.xyaxis"),
        ]
        for (market, row) in zip(markets, expected) {
            #expect(market.id == row.0)
            #expect(market.name == row.1)
            #expect(market.shortName == row.2)
            #expect(market.kind == row.3)
            #expect(market.timeZoneID == row.4)
            #expect(market.colorToken == row.5)
            #expect(market.symbolName == row.6)
            // Every zone must resolve as a real IANA identifier on this OS.
            #expect(TimeZone(identifier: market.timeZoneID) != nil, "unresolvable zone \(market.timeZoneID)")
        }
    }

    @Test func segmentHoursMatchSpine() throws {
        let sessions = try SessionsFile.loadBundled()
        let byID = Dictionary(uniqueKeysWithValues: sessions.markets.map { ($0.id, $0) })

        // Forex sessions: local-business-hours convention, Mon–Fri, no wrap.
        let fxHours: [(MarketID, Int, Int)] = [(.fxSydney, 7, 16), (.fxTokyo, 9, 18), (.fxLondon, 8, 17), (.fxNewYork, 8, 17)]
        for (id, openHour, closeHour) in fxHours {
            let segment = try #require(byID[id]?.segments.first)
            #expect(segment.kind == .regular)
            #expect(segment.open == WallClockTime(hour: openHour, minute: 0))
            #expect(segment.close == WallClockTime(hour: closeHour, minute: 0))
            #expect(segment.weekdays == [2, 3, 4, 5, 6])
            #expect(!segment.wrapsMidnight)
        }

        // usEquities: preMarket 04:00–09:30 · regular 09:30–16:00 · afterHours 16:00–20:00.
        let usSegments = try #require(byID[.usEquities]?.segments)
        #expect(usSegments.map(\.kind) == [.preMarket, .regular, .afterHours])
        #expect(usSegments[0].open == WallClockTime(hour: 4, minute: 0))
        #expect(usSegments[0].close == WallClockTime(hour: 9, minute: 30))
        #expect(usSegments[1].open == WallClockTime(hour: 9, minute: 30))
        #expect(usSegments[1].close == WallClockTime(hour: 16, minute: 0))
        #expect(usSegments[2].open == WallClockTime(hour: 16, minute: 0))
        #expect(usSegments[2].close == WallClockTime(hour: 20, minute: 0))
        #expect(usSegments.allSatisfy { !$0.wrapsMidnight && $0.weekdays == [2, 3, 4, 5, 6] })

        // lse: openingAuction 07:50–08:00 · regular 08:00–16:30 · closingAuction 16:30–16:35.
        let lseSegments = try #require(byID[.lse]?.segments)
        #expect(lseSegments.map(\.kind) == [.openingAuction, .regular, .closingAuction])
        #expect(lseSegments[0].open == WallClockTime(hour: 7, minute: 50))
        #expect(lseSegments[0].close == WallClockTime(hour: 8, minute: 0))
        #expect(lseSegments[1].open == WallClockTime(hour: 8, minute: 0))
        #expect(lseSegments[1].close == WallClockTime(hour: 16, minute: 30))
        #expect(lseSegments[2].open == WallClockTime(hour: 16, minute: 30))
        #expect(lseSegments[2].close == WallClockTime(hour: 16, minute: 35))

        // cmeEquity: regular 17:00–16:00 next day (wrapsMidnight, opens Sun–Thu),
        // maintenanceBreak 16:00–17:00 Mon–Thu.
        let cmeSegments = try #require(byID[.cmeEquity]?.segments)
        #expect(cmeSegments.map(\.kind) == [.regular, .maintenanceBreak])
        #expect(cmeSegments[0].open == WallClockTime(hour: 17, minute: 0))
        #expect(cmeSegments[0].close == WallClockTime(hour: 16, minute: 0))
        #expect(cmeSegments[0].weekdays == [1, 2, 3, 4, 5])
        #expect(cmeSegments[0].wrapsMidnight)
        #expect(cmeSegments[1].open == WallClockTime(hour: 16, minute: 0))
        #expect(cmeSegments[1].close == WallClockTime(hour: 17, minute: 0))
        #expect(cmeSegments[1].weekdays == [2, 3, 4, 5])
        #expect(!cmeSegments[1].wrapsMidnight)
    }

    @Test func holidayFixtureSpotChecks() throws {
        let holidays = try HolidaysFile.loadBundled()
        let us = try #require(holidays.calendars.first { $0.marketIDs == [.usEquities] })
        let lse = try #require(holidays.calendars.first { $0.marketIDs == [.lse] })

        // NYSE 2026-09-07 Labor Day: full closure (T8 anchor).
        let laborDay = try #require(us.days.first { $0.date == DayKey(year: 2026, month: 9, day: 7) })
        #expect(laborDay.name == "Labor Day")
        #expect(laborDay.closure == .full)
        #expect(laborDay.earlyClose == nil)

        // NYSE 2026-11-27 half day: early close 13:00 ET (T9 anchor).
        let dayAfterThanksgiving = try #require(us.days.first { $0.date == DayKey(year: 2026, month: 11, day: 27) })
        #expect(dayAfterThanksgiving.closure == .half)
        #expect(dayAfterThanksgiving.earlyClose == WallClockTime(hour: 13, minute: 0))

        // LSE 2026-12-24 half day: early close 12:30 local (T10 anchor).
        let christmasEve = try #require(lse.days.first { $0.date == DayKey(year: 2026, month: 12, day: 24) })
        #expect(christmasEve.closure == .half)
        #expect(christmasEve.earlyClose == WallClockTime(hour: 12, minute: 30))

        // LSE Christmas run: 12-25 and 12-28 both full closures (T11 anchor).
        #expect(lse.days.first { $0.date == DayKey(year: 2026, month: 12, day: 25) }?.closure == .full)
        #expect(lse.days.first { $0.date == DayKey(year: 2026, month: 12, day: 28) }?.closure == .full)

        // Every half day carries an earlyClose; every full day does not.
        for calendar in holidays.calendars {
            for day in calendar.days {
                switch day.closure {
                case .half: #expect(day.earlyClose != nil, "\(day.name) half day missing earlyClose")
                case .full: #expect(day.earlyClose == nil, "\(day.name) full day has earlyClose")
                }
            }
        }
    }

    @Test func killzoneWindowsMatchSpine() throws {
        let killzones = try KillzonesFile.loadBundled().killzones
        let byID = Dictionary(uniqueKeysWithValues: killzones.map { ($0.id, $0) })

        // (id, name, open, close, weekdays, wraps) — spine §3 + 03 §2c.
        let expected: [(KillzoneID, String, WallClockTime, WallClockTime, Set<Int>, Bool)] = [
            (.asia, "Asian Killzone", WallClockTime(hour: 20, minute: 0), WallClockTime(hour: 0, minute: 0), [1, 2, 3, 4, 5], true),
            (.london, "London Killzone", WallClockTime(hour: 2, minute: 0), WallClockTime(hour: 5, minute: 0), [2, 3, 4, 5, 6], false),
            (.nyAM, "NY AM Killzone", WallClockTime(hour: 7, minute: 0), WallClockTime(hour: 10, minute: 0), [2, 3, 4, 5, 6], false),
            (.londonClose, "London Close KZ", WallClockTime(hour: 10, minute: 0), WallClockTime(hour: 12, minute: 0), [2, 3, 4, 5, 6], false),
            (.nyPM, "NY PM Session", WallClockTime(hour: 13, minute: 30), WallClockTime(hour: 16, minute: 0), [2, 3, 4, 5, 6], false),
        ]
        for row in expected {
            let record = try #require(byID[row.0])
            #expect(record.name == row.1)
            #expect(record.open == row.2)
            #expect(record.close == row.3)
            #expect(record.weekdays == row.4)
            #expect(record.wrapsMidnight == row.5)
        }
    }
}
