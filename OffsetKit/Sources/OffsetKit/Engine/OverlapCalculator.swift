//
//  OverlapCalculator.swift
//  OffsetKit
//
//  Structural London–NY overlap per docs/03-SESSION-ENGINE.md §4 step 3 and
//  DECISIONS #2: NEVER hardcoded. Pair each fxNewYork regular occurrence with the
//  fxLondon regular occurrence whose openDate falls on the same America/New_York
//  calendar day; overlap = max(opens) ..< min(closes) when non-empty. Because both
//  endpoints come from materialized instants, the 5-hour DST-mismatch weeks fall
//  out automatically (03 §6.2).
//

import Foundation

nonisolated public struct OverlapCalculator: Sendable {

    public init() {}

    /// Overlap windows for same-NY-day pairs of regular occurrences, sorted by start.
    public func overlaps(london: [SessionOccurrence], newYork: [SessionOccurrence]) -> [DateInterval] {
        guard let zone = TimeZone(identifier: "America/New_York") else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        var londonByDay: [DayKey: SessionOccurrence] = [:]
        for occurrence in london where occurrence.market == .fxLondon && occurrence.kind == .regular {
            let day = DayKey(occurrence.openDate, in: calendar)
            if londonByDay[day] == nil { londonByDay[day] = occurrence }
        }

        var windows: [DateInterval] = []
        for occurrence in newYork where occurrence.market == .fxNewYork && occurrence.kind == .regular {
            let day = DayKey(occurrence.openDate, in: calendar)
            guard let paired = londonByDay[day] else { continue }
            let start = max(paired.openDate, occurrence.openDate)
            let end = min(paired.closeDate, occurrence.closeDate)
            if start < end {
                windows.append(DateInterval(start: start, end: end))
            }
        }
        return windows.sorted { $0.start < $1.start }
    }
}
