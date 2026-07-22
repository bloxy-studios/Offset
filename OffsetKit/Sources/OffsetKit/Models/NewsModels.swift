//
//  NewsModels.swift
//  OffsetKit
//
//  News, econ-event and AI briefing model types. Names/signatures per
//  docs/00-SPINE.md §4 — verbatim.
//

import Foundation

nonisolated public enum EconImpact: String, Codable, Comparable, Sendable {
    case low, medium, high, holiday

    // Raw-valued enums are excluded from synthesized Comparable (SE-0266);
    // order is declaration order: low < medium < high < holiday.
    private var comparableRank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .holiday: 3
        }
    }

    public static func < (lhs: EconImpact, rhs: EconImpact) -> Bool {
        lhs.comparableRank < rhs.comparableRank
    }
}

nonisolated public struct EconEvent: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let currency: String
    public let date: Date
    public let impact: EconImpact
    public let forecast: String?
    public let previous: String?

    public init(
        id: String,
        title: String,
        currency: String,
        date: Date,
        impact: EconImpact,
        forecast: String?,
        previous: String?
    ) {
        self.id = id
        self.title = title
        self.currency = currency
        self.date = date
        self.impact = impact
        self.forecast = forecast
        self.previous = previous
    }
}

nonisolated public struct Headline: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let source: String
    public let url: URL
    public let publishedAt: Date
    public var summary: String?
    public let related: [MarketID]

    public init(
        id: String,
        title: String,
        source: String,
        url: URL,
        publishedAt: Date,
        summary: String? = nil,
        related: [MarketID]
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.url = url
        self.publishedAt = publishedAt
        self.summary = summary
        self.related = related
    }
}

nonisolated public enum TraderLevel: String, Codable, Sendable {
    case beginner, pro
}

nonisolated public enum SummaryProvider: String, Codable, Sendable {
    case onDevice, exa, template
}

nonisolated public struct Briefing: Codable, Sendable {
    public let generatedAt: Date
    public let traderLevel: TraderLevel
    public let headline: String                   // one-sentence "what today is about"
    public let bullets: [String]                  // 3–5
    public let watchouts: [String]                // 0–3 (econ releases, unusual hours)
    public let provider: SummaryProvider

    public init(
        generatedAt: Date,
        traderLevel: TraderLevel,
        headline: String,
        bullets: [String],
        watchouts: [String],
        provider: SummaryProvider
    ) {
        self.generatedAt = generatedAt
        self.traderLevel = traderLevel
        self.headline = headline
        self.bullets = bullets
        self.watchouts = watchouts
        self.provider = provider
    }
}
