# 03 — SESSION ENGINE: Data, Materialization, DST, Tests

Authoritative spec for `OffsetKit/Sources/OffsetKit/Engine/` (`SessionScheduleEngine`, `OverlapCalculator`, `HolidayCalendar`) and `OffsetKit/Sources/OffsetKit/Resources/` seed JSON. Uses spine §3/§4 vocabulary verbatim. All market hours, holiday dates, and DST dates in this doc come from `research/market-sessions-and-notifications.md` (cited by section as "research §n"). Anything not in that file is explicitly marked UNVERIFIED.

## PROPOSED ADDITIONS

New vocabulary introduced by this doc (spine §7 rule 1). Everything else is spine-verbatim.

| Name | Kind | Purpose |
|---|---|---|
| `DayKey` | struct | A calendar day in a specific market zone: `{ year, month, day }`. Codable as `"yyyy-MM-dd"` string. Hashable, Comparable, Sendable |
| `SeedData` | struct | Immutable decoded bundle content: `markets: [MarketRecord]`, `holidays: HolidayCalendar`, `killzones: [KillzoneRecord]` |
| `SessionsFile`, `MarketRecord` | Codable structs | Decode `sessions.json` |
| `HolidaysFile`, `HolidayCalendarRecord`, `HolidayDay`, `ClosureKind`, `HolidayPolicy` | Codable structs/enums | Decode `holidays.json` |
| `KillzonesFile`, `KillzoneRecord` | Codable structs | Decode `killzones.json` |
| `occurrenceScanPadding` | constant, 26 h | Day-scan padding so wrapped (CME) and far-east (Sydney UTC+11) occurrences straddling the range edge are found |
| `statusLookaheadDays` | constant, 14 | Bounded forward search for "next open" (mirrors research §3 bounded loop) |
| `perDayCap`-related planner names | — | live in 04 doc, not here |
| Interpretation note | — | `MarketEventKind.preOpen/.preClose` are reused as the lead-event kinds for non-market targets (overlap, killzone, fxWeek, econ), with `market == nil`. Not new vocabulary — a documented interpretation of spine §4 |
| `HolidayCalendar` API | methods | `closure(on:market:) -> HolidayDay?`, `earlyClose(on:market:) -> WallClockTime?`, `advisory(on:market:) -> Bool`, `validThrough(market:) -> DayKey?` (type name is spine §2; method names defined here) |

---

## 1. Overview

`SessionScheduleEngine` is a **pure, deterministic, `Sendable` value type** in OffsetKit:

```swift
struct SessionScheduleEngine: Sendable {
    let seed: SeedData                       // immutable, injected
    init(seed: SeedData)
    static func loadBundledSeed() throws -> SeedData   // Bundle.module JSON decode; app calls once at startup
}
```

Contract:

- **Inputs only**: `(range, markets, conventions)` / `(range, settings, econEvents)` / `(date, …)`. The current time is always a parameter — the engine never calls `Date()`, never reads `TimeZone.current`, never touches UserDefaults, network, or SwiftData. No singletons; `loadBundledSeed()` is a factory, and tests inject fixture `SeedData` directly.
- **Deterministic**: identical inputs (including seed) produce byte-identical outputs, including `MarketEvent.id` strings and array order — guaranteed by fixed sort keys (§3 step 6, §4 step 8) and by computing day keys in each market's own zone, never the device zone.
- **Golden rule** (research §0, §5): every session is wall-clock in its market's IANA zone, materialized per-occurrence via a `Calendar` whose `timeZone` is that zone. No fixed UTC offsets anywhere in OffsetKit. Output `Date` values are absolute instants; device-local rendering is pure formatting in the UI layer (research §3).
- Concurrency: all engine types are `Sendable` value types with synchronous pure methods — callable from any executor under Approachable Concurrency (module details in 02 doc).
- Forex markets have **no holiday calendar** (research §5 engine sketch: `holidayCalendarID … nil for forex`; research §1: FX is fully closed only on weekends "plus, in practice, Christmas Day and New Year's Day"). v1 models FX as weekday-only; Christmas/New Year FX thinning is display copy only, not engine data.

Beginner/Pro: the engine itself is level-blind except for one gate — killzone events are emitted only for Pro or when a killzone `AlertRule` is enabled (§4 step 5). All other Beginner/Pro differences live in UI (07) and default rules (04).

---

## 2. Seed data files

Three JSON resources in `OffsetKit/Sources/OffsetKit/Resources/`, decoded once at startup with a plain `JSONDecoder` (no date strategies needed — all dates are `"yyyy-MM-dd"` strings, all times are `WallClockTime` objects). `weekdays` uses the `Calendar` convention **1=Sun … 7=Sat** (spine §4 `TradingSegment`).

### 2a. sessions.json

Hours are spine §3 verbatim; underlying verification: forex research §1 (BabyPips local-business-hours convention, VERIFIED archive), NYSE/Nasdaq research §3 (VERIFIED), LSE research §3 (VERIFIED, Millennium Exchange parameters v9.9), CME research §4 (VERIFIED archive for the Sun 17:00 → Fri 16:00 CT + 16:00–17:00 CT Mon–Thu break pattern).

```json
{
  "version": 1,
  "markets": [
    {
      "id": "fxSydney", "name": "Sydney Session", "shortName": "SYD",
      "kind": "forexSession", "timeZoneID": "Australia/Sydney",
      "colorToken": "sydneyAmber", "symbolName": "globe.asia.australia.fill",
      "segments": [
        { "kind": "regular", "open": { "hour": 7, "minute": 0 }, "close": { "hour": 16, "minute": 0 },
          "weekdays": [2, 3, 4, 5, 6], "wrapsMidnight": false }
      ]
    },
    {
      "id": "fxTokyo", "name": "Tokyo Session", "shortName": "TYO",
      "kind": "forexSession", "timeZoneID": "Asia/Tokyo",
      "colorToken": "tokyoRose", "symbolName": "sunrise.fill",
      "segments": [
        { "kind": "regular", "open": { "hour": 9, "minute": 0 }, "close": { "hour": 18, "minute": 0 },
          "weekdays": [2, 3, 4, 5, 6], "wrapsMidnight": false }
      ]
    },
    {
      "id": "fxLondon", "name": "London Session", "shortName": "LDN",
      "kind": "forexSession", "timeZoneID": "Europe/London",
      "colorToken": "londonBlue", "symbolName": "globe.europe.africa.fill",
      "segments": [
        { "kind": "regular", "open": { "hour": 8, "minute": 0 }, "close": { "hour": 17, "minute": 0 },
          "weekdays": [2, 3, 4, 5, 6], "wrapsMidnight": false }
      ]
    },
    {
      "id": "fxNewYork", "name": "New York Session", "shortName": "NYC",
      "kind": "forexSession", "timeZoneID": "America/New_York",
      "colorToken": "newYorkGreen", "symbolName": "globe.americas.fill",
      "segments": [
        { "kind": "regular", "open": { "hour": 8, "minute": 0 }, "close": { "hour": 17, "minute": 0 },
          "weekdays": [2, 3, 4, 5, 6], "wrapsMidnight": false }
      ]
    },
    {
      "id": "usEquities", "name": "US Stocks (NYSE·Nasdaq)", "shortName": "US",
      "kind": "equityExchange", "timeZoneID": "America/New_York",
      "colorToken": "usIndigo", "symbolName": "building.columns.fill",
      "segments": [
        { "kind": "preMarket", "open": { "hour": 4, "minute": 0 }, "close": { "hour": 9, "minute": 30 },
          "weekdays": [2, 3, 4, 5, 6], "wrapsMidnight": false },
        { "kind": "regular", "open": { "hour": 9, "minute": 30 }, "close": { "hour": 16, "minute": 0 },
          "weekdays": [2, 3, 4, 5, 6], "wrapsMidnight": false },
        { "kind": "afterHours", "open": { "hour": 16, "minute": 0 }, "close": { "hour": 20, "minute": 0 },
          "weekdays": [2, 3, 4, 5, 6], "wrapsMidnight": false }
      ]
    },
    {
      "id": "lse", "name": "London Stock Exchange", "shortName": "LSE",
      "kind": "equityExchange", "timeZoneID": "Europe/London",
      "colorToken": "lseCyan", "symbolName": "building.2.fill",
      "segments": [
        { "kind": "openingAuction", "open": { "hour": 7, "minute": 50 }, "close": { "hour": 8, "minute": 0 },
          "weekdays": [2, 3, 4, 5, 6], "wrapsMidnight": false },
        { "kind": "regular", "open": { "hour": 8, "minute": 0 }, "close": { "hour": 16, "minute": 30 },
          "weekdays": [2, 3, 4, 5, 6], "wrapsMidnight": false },
        { "kind": "closingAuction", "open": { "hour": 16, "minute": 30 }, "close": { "hour": 16, "minute": 35 },
          "weekdays": [2, 3, 4, 5, 6], "wrapsMidnight": false }
      ]
    },
    {
      "id": "cmeEquity", "name": "CME Globex (Futures)", "shortName": "CME",
      "kind": "futures", "timeZoneID": "America/Chicago",
      "colorToken": "cmeOrange", "symbolName": "chart.line.uptrend.xyaxis",
      "segments": [
        { "kind": "regular", "open": { "hour": 17, "minute": 0 }, "close": { "hour": 16, "minute": 0 },
          "weekdays": [1, 2, 3, 4, 5], "wrapsMidnight": true },
        { "kind": "maintenanceBreak", "open": { "hour": 16, "minute": 0 }, "close": { "hour": 17, "minute": 0 },
          "weekdays": [2, 3, 4, 5], "wrapsMidnight": false }
      ]
    }
  ]
}
```

**CME wrapsMidnight modelling.** A `regular` occurrence *belongs to its open day*: `weekdays [1…5]` means sessions open Sun–Thu at 17:00 CT and each closes 16:00 CT the **next** day (`wrapsMidnight: true`). This encodes all three CME special cases structurally, with zero special-case code: Sunday 17:00 open (weekday 1 in the set), Friday 16:00 close (the Thursday-open occurrence's close), and *no* Friday-evening session (weekday 6 absent). The `maintenanceBreak` runs Mon–Thu 16:00–17:00 CT (weekdays [2…5]) between consecutive daily sessions (research §4). The 15:15–15:30 CT equity-halt is **omitted in v1** (DECISIONS: unverified vs official source; research §4 flags it UNVERIFIED — cmegroup.com blocks automation).

Note: `colorToken` values are the spine §3 tokens without the leading dot (`.sydneyAmber` in Swift ⇔ `"sydneyAmber"` in data); hex values live in `DesignSystem/OffsetTheme.swift`.

### 2b. holidays.json

All dates below are VERIFIED in research §3 (NYSE 2026/2027 from nyse.com + nasdaqtrader.com; LSE 2026/2027 from londonstockexchange.com + gov.uk, with Jan–May 2026 rows "VERIFIED-by-rule"). Half-day early closes: NYSE 13:00 ET, LSE 12:30 local (research §3; DECISIONS micro-decision). The exchanges have published partial 2028 data (NYSE incl. Mon Jul 3, 2028 half-day; LSE incl. Mon Jan 3, 2028 closure — research §3), but full 2028 calendars were **not captured in the research pass**, so v1 ships 2026–2027 with `validThrough: "2027-12-31"`; the app shows the "holiday data expiring" nudge within 60 days of `validThrough` (research §6 recommended pattern).

```json
{
  "version": 1,
  "calendars": [
    {
      "marketIDs": ["usEquities"],
      "policy": "exact",
      "validThrough": "2027-12-31",
      "days": [
        { "date": "2026-01-01", "name": "New Year's Day", "closure": "full" },
        { "date": "2026-01-19", "name": "Martin Luther King, Jr. Day", "closure": "full" },
        { "date": "2026-02-16", "name": "Washington's Birthday", "closure": "full" },
        { "date": "2026-04-03", "name": "Good Friday", "closure": "full" },
        { "date": "2026-05-25", "name": "Memorial Day", "closure": "full" },
        { "date": "2026-06-19", "name": "Juneteenth National Independence Day", "closure": "full" },
        { "date": "2026-07-03", "name": "Independence Day (observed)", "closure": "full" },
        { "date": "2026-09-07", "name": "Labor Day", "closure": "full" },
        { "date": "2026-11-26", "name": "Thanksgiving Day", "closure": "full" },
        { "date": "2026-11-27", "name": "Day after Thanksgiving", "closure": "half", "earlyClose": { "hour": 13, "minute": 0 } },
        { "date": "2026-12-24", "name": "Christmas Eve", "closure": "half", "earlyClose": { "hour": 13, "minute": 0 } },
        { "date": "2026-12-25", "name": "Christmas Day", "closure": "full" },
        { "date": "2027-01-01", "name": "New Year's Day", "closure": "full" },
        { "date": "2027-01-18", "name": "Martin Luther King, Jr. Day", "closure": "full" },
        { "date": "2027-02-15", "name": "Washington's Birthday", "closure": "full" },
        { "date": "2027-03-26", "name": "Good Friday", "closure": "full" },
        { "date": "2027-05-31", "name": "Memorial Day", "closure": "full" },
        { "date": "2027-06-18", "name": "Juneteenth (observed)", "closure": "full" },
        { "date": "2027-07-05", "name": "Independence Day (observed)", "closure": "full" },
        { "date": "2027-09-06", "name": "Labor Day", "closure": "full" },
        { "date": "2027-11-25", "name": "Thanksgiving Day", "closure": "full" },
        { "date": "2027-11-26", "name": "Day after Thanksgiving", "closure": "half", "earlyClose": { "hour": 13, "minute": 0 } },
        { "date": "2027-12-24", "name": "Christmas Day (observed)", "closure": "full" }
      ]
    },
    {
      "marketIDs": ["lse"],
      "policy": "exact",
      "validThrough": "2027-12-31",
      "days": [
        { "date": "2026-01-01", "name": "New Year's Day", "closure": "full" },
        { "date": "2026-04-03", "name": "Good Friday", "closure": "full" },
        { "date": "2026-04-06", "name": "Easter Monday", "closure": "full" },
        { "date": "2026-05-04", "name": "Early May Bank Holiday", "closure": "full" },
        { "date": "2026-05-25", "name": "Spring Bank Holiday", "closure": "full" },
        { "date": "2026-08-31", "name": "Summer Bank Holiday", "closure": "full" },
        { "date": "2026-12-24", "name": "Christmas Eve", "closure": "half", "earlyClose": { "hour": 12, "minute": 30 } },
        { "date": "2026-12-25", "name": "Christmas Day", "closure": "full" },
        { "date": "2026-12-28", "name": "Boxing Day (substitute)", "closure": "full" },
        { "date": "2026-12-31", "name": "New Year's Eve", "closure": "half", "earlyClose": { "hour": 12, "minute": 30 } },
        { "date": "2027-01-01", "name": "New Year's Day", "closure": "full" },
        { "date": "2027-03-26", "name": "Good Friday", "closure": "full" },
        { "date": "2027-03-29", "name": "Easter Monday", "closure": "full" },
        { "date": "2027-05-03", "name": "Early May Bank Holiday", "closure": "full" },
        { "date": "2027-05-31", "name": "Spring Bank Holiday", "closure": "full" },
        { "date": "2027-08-30", "name": "Summer Bank Holiday", "closure": "full" },
        { "date": "2027-12-24", "name": "Christmas Eve", "closure": "half", "earlyClose": { "hour": 12, "minute": 30 } },
        { "date": "2027-12-27", "name": "Christmas Day (substitute)", "closure": "full" },
        { "date": "2027-12-28", "name": "Boxing Day (substitute)", "closure": "full" },
        { "date": "2027-12-31", "name": "New Year's Eve", "closure": "half", "earlyClose": { "hour": 12, "minute": 30 } }
      ]
    },
    {
      "marketIDs": ["cmeEquity"],
      "policy": "advisoryOnUSHolidays",
      "validThrough": "2027-12-31",
      "days": []
    }
  ]
}
```

**CME holiday treatment.** Research §4: CME publishes per-holiday Globex schedules "finalized approximately two weeks prior to the holiday"; US-holiday early closes for equity indexes are "typically 12:00 CT halts" but exact per-day hours were not verifiable (cmegroup.com blocks automation). Per research §4's app simplification and DECISIONS: v1 treats CME as **normal hours on all days** (`days: []`), and `policy: "advisoryOnUSHolidays"` makes `HolidayCalendar.advisory(on:market:)` return `true` on any date that is a **usEquities** closure or half-day, so the UI can show "US holiday — CME hours may differ" on MarketDetailView and in that day's timeline. UNVERIFIED: precise CME per-holiday hours; do not encode them until manually verified against cmegroup.com.

### 2c. killzones.json

The 5 killzones from spine §3, all `America/New_York`, majority-ICT-convention defaults (research §2, CONVENTION — variance is real; user-editable via `ConventionSettings.killzoneWindows`, which overrides `open`/`close` only). `weekdays` are a derived editorial default consistent with the FX week (Sun 17:00 open → Fri 17:00 close, research §1): the `asia` killzone runs Sun–Thu evenings and wraps midnight; all others run Mon–Fri.

```json
{
  "version": 1,
  "timeZoneID": "America/New_York",
  "killzones": [
    { "id": "asia", "name": "Asian Killzone",
      "open": { "hour": 20, "minute": 0 }, "close": { "hour": 0, "minute": 0 },
      "weekdays": [1, 2, 3, 4, 5], "wrapsMidnight": true },
    { "id": "london", "name": "London Killzone",
      "open": { "hour": 2, "minute": 0 }, "close": { "hour": 5, "minute": 0 },
      "weekdays": [2, 3, 4, 5, 6], "wrapsMidnight": false },
    { "id": "nyAM", "name": "NY AM Killzone",
      "open": { "hour": 7, "minute": 0 }, "close": { "hour": 10, "minute": 0 },
      "weekdays": [2, 3, 4, 5, 6], "wrapsMidnight": false },
    { "id": "londonClose", "name": "London Close KZ",
      "open": { "hour": 10, "minute": 0 }, "close": { "hour": 12, "minute": 0 },
      "weekdays": [2, 3, 4, 5, 6], "wrapsMidnight": false },
    { "id": "nyPM", "name": "NY PM Session",
      "open": { "hour": 13, "minute": 30 }, "close": { "hour": 16, "minute": 0 },
      "weekdays": [2, 3, 4, 5, 6], "wrapsMidnight": false }
  ]
}
```

### 2d. Codable decode structs

```swift
// Resources decode layer (OffsetKit/Models). All Sendable value types.
struct SessionsFile: Codable, Sendable { let version: Int; let markets: [MarketRecord] }
struct MarketRecord: Codable, Sendable {
    let id: MarketID; let name: String; let shortName: String
    let kind: MarketKind; let timeZoneID: String
    let colorToken: String; let symbolName: String
    let segments: [TradingSegment]                      // spine type, Codable as-is
    var market: Market {                                 // projection to spine §4 Market
        Market(id: id, name: name, shortName: shortName, kind: kind,
               timeZoneID: timeZoneID, colorToken: colorToken, symbolName: symbolName)
    }
}

struct HolidaysFile: Codable, Sendable { let version: Int; let calendars: [HolidayCalendarRecord] }
enum HolidayPolicy: String, Codable, Sendable { case exact, advisoryOnUSHolidays }
enum ClosureKind: String, Codable, Sendable { case full, half }
struct HolidayDay: Codable, Sendable {
    let date: DayKey            // decoded from "yyyy-MM-dd"
    let name: String
    let closure: ClosureKind
    let earlyClose: WallClockTime?   // present iff closure == .half
}
struct HolidayCalendarRecord: Codable, Sendable {
    let marketIDs: [MarketID]; let policy: HolidayPolicy
    let validThrough: DayKey;  let days: [HolidayDay]
}

struct KillzonesFile: Codable, Sendable { let version: Int; let timeZoneID: String; let killzones: [KillzoneRecord] }
struct KillzoneRecord: Codable, Sendable {
    let id: KillzoneID; let name: String
    let open: WallClockTime; let close: WallClockTime
    let weekdays: Set<Int>; let wrapsMidnight: Bool
}

struct DayKey: Codable, Hashable, Comparable, Sendable {
    var year: Int; var month: Int; var day: Int
    init(_ date: Date, in calendar: Calendar)       // components in calendar's zone
    // Codable via single "yyyy-MM-dd" string; Comparable lexicographic on (y, m, d)
}
```

`HolidayCalendar` (spine §2 engine file) is built from `HolidaysFile` at load and answers: `closure(on: DayKey, market: MarketID) -> HolidayDay?` (full closures only), `earlyClose(on:market:) -> WallClockTime?` (half days), `advisory(on:market:) -> Bool` (CME policy), `validThrough(market:) -> DayKey?`. Decode failures are programmer errors (bundled data): `loadBundledSeed()` throws, app fails fast with an OSLog fault. Note: `ConventionSettings.killzoneWindows` uses a labeled tuple, which Codable cannot synthesize — `ConventionSettings` implements custom Codable encoding each window as `{ "open": …, "close": … }` (owned by 02 doc; noted here because this engine consumes it).

---

## 3. Materialization algorithm — `occurrences(in:markets:conventions:)`

Signature (spine §4): `func occurrences(in range: DateInterval, markets: Set<MarketID>, conventions: ConventionSettings) -> [SessionOccurrence]`.

Range convention: **half-open** `range.start ≤ t < range.end` for event membership; an occurrence is included if its interval **intersects** the range (`openDate < range.end && closeDate > range.start`) so sessions already in progress at `range.start` are returned (timeline and `marketStatus` need them).

```
occurrences(range, markets, conventions):
  result = []
  for market in MarketID.allCases where markets.contains(market):        // fixed iteration order
    segments = conventions.sessionOverrides[market] ?? seed segments      // Pro editable defaults
    cal      = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: market.timeZoneID)!
    day      = startOfDay(of: range.start - occurrenceScanPadding, in: cal)   // 26 h back-padding
    while day < range.end + occurrenceScanPadding:
      weekday = cal.component(.weekday, from: day)                        // 1=Sun … 7=Sat
      dk = DayKey(day, in: cal)
      if seed.holidays.closure(on: dk, market: market) == nil:            // full closure ⇒ drop ALL segments
        for seg in segments where seg.weekdays.contains(weekday):
          (open, close) = effectiveTimes(seg, earlyClose: seed.holidays.earlyClose(on: dk, market: market))
          if open == nil: continue                                        // segment suppressed on half day
          openDate  = resolve(dk, open, cal)
          closeDate = resolve(seg.wrapsMidnight ? dk.next(in: cal) : dk, close, cal)
          guard openDate < closeDate else { continue }                    // defensive (custom conventions)
          if openDate < range.end && closeDate > range.start:
            result += SessionOccurrence(market: market, kind: seg.kind,
                                        openDate: openDate, closeDate: closeDate)
      day = cal.date(byAdding: .day, value: 1, to: day)                   // never +86400 (research §3 pitfall 4)
  return result sorted by (openDate, MarketID.allCases index, SegmentKind declaration order)
```

### 3.1 Wall-clock → `Date` resolution (DST-safe)

The only place a wall time becomes an instant. Uses the `Calendar.nextDate(after:matching:matchingPolicy:repeatedTimePolicy:direction:)` machinery from research §3:

```swift
func resolve(_ day: DayKey, _ time: WallClockTime, _ cal: Calendar) -> Date? {
    guard let dayStart = cal.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
    else { return nil }
    if time.hour == 0 && time.minute == 0 { return dayStart }        // 00:00 == day start (asia KZ close)
    return cal.nextDate(after: dayStart,
                        matching: DateComponents(hour: time.hour, minute: time.minute),
                        matchingPolicy: .nextTime,                    // skipped times → next valid instant
                        repeatedTimePolicy: .first,                   // duplicated times → first pass
                        direction: .forward)
}
```

- `.nextTime` handles **nonexistent** wall times (US spring-forward 2026-03-08 has no 02:00–03:00): a user-edited 02:30 killzone edge resolves to 03:00 EDT that day (research §3 pitfall 2).
- `.first` handles **duplicated** wall times (fall-back 2026-11-01 has two 01:00–02:00 passes): deterministic first pass (research §3 pitfall 3).
- Midnight anchor is safe: all five zones in scope transition at 01:00–03:00 local, never at 00:00, so `cal.date(from:)` for the day components is exact (IANA tzdata via research §5).
- Search starts at the day's start and moves forward, so the hit is always within that local day (or the wrap day for `wrapsMidnight` closes).

### 3.2 Half-day mapping — `effectiveTimes(seg, earlyClose:)`

Applied only when `earlyClose != nil` for the occurrence's open-day `DayKey`:

| Market | Segment | Normal | Half day (early close E) | Source |
|---|---|---|---|---|
| usEquities | preMarket | 04:00–09:30 | unchanged | research §3 |
| usEquities | regular | 09:30–16:00 | 09:30–**E (13:00)** | research §3 NYSE "Early-close days: 13:00 close" |
| usEquities | afterHours | 16:00–20:00 | **13:00–17:00** | research §3 "NYSE late sessions end 17:00 on those days"; DECISIONS half-day rule |
| lse | openingAuction | 07:50–08:00 | unchanged | research §3 |
| lse | regular | 08:00–16:30 | 08:00–**E (12:30)** | research §3 LSE "continuous trading ends 12:30" |
| lse | closingAuction | 16:30–16:35 | **12:30–12:35** | research §3 "closing auction 12:30–12:35" |
| cmeEquity | (all) | — | never (no half days in v1; advisory policy §2b) | research §4 |

Generalized rule (survives Pro `sessionOverrides`): the `regular` segment's close becomes `E`; a segment that **starts at the normal regular close** (afterHours, closingAuction) is shifted to start at `E`, keeping its duration for auctions and using close `E+4h` for usEquities afterHours per the table; segments ending at or before `E` are unchanged; a shifted segment whose window becomes empty is suppressed.

### 3.3 CME wrap rules (restated for implementers)

- The occurrence **belongs to its open date's day**: holiday lookup, weekday mask, and (in §4) the event `dayKey` all use the OPEN day in `America/Chicago`.
- Sunday open: weekday 1 in the segment's weekday set — no special code path.
- Friday close: the Thursday-open occurrence closes Friday 16:00 CT via `wrapsMidnight` (+1 day resolution); weekday 6 absent from the set means no Friday-evening open.
- `maintenanceBreak` occurrences (Mon–Thu 16:00–17:00 CT) are materialized like any segment; they render as gaps on `SessionTimelineView` and drive `marketStatus`, but never produce open/close `MarketEvent`s (§4 step 2).

---

## 4. Event derivation — `events(in:settings:econEvents:)`

Signature (spine §4): `func events(in range: DateInterval, settings: AppSettings, econEvents: [EconEvent]) -> [MarketEvent]`, sorted by date.

```
events(range, settings, econEvents):
  scan = DateInterval(range.start - occurrenceScanPadding, range.end + occurrenceScanPadding)
  occ  = occurrences(in: scan, markets: settings.enabledMarkets, conventions: settings.conventions)

  1. STRUCTURAL open/close — for every occurrence with kind != maintenanceBreak:
       emit MarketEvent(kind: .open,  market: occ.market, date: occ.openDate,  …)
       emit MarketEvent(kind: .close, market: occ.market, date: occ.closeDate, …)
     (Emitted regardless of AlertRules: TodayView, nextEvent and the Live Activity need them.
      Rules gate NOTIFICATIONS in 04, not events.)

  2. FX WEEK MARKERS — if settings.enabledMarkets contains any forexSession market:
     for each week intersecting scan, materialize in America/New_York:
       weekOpen  = Sunday 17:00, weekClose = Friday 17:00           (spine §3; research §1 VERIFIED convention)
     emit .weekOpen / .weekClose with market = nil.

  3. OVERLAP (structural, never hardcoded — spine §3, DECISIONS #2):
     if both fxLondon and fxNewYork are enabled:
       pair each fxNewYork regular occurrence N with the fxLondon regular occurrence L whose
       openDate falls on the same America/New_York calendar day as N.openDate
       start = max(L.openDate, N.openDate); end = min(L.closeDate, N.closeDate)
       if start < end: emit .overlapStart at start, .overlapEnd at end (market = nil)
     Implemented in OverlapCalculator; self-adjusts in DST mismatch weeks (§6).

  4. KILLZONES — emitted iff settings.traderLevel == .pro OR any enabled AlertRule targets a killzone
     (Beginner/Pro gate: Beginner sees no killzone events anywhere unless they opted into a killzone alert):
     for each America/New_York day in scan, for each KillzoneRecord kz where weekday matches:
       (open, close) = settings.conventions.killzoneWindows[kz.id] ?? seed window
       materialize via resolve() in America/New_York (asia wraps midnight)
       emit .killzoneStart(kz.id) / .killzoneEnd(kz.id), market = nil.

  5. ECON — for e in econEvents where settings.econCurrencies.contains(e.currency)
             and e.impact != .holiday                                  // FF "holiday" rows are display-only
             and (e.impact == .high OR an enabled .econ rule admits e.impact):
       emit .econRelease(e.id) at e.date, market = nil.

  6. LEADS — for each ENABLED AlertRule with .before(minutes: m) in moments:
       anchors = events from steps 1–5 matching rule.target
       .before is boundary-relative, resolved by the rule's OTHER moments:
         rule contains .atOpen (or neither boundary — open is the default anchor):
             open-like anchors (open, overlapStart, killzoneStart, weekOpen, econRelease)
             → emit .preOpen(leadMinutes: m) at anchor.date - m·60
         rule contains .atClose:
             close-like anchors (close, overlapEnd, killzoneEnd, weekClose)
             → emit .preClose(leadMinutes: m) at anchor.date - m·60
       Lead events carry the anchor's market (or nil) and derive their id from the anchor (§4.1).

  7. FILTER to half-open range: keep events with range.start ≤ date < range.end.
  8. SORT by (date, kind rank, id) — kind rank order: open, close, preOpen, preClose, overlapStart,
     overlapEnd, killzoneStart, killzoneEnd, weekOpen, weekClose, econRelease. Ties beyond that
     break on id lexicographically. Fully deterministic.
```

`title`/`subtitle` are filled from templates owned by 07-UI-UX-SPEC (e.g. title "London opens", subtitle "08:00 London · 3:00 AM your time" — subtitle formatting happens in the UI layer for `.local`/`.market`/`.both` `timeDisplayMode`; the engine emits market-zone wall-clock strings only).

`nextEvent(after:settings:econEvents:)` = first element of `events(in:)` with `date > after`, searched over an expanding window (48 h, then 8 days) so the common case computes one day, and a Friday-evening query still finds Sunday's `weekOpen`. Returns `nil` only if the horizon is empty (never happens with any market enabled). Hero/Live-Activity target *selection policy* (which kinds are countdown-worthy) is owned by 05-LIVE-ACTIVITY; the engine is kind-agnostic.

### 4.1 Stable deterministic `MarketEvent.id`

Grammar (ASCII, colon-separated fields; all tokens are raw enum values, so no field ever contains a colon):

```
eventID      = kindField ":" subjectField [":" segmentField] ":" dayField
             | "econ:" econEventID
             | leadKind ":" subjectField [":" segmentField] ":" dayField
             | leadKind ":econ:" econEventID

kindField    = "open" | "close" | "overlapStart" | "overlapEnd"
             | "kzStart" | "kzEnd" | "weekOpen" | "weekClose"
leadKind     = "preOpen-" minutes | "preClose-" minutes          ; e.g. "preOpen-15"
subjectField = MarketID.rawValue                                  ; open/close/leads on markets
             | KillzoneID.rawValue                                ; kzStart/kzEnd (+ their leads)
             | "fxLondon-fxNewYork"                               ; overlap events
             | "fx"                                               ; weekOpen/weekClose
segmentField = SegmentKind.rawValue, present IFF the event is a market open/close (or its lead)
               AND the segment != regular                         ; "preMarket", "afterHours",
                                                                  ; "openingAuction", "closingAuction"
dayField     = "yyyy-MM-dd" of the governing trading day:
               market events   → the occurrence's OPEN day in the market's zone
                                 (CME: the close event of the Mon-open session that fires Tue
                                  still carries Monday's date)
               overlap/killzone/fxWeek → the window's open day in America/New_York
econEventID  = EconEvent.id verbatim (uniqueness owned by 06-NEWS-AI)
```

Examples: `open:usEquities:2026-07-22` · `open:usEquities:preMarket:2026-07-22` · `close:cmeEquity:2026-07-20` (fires Tue 2026-07-21 21:00Z) · `preOpen-15:fxLondon:2026-03-09` · `kzStart:london:2026-03-09` · `preOpen-5:nyAM:2026-03-09` · `overlapStart:fxLondon-fxNewYork:2026-03-09` · `weekOpen:fx:2026-07-26` · `econ:ff-2026-07-30-usd-fomc` · `preOpen-15:econ:ff-2026-07-30-usd-fomc`.

Determinism guarantees: (a) same inputs → identical ids (no UUIDs, no hashing, no device zone anywhere — `dayField` uses the market/NY zone); (b) an event's id survives rebuilds and *content* changes (a half-day truncation moves `close:usEquities:2026-11-27` to 13:00 ET without changing its id — 04's idempotent re-add then just replaces the pending request); (c) ids are valid `UNNotificationRequest` identifiers and thread-safe merge keys for 04's planner. MarketID and KillzoneID raw values never collide (`fxLondon` vs `london`), so the subject field is unambiguous.

---

## 5. `marketStatus(at:market:conventions:)`

```
marketStatus(date, market, conventions):
  occ = occurrences(in: DateInterval(date - 26h, date + statusLookaheadDays days), [market], conventions)
  nextRegularOpen = first occ with kind == .regular and openDate > date        // bounded 14-day scan,
                                                                               // research §3 pattern
  if let cur = occ.first(where: { $0.openDate <= date && date < $0.closeDate }):
    switch cur.kind:
      .regular                       → .open(closesAt: cur.closeDate)
      .preMarket, .openingAuction    → .preMarket(opensAt: same-day regular openDate)
      .afterHours, .closingAuction   → .afterHours(endsAt: cur.closeDate)
      .maintenanceBreak              → .closed(opensAt: nextRegularOpen)       // CME 16:00–17:00 CT
  else:
    dk = DayKey(date, in: market's calendar)
    if let h = seed.holidays.closure(on: dk, market: market), weekday(dk) is Mon–Fri:
        → .holiday(name: h.name, opensAt: nextRegularOpen)
    else → .closed(opensAt: nextRegularOpen)
```

Rules and notes:

- Segments never overlap (all boundaries are shared instants with half-open membership: preMarket 04:00–09:30 hands to regular 09:30; LSE auction 07:50–08:00 hands to regular; CME break 16:00–17:00 sits between wrapped sessions), so "the occurrence containing `date`" is unique.
- `opensAt` for `.closed`/`.holiday` always points at the next **regular** open — the headline number a Beginner expects ("Opens 9:30 AM"). The timeline still shows preMarket bands; MarketDetailView may additionally surface "pre-market from 4:00 AM" (07 doc copy).
- `.preMarket`/`.afterHours` statuses arise for `usEquities` (spine §3) and, by the same mapping, for `lse` auction windows; forex and CME never produce them.
- `.holiday` applies only during the closure's calendar day in the market's own zone; the surrounding weekend stays `.closed`. Example: LSE at 2026-12-25T10:00:00+00:00 → `.holiday(name: "Christmas Day", opensAt: 2026-12-29T08:00:00+00:00)` (Dec 28 is also closed — Boxing Day substitute).
- Half days need no code here: truncation already happened in §3.2, so 2026-11-27 14:00 ET is `.afterHours(endsAt: 17:00 ET)` and 2026-11-27 18:00 ET is `.closed`.
- CME advisory days (`advisory(on:market:) == true`) do not change status; the UI adds the advisory chip (§2b).

---

## 6. DST correctness

### 6.1 Ground truth (research §5, IANA tzdata via zdump — the same data iOS uses)

| Zone | 2026 spring | 2026 autumn | 2027 spring | 2027 autumn |
|---|---|---|---|---|
| America/New_York, America/Chicago | Sun **2026-03-08** 02:00→03:00 | Sun **2026-11-01** 02:00→01:00 | Sun 2027-03-14 | Sun 2027-11-07 |
| Europe/London | Sun **2026-03-29** 01:00→02:00 | Sun **2026-10-25** 02:00→01:00 | Sun 2027-03-28 | Sun 2027-10-31 |
| Australia/Sydney | DST **ends** Sun 2026-04-05 03:00→02:00 | DST **begins** Sun 2026-10-04 02:00→03:00 | ends Sun 2027-04-04 | begins Sun 2027-10-03 |

**London–New York mismatch windows** (offset 4 h instead of the normal 5 h): **2026-03-08 → 2026-03-29** (3 weeks), **2026-10-25 → 2026-11-01** (1 week), 2027-03-14 → 2027-03-28 (2 weeks), 2027-10-31 → 2027-11-07 (1 week). Sydney–New York cycles 14 h → 15 h (2026-10-04 → 2026-11-01) → 16 h.

### 6.2 Worked example — the London–NY overlap through March 2026 (research §5 worked example)

Overlap is structural: `max(opens)..<min(closes)` of the day's fxLondon and fxNewYork regular occurrences. Under default conventions that is NY open → London close.

| Week (Monday) | London zone | NY zone | London 08:00 open, in NY time | London 17:00 close, in NY time | Overlap (NY wall clock) | Duration |
|---|---|---|---|---|---|---|
| 2026-03-02 (normal) | GMT +0 | EST −5 | 03:00 | 12:00 | 08:00–12:00 | **4 h** |
| 2026-03-09 (mismatch: US on EDT, UK still GMT) | GMT +0 | EDT −4 | 04:00 | 13:00 | 08:00–13:00 | **5 h** |
| 2026-03-30 (UK caught up, BST) | BST +1 | EDT −4 | 03:00 | 12:00 | 08:00–12:00 | **4 h** |

The same 1-hour stretch recurs 2026-10-26 → 2026-10-30 (UK fell back Oct 25, US falls back Nov 1), and in the mirrored 2027 windows. Note the research-documented side effect for Pro users: a killzone pinned at 02:00–05:00 `America/New_York` covers 06:00–09:00 **London wall clock** during mismatch weeks instead of the usual 07:00–10:00 — expected behavior, not a bug (ICT windows are NY-anchored by definition, research §2).

Because the engine computes both endpoints from **materialized instants**, the 5-hour weeks fall out automatically — nothing is hardcoded to "08:00–12:00 ET" (which research §1 flags as the always-wrong simplification).

### 6.3 Engineering rules (non-negotiable; research §5 rule + §3 pitfalls)

1. Store sessions as `(weekdays, wall-clock open/close, IANA zone)`; materialize per-occurrence with a `Calendar` in that zone. Never `TimeZone(abbreviation:)`, never `TimeZone(secondsFromGMT:)` ("EST" is UTC−5 year-round).
2. Never derive one market from another ("London = NY + 5h" is wrong 4 weeks a year). One calendar per market, always.
3. Never advance days with `addingTimeInterval(86400)` — DST days are 23/25 h; use `calendar.date(byAdding: .day, …)`.
4. Resolve skipped/duplicated wall times with `matchingPolicy: .nextTime`, `repeatedTimePolicy: .first` (§3.1).
5. Never cache materialized instants across a device zone change or a DST boundary: `ScheduleStore` recomputes on `NSSystemTimeZoneDidChange` (after `TimeZone.resetSystemTimeZone()`), `significantTimeChangeNotification`, `NSCalendarDayChanged`, and foreground (research §2 signal table; wiring in 02/04 docs). The engine itself holds no caches, which is what makes this rule enforceable.
6. `MarketEvent.id` day keys are computed in the market's zone, never the device zone — a user in Tokyo and a user in Chicago produce identical ids for identical settings.
7. Tests assert engine output equals `UNCalendarNotificationTrigger.nextTriggerDate()` for pinned-zone components (research §3 pitfall 7; test T18 below and 04 doc §4).

---

## 7. Unit test plan (Swift Testing, `OffsetKit/Tests/OffsetKitTests/`)

Conventions: fixture `SeedData` = the shipped JSON (decoded in tests via `loadBundledSeed()`); `defaultSettings` = `AppSettings` defaults (spine §4) with all seven markets enabled; `pro(settings)` flips `traderLevel = .pro`. Expected instants are written ISO-8601 with offset and asserted via `Date(timeIntervalSince1970:)` equivalents. All fixture dates/offsets trace to research §3–§5.

```swift
@Suite("Seed decode")           // T1
@Test func decodesAllSeedFiles()
// sessions.json → 7 MarketRecords in MarketID.allCases order; usEquities has 3 segments, lse 3, cmeEquity 2.
// holidays.json → usEquities: 10 full + 2 half in 2026; lse: 8 full + 2 half in 2026; cme policy
// advisoryOnUSHolidays with 0 days; validThrough == 2027-12-31 for all three.
// killzones.json → 5 records, timeZoneID "America/New_York", asia wrapsMidnight true.

@Suite("Materialization basics")
@Test func londonOpenNormalWeek()                      // T2
// Mon 2026-03-02 (UK GMT): fxLondon regular openDate == 2026-03-02T08:00:00+00:00
// == 2026-03-02T03:00:00-05:00 in America/New_York (device-local projection is formatting only).
@Test func londonOpenMismatchWeek()                    // T3
// Mon 2026-03-09 (US on EDT since 03-08, UK still GMT): openDate == 2026-03-09T08:00:00+00:00
// == 2026-03-09T04:00:00-04:00 NY. One hour "later" in NY terms than T2 — research §5.

@Suite("Overlap across DST mismatch")                  // OverlapCalculator, structural
@Test func overlapNormalWeekIs4h()                     // T4
// Mon 2026-03-02: overlapStart == 2026-03-02T08:00:00-05:00 (13:00:00Z),
// overlapEnd == 2026-03-02T17:00:00+00:00 (17:00:00Z); duration == 14_400 s (4 h).
@Test func overlapSpringMismatchIs5h()                 // T5
// Mon 2026-03-09 (inside 2026-03-08..29 window): overlapStart == 2026-03-09T08:00:00-04:00
// (12:00:00Z), overlapEnd == 2026-03-09T17:00:00+00:00 (17:00:00Z); duration == 18_000 s (5 h).
// NOTE research §5 worked example: the overlap STRETCHES to 5 h during mismatch weeks
// and is 4 h in normal weeks — the engine must reproduce exactly this asymmetry.
@Test func overlapAfterUKCatchUpIs4h()                 // T6
// Mon 2026-03-30 (UK on BST since 03-29): overlapStart == 2026-03-30T08:00:00-04:00 (12:00:00Z),
// overlapEnd == 2026-03-30T17:00:00+01:00 (16:00:00Z); duration == 14_400 s.
@Test func overlapAutumnMismatchIs5h()                 // T7
// Mon 2026-10-26 (UK fell back 10-25; US still EDT until 11-01): start == 2026-10-26T08:00:00-04:00
// (12:00:00Z), end == 2026-10-26T17:00:00+00:00 (17:00:00Z); 5 h. Then Mon 2026-11-02:
// start == 2026-11-02T08:00:00-05:00 (13:00:00Z), end == 17:00:00Z; back to 4 h.

@Suite("Holidays and half days")
@Test func nyseFullHolidayDrops()                      // T8
// Mon 2026-09-07 (Labor Day, research §3): occurrences for usEquities on that NY day == []
// (preMarket, regular, afterHours all dropped). fxNewYork (forex) still materializes normally.
// marketStatus(at: 2026-09-07T12:00:00-04:00, .usEquities) == .holiday(name: "Labor Day",
// opensAt: 2026-09-08T09:30:00-04:00).
@Test func nyseHalfDayTruncates()                      // T9
// Fri 2026-11-27 (research §3, US back on EST since 11-01): regular == 09:30–13:00 EST
// (closeDate == 2026-11-27T13:00:00-05:00 == 18:00:00Z); afterHours == 13:00–17:00 EST;
// preMarket unchanged 04:00–09:30 EST. Status at 14:00 EST == .afterHours(endsAt:
// 2026-11-27T17:00:00-05:00); at 18:00 EST == .closed(opensAt: 2026-11-30T09:30:00-05:00).
@Test func lseHalfDayTruncates()                       // T10
// Thu 2026-12-24 (research §3): regular closeDate == 2026-12-24T12:30:00+00:00;
// closingAuction == 12:30–12:35 GMT; openingAuction unchanged 07:50–08:00.
@Test func lseChristmasRunClosures()                   // T11
// 2026-12-25 and 2026-12-28 produce no lse occurrences; status on 12-25 ==
// .holiday(name: "Christmas Day", opensAt: 2026-12-29T08:00:00+00:00).

@Suite("CME Globex wrap")
@Test func cmeOvernightWrapBelongsToOpenDay()          // T12
// Tue 2026-07-21 (CDT −5): exactly one regular occurrence with openDate ==
// 2026-07-21T17:00:00-05:00 (22:00:00Z) and closeDate == 2026-07-22T16:00:00-05:00 (21:00:00Z);
// 23 h duration. maintenanceBreak Tue 16:00–17:00 CDT exists separately.
@Test func cmeFridayCloseAndNoFridayOpen()             // T13
// Week of 2026-07-20: last occurrence of the week opens Thu 2026-07-23T17:00:00-05:00 and
// closes Fri 2026-07-24T16:00:00-05:00. No occurrence opens Friday; no maintenanceBreak Friday.
@Test func cmeSundayOpen()                             // T14
// Sun 2026-07-26: occurrence opens 2026-07-26T17:00:00-05:00 (22:00:00Z), closes
// 2026-07-27T16:00:00-05:00. marketStatus at Sat 2026-07-25T12:00:00-05:00 ==
// .closed(opensAt: 2026-07-26T17:00:00-05:00).
@Test func cmeMaintenanceBreakIsClosed()               // T15
// marketStatus(at: 2026-07-22T16:30:00-05:00, .cmeEquity) == .closed(opensAt:
// 2026-07-22T17:00:00-05:00). The break occurrence itself never yields open/close events.

@Suite("Killzones and wall-clock resolution")          // pro(settings)
@Test func killzoneAcrossSpringForward()               // T16
// london killzone (02:00–05:00 America/New_York): Fri 2026-03-06 window ==
// [2026-03-06T02:00:00-05:00, 2026-03-06T05:00:00-05:00] == [07:00Z, 10:00Z];
// Mon 2026-03-09 window == [2026-03-09T02:00:00-04:00, 2026-03-09T05:00:00-04:00]
// == [06:00Z, 09:00Z]. Assert the Monday window covers 06:00–09:00 Europe/London wall clock
// (research §5: NY-pinned killzones drift against London during mismatch weeks — by design).
@Test func skippedWallTimeResolvesForward()            // T17
// resolve(2026-03-08, WallClockTime(hour: 2, minute: 30), NY calendar) ==
// 2026-03-08T03:00:00-04:00 (07:00:00Z) via .nextTime — 02:30 does not exist that day.
// Guards user-edited killzone edges (research §3 pitfall 2).
@Test func duplicatedWallTimeTakesFirstPass()          // T18
// resolve(2026-11-01, WallClockTime(hour: 1, minute: 30), NY calendar) ==
// 2026-11-01T01:30:00-04:00 (05:30:00Z) — the FIRST of the two 01:30s, via .first.
// Cross-check: UNCalendarNotificationTrigger(dateMatching: same components with explicit
// timeZone, repeats: false).nextTriggerDate() must equal the engine's instant (research §3 pitfall 7).

@Suite("Events and ids")
@Test func eventIDsAreStableAndDeterministic()         // T19
// events(in: 2026-07-20T00:00Z ..< 2026-07-25T00:00Z, defaultSettings, []) called twice
// → element-wise identical arrays (ids AND order). Spot-assert exact ids:
//   "open:usEquities:2026-07-22" at 2026-07-22T09:30:00-04:00
//   "open:usEquities:preMarket:2026-07-22" at 2026-07-22T04:00:00-04:00
//   "close:cmeEquity:2026-07-21" at 2026-07-22T16:00:00-05:00   (open-day keyed)
//   "preOpen-15:fxLondon:2026-07-22" at 2026-07-22T07:45:00+01:00 (default Beginner rule lead)
@Test func fxWeekMarkersAndCoincidence()               // T20
// weekClose == 2026-07-24T17:00:00-04:00 (21:00:00Z), id "weekClose:fx:2026-07-24";
// weekOpen == 2026-07-26T17:00:00-04:00 (21:00:00Z), id "weekOpen:fx:2026-07-26".
// Assert fxSydney's Monday occurrence opens 2026-07-27T07:00:00+10:00 (AEST, DST off since
// 04-05) == 2026-07-26T21:00:00Z — the SAME instant as weekOpen. (04 doc's planner merges
// these coincident notifications; the engine must emit both events with distinct ids.)
@Test func deviceLocalTimelineProjectionSanity()       // T21
// 24 h device-local window, device zone America/New_York, Mon 2026-03-09T00:00:00-04:00
// ..< 2026-03-10T00:00:00-04:00 (04:00Z..04:00Z): the set of regular-segment .open event ids is
// exactly { "open:fxSydney:2026-03-10",   // Tue 07:00 AEDT == 2026-03-09T20:00:00Z == Mon 16:00 EDT
//           "open:fxTokyo:2026-03-10",    // Tue 09:00 JST  == 2026-03-10T00:00:00Z == Mon 20:00 EDT
//           "open:fxLondon:2026-03-09",   // 08:00 GMT == Mon 04:00 EDT (mismatch week)
//           "open:fxNewYork:2026-03-09",  // 08:00 EDT
//           "open:usEquities:2026-03-09", // 09:30 EDT
//           "open:lse:2026-03-09",        // 08:00 GMT
//           "open:cmeEquity:2026-03-09" } // 17:00 CDT == Mon 18:00 EDT
// and every event date lies inside the window. Verifies cross-day id keying (Sydney/Tokyo carry
// TUESDAY day keys while rendering inside device-local Monday) and the full 7-market lane set.
@Test func beginnerHidesKillzoneEvents()               // T22
// Same range with defaultSettings (Beginner, killzone rules disabled): events contain no
// killzoneStart/killzoneEnd. With pro(settings): all five killzones emit per weekday mask.
```

Coverage summary vs required list: normal-week London open (T2), US spring-forward window behavior (T3/T5), UK catch-up (T6), autumn mismatch (T7), NYSE holiday drop (T8), NYSE half-day truncation (T9), LSE half-day (T10), CME wrap + Friday close + Sunday open (T12–T14), killzone across DST (T16), skipped/duplicated wall times (T17/T18), stable ids (T19), 24 h device-local projection (T21), plus decode (T1), status (T8/T9/T15), week markers (T20), Beginner/Pro gate (T22). Precedence note: research §5's worked example fixes the overlap at **4 h in normal weeks and 5 h inside mismatch windows**; these tests encode the research values (research data > any doc prose, per spine precedence).

Fixture hygiene: never construct expected dates through the device calendar — build them from explicit `DateComponents` with an explicit `TimeZone(identifier:)`, or from literal Unix timestamps, so the suite passes on CI machines in any zone. Run the suite once with `TZ=America/New_York` and once with `TZ=Asia/Tokyo` (scheme test-plan environment variable) to prove device-zone independence.
