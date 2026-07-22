//
//  SessionScheduleEngine.swift
//  OffsetKit
//
//  THE core pure engine — deterministic, no side effects, fully unit-tested.
//  Signatures per spine §4 verbatim; algorithms per docs/03-SESSION-ENGINE.md
//  §3 (materialization), §3.1 (DST-safe wall-clock resolution), §3.2 (half days),
//  §4 (event derivation), §4.1 (stable ids), §5 (marketStatus).
//
//  Contract (03 §1): inputs only — the engine never calls Date(), never reads
//  TimeZone.current, no singletons, no I/O. Identical inputs produce byte-identical
//  outputs, including MarketEvent.id strings and array order.
//

import Foundation

// MARK: - Constants (03 PROPOSED ADDITIONS, adopted via spine §8)

/// Day-scan padding so wrapped (CME) and far-east (Sydney) occurrences straddling
/// the range edge are found.
nonisolated let occurrenceScanPadding: TimeInterval = 26 * 60 * 60

/// Bounded forward search for "next open" (mirrors research §3 bounded loop).
nonisolated let statusLookaheadDays = 14

// MARK: - SeedData

/// Immutable decoded bundle content (03 PROPOSED ADDITIONS).
nonisolated public struct SeedData: Sendable {
    public let markets: [MarketRecord]
    public let holidays: HolidayCalendar
    public let killzones: [KillzoneRecord]

    public init(markets: [MarketRecord], holidays: HolidayCalendar, killzones: [KillzoneRecord]) {
        self.markets = markets
        self.holidays = holidays
        self.killzones = killzones
    }
}

// MARK: - Wall-clock resolution (03 §3.1 — the only place a wall time becomes an instant)

/// Resolve `time` on `day` in `cal`'s zone, DST-safe:
/// `.nextTime` maps skipped wall times forward (spring-forward gap);
/// `.first` takes the first pass of duplicated wall times (fall-back hour).
/// 00:00 is the day start exactly (asia killzone close).
nonisolated func resolve(_ day: DayKey, _ time: WallClockTime, _ cal: Calendar) -> Date? {
    guard let dayStart = cal.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) else {
        return nil
    }
    if time.hour == 0 && time.minute == 0 { return dayStart }
    return cal.nextDate(
        after: dayStart,
        matching: DateComponents(hour: time.hour, minute: time.minute),
        matchingPolicy: .nextTime,
        repeatedTimePolicy: .first,
        direction: .forward
    )
}

extension DayKey {
    /// The following calendar day in `cal`'s zone (never +86400 — DST days are 23/25 h).
    nonisolated func next(in cal: Calendar) -> DayKey {
        guard let start = cal.date(from: DateComponents(year: year, month: month, day: day)),
              let following = cal.date(byAdding: .day, value: 1, to: start) else {
            return self
        }
        return DayKey(following, in: cal)
    }

    /// "yyyy-MM-dd" — the event-id day field (03 §4.1) and the Codable form.
    nonisolated var isoDayString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

// MARK: - Half-day mapping (03 §3.2)

/// Effective (open, close) for a segment on a day whose early close is `earlyClose`.
/// Generalized rule (survives Pro sessionOverrides): the regular segment's close
/// becomes E; a segment that starts at the normal regular close (afterHours,
/// closingAuction) shifts to start at E keeping its wall-clock duration; segments
/// ending at or before E are unchanged; an emptied window is suppressed (nil).
nonisolated func effectiveTimes(
    _ segment: TradingSegment,
    earlyClose: WallClockTime?,
    normalRegularClose: WallClockTime?
) -> (open: WallClockTime, close: WallClockTime)? {
    guard let early = earlyClose else { return (segment.open, segment.close) }

    if segment.kind == .regular {
        guard segment.open < early else { return nil }
        return (segment.open, early)
    }
    if let regularClose = normalRegularClose, segment.open == regularClose {
        let durationMinutes = (segment.close.hour * 60 + segment.close.minute)
            - (segment.open.hour * 60 + segment.open.minute)
        let shiftedCloseMinutes = early.hour * 60 + early.minute + durationMinutes
        guard durationMinutes > 0, shiftedCloseMinutes < 24 * 60 else { return nil }
        return (early, WallClockTime(hour: shiftedCloseMinutes / 60, minute: shiftedCloseMinutes % 60))
    }
    return (segment.open, segment.close)
}

// MARK: - SessionScheduleEngine

nonisolated public struct SessionScheduleEngine: Sendable {

    public let seed: SeedData

    public init(seed: SeedData) {
        self.seed = seed
    }

    /// Decode the three bundled seed JSONs (03 §2). Decode failures are programmer
    /// errors — the app fails fast with an OSLog fault at startup.
    public static func loadBundledSeed() throws -> SeedData {
        SeedData(
            markets: try SessionsFile.loadBundled().markets,
            holidays: HolidayCalendar(file: try HolidaysFile.loadBundled()),
            killzones: try KillzonesFile.loadBundled().killzones
        )
    }

    // MARK: Occurrences (03 §3)

    public func occurrences(
        in range: DateInterval,
        markets: Set<MarketID>,
        conventions: ConventionSettings
    ) -> [SessionOccurrence] {
        var result: [SessionOccurrence] = []

        for market in MarketID.allCases where markets.contains(market) {          // fixed iteration order
            guard let record = record(for: market), let calendar = calendar(for: market) else { continue }
            let segments = conventions.sessionOverrides[market] ?? record.segments  // Pro-editable defaults
            let normalRegularClose = segments.first(where: { $0.kind == .regular })?.close

            var day = calendar.startOfDay(for: range.start.addingTimeInterval(-occurrenceScanPadding))
            let scanEnd = range.end.addingTimeInterval(occurrenceScanPadding)

            while day < scanEnd {
                let weekday = calendar.component(.weekday, from: day)              // 1=Sun … 7=Sat
                let dayKey = DayKey(day, in: calendar)

                if seed.holidays.closure(on: dayKey, market: market) == nil {      // full closure drops ALL segments
                    let earlyClose = seed.holidays.earlyClose(on: dayKey, market: market)
                    for segment in segments where segment.weekdays.contains(weekday) {
                        guard
                            let times = effectiveTimes(segment, earlyClose: earlyClose,
                                                       normalRegularClose: normalRegularClose),
                            let openDate = resolve(dayKey, times.open, calendar),
                            let closeDate = resolve(segment.wrapsMidnight ? dayKey.next(in: calendar) : dayKey,
                                                    times.close, calendar),
                            openDate < closeDate,                                   // defensive (custom conventions)
                            openDate < range.end, closeDate > range.start           // intersects (in-progress included)
                        else { continue }
                        result.append(SessionOccurrence(market: market, kind: segment.kind,
                                                        openDate: openDate, closeDate: closeDate))
                    }
                }
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = nextDay                                                       // never +86400 (research §3 pitfall 4)
            }
        }

        return result.sorted { a, b in
            if a.openDate != b.openDate { return a.openDate < b.openDate }
            let marketA = Self.marketOrder[a.market] ?? 0
            let marketB = Self.marketOrder[b.market] ?? 0
            if marketA != marketB { return marketA < marketB }
            return Self.segmentOrder(a.kind) < Self.segmentOrder(b.kind)
        }
    }

    // MARK: Events (03 §4)

    public func events(
        in range: DateInterval,
        settings: AppSettings,
        econEvents: [EconEvent]
    ) -> [MarketEvent] {
        let scan = DateInterval(
            start: range.start.addingTimeInterval(-occurrenceScanPadding),
            end: range.end.addingTimeInterval(occurrenceScanPadding)
        )
        let occurrences = occurrences(in: scan, markets: settings.enabledMarkets,
                                      conventions: settings.conventions)
        var anchors: [Anchor] = []

        // 1. STRUCTURAL open/close — emitted regardless of AlertRules (Today, nextEvent
        //    and the Live Activity need them; rules gate NOTIFICATIONS in 04, not events).
        for occurrence in occurrences where occurrence.kind != .maintenanceBreak {
            guard let record = record(for: occurrence.market),
                  let calendar = calendar(for: occurrence.market) else { continue }
            let dayKey = DayKey(occurrence.openDate, in: calendar)                  // OPEN day keys the id (CME wrap)
            let segmentField = occurrence.kind == .regular ? "" : ":\(occurrence.kind.rawValue)"
            let idBody = "\(occurrence.market.rawValue)\(segmentField):\(dayKey.isoDayString)"
            let subject = Anchor.Subject.market(occurrence.market, occurrence.kind)
            let segmentSuffix = Self.segmentTitleSuffix(occurrence.kind)

            anchors.append(Anchor(
                event: MarketEvent(
                    id: "open:\(idBody)", kind: .open, market: occurrence.market, date: occurrence.openDate,
                    title: "\(record.shortName)\(segmentSuffix) opens",
                    subtitle: Self.wallClockLabel(occurrence.openDate, calendar: calendar, shortName: record.shortName)
                ),
                boundary: .openLike, subject: subject, idBody: idBody
            ))
            anchors.append(Anchor(
                event: MarketEvent(
                    id: "close:\(idBody)", kind: .close, market: occurrence.market, date: occurrence.closeDate,
                    title: "\(record.shortName)\(segmentSuffix) closes",
                    subtitle: Self.wallClockLabel(occurrence.closeDate, calendar: calendar, shortName: record.shortName)
                ),
                boundary: .closeLike, subject: subject, idBody: idBody
            ))
        }

        let newYorkCalendar = Self.newYorkCalendar()

        // 2. FX WEEK MARKERS — Sunday 17:00 / Friday 17:00 America/New_York (spine §3).
        let forexEnabled = seed.markets.contains {
            $0.kind == .forexSession && settings.enabledMarkets.contains($0.id)
        }
        if forexEnabled, let nyCalendar = newYorkCalendar {
            forEachDay(in: scan, calendar: nyCalendar) { dayKey, weekday in
                let time = WallClockTime(hour: 17, minute: 0)
                if weekday == 1, let date = resolve(dayKey, time, nyCalendar) {
                    let idBody = "fx:\(dayKey.isoDayString)"
                    anchors.append(Anchor(
                        event: MarketEvent(id: "weekOpen:\(idBody)", kind: .weekOpen, market: nil, date: date,
                                           title: "FX week opens",
                                           subtitle: Self.wallClockLabel(date, calendar: nyCalendar, shortName: "NYC")),
                        boundary: .openLike, subject: .fxWeek, idBody: idBody
                    ))
                }
                if weekday == 6, let date = resolve(dayKey, time, nyCalendar) {
                    let idBody = "fx:\(dayKey.isoDayString)"
                    anchors.append(Anchor(
                        event: MarketEvent(id: "weekClose:\(idBody)", kind: .weekClose, market: nil, date: date,
                                           title: "FX week closes",
                                           subtitle: Self.wallClockLabel(date, calendar: nyCalendar, shortName: "NYC")),
                        boundary: .closeLike, subject: .fxWeek, idBody: idBody
                    ))
                }
            }
        }

        // 3. OVERLAP — structural, never hardcoded (spine §3, DECISIONS #2).
        if settings.enabledMarkets.contains(.fxLondon), settings.enabledMarkets.contains(.fxNewYork),
           let nyCalendar = newYorkCalendar {
            let windows = OverlapCalculator().overlaps(
                london: occurrences.filter { $0.market == .fxLondon && $0.kind == .regular },
                newYork: occurrences.filter { $0.market == .fxNewYork && $0.kind == .regular }
            )
            for window in windows {
                let dayKey = DayKey(window.start, in: nyCalendar)                   // window's open day in NY
                let idBody = "fxLondon-fxNewYork:\(dayKey.isoDayString)"
                anchors.append(Anchor(
                    event: MarketEvent(id: "overlapStart:\(idBody)", kind: .overlapStart, market: nil,
                                       date: window.start, title: "London–NY overlap begins",
                                       subtitle: Self.wallClockLabel(window.start, calendar: nyCalendar, shortName: "NYC")),
                    boundary: .openLike, subject: .overlap, idBody: idBody
                ))
                anchors.append(Anchor(
                    event: MarketEvent(id: "overlapEnd:\(idBody)", kind: .overlapEnd, market: nil,
                                       date: window.end, title: "London–NY overlap ends",
                                       subtitle: Self.wallClockLabel(window.end, calendar: nyCalendar, shortName: "NYC")),
                    boundary: .closeLike, subject: .overlap, idBody: idBody
                ))
            }
        }

        // 4. KILLZONES — emitted iff Pro OR any enabled AlertRule targets a killzone
        //    (Beginner sees no killzone events anywhere unless they opted into one).
        let killzoneRuleEnabled = settings.alertRules.contains { rule in
            guard rule.enabled, case .killzone = rule.target else { return false }
            return true
        }
        if settings.traderLevel == .pro || killzoneRuleEnabled, let nyCalendar = newYorkCalendar {
            forEachDay(in: scan, calendar: nyCalendar) { dayKey, weekday in
                for record in seed.killzones where record.weekdays.contains(weekday) {
                    let window = settings.conventions.killzoneWindows[record.id] ?? (record.open, record.close)
                    guard let start = resolve(dayKey, window.open, nyCalendar),
                          let end = resolve(record.wrapsMidnight ? dayKey.next(in: nyCalendar) : dayKey,
                                            window.close, nyCalendar),
                          start < end else { continue }
                    let idBody = "\(record.id.rawValue):\(dayKey.isoDayString)"
                    anchors.append(Anchor(
                        event: MarketEvent(id: "kzStart:\(idBody)", kind: .killzoneStart(record.id), market: nil,
                                           date: start, title: "\(record.name) begins",
                                           subtitle: Self.wallClockLabel(start, calendar: nyCalendar, shortName: "NYC")),
                        boundary: .openLike, subject: .killzone(record.id), idBody: idBody
                    ))
                    anchors.append(Anchor(
                        event: MarketEvent(id: "kzEnd:\(idBody)", kind: .killzoneEnd(record.id), market: nil,
                                           date: end, title: "\(record.name) ends",
                                           subtitle: Self.wallClockLabel(end, calendar: nyCalendar, shortName: "NYC")),
                        boundary: .closeLike, subject: .killzone(record.id), idBody: idBody
                    ))
                }
            }
        }

        // 5. ECON — high impact always; lower impacts only when an enabled .econ rule admits them.
        //    ForexFactory "holiday" rows are display-only (03 §4 step 5).
        let econMinimums: [EconImpact] = settings.alertRules.compactMap { rule in
            guard rule.enabled, case .econ(let minImpact) = rule.target else { return nil }
            return minImpact
        }
        for econEvent in econEvents where settings.econCurrencies.contains(econEvent.currency) {
            guard econEvent.impact != .holiday else { continue }
            let admitted = econEvent.impact == .high || econMinimums.contains { econEvent.impact >= $0 }
            guard admitted else { continue }
            let idBody = "econ:\(econEvent.id)"
            anchors.append(Anchor(
                event: MarketEvent(id: idBody, kind: .econRelease(econEvent.id), market: nil,
                                   date: econEvent.date, title: econEvent.title,
                                   subtitle: "\(econEvent.currency) · \(econEvent.impact.rawValue)"),
                boundary: .openLike, subject: .econ(econEvent.impact), idBody: idBody
            ))
        }

        // 6. LEADS — boundary-relative, resolved by the rule's OTHER moments (03 §4 step 6).
        var leadEvents: [MarketEvent] = []
        for rule in settings.alertRules where rule.enabled {
            let leadMinutes = rule.moments.compactMap { moment -> Int? in
                guard case .before(let minutes) = moment else { return nil }
                return minutes
            }.sorted()
            guard !leadMinutes.isEmpty else { continue }
            let opensAnchored = rule.moments.contains(.atOpen) ||
                !(rule.moments.contains(.atOpen) || rule.moments.contains(.atClose))
            let closesAnchored = rule.moments.contains(.atClose)

            for minutes in leadMinutes {
                for anchor in anchors where Self.matches(target: rule.target, anchor: anchor) {
                    let date = anchor.event.date.addingTimeInterval(TimeInterval(-minutes * 60))
                    let title = "\(anchor.event.title) in \(minutes) min"
                    switch anchor.boundary {
                    case .openLike where opensAnchored:
                        leadEvents.append(MarketEvent(
                            id: "preOpen-\(minutes):\(anchor.idBody)", kind: .preOpen(leadMinutes: minutes),
                            market: anchor.event.market, date: date, title: title, subtitle: anchor.event.subtitle))
                    case .closeLike where closesAnchored:
                        leadEvents.append(MarketEvent(
                            id: "preClose-\(minutes):\(anchor.idBody)", kind: .preClose(leadMinutes: minutes),
                            market: anchor.event.market, date: date, title: title, subtitle: anchor.event.subtitle))
                    default:
                        break
                    }
                }
            }
        }

        // 7. FILTER to half-open range (+ id dedupe: two rules can derive the same lead).
        // 8. SORT by (date, kind rank, id) — fully deterministic.
        var seenIDs: Set<String> = []
        return (anchors.map(\.event) + leadEvents)
            .filter { range.start <= $0.date && $0.date < range.end }
            .sorted { a, b in
                if a.date != b.date { return a.date < b.date }
                let rankA = Self.kindRank(a.kind), rankB = Self.kindRank(b.kind)
                if rankA != rankB { return rankA < rankB }
                return a.id < b.id
            }
            .filter { seenIDs.insert($0.id).inserted }
    }

    // MARK: nextEvent (03 §4 end)

    /// First event strictly after `date`, searched over an expanding window
    /// (48 h, then 8 days) so the common case computes one day and a Friday-evening
    /// query still finds Sunday's weekOpen.
    public func nextEvent(after date: Date, settings: AppSettings, econEvents: [EconEvent]) -> MarketEvent? {
        for windowHours in [48.0, 8.0 * 24.0] {
            let window = DateInterval(start: date, end: date.addingTimeInterval(windowHours * 3600))
            if let next = events(in: window, settings: settings, econEvents: econEvents)
                .first(where: { $0.date > date }) {
                return next
            }
        }
        return nil
    }

    // MARK: marketStatus (03 §5)

    public func marketStatus(at date: Date, market: MarketID, conventions: ConventionSettings) -> MarketStatus {
        let scan = DateInterval(
            start: date.addingTimeInterval(-occurrenceScanPadding),
            end: date.addingTimeInterval(TimeInterval(statusLookaheadDays) * 86400)
        )
        let occurrences = occurrences(in: scan, markets: [market], conventions: conventions)
        // Bounded 14-day forward search (research §3 pattern); the fallback is
        // unreachable with shipped data (no market is closed 14 straight days).
        let nextRegularOpen = occurrences.first(where: { $0.kind == .regular && $0.openDate > date })?.openDate
            ?? scan.end

        if let current = occurrences.first(where: { $0.openDate <= date && date < $0.closeDate }) {
            switch current.kind {
            case .regular:
                return .open(closesAt: current.closeDate)
            case .preMarket, .openingAuction:
                return .preMarket(opensAt: nextRegularOpen)
            case .afterHours, .closingAuction:
                return .afterHours(endsAt: current.closeDate)
            case .maintenanceBreak:
                return .closed(opensAt: nextRegularOpen)                            // CME 16:00–17:00 CT
            }
        }

        if let calendar = calendar(for: market) {
            let dayKey = DayKey(date, in: calendar)
            let weekday = calendar.component(.weekday, from: date)
            if let holiday = seed.holidays.closure(on: dayKey, market: market), (2...6).contains(weekday) {
                return .holiday(name: holiday.name, opensAt: nextRegularOpen)
            }
        }
        return .closed(opensAt: nextRegularOpen)
    }

    // MARK: - Internals

    /// Anchor = a step-1–5 event plus the metadata leads need (03 §4 step 6).
    private nonisolated struct Anchor {
        nonisolated enum Boundary { case openLike, closeLike }
        nonisolated enum Subject {
            case market(MarketID, SegmentKind)
            case overlap
            case killzone(KillzoneID)
            case fxWeek
            case econ(EconImpact)
        }
        let event: MarketEvent
        let boundary: Boundary
        let subject: Subject
        let idBody: String                       // event id minus its kind field
    }

    private static func matches(target: AlertTarget, anchor: Anchor) -> Bool {
        switch (target, anchor.subject) {
        case (.market(let id, let segment), .market(let anchorID, let anchorSegment)):
            return id == anchorID && segment == anchorSegment
        case (.overlap, .overlap), (.fxWeek, .fxWeek):
            return true
        case (.killzone(let id), .killzone(let anchorID)):
            return id == anchorID
        case (.econ(let minImpact), .econ(let impact)):
            return impact >= minImpact
        default:
            return false
        }
    }

    private func record(for market: MarketID) -> MarketRecord? {
        seed.markets.first { $0.id == market }
    }

    private func calendar(for market: MarketID) -> Calendar? {
        guard let record = record(for: market), let zone = TimeZone(identifier: record.timeZoneID) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private static func newYorkCalendar() -> Calendar? {
        guard let zone = TimeZone(identifier: "America/New_York") else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// Walk local calendar days covering `interval` (start-of-day stepping, never +86400).
    private func forEachDay(in interval: DateInterval, calendar: Calendar,
                            _ body: (DayKey, Int) -> Void) {
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            body(DayKey(day, in: calendar), calendar.component(.weekday, from: day))
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }
    }

    private static let marketOrder: [MarketID: Int] = Dictionary(
        uniqueKeysWithValues: MarketID.allCases.enumerated().map { ($0.element, $0.offset) }
    )

    private static func segmentOrder(_ kind: SegmentKind) -> Int {
        switch kind {                                                               // declaration order (spine §4)
        case .preMarket: 0
        case .regular: 1
        case .afterHours: 2
        case .openingAuction: 3
        case .closingAuction: 4
        case .maintenanceBreak: 5
        }
    }

    private static func segmentTitleSuffix(_ kind: SegmentKind) -> String {
        switch kind {
        case .regular: ""
        case .preMarket: " pre-market"
        case .afterHours: " after-hours"
        case .openingAuction: " opening auction"
        case .closingAuction: " closing auction"
        case .maintenanceBreak: " maintenance break"
        }
    }

    /// Sort rank per 03 §4 step 8.
    private static func kindRank(_ kind: MarketEventKind) -> Int {
        switch kind {
        case .open: 0
        case .close: 1
        case .preOpen: 2
        case .preClose: 3
        case .overlapStart: 4
        case .overlapEnd: 5
        case .killzoneStart: 6
        case .killzoneEnd: 7
        case .weekOpen: 8
        case .weekClose: 9
        case .econRelease: 10
        }
    }

    /// Market-zone wall-clock label, e.g. "08:00 LDN" — device-local rendering is
    /// pure formatting in the UI layer (03 §4; 07 owns final copy).
    private static func wallClockLabel(_ date: Date, calendar: Calendar, shortName: String) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d %@", components.hour ?? 0, components.minute ?? 0, shortName)
    }
}
