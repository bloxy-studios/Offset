//
//  KillzoneResolutionTests.swift
//  OffsetKitTests
//
//  docs/03 §7 T16–T18 — killzones across DST, skipped/duplicated wall-time
//  resolution (research §3 pitfalls 2/3/7).
//

import Foundation
import Testing
import UserNotifications
@testable import OffsetKit

@Suite("Killzones and wall-clock resolution")
struct KillzoneResolutionTests {

    // T16 — london killzone (02:00–05:00 America/New_York) around the US spring-forward:
    // Fri 2026-03-06 == [07:00Z, 10:00Z]; Mon 2026-03-09 == [06:00Z, 09:00Z], which is
    // 06:00–09:00 LONDON wall clock — NY-pinned killzones drift by design (research §5).
    @Test func killzoneAcrossSpringForward() throws {
        let engine = try makeEngine()

        let friday = engine.events(in: utcInterval(1_772_755_200, 1_772_841_600),  // 2026-03-06 UTC day
                                   settings: proSettings(), econEvents: [])
        let fridayStart = try #require(friday.event(withID: "kzStart:london:2026-03-06"))
        let fridayEnd = try #require(friday.event(withID: "kzEnd:london:2026-03-06"))
        #expect(fridayStart.date == epochDate(1_772_780_400))   // 02:00 EST == 07:00Z
        #expect(fridayEnd.date == epochDate(1_772_791_200))     // 05:00 EST == 10:00Z

        let monday = engine.events(in: utcInterval(1_773_014_400, 1_773_100_800),  // 2026-03-09 UTC day
                                   settings: proSettings(), econEvents: [])
        let mondayStart = try #require(monday.event(withID: "kzStart:london:2026-03-09"))
        let mondayEnd = try #require(monday.event(withID: "kzEnd:london:2026-03-09"))
        #expect(mondayStart.date == epochDate(1_773_036_000))   // 02:00 EDT == 06:00Z
        #expect(mondayEnd.date == epochDate(1_773_046_800))     // 05:00 EDT == 09:00Z

        // The Monday window covers 06:00–09:00 Europe/London wall clock.
        let london = try zonedCalendar("Europe/London")
        #expect(london.component(.hour, from: mondayStart.date) == 6)
        #expect(london.component(.hour, from: mondayEnd.date) == 9)
    }

    // T17 — 02:30 does not exist on 2026-03-08 in New York (spring-forward gap):
    // .nextTime resolves forward to 03:00 EDT (guards user-edited killzone edges).
    @Test func skippedWallTimeResolvesForward() throws {
        let newYork = try zonedCalendar("America/New_York")
        let resolved = resolve(DayKey(year: 2026, month: 3, day: 8), WallClockTime(hour: 2, minute: 30), newYork)
        #expect(resolved == epochDate(1_772_953_200))           // 2026-03-08T03:00:00-04:00 == 07:00Z
    }

    // T18 — 01:30 happens twice on 2026-11-01 in New York (fall-back): .first takes the
    // FIRST pass (EDT). Cross-check: UNCalendarNotificationTrigger with the same pinned
    // components must compute the same instant (research §3 pitfall 7).
    @Test func duplicatedWallTimeTakesFirstPass() throws {
        let newYork = try zonedCalendar("America/New_York")
        let resolved = resolve(DayKey(year: 2026, month: 11, day: 1), WallClockTime(hour: 1, minute: 30), newYork)
        #expect(resolved == epochDate(1_793_511_000))           // 2026-11-01T01:30:00-04:00 == 05:30Z

        var components = DateComponents()
        components.timeZone = TimeZone(identifier: "America/New_York")
        components.year = 2026; components.month = 11; components.day = 1
        components.hour = 1; components.minute = 30
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let triggerDate = try #require(trigger.nextTriggerDate())
        #expect(triggerDate == epochDate(1_793_511_000))
    }
}
