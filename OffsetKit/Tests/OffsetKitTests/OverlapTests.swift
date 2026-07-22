//
//  OverlapTests.swift
//  OffsetKitTests
//
//  docs/03 §7 T4–T7 — the London–NY overlap across the 2026 DST mismatch windows.
//  Canonical values (spine §8 ruling 2): 4 h in normal weeks, 5 h inside mismatch
//  windows (2026: Mar 8–29, Oct 25–Nov 1) — the engine must reproduce exactly this
//  asymmetry from materialized instants, nothing hardcoded.
//

import Foundation
import Testing
@testable import OffsetKit

@Suite("Overlap across DST mismatch")
struct OverlapDSTTests {

    private func overlapWindow(utcDayStart: Int, dayString: String) throws -> (start: Date, end: Date) {
        let engine = try makeEngine()
        let events = engine.events(
            in: utcInterval(utcDayStart, utcDayStart + 86_400),
            settings: defaultSettings(),
            econEvents: []
        )
        let start = try #require(events.event(withID: "overlapStart:fxLondon-fxNewYork:\(dayString)"))
        let end = try #require(events.event(withID: "overlapEnd:fxLondon-fxNewYork:\(dayString)"))
        #expect(start.kind == .overlapStart)
        #expect(end.kind == .overlapEnd)
        #expect(start.market == nil)
        return (start.date, end.date)
    }

    // T4 — Mon 2026-03-02 (normal week): 08:00–12:00 EST wall clock, 4 h.
    @Test func overlapNormalWeekIs4h() throws {
        let window = try overlapWindow(utcDayStart: 1_772_409_600, dayString: "2026-03-02")
        #expect(window.start == epochDate(1_772_456_400))   // 2026-03-02T08:00-05:00 == 13:00Z
        #expect(window.end == epochDate(1_772_470_800))     // 17:00 GMT == 17:00Z
        #expect(window.end.timeIntervalSince(window.start) == 14_400)
    }

    // T5 — Mon 2026-03-09 (inside the 2026-03-08..29 window): 5 h.
    @Test func overlapSpringMismatchIs5h() throws {
        let window = try overlapWindow(utcDayStart: 1_773_014_400, dayString: "2026-03-09")
        #expect(window.start == epochDate(1_773_057_600))   // 08:00 EDT == 12:00Z
        #expect(window.end == epochDate(1_773_075_600))     // 17:00 GMT == 17:00Z
        #expect(window.end.timeIntervalSince(window.start) == 18_000)
    }

    // T6 — Mon 2026-03-30 (UK on BST since 03-29): back to 4 h.
    @Test func overlapAfterUKCatchUpIs4h() throws {
        let window = try overlapWindow(utcDayStart: 1_774_828_800, dayString: "2026-03-30")
        #expect(window.start == epochDate(1_774_872_000))   // 08:00 EDT == 12:00Z
        #expect(window.end == epochDate(1_774_886_400))     // 17:00 BST == 16:00Z
        #expect(window.end.timeIntervalSince(window.start) == 14_400)
    }

    // T7 — Mon 2026-10-26 (UK fell back 10-25, US still EDT): 5 h; then Mon 2026-11-02: 4 h.
    @Test func overlapAutumnMismatchIs5h() throws {
        let mismatch = try overlapWindow(utcDayStart: 1_792_972_800, dayString: "2026-10-26")
        #expect(mismatch.start == epochDate(1_793_016_000)) // 08:00 EDT == 12:00Z
        #expect(mismatch.end == epochDate(1_793_034_000))   // 17:00 GMT == 17:00Z
        #expect(mismatch.end.timeIntervalSince(mismatch.start) == 18_000)

        let normal = try overlapWindow(utcDayStart: 1_793_577_600, dayString: "2026-11-02")
        #expect(normal.start == epochDate(1_793_624_400))   // 08:00 EST == 13:00Z
        #expect(normal.end == epochDate(1_793_638_800))     // 17:00 GMT == 17:00Z
        #expect(normal.end.timeIntervalSince(normal.start) == 14_400)
    }
}
