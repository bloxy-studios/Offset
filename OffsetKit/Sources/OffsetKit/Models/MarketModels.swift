//
//  MarketModels.swift
//  OffsetKit
//
//  Canonical market model types. Names/signatures per docs/00-SPINE.md §4 — verbatim.
//  All types are nonisolated Sendable values (module default isolation is MainActor;
//  models opt out explicitly per docs/02-ARCHITECTURE.md §2).
//

import Foundation

/// The seven markets in scope. Spine §3/§4.
nonisolated public enum MarketID: String, Codable, CaseIterable, Sendable, Identifiable {
    case fxSydney, fxTokyo, fxLondon, fxNewYork, usEquities, lse, cmeEquity

    public var id: String { rawValue }
}

nonisolated public enum MarketKind: String, Codable, Sendable {
    case forexSession, equityExchange, futures
}

/// Static description of one market (hours live in `TradingSegment`s). Spine §4.
nonisolated public struct Market: Identifiable, Sendable {
    public let id: MarketID
    public let name: String
    public let shortName: String
    public let kind: MarketKind
    public let timeZoneID: String
    public let colorToken: String
    public let symbolName: String

    public init(
        id: MarketID,
        name: String,
        shortName: String,
        kind: MarketKind,
        timeZoneID: String,
        colorToken: String,
        symbolName: String
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.kind = kind
        self.timeZoneID = timeZoneID
        self.colorToken = colorToken
        self.symbolName = symbolName
    }
}

/// A wall-clock time of day — no date, no zone. Spine §4.
/// Materialization into absolute instants is the engine's job (docs/03 §3.1).
nonisolated public struct WallClockTime: Codable, Hashable, Sendable, Comparable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public static func < (lhs: WallClockTime, rhs: WallClockTime) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}

nonisolated public enum SegmentKind: String, Codable, Sendable {
    case preMarket, regular, afterHours, openingAuction, closingAuction, maintenanceBreak
}

/// One recurring trading window, wall-clock in the market's own IANA zone. Spine §4.
/// `weekdays` uses the `Calendar` convention: 1=Sun … 7=Sat.
nonisolated public struct TradingSegment: Codable, Sendable {
    public let kind: SegmentKind
    public let open: WallClockTime
    public let close: WallClockTime
    public let weekdays: Set<Int>
    public let wrapsMidnight: Bool

    public init(
        kind: SegmentKind,
        open: WallClockTime,
        close: WallClockTime,
        weekdays: Set<Int>,
        wrapsMidnight: Bool
    ) {
        self.kind = kind
        self.open = open
        self.close = close
        self.weekdays = weekdays
        self.wrapsMidnight = wrapsMidnight
    }
}

/// A materialized occurrence of a segment: absolute instants. Spine §4.
nonisolated public struct SessionOccurrence: Sendable, Identifiable {
    public let market: MarketID
    public let kind: SegmentKind
    public let openDate: Date
    public let closeDate: Date

    public init(market: MarketID, kind: SegmentKind, openDate: Date, closeDate: Date) {
        self.market = market
        self.kind = kind
        self.openDate = openDate
        self.closeDate = closeDate
    }

    /// Derived identity: a market materializes at most one occurrence of a given
    /// segment kind opening at a given instant.
    public var id: String {
        "\(market.rawValue):\(kind.rawValue):\(openDate.timeIntervalSinceReferenceDate)"
    }
}

nonisolated public enum KillzoneID: String, Codable, CaseIterable, Sendable {
    case asia, london, nyAM, londonClose, nyPM
}
