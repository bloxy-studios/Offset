//
//  EventModels.swift
//  OffsetKit
//
//  Market event and status types. Names/signatures per docs/00-SPINE.md §4 — verbatim.
//

import Foundation

nonisolated public enum MarketEventKind: Hashable, Sendable {
    case open, close
    case preOpen(leadMinutes: Int), preClose(leadMinutes: Int)
    case overlapStart, overlapEnd
    case killzoneStart(KillzoneID), killzoneEnd(KillzoneID)
    case weekOpen, weekClose
    case econRelease(String)                      // EconEvent.id
}

/// A single dated event on the schedule. `id` is stable and deterministic per the
/// grammar in docs/03-SESSION-ENGINE.md §4.1 (owned by the engine, M2).
nonisolated public struct MarketEvent: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: MarketEventKind
    public let market: MarketID?                  // nil for overlap/killzone/econ
    public let date: Date
    public let title: String                      // "London opens"
    public let subtitle: String                   // "08:00 London · 3:00 AM your time"

    public init(
        id: String,
        kind: MarketEventKind,
        market: MarketID?,
        date: Date,
        title: String,
        subtitle: String
    ) {
        self.id = id
        self.kind = kind
        self.market = market
        self.date = date
        self.title = title
        self.subtitle = subtitle
    }
}

nonisolated public enum MarketStatus: Sendable, Equatable {
    case open(closesAt: Date)
    case closed(opensAt: Date)
    case preMarket(opensAt: Date)
    case afterHours(endsAt: Date)
    case holiday(name: String, opensAt: Date)
}
