//
//  EngineMaterializationTests.swift
//  OffsetKitTests
//
//  docs/03 §7 — T2/T3 (materialization basics), T8–T11 (holidays and half days),
//  T12–T15 (CME Globex wrap). All expected instants are IANA-tzdata-derived epochs.
//

import Foundation
import Testing
@testable import OffsetKit

@Suite("Materialization basics")
struct MaterializationBasicsTests {

    // T2 — Mon 2026-03-02 (UK GMT): fxLondon regular == 2026-03-02T08:00:00+00:00.
    @Test func londonOpenNormalWeek() throws {
        let engine = try makeEngine()
        let occurrences = engine.occurrences(
            in: utcInterval(1_772_409_600, 1_772_496_000),          // 2026-03-02T00:00Z ..< 03-03T00:00Z
            markets: [.fxLondon],
            conventions: ConventionSettings()
        )
        let regular = occurrences.filter { $0.kind == .regular }
        #expect(regular.count == 1)
        #expect(regular.first?.openDate == epochDate(1_772_438_400))   // 08:00 GMT == 03:00 EST
        #expect(regular.first?.closeDate == epochDate(1_772_470_800))  // 17:00 GMT
    }

    // T3 — Mon 2026-03-09 (US on EDT since 03-08, UK still GMT): open still 08:00 GMT,
    // one hour "later" in NY terms than T2 (research §5).
    @Test func londonOpenMismatchWeek() throws {
        let engine = try makeEngine()
        let occurrences = engine.occurrences(
            in: utcInterval(1_773_014_400, 1_773_100_800),          // 2026-03-09T00:00Z ..< 03-10T00:00Z
            markets: [.fxLondon],
            conventions: ConventionSettings()
        )
        let regular = occurrences.filter { $0.kind == .regular }
        #expect(regular.count == 1)
        #expect(regular.first?.openDate == epochDate(1_773_043_200))   // 08:00 GMT == 04:00 EDT
        #expect(regular.first?.closeDate == epochDate(1_773_075_600))  // 17:00 GMT
        // Same instant viewed from New York is 04:00 (device-local projection is formatting only).
        let newYork = try zonedCalendar("America/New_York")
        let localHour = newYork.component(.hour, from: epochDate(1_773_043_200))
        #expect(localHour == 4)
    }
}

@Suite("Holidays and half days")
struct HolidayTests {

    // T8 — Mon 2026-09-07 Labor Day: all usEquities segments dropped; forex unaffected.
    @Test func nyseFullHolidayDrops() throws {
        let engine = try makeEngine()
        let laborDayUTC = utcInterval(1_788_739_200, 1_788_825_600)   // 2026-09-07T00:00Z ..< 09-08T00:00Z

        let us = engine.occurrences(in: laborDayUTC, markets: [.usEquities], conventions: ConventionSettings())
        #expect(us.isEmpty)

        let fxNY = engine.occurrences(in: laborDayUTC, markets: [.fxNewYork], conventions: ConventionSettings())
        #expect(fxNY.count == 1)                                       // forex has no holiday calendar

        let status = engine.marketStatus(at: epochDate(1_788_796_800), // 12:00 EDT
                                         market: .usEquities, conventions: ConventionSettings())
        #expect(status == .holiday(name: "Labor Day", opensAt: epochDate(1_788_874_200))) // Tue 09:30 EDT
    }

    // T9 — Fri 2026-11-27 half day (US back on EST since 11-01): regular 09:30–13:00,
    // afterHours 13:00–17:00, preMarket unchanged 04:00–09:30.
    @Test func nyseHalfDayTruncates() throws {
        let engine = try makeEngine()
        let occurrences = engine.occurrences(
            in: utcInterval(1_795_737_600, 1_795_824_000),            // 2026-11-27T00:00Z ..< 11-28T00:00Z
            markets: [.usEquities],
            conventions: ConventionSettings()
        )
        #expect(occurrences.count == 3)
        let byKind = Dictionary(grouping: occurrences, by: \.kind)

        let preMarket = try #require(byKind[.preMarket]?.first)
        #expect(preMarket.openDate == epochDate(1_795_770_000))       // 04:00 EST
        #expect(preMarket.closeDate == epochDate(1_795_789_800))      // 09:30 EST

        let regular = try #require(byKind[.regular]?.first)
        #expect(regular.openDate == epochDate(1_795_789_800))         // 09:30 EST
        #expect(regular.closeDate == epochDate(1_795_802_400))        // 13:00 EST == 18:00:00Z

        let afterHours = try #require(byKind[.afterHours]?.first)
        #expect(afterHours.openDate == epochDate(1_795_802_400))      // 13:00 EST
        #expect(afterHours.closeDate == epochDate(1_795_816_800))     // 17:00 EST

        let at14EST = engine.marketStatus(at: epochDate(1_795_806_000), market: .usEquities,
                                          conventions: ConventionSettings())
        #expect(at14EST == .afterHours(endsAt: epochDate(1_795_816_800)))

        let at18EST = engine.marketStatus(at: epochDate(1_795_820_400), market: .usEquities,
                                          conventions: ConventionSettings())
        #expect(at18EST == .closed(opensAt: epochDate(1_796_049_000)))  // Mon 11-30 09:30 EST
    }

    // T10 — Thu 2026-12-24 LSE half day: regular ends 12:30, closing auction 12:30–12:35,
    // opening auction unchanged.
    @Test func lseHalfDayTruncates() throws {
        let engine = try makeEngine()
        let occurrences = engine.occurrences(
            in: utcInterval(1_798_070_400, 1_798_156_800),            // 2026-12-24T00:00Z ..< 12-25T00:00Z
            markets: [.lse],
            conventions: ConventionSettings()
        )
        #expect(occurrences.count == 3)
        let byKind = Dictionary(grouping: occurrences, by: \.kind)

        let openingAuction = try #require(byKind[.openingAuction]?.first)
        #expect(openingAuction.openDate == epochDate(1_798_098_600))  // 07:50 GMT
        #expect(openingAuction.closeDate == epochDate(1_798_099_200)) // 08:00 GMT

        let regular = try #require(byKind[.regular]?.first)
        #expect(regular.openDate == epochDate(1_798_099_200))         // 08:00 GMT
        #expect(regular.closeDate == epochDate(1_798_115_400))        // 12:30 GMT

        let closingAuction = try #require(byKind[.closingAuction]?.first)
        #expect(closingAuction.openDate == epochDate(1_798_115_400))  // 12:30 GMT
        #expect(closingAuction.closeDate == epochDate(1_798_115_700)) // 12:35 GMT
    }

    // T11 — 2026-12-25 and 12-28 produce no lse occurrences (Christmas + Boxing Day
    // substitute); status on 12-25 names the holiday and points at 12-29 08:00.
    @Test func lseChristmasRunClosures() throws {
        let engine = try makeEngine()
        let christmas = engine.occurrences(in: utcInterval(1_798_156_800, 1_798_243_200),  // 12-25
                                           markets: [.lse], conventions: ConventionSettings())
        #expect(christmas.isEmpty)
        let boxingSub = engine.occurrences(in: utcInterval(1_798_416_000, 1_798_502_400),  // 12-28
                                           markets: [.lse], conventions: ConventionSettings())
        #expect(boxingSub.isEmpty)

        let status = engine.marketStatus(at: epochDate(1_798_192_800),  // 12-25T10:00Z
                                         market: .lse, conventions: ConventionSettings())
        #expect(status == .holiday(name: "Christmas Day", opensAt: epochDate(1_798_531_200))) // 12-29 08:00 GMT
    }
}

@Suite("CME Globex wrap")
struct CMEWrapTests {

    // T12 — Tue 2026-07-21 (CDT −5): one regular occurrence opening Tue 17:00 CDT,
    // closing Wed 16:00 CDT (23 h); maintenanceBreak Tue 16:00–17:00 CDT separate.
    @Test func cmeOvernightWrapBelongsToOpenDay() throws {
        let engine = try makeEngine()
        let occurrences = engine.occurrences(
            in: utcInterval(1_784_592_000, 1_784_678_400),            // 2026-07-21T00:00Z ..< 07-22T00:00Z
            markets: [.cmeEquity],
            conventions: ConventionSettings()
        )
        let tuesdayOpens = occurrences.filter { $0.kind == .regular && $0.openDate == epochDate(1_784_671_200) }
        #expect(tuesdayOpens.count == 1)
        let session = try #require(tuesdayOpens.first)
        #expect(session.closeDate == epochDate(1_784_754_000))        // Wed 16:00 CDT == 21:00Z
        #expect(session.closeDate.timeIntervalSince(session.openDate) == 82_800)  // 23 h

        let breaks = occurrences.filter { $0.kind == .maintenanceBreak && $0.openDate == epochDate(1_784_667_600) }
        #expect(breaks.count == 1)
        #expect(breaks.first?.closeDate == epochDate(1_784_671_200))  // Tue 16:00–17:00 CDT
    }

    // T13 — Week of 2026-07-20: last session opens Thu 17:00 CDT and closes Fri 16:00 CDT;
    // nothing opens Friday; no Friday maintenance break.
    @Test func cmeFridayCloseAndNoFridayOpen() throws {
        let engine = try makeEngine()
        let occurrences = engine.occurrences(
            in: utcInterval(1_784_505_600, 1_784_937_600),            // 2026-07-20T00:00Z ..< 07-25T00:00Z
            markets: [.cmeEquity],
            conventions: ConventionSettings()
        )
        let thursdaySession = occurrences.filter { $0.kind == .regular && $0.openDate == epochDate(1_784_844_000) }
        #expect(thursdaySession.count == 1)
        #expect(thursdaySession.first?.closeDate == epochDate(1_784_926_800))  // Fri 16:00 CDT

        // No regular occurrence opens Friday 17:00 CDT (== 1784930400).
        #expect(!occurrences.contains { $0.kind == .regular && $0.openDate == epochDate(1_784_930_400) })
        // No maintenance break starting Friday 16:00 CDT (== 1784926800).
        #expect(!occurrences.contains { $0.kind == .maintenanceBreak && $0.openDate == epochDate(1_784_926_800) })
        // Break days this week: Mon–Thu only → 4 breaks.
        #expect(occurrences.count(where: { $0.kind == .maintenanceBreak }) == 4)
    }

    // T14 — Sun 2026-07-26 opens 17:00 CDT, closes Mon 16:00 CDT; Saturday is fully closed.
    @Test func cmeSundayOpen() throws {
        let engine = try makeEngine()
        let sunday = engine.occurrences(
            in: utcInterval(1_785_024_000, 1_785_110_400),            // 2026-07-26T00:00Z ..< 07-27T00:00Z
            markets: [.cmeEquity],
            conventions: ConventionSettings()
        )
        let sundaySession = sunday.filter { $0.kind == .regular && $0.openDate == epochDate(1_785_103_200) }
        #expect(sundaySession.count == 1)
        #expect(sundaySession.first?.closeDate == epochDate(1_785_186_000))    // Mon 16:00 CDT

        let saturday = engine.occurrences(
            in: utcInterval(1_784_937_600, 1_785_024_000),            // 2026-07-25T00:00Z ..< 07-26T00:00Z
            markets: [.cmeEquity],
            conventions: ConventionSettings()
        )
        #expect(saturday.isEmpty)

        let status = engine.marketStatus(at: epochDate(1_784_998_800),  // Sat 12:00 CDT
                                         market: .cmeEquity, conventions: ConventionSettings())
        #expect(status == .closed(opensAt: epochDate(1_785_103_200)))   // Sun 17:00 CDT
    }

    // T15 — Inside the 16:00–17:00 CT break the market is closed (opens 17:00);
    // the break never yields open/close events.
    @Test func cmeMaintenanceBreakIsClosed() throws {
        let engine = try makeEngine()
        let status = engine.marketStatus(at: epochDate(1_784_755_800),  // Wed 2026-07-22 16:30 CDT
                                         market: .cmeEquity, conventions: ConventionSettings())
        #expect(status == .closed(opensAt: epochDate(1_784_757_600)))   // Wed 17:00 CDT

        let events = try makeEngine().events(
            in: utcInterval(1_784_750_400, 1_784_764_800),            // 2026-07-22T19:00Z ..< 23:00Z
            settings: defaultSettings(),
            econEvents: []
        )
        #expect(!events.contains { $0.id.contains("maintenanceBreak") })
    }
}
