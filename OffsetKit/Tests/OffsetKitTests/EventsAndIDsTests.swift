//
//  EventsAndIDsTests.swift
//  OffsetKitTests
//
//  docs/03 §7 T19–T22 — stable deterministic ids (03 §4.1 grammar), FX week markers,
//  device-local projection sanity, and the Beginner/Pro killzone gate.
//

import Foundation
import Testing
@testable import OffsetKit

@Suite("Events and ids")
struct EventsAndIDsTests {

    // T19 — events() is deterministic (ids AND order), with exact spot ids.
    @Test func eventIDsAreStableAndDeterministic() throws {
        let engine = try makeEngine()
        let range = utcInterval(1_784_505_600, 1_784_937_600)   // 2026-07-20T00:00Z ..< 07-25T00:00Z
        let settings = defaultSettings()

        let first = engine.events(in: range, settings: settings, econEvents: [])
        let second = engine.events(in: range, settings: settings, econEvents: [])
        #expect(first == second)                                 // element-wise identical, order included

        // Rule UUIDs must not leak into events: a fresh settings value gives identical output.
        let third = engine.events(in: range, settings: defaultSettings(), econEvents: [])
        #expect(first == third)

        let usOpen = try #require(first.event(withID: "open:usEquities:2026-07-22"))
        #expect(usOpen.date == epochDate(1_784_727_000))         // 09:30 EDT
        #expect(usOpen.kind == .open)
        #expect(usOpen.market == .usEquities)

        let usPreMarketOpen = try #require(first.event(withID: "open:usEquities:preMarket:2026-07-22"))
        #expect(usPreMarketOpen.date == epochDate(1_784_707_200))  // 04:00 EDT

        let cmeClose = try #require(first.event(withID: "close:cmeEquity:2026-07-21"))
        #expect(cmeClose.date == epochDate(1_784_754_000))       // fires Wed 2026-07-22T21:00Z, open-day keyed

        let londonLead = try #require(first.event(withID: "preOpen-15:fxLondon:2026-07-22"))
        #expect(londonLead.date == epochDate(1_784_702_700))     // 07:45 BST (default Beginner rule R1)
        #expect(londonLead.kind == .preOpen(leadMinutes: 15))
        #expect(londonLead.market == .fxLondon)
    }

    // T20 — FX week markers, and the Sunday coincidence: weekOpen (17:00 NY) is the SAME
    // instant as fxSydney's Monday open (07:00 AEST) — both events, distinct ids
    // (04's planner merges them; the engine must emit both).
    @Test func fxWeekMarkersAndCoincidence() throws {
        let engine = try makeEngine()
        let events = engine.events(
            in: utcInterval(1_784_505_600, 1_785_110_400),      // 2026-07-20T00:00Z ..< 07-27T00:00Z
            settings: defaultSettings(),
            econEvents: []
        )

        let weekClose = try #require(events.event(withID: "weekClose:fx:2026-07-24"))
        #expect(weekClose.date == epochDate(1_784_926_800))      // Fri 17:00 EDT == 21:00Z
        #expect(weekClose.kind == .weekClose)

        let weekOpen = try #require(events.event(withID: "weekOpen:fx:2026-07-26"))
        #expect(weekOpen.date == epochDate(1_785_099_600))       // Sun 17:00 EDT == 21:00Z

        let sydneyOpen = try #require(events.event(withID: "open:fxSydney:2026-07-27"))
        #expect(sydneyOpen.date == epochDate(1_785_099_600))     // Mon 07:00 AEST — SAME instant
        #expect(weekOpen.id != sydneyOpen.id)
    }

    // T21 — 24 h device-local window (America/New_York), Mon 2026-03-09: the set of
    // regular-segment .open ids is exactly the seven markets, with Sydney/Tokyo carrying
    // TUESDAY day keys while rendering inside device-local Monday.
    @Test func deviceLocalTimelineProjectionSanity() throws {
        let engine = try makeEngine()
        let window = utcInterval(1_773_028_800, 1_773_115_200)  // 2026-03-09T00:00-04:00 ..< 03-10T00:00-04:00
        let events = engine.events(in: window, settings: defaultSettings(), econEvents: [])

        // Regular-segment market opens have 3-field ids: "open:{market}:{day}".
        let regularOpenIDs = Set(events.filter { event in
            event.kind == .open && event.id.components(separatedBy: ":").count == 3
        }.map(\.id))

        #expect(regularOpenIDs == [
            "open:fxSydney:2026-03-10",     // Tue 07:00 AEDT == Mon 16:00 EDT
            "open:fxTokyo:2026-03-10",      // Tue 09:00 JST  == Mon 20:00 EDT
            "open:fxLondon:2026-03-09",     // 08:00 GMT == Mon 04:00 EDT (mismatch week)
            "open:fxNewYork:2026-03-09",    // 08:00 EDT
            "open:usEquities:2026-03-09",   // 09:30 EDT
            "open:lse:2026-03-09",          // 08:00 GMT
            "open:cmeEquity:2026-03-09",    // 17:00 CDT == Mon 18:00 EDT
        ])

        #expect(events.event(withID: "open:fxSydney:2026-03-10")?.date == epochDate(1_773_086_400))
        #expect(events.event(withID: "open:fxTokyo:2026-03-10")?.date == epochDate(1_773_100_800))
        #expect(events.event(withID: "open:cmeEquity:2026-03-09")?.date == epochDate(1_773_093_600))

        // Every returned event lies inside the half-open window.
        #expect(events.allSatisfy { window.start <= $0.date && $0.date < window.end })
    }

    // T22 — Beginner (default settings, killzone rules disabled) sees no killzone events;
    // Pro emits all five per weekday mask.
    @Test func beginnerHidesKillzoneEvents() throws {
        let engine = try makeEngine()
        let window = utcInterval(1_773_028_800, 1_773_115_200)  // same Monday window as T21

        let beginnerEvents = engine.events(in: window, settings: defaultSettings(), econEvents: [])
        #expect(!beginnerEvents.contains { event in
            if case .killzoneStart = event.kind { return true }
            if case .killzoneEnd = event.kind { return true }
            return false
        })

        let proEvents = engine.events(in: window, settings: proSettings(), econEvents: [])
        let mondayKillzoneStarts = Set(proEvents.compactMap { event -> KillzoneID? in
            guard case .killzoneStart(let id) = event.kind, event.id.hasSuffix(":2026-03-09") else { return nil }
            return id
        })
        #expect(mondayKillzoneStarts == Set(KillzoneID.allCases))  // all five emit on a Monday
    }
}
