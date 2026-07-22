//
//  StorageTests.swift
//  OffsetKitTests
//
//  M3 acceptance: settings round-trip + migration stub (02 §4.1 policy),
//  CacheStore round-trips + retention (02 §4.2), KeychainStore basics (02 §6).
//  All stores use injected scratch backends — never the real App Group.
//

import Foundation
import Testing
@testable import OffsetKit

// MARK: - SettingsStore

@Suite("SettingsStore")
struct SettingsStoreTests {

    private func scratchDefaults() throws -> UserDefaults {
        let name = "offset.tests.settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func firstLaunchPersistsDefaults() throws {
        let defaults = try scratchDefaults()
        let store = SettingsStore(defaults: defaults)

        let settings = store.load()
        #expect(settings.traderLevel == .beginner)
        #expect(settings.alertRules.count == 20)                        // 04 §2.1 default set
        #expect(defaults.data(forKey: SettingsStore.envelopeKey) != nil)  // envelope persisted
        #expect(!store.wasReset)

        // Envelope carries the current schema version.
        let data = try #require(defaults.data(forKey: SettingsStore.envelopeKey))
        let envelope = try JSONDecoder().decode(SettingsEnvelope.self, from: data)
        #expect(envelope.schemaVersion == settingsSchemaVersion)
    }

    @Test func roundTripPersistsMutations() throws {
        let defaults = try scratchDefaults()
        var settings = SettingsStore(defaults: defaults).load()

        settings.traderLevel = .pro
        settings.enabledMarkets = [.fxLondon, .usEquities]
        settings.timeDisplayMode = .market
        settings.dismissedExplainerIDs = ["overlap"]
        settings.conventions.killzoneWindows[.asia] = (
            open: WallClockTime(hour: 21, minute: 0), close: WallClockTime(hour: 1, minute: 0)
        )
        SettingsStore(defaults: defaults).save(settings)

        // A separate store instance over the same backend sees the same values.
        let reloaded = SettingsStore(defaults: defaults).load()
        #expect(reloaded.traderLevel == .pro)
        #expect(reloaded.enabledMarkets == [.fxLondon, .usEquities])
        #expect(reloaded.timeDisplayMode == .market)
        #expect(reloaded.dismissedExplainerIDs == ["overlap"])
        let window = try #require(reloaded.conventions.killzoneWindows[.asia])
        #expect(window.open == WallClockTime(hour: 21, minute: 0))
        #expect(window.close == WallClockTime(hour: 1, minute: 0))
    }

    @Test func downgradeQuarantinesAndResets() throws {
        let defaults = try scratchDefaults()
        // A blob from "the future": higher schema version than this build knows.
        let future = SettingsEnvelope(schemaVersion: settingsSchemaVersion + 1, settings: AppSettings())
        let raw = try JSONEncoder().encode(future)
        defaults.set(raw, forKey: SettingsStore.envelopeKey)

        let store = SettingsStore(defaults: defaults)
        let settings = store.load()
        #expect(settings.traderLevel == .beginner)                      // reset to defaults
        #expect(store.wasReset)                                          // quarantine flagged
        #expect(defaults.data(forKey: SettingsStore.quarantineKey) == raw)  // raw blob preserved

        store.clearResetFlag()
        #expect(!store.wasReset)
    }

    @Test func corruptBlobQuarantinesAndResets() throws {
        let defaults = try scratchDefaults()
        defaults.set(Data("not json at all".utf8), forKey: SettingsStore.envelopeKey)

        let store = SettingsStore(defaults: defaults)
        let settings = store.load()
        #expect(settings.enabledMarkets == Set(MarketID.allCases))
        #expect(store.wasReset)

        // The reset envelope is decodable again.
        let healed = try #require(defaults.data(forKey: SettingsStore.envelopeKey))
        #expect((try? JSONDecoder().decode(SettingsEnvelope.self, from: healed)) != nil)
    }

    @Test func migrationChainStub() throws {
        // At the current version the chain is a no-op…
        let blob = Data(#"{"anything":true}"#.utf8)
        #expect(try SettingsStore.migrate(blob, from: settingsSchemaVersion) == blob)
        // …and an unknown older version has no registered step → throws
        // (load() would quarantine; the machinery itself must refuse to guess).
        #expect(throws: (any Error).self) {
            try SettingsStore.migrate(blob, from: 0)
        }
    }
}

// MARK: - CacheStore

@MainActor
@Suite("CacheStore")
struct CacheStoreTests {

    private func utcCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 1
        return calendar
    }

    @Test func headlineRoundTripAndUpsert() throws {
        let store = try CacheStore.inMemory()
        let url = try #require(URL(string: "https://example.com/a"))
        let published = Date(timeIntervalSince1970: 1_784_700_000)

        let original = Headline(id: "h1", title: "Dollar rallies", source: "Test",
                                url: url, publishedAt: published, summary: nil,
                                related: [.fxNewYork, .usEquities])
        try store.upsertHeadlines([original], fetchedAt: published)

        var fetched = try store.headlines()
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == "h1")
        #expect(fetched.first?.related == [.fxNewYork, .usEquities])
        #expect(fetched.first?.summary == nil)

        // Upsert by id: same id with a summary updates in place — no duplicate.
        var updated = original
        updated.summary = "Two-sentence AI summary."
        try store.upsertHeadlines([updated], fetchedAt: published.addingTimeInterval(60))
        fetched = try store.headlines()
        #expect(fetched.count == 1)
        #expect(fetched.first?.summary == "Two-sentence AI summary.")
    }

    @Test func econEventRoundTrip() throws {
        let store = try CacheStore.inMemory()
        let event = EconEvent(id: "ff-2026-07-30-usd-fomc", title: "FOMC Statement",
                              currency: "USD", date: Date(timeIntervalSince1970: 1_785_500_000),
                              impact: .high, forecast: "5.5%", previous: "5.5%")
        try store.upsertEconEvents([event], fetchedAt: .now)

        let fetched = try store.econEvents()
        #expect(fetched.count == 1)
        #expect(fetched.first == event)
    }

    @Test func briefingKeyedStorage() throws {
        let store = try CacheStore.inMemory()
        let briefing = Briefing(generatedAt: Date(timeIntervalSince1970: 1_784_720_000),
                                traderLevel: .beginner, headline: "Quiet Monday ahead",
                                bullets: ["London opens 3 AM", "No high-impact releases"],
                                watchouts: [], provider: .template)
        try store.saveBriefing(briefing, key: "2026-07-22|beginner")

        let fetched = try #require(try store.briefing(key: "2026-07-22|beginner"))
        #expect(fetched.headline == "Quiet Monday ahead")
        #expect(fetched.provider == .template)
        #expect(try store.briefing(key: "2026-07-23|beginner") == nil)

        // Same-key save replaces (pull-to-refresh semantics).
        let regenerated = Briefing(generatedAt: briefing.generatedAt.addingTimeInterval(3600),
                                   traderLevel: .beginner, headline: "Revised look",
                                   bullets: briefing.bullets, watchouts: [], provider: .exa)
        try store.saveBriefing(regenerated, key: "2026-07-22|beginner")
        #expect(try store.recentBriefings().count == 1)
        #expect(try store.briefing(key: "2026-07-22|beginner")?.headline == "Revised look")
    }

    @Test func pruneAppliesRetention() throws {
        let store = try CacheStore.inMemory()
        let calendar = try utcCalendar()
        let now = Date(timeIntervalSince1970: 1_784_721_600)            // 2026-07-22T12:00Z (Wed)
        let url = try #require(URL(string: "https://example.com"))

        // Headlines: 1 day old kept, 4 days old pruned.
        try store.upsertHeadlines([
            Headline(id: "fresh", title: "Fresh", source: "T", url: url,
                     publishedAt: now.addingTimeInterval(-86_400), summary: nil, related: []),
            Headline(id: "stale", title: "Stale", source: "T", url: url,
                     publishedAt: now.addingTimeInterval(-4 * 86_400), summary: nil, related: []),
        ], fetchedAt: now)

        // Econ: current week (Sun 07-19 … Sat 07-25) and next week kept; outside pruned.
        func econ(_ id: String, _ epoch: Int) -> EconEvent {
            EconEvent(id: id, title: id, currency: "USD",
                      date: Date(timeIntervalSince1970: TimeInterval(epoch)),
                      impact: .high, forecast: nil, previous: nil)
        }
        try store.upsertEconEvents([
            econ("thisWeek", 1_784_894_400),    // Fri 2026-07-24 12:00Z
            econ("nextWeek", 1_785_240_000),    // Tue 2026-07-28 12:00Z
            econ("lastWeek", 1_784_376_000),    // Sat 2026-07-18 12:00Z → pruned
            econ("farFuture", 1_785_715_200),   // Mon 2026-08-03 00:00Z → pruned (≥ next week end)
        ], fetchedAt: now)

        // Briefings: 9 daily keys → only the newest 7 survive.
        for day in 14...22 {
            let briefing = Briefing(generatedAt: now, traderLevel: .beginner,
                                    headline: "Day \(day)", bullets: [], watchouts: [],
                                    provider: .template)
            try store.saveBriefing(briefing, key: String(format: "2026-07-%02d|beginner", day))
        }

        try store.prune(now: now, calendar: calendar)

        #expect(try store.headlines().map(\.id) == ["fresh"])
        #expect(Set(try store.econEvents().map(\.id)) == ["thisWeek", "nextWeek"])
        let briefingKeys = try store.recentBriefings(limit: 10)
        #expect(briefingKeys.count == 7)
        #expect(briefingKeys.first?.headline == "Day 22")
        #expect(briefingKeys.last?.headline == "Day 16")
    }
}

// NOTE: KeychainStore tests live in the app-hosted OffsetTests bundle —
// SecItem requires a host app's keychain entitlements; the unhosted SPM test
// runner cannot persist keychain items (verified: SecItemAdd no-ops there).
