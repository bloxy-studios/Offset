//
//  HolidayCalendar.swift
//  OffsetKit
//
//  Holiday lookup built from the bundled holidays.json. Type name per spine §2;
//  API per docs/03-SESSION-ENGINE.md PROPOSED ADDITIONS (adopted via spine §8):
//  closure(on:market:) — full closures only · earlyClose(on:market:) — half days ·
//  advisory(on:market:) — CME advisoryOnUSHolidays policy · validThrough(market:).
//

import Foundation

nonisolated public struct HolidayCalendar: Sendable {

    private struct MarketCalendar: Sendable {
        let policy: HolidayPolicy
        let validThrough: DayKey
        let byDay: [DayKey: HolidayDay]
    }

    private let calendars: [MarketID: MarketCalendar]
    /// Every usEquities closure or half day — drives the advisory policy (03 §2b).
    private let usHolidayDays: Set<DayKey>

    public init(file: HolidaysFile) {
        var calendars: [MarketID: MarketCalendar] = [:]
        var usDays: Set<DayKey> = []
        for record in file.calendars {
            var byDay: [DayKey: HolidayDay] = [:]
            byDay.reserveCapacity(record.days.count)
            for day in record.days where byDay[day.date] == nil {
                byDay[day.date] = day
            }
            let calendar = MarketCalendar(policy: record.policy, validThrough: record.validThrough, byDay: byDay)
            for market in record.marketIDs {
                calendars[market] = calendar
            }
            if record.marketIDs.contains(.usEquities) {
                usDays.formUnion(byDay.keys)
            }
        }
        self.calendars = calendars
        self.usHolidayDays = usDays
    }

    /// The full-closure record for `day`, or nil (half days do NOT close the market).
    public func closure(on day: DayKey, market: MarketID) -> HolidayDay? {
        guard let holiday = calendars[market]?.byDay[day], holiday.closure == .full else { return nil }
        return holiday
    }

    /// The early-close wall time when `day` is a half day for `market`, else nil.
    public func earlyClose(on day: DayKey, market: MarketID) -> WallClockTime? {
        guard let holiday = calendars[market]?.byDay[day], holiday.closure == .half else { return nil }
        return holiday.earlyClose
    }

    /// True when `market` follows `advisoryOnUSHolidays` and `day` is a usEquities
    /// closure or half day — the UI shows "US holiday — hours may differ" (03 §2b).
    public func advisory(on day: DayKey, market: MarketID) -> Bool {
        guard calendars[market]?.policy == .advisoryOnUSHolidays else { return false }
        return usHolidayDays.contains(day)
    }

    /// Last day the bundled data covers for `market`; nil when the market has no
    /// holiday calendar (forex — research §1/§5: FX has no holiday calendar in v1).
    public func validThrough(market: MarketID) -> DayKey? {
        calendars[market]?.validThrough
    }
}
