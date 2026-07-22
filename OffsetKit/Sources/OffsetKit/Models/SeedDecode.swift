//
//  SeedDecode.swift
//  OffsetKit
//
//  Decode layer for the bundled seed JSONs, per docs/03-SESSION-ENGINE.md §2d
//  (PROPOSED ADDITIONS adopted via spine §8). All Sendable value types.
//
//  `SessionScheduleEngine.loadBundledSeed()` (M2) composes these decoders into
//  `SeedData`; until then the internal `loadBundled()` factories are the
//  test-visible decode surface.
//

import Foundation

// MARK: - DayKey

/// A calendar day in a specific market zone. Codable as a `"yyyy-MM-dd"` string.
/// Comparable lexicographic on (year, month, day).
nonisolated public struct DayKey: Codable, Hashable, Comparable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Components of `date` in `calendar`'s zone — never the device zone implicitly.
    public init(_ date: Date, in calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 0, month: components.month ?? 0, day: components.day ?? 0)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected \"yyyy-MM-dd\", got '\(string)'"
            )
        }
        self.init(year: year, month: month, day: day)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "%04d-%02d-%02d", year, month, day))
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

// MARK: - sessions.json

nonisolated public struct SessionsFile: Codable, Sendable {
    public let version: Int
    public let markets: [MarketRecord]

    public init(version: Int, markets: [MarketRecord]) {
        self.version = version
        self.markets = markets
    }
}

nonisolated public struct MarketRecord: Codable, Sendable {
    public let id: MarketID
    public let name: String
    public let shortName: String
    public let kind: MarketKind
    public let timeZoneID: String
    public let colorToken: String
    public let symbolName: String
    public let segments: [TradingSegment]

    public init(
        id: MarketID,
        name: String,
        shortName: String,
        kind: MarketKind,
        timeZoneID: String,
        colorToken: String,
        symbolName: String,
        segments: [TradingSegment]
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.kind = kind
        self.timeZoneID = timeZoneID
        self.colorToken = colorToken
        self.symbolName = symbolName
        self.segments = segments
    }

    /// Projection to the spine §4 `Market`.
    public var market: Market {
        Market(
            id: id, name: name, shortName: shortName, kind: kind,
            timeZoneID: timeZoneID, colorToken: colorToken, symbolName: symbolName
        )
    }
}

// MARK: - holidays.json

nonisolated public struct HolidaysFile: Codable, Sendable {
    public let version: Int
    public let calendars: [HolidayCalendarRecord]

    public init(version: Int, calendars: [HolidayCalendarRecord]) {
        self.version = version
        self.calendars = calendars
    }
}

nonisolated public enum HolidayPolicy: String, Codable, Sendable {
    case exact, advisoryOnUSHolidays
}

nonisolated public enum ClosureKind: String, Codable, Sendable {
    case full, half
}

nonisolated public struct HolidayDay: Codable, Sendable {
    public let date: DayKey
    public let name: String
    public let closure: ClosureKind
    public let earlyClose: WallClockTime?   // present iff closure == .half

    public init(date: DayKey, name: String, closure: ClosureKind, earlyClose: WallClockTime? = nil) {
        self.date = date
        self.name = name
        self.closure = closure
        self.earlyClose = earlyClose
    }
}

nonisolated public struct HolidayCalendarRecord: Codable, Sendable {
    public let marketIDs: [MarketID]
    public let policy: HolidayPolicy
    public let validThrough: DayKey
    public let days: [HolidayDay]

    public init(marketIDs: [MarketID], policy: HolidayPolicy, validThrough: DayKey, days: [HolidayDay]) {
        self.marketIDs = marketIDs
        self.policy = policy
        self.validThrough = validThrough
        self.days = days
    }
}

// MARK: - killzones.json

nonisolated public struct KillzonesFile: Codable, Sendable {
    public let version: Int
    public let timeZoneID: String
    public let killzones: [KillzoneRecord]

    public init(version: Int, timeZoneID: String, killzones: [KillzoneRecord]) {
        self.version = version
        self.timeZoneID = timeZoneID
        self.killzones = killzones
    }
}

nonisolated public struct KillzoneRecord: Codable, Sendable {
    public let id: KillzoneID
    public let name: String
    public let open: WallClockTime
    public let close: WallClockTime
    public let weekdays: Set<Int>
    public let wrapsMidnight: Bool

    public init(
        id: KillzoneID,
        name: String,
        open: WallClockTime,
        close: WallClockTime,
        weekdays: Set<Int>,
        wrapsMidnight: Bool
    ) {
        self.id = id
        self.name = name
        self.open = open
        self.close = close
        self.weekdays = weekdays
        self.wrapsMidnight = wrapsMidnight
    }
}

// MARK: - Bundled decode (internal; composed by SessionScheduleEngine.loadBundledSeed() in M2)

extension SessionsFile {
    /// Decode the bundled `sessions.json` (docs/03 §2a). Decode failures are
    /// programmer errors — bundled data is fixed at build time.
    nonisolated static func loadBundled() throws -> SessionsFile {
        try JSONDecoder().decode(SessionsFile.self, from: seedResourceData(named: "sessions"))
    }
}

extension HolidaysFile {
    /// Decode the bundled `holidays.json` (docs/03 §2b).
    nonisolated static func loadBundled() throws -> HolidaysFile {
        try JSONDecoder().decode(HolidaysFile.self, from: seedResourceData(named: "holidays"))
    }
}

extension KillzonesFile {
    /// Decode the bundled `killzones.json` (docs/03 §2c).
    nonisolated static func loadBundled() throws -> KillzonesFile {
        try JSONDecoder().decode(KillzonesFile.self, from: seedResourceData(named: "killzones"))
    }
}

/// Read one seed JSON from the package resource bundle.
nonisolated func seedResourceData(named name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).json"])
    }
    return try Data(contentsOf: url)
}
