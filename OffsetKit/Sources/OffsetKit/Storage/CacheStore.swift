//
//  CacheStore.swift
//  OffsetKit
//
//  SwiftData cache in the App Group container, per 02 §4.2. @MainActor façade
//  (02 §2 isolation table sanctions "actor or @MainActor"; callers await it).
//  @Model classes mirror spine structs and NEVER leak past CacheStore — clients
//  and UI see spine value types only. Single writer: the app process; the widget
//  extension opens read-only by convention (no insert/save calls there).
//

import Foundation
import OSLog
import SwiftData

// MARK: - @Model mirrors (02 §4.2 — internal by design)

@Model
final class CachedHeadline {                       // ↔ Headline (spine §4)
    @Attribute(.unique) var id: String
    var title: String
    var source: String
    var urlString: String
    var publishedAt: Date
    var summary: String?
    var relatedRaw: [String]
    var fetchedAt: Date

    init(id: String, title: String, source: String, urlString: String,
         publishedAt: Date, summary: String?, relatedRaw: [String], fetchedAt: Date) {
        self.id = id
        self.title = title
        self.source = source
        self.urlString = urlString
        self.publishedAt = publishedAt
        self.summary = summary
        self.relatedRaw = relatedRaw
        self.fetchedAt = fetchedAt
    }
}

@Model
final class CachedEconEvent {                      // ↔ EconEvent (spine §4)
    @Attribute(.unique) var id: String
    var title: String
    var currency: String
    var date: Date
    var impactRaw: String
    var forecast: String?
    var previous: String?
    var fetchedAt: Date

    init(id: String, title: String, currency: String, date: Date,
         impactRaw: String, forecast: String?, previous: String?, fetchedAt: Date) {
        self.id = id
        self.title = title
        self.currency = currency
        self.date = date
        self.impactRaw = impactRaw
        self.forecast = forecast
        self.previous = previous
        self.fetchedAt = fetchedAt
    }
}

@Model
final class CachedBriefing {                       // ↔ Briefing (spine §4)
    @Attribute(.unique) var key: String            // "yyyy-MM-dd|<traderLevel>" (06 §6)
    var generatedAt: Date
    var traderLevelRaw: String
    var providerRaw: String
    var headline: String
    var bullets: [String]
    var watchouts: [String]

    init(key: String, generatedAt: Date, traderLevelRaw: String, providerRaw: String,
         headline: String, bullets: [String], watchouts: [String]) {
        self.key = key
        self.generatedAt = generatedAt
        self.traderLevelRaw = traderLevelRaw
        self.providerRaw = providerRaw
        self.headline = headline
        self.bullets = bullets
        self.watchouts = watchouts
    }
}

// MARK: - CacheStore

@MainActor
public final class CacheStore {

    private let container: ModelContainer
    private let context: ModelContext
    private let logger = Logger(subsystem: offsetLogSubsystem, category: "news")

    private init(configuration: ModelConfiguration) throws {
        container = try ModelContainer(
            for: CachedHeadline.self, CachedEconEvent.self, CachedBriefing.self,
            configurations: configuration
        )
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    /// Production store in the App Group container (02 §4.2).
    public static func appGroup() throws -> CacheStore {
        try CacheStore(configuration: ModelConfiguration(
            "OffsetCache",
            groupContainer: .identifier(AppGroup.identifier)
        ))
    }

    /// Ephemeral store for tests and previews.
    public static func inMemory() throws -> CacheStore {
        try CacheStore(configuration: ModelConfiguration(
            "OffsetCacheEphemeral",
            isStoredInMemoryOnly: true
        ))
    }

    // MARK: Headlines

    public func upsertHeadlines(_ headlines: [Headline], fetchedAt: Date) throws {
        for headline in headlines {
            let id = headline.id
            var descriptor = FetchDescriptor<CachedHeadline>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                existing.title = headline.title
                existing.source = headline.source
                existing.urlString = headline.url.absoluteString
                existing.publishedAt = headline.publishedAt
                if let summary = headline.summary { existing.summary = summary }
                existing.relatedRaw = headline.related.map(\.rawValue)
                existing.fetchedAt = fetchedAt
            } else {
                context.insert(CachedHeadline(
                    id: headline.id, title: headline.title, source: headline.source,
                    urlString: headline.url.absoluteString, publishedAt: headline.publishedAt,
                    summary: headline.summary, relatedRaw: headline.related.map(\.rawValue),
                    fetchedAt: fetchedAt
                ))
            }
        }
        try context.save()
    }

    public func headlines() throws -> [Headline] {
        let descriptor = FetchDescriptor<CachedHeadline>(
            sortBy: [SortDescriptor(\.publishedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).compactMap { cached in
            guard let url = URL(string: cached.urlString) else { return nil }
            return Headline(
                id: cached.id, title: cached.title, source: cached.source, url: url,
                publishedAt: cached.publishedAt, summary: cached.summary,
                related: cached.relatedRaw.compactMap(MarketID.init(rawValue:))
            )
        }
    }

    // MARK: Econ events

    public func upsertEconEvents(_ events: [EconEvent], fetchedAt: Date) throws {
        for event in events {
            let id = event.id
            var descriptor = FetchDescriptor<CachedEconEvent>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                existing.title = event.title
                existing.currency = event.currency
                existing.date = event.date
                existing.impactRaw = event.impact.rawValue
                existing.forecast = event.forecast
                existing.previous = event.previous
                existing.fetchedAt = fetchedAt
            } else {
                context.insert(CachedEconEvent(
                    id: event.id, title: event.title, currency: event.currency, date: event.date,
                    impactRaw: event.impact.rawValue, forecast: event.forecast,
                    previous: event.previous, fetchedAt: fetchedAt
                ))
            }
        }
        try context.save()
    }

    public func econEvents() throws -> [EconEvent] {
        let descriptor = FetchDescriptor<CachedEconEvent>(sortBy: [SortDescriptor(\.date)])
        return try context.fetch(descriptor).compactMap { cached in
            guard let impact = EconImpact(rawValue: cached.impactRaw) else { return nil }
            return EconEvent(
                id: cached.id, title: cached.title, currency: cached.currency,
                date: cached.date, impact: impact,
                forecast: cached.forecast, previous: cached.previous
            )
        }
    }

    // MARK: Briefings

    public func saveBriefing(_ briefing: Briefing, key: String) throws {
        var descriptor = FetchDescriptor<CachedBriefing>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            existing.generatedAt = briefing.generatedAt
            existing.traderLevelRaw = briefing.traderLevel.rawValue
            existing.providerRaw = briefing.provider.rawValue
            existing.headline = briefing.headline
            existing.bullets = briefing.bullets
            existing.watchouts = briefing.watchouts
        } else {
            context.insert(CachedBriefing(
                key: key, generatedAt: briefing.generatedAt,
                traderLevelRaw: briefing.traderLevel.rawValue, providerRaw: briefing.provider.rawValue,
                headline: briefing.headline, bullets: briefing.bullets, watchouts: briefing.watchouts
            ))
        }
        try context.save()
    }

    public func briefing(key: String) throws -> Briefing? {
        var descriptor = FetchDescriptor<CachedBriefing>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first.flatMap(Self.briefing(from:))
    }

    public func recentBriefings(limit: Int = 7) throws -> [Briefing] {
        var descriptor = FetchDescriptor<CachedBriefing>(sortBy: [SortDescriptor(\.key, order: .reverse)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).compactMap(Self.briefing(from:))
    }

    private nonisolated static func briefing(from cached: CachedBriefing) -> Briefing? {
        guard let level = TraderLevel(rawValue: cached.traderLevelRaw),
              let provider = SummaryProvider(rawValue: cached.providerRaw) else { return nil }
        return Briefing(
            generatedAt: cached.generatedAt, traderLevel: level, headline: cached.headline,
            bullets: cached.bullets, watchouts: cached.watchouts, provider: provider
        )
    }

    // MARK: Retention (02 §4.2 table; runs on every write pass + NSCalendarDayChanged)

    public func prune(now: Date, calendar: Calendar = .current) throws {
        // Headlines: publishedAt within the last 3 days.
        let headlineCutoff = now.addingTimeInterval(-3 * 86_400)
        try context.delete(model: CachedHeadline.self,
                           where: #Predicate { $0.publishedAt < headlineCutoff })

        // Econ events: keep start of current week through end of next week.
        if let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now),
           let nextWeekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeek.end) {
            let weekStart = currentWeek.start
            try context.delete(model: CachedEconEvent.self,
                               where: #Predicate { $0.date < weekStart || $0.date >= nextWeekEnd })
        }

        // Briefings: last 7 by key date (pull-to-refresh replaces same-day keys).
        let briefings = try context.fetch(
            FetchDescriptor<CachedBriefing>(sortBy: [SortDescriptor(\.key, order: .reverse)])
        )
        for stale in briefings.dropFirst(7) {
            context.delete(stale)
        }
        try context.save()
    }
}
