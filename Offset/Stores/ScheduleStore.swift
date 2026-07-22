//
//  ScheduleStore.swift
//  Offset
//
//  @MainActor @Observable engine façade (spine §4 app-target observable layer;
//  02 §3 Pipeline A). Owns the loaded AppSettings and the derived schedule state
//  the UI reads. The engine itself is pure — this store injects `now`/zone and
//  re-derives on every refresh signal (03 §6.3 rule 5: never cache materialized
//  instants across zone/DST changes).
//

import Foundation
import Observation
import OffsetKit

@MainActor
@Observable
final class ScheduleStore {

    // MARK: Derived state (read by UI)

    private(set) var todayEvents: [MarketEvent] = []
    private(set) var nextEvent: MarketEvent?
    private(set) var statuses: [MarketID: MarketStatus] = [:]
    private(set) var referenceDate = Date.distantPast

    private(set) var settings: AppSettings

    /// Econ events feeding Pipeline A (populated by NewsStore in M8; empty until then).
    var econEvents: [EconEvent] = []

    let engine: SessionScheduleEngine
    private let settingsStore: SettingsStore

    init(engine: SessionScheduleEngine, settingsStore: SettingsStore = SettingsStore()) {
        self.engine = engine
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
    }

    /// Re-derive everything for `now` in `zone` (device zone by default —
    /// injectable so zone-change behavior is unit-testable).
    func refresh(now: Date = Date(), zone: TimeZone = .current) {
        referenceDate = now

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)

        todayEvents = engine.events(in: DateInterval(start: dayStart, end: dayEnd),
                                    settings: settings, econEvents: econEvents)
        nextEvent = engine.nextEvent(after: now, settings: settings, econEvents: econEvents)
        statuses = Dictionary(uniqueKeysWithValues: settings.enabledMarkets.map { market in
            (market, engine.marketStatus(at: now, market: market, conventions: settings.conventions))
        })
    }

    /// Persist new settings and re-derive (single-writer discipline: 02 §3 table).
    func update(settings newSettings: AppSettings, now: Date = Date(), zone: TimeZone = .current) {
        settings = newSettings
        settingsStore.save(newSettings)
        refresh(now: now, zone: zone)
    }
}
