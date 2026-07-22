//
//  ScheduleStoreTests.swift
//  OffsetTests
//
//  M3 acceptance: zone-change simulation recomputes the schedule (unit-level).
//  App-hosted tests over the @MainActor stores; all state injected (scratch
//  UserDefaults suites, fixed instants, explicit zones).
//

import Foundation
import OffsetKit
import Testing
@testable import Offset

@MainActor
@Suite("ScheduleStore")
struct ScheduleStoreTests {

    private func makeStore() throws -> ScheduleStore {
        let suiteName = "offset.tests.schedulestore.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let engine = SessionScheduleEngine(seed: try SessionScheduleEngine.loadBundledSeed())
        return ScheduleStore(engine: engine, settingsStore: SettingsStore(defaults: defaults))
    }

    // Same instant, different device zone ⇒ different "today" window ⇒ the
    // derived schedule recomputes (03 §6.3 rule 5 at the store level).
    @Test func zoneChangeRecomputesSchedule() throws {
        let store = try makeStore()
        // 2026-03-09T15:00Z — Mon 11:00 in New York, already Tue 00:00 in Tokyo.
        let now = Date(timeIntervalSince1970: 1_773_068_400)
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))

        store.refresh(now: now, zone: newYork)
        let newYorkIDs = Set(store.todayEvents.map(\.id))
        #expect(!newYorkIDs.isEmpty)
        #expect(store.referenceDate == now)
        #expect(store.nextEvent != nil)
        #expect(store.statuses.count == store.settings.enabledMarkets.count)

        store.refresh(now: now, zone: tokyo)
        let tokyoIDs = Set(store.todayEvents.map(\.id))
        #expect(!tokyoIDs.isEmpty)
        #expect(newYorkIDs != tokyoIDs)

        // NY's Monday window holds the Mar 9 London open (08:00Z ≥ 04:00Z);
        // Tokyo's "today" started 15:00Z, so it must hold Mar 10's instead.
        #expect(newYorkIDs.contains("open:fxLondon:2026-03-09"))
        #expect(!tokyoIDs.contains("open:fxLondon:2026-03-09"))
        #expect(tokyoIDs.contains("open:fxLondon:2026-03-10"))
    }

    @Test func settingsUpdatePersistsAndRefreshes() throws {
        let suiteName = "offset.tests.schedulestore.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let engine = SessionScheduleEngine(seed: try SessionScheduleEngine.loadBundledSeed())
        let store = ScheduleStore(engine: engine, settingsStore: SettingsStore(defaults: defaults))

        let now = Date(timeIntervalSince1970: 1_773_068_400)
        var updated = store.settings
        updated.traderLevel = .pro
        updated.enabledMarkets = [.fxLondon, .fxNewYork]
        store.update(settings: updated, now: now,
                     zone: try #require(TimeZone(identifier: "America/New_York")))

        #expect(store.settings.traderLevel == .pro)
        #expect(store.statuses.keys.count == 2)                    // only enabled markets
        #expect(store.todayEvents.contains { $0.id.hasPrefix("kzStart:") })  // Pro emits killzones

        // Persisted: a fresh store over the same defaults loads the update.
        let reloaded = SettingsStore(defaults: defaults).load()
        #expect(reloaded.traderLevel == .pro)
        #expect(reloaded.enabledMarkets == [.fxLondon, .fxNewYork])
    }
}

@MainActor
@Suite("RefreshCoordinator")
struct RefreshCoordinatorTests {

    @Test func timeZoneChangeSignalRecomputes() throws {
        let suiteName = "offset.tests.refresh.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let engine = SessionScheduleEngine(seed: try SessionScheduleEngine.loadBundledSeed())
        let store = ScheduleStore(engine: engine, settingsStore: SettingsStore(defaults: defaults))
        let coordinator = RefreshCoordinator(scheduleStore: store)

        #expect(store.referenceDate == .distantPast)
        let now = Date(timeIntervalSince1970: 1_773_068_400)
        coordinator.handleTimeZoneChange(now: now)

        #expect(store.referenceDate == now)                        // schedule recomputed
        #expect(!store.todayEvents.isEmpty)
        #expect(coordinator.lastRefresh == now)
    }

    @Test func significantTimeChangeAndDayChangeRecompute() throws {
        let suiteName = "offset.tests.refresh.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let engine = SessionScheduleEngine(seed: try SessionScheduleEngine.loadBundledSeed())
        let store = ScheduleStore(engine: engine, settingsStore: SettingsStore(defaults: defaults))
        let coordinator = RefreshCoordinator(scheduleStore: store)
        let zone = try #require(TimeZone(identifier: "America/New_York"))

        let monday = Date(timeIntervalSince1970: 1_773_068_400)
        coordinator.handleSignificantTimeChange(now: monday, zone: zone)
        let mondayCount = store.todayEvents.count
        #expect(mondayCount > 0)

        let tuesday = Date(timeIntervalSince1970: 1_773_068_400 + 86_400)
        coordinator.handleDayChange(now: tuesday, zone: zone)
        #expect(store.referenceDate == tuesday)                    // horizon rolled
    }
}
