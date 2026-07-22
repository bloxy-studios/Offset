# 00 — SPINE: Canonical Contracts for Offset

**This document is law.** Every other doc, and ultimately all generated code, must use these names, types, values, and structures VERBATIM. If an author needs something not defined here, they add a clearly-marked `PROPOSED ADDITIONS` section at the top of their doc — they never silently invent parallel vocabulary.

Precedence on conflict: `DECISIONS.md` > `00-SPINE.md` > area docs (01–08) > research files.

---

## 1. Identity

| Key | Value |
|---|---|
| App name | **Offset** |
| Tagline | Every market. Your time. |
| One-liner | A session-aware trading clock: every major market's opens, closes, overlaps and killzones — converted to your local time, alerted reliably, counted down in the Dynamic Island — with an AI briefing before you sit down. |
| Platform | iPhone-only (iPad compatibility mode). Portrait-primary. |
| Minimum OS | iOS 26.0 |
| Toolchain | Xcode 26.6, Swift 6.2, **Approachable Concurrency** (default `MainActor` isolation module setting), Swift Testing for tests |
| Dependencies | **None.** First-party frameworks only: SwiftUI, SwiftData, WidgetKit, ActivityKit, AlarmKit, UserNotifications, BackgroundTasks, FoundationModels, TipKit, OSLog, AppIntents |
| Distribution | Personal (Xcode install). Paid Apple Developer account recommended |
| User's device | iPhone 14 Pro Max → Dynamic Island ✅, Apple Intelligence ❌ (Exa is primary summarizer at runtime; on-device path still built) |

Placeholders used throughout docs and code: `YOURTEAMID`, and org root `dev.offsetapp`. Bundle ids: app `dev.offsetapp.offset`, widget extension `dev.offsetapp.offset.widgets`. App Group: `group.dev.offsetapp.offset`. URL scheme: `offset://`. BGTask ids: `dev.offsetapp.offset.refresh.schedule`, `dev.offsetapp.offset.refresh.news`.

---

## 2. Target topology & file tree

Three build products + one local Swift package:

```
Offset/                                  (repo root)
├── Offset.xcodeproj
├── Config/
│   ├── Secrets.xcconfig                 (gitignored: FINNHUB_API_KEY, EXA_API_KEY)
│   └── Secrets.example.xcconfig
├── Offset/                              (APP TARGET — SwiftUI app)
│   ├── OffsetApp.swift                  (@main, scene, BG task registration)
│   ├── RootTabView.swift                (tab shell, bottom accessory)
│   ├── Features/
│   │   ├── Today/                       (TodayView + dashboard cards + SessionTimelineView)
│   │   ├── Markets/                     (MarketsListView, MarketDetailView)
│   │   ├── News/                        (NewsFeedView, BriefingCardView)
│   │   ├── Alerts/                      (AlertsView, AlertRuleEditorView, CriticalAlarmsSection)
│   │   ├── Search/                      (SearchView — markets, events, glossary)
│   │   └── Settings/                    (SettingsView, ConventionsEditorView, TraderLevelPicker)
│   ├── Onboarding/                      (OnboardingFlow — 4 screens)
│   ├── Learn/                           (GlossaryView, ExplainerCard, glossary.json)
│   ├── DesignSystem/                    (OffsetTheme.swift, MarketChip, CountdownText, GlassHelpers)
│   └── Support/                         (Haptics, Formatters, DeepLinkRouter)
├── OffsetKit/                           (LOCAL SPM PACKAGE — pure logic, fully unit-testable)
│   ├── Package.swift
│   ├── Sources/OffsetKit/
│   │   ├── Models/                      (all types in §4)
│   │   ├── Engine/                      (SessionScheduleEngine, OverlapCalculator, HolidayCalendar)
│   │   ├── Scheduling/                  (NotificationPlanner, AlarmPlanner)
│   │   ├── News/                        (ForexFactoryClient, FinnhubClient, ExaClient)
│   │   ├── AI/                          (BriefingEngine, Summarizer protocol + 3 impls)
│   │   ├── Storage/                     (SettingsStore, CacheStore [SwiftData], AppGroup)
│   │   └── Resources/                   (sessions.json, holidays.json, killzones.json)
│   └── Tests/OffsetKitTests/            (engine, DST, budgeter, decode tests)
├── OffsetWidgets/                       (EXTENSION TARGET — WidgetKit + ActivityKit + AlarmKit UI)
│   ├── OffsetWidgetsBundle.swift
│   ├── MarketCountdownLiveActivity.swift
│   ├── NextEventWidget.swift            (systemSmall, systemMedium)
│   ├── SessionTimelineWidget.swift      (systemMedium, systemLarge)
│   ├── AccessoryWidgets.swift           (circular, rectangular, inline)
│   └── AlarmPresentationSupport.swift
└── Shared/                              (compiled into BOTH app + extension)
    ├── MarketCountdownAttributes.swift  (ActivityAttributes — must be identical in both targets)
    ├── AlarmMetadata.swift
    └── SharedConstants.swift            (App Group id, deep-link builders)
```

Dependency rules: `OffsetKit` imports Foundation, SwiftData, UserNotifications, AlarmKit, FoundationModels — **never SwiftUI/WidgetKit**. App + extension import OffsetKit. UI-facing observable stores live in the app target.

---

## 3. Canonical market data

Seven markets. All hours are **wall-clock in the market's own IANA zone**, materialized per-occurrence (never fixed UTC offsets). Weekdays: Mon–Fri unless noted.

| MarketID | Display name | Short | Kind | IANA zone | Segments (local wall-clock) | Color token | SF Symbol |
|---|---|---|---|---|---|---|---|
| `fxSydney` | Sydney Session | SYD | forexSession | Australia/Sydney | regular 07:00–16:00 | `.sydneyAmber` #FFB340 | `globe.asia.australia.fill` |
| `fxTokyo` | Tokyo Session | TYO | forexSession | Asia/Tokyo | regular 09:00–18:00 | `.tokyoRose` #FF5E7A | `sunrise.fill` |
| `fxLondon` | London Session | LDN | forexSession | Europe/London | regular 08:00–17:00 | `.londonBlue` #4DA3FF | `globe.europe.africa.fill` |
| `fxNewYork` | New York Session | NYC | forexSession | America/New_York | regular 08:00–17:00 | `.newYorkGreen` #30D158 | `globe.americas.fill` |
| `usEquities` | US Stocks (NYSE·Nasdaq) | US | equityExchange | America/New_York | preMarket 04:00–09:30 · regular 09:30–16:00 · afterHours 16:00–20:00 | `.usIndigo` #6E7CFF | `building.columns.fill` |
| `lse` | London Stock Exchange | LSE | equityExchange | Europe/London | openingAuction 07:50–08:00 · regular 08:00–16:30 · closingAuction 16:30–16:35 | `.lseCyan` #40C8E0 | `building.2.fill` |
| `cmeEquity` | CME Globex (Futures) | CME | futures | America/Chicago | regular 17:00–16:00 next day (wrapsMidnight), Sun open 17:00, Fri close 16:00, maintenanceBreak 16:00–17:00 Mon–Thu | `.cmeOrange` #FF9F0A | `chart.line.uptrend.xyaxis` |

**FX week markers** (display + alert events, not segments): `weekOpen` Sunday 17:00 America/New_York · `weekClose` Friday 17:00 America/New_York.

**Killzones** (Pro layer; defaults per majority ICT convention; all America/New_York; user-editable):

| KillzoneID | Name | Default window |
|---|---|---|
| `asia` | Asian Killzone | 20:00–00:00 |
| `london` | London Killzone | 02:00–05:00 |
| `nyAM` | NY AM Killzone | 07:00–10:00 |
| `londonClose` | London Close KZ | 10:00–12:00 |
| `nyPM` | NY PM Session | 13:30–16:00 |

**Overlap** is computed structurally, never hardcoded: `overlap(fxLondon, fxNewYork) = max(opens)..<min(closes)` per materialized day. It self-adjusts during DST mismatch weeks (2026: Mar 8–29, Oct 25–Nov 1; 2027: Mar 14–28, Oct 31–Nov 7).

**Half-days**: NYSE half-days close 13:00 ET (after-hours truncated to 13:00–17:00); LSE half-days close 12:30 local. Holiday + half-day dates 2026–2028 ship in `holidays.json` (values in research file `market-sessions-and-notifications.md`).

---

## 4. Canonical types (OffsetKit/Models)

Signatures are canonical; bodies/conformance details live in area docs.

```swift
enum MarketID: String, Codable, CaseIterable, Sendable, Identifiable {
    case fxSydney, fxTokyo, fxLondon, fxNewYork, usEquities, lse, cmeEquity
}
enum MarketKind: String, Codable, Sendable { case forexSession, equityExchange, futures }

struct Market: Identifiable, Sendable {
    let id: MarketID; let name: String; let shortName: String
    let kind: MarketKind; let timeZoneID: String
    let colorToken: String; let symbolName: String
}

struct WallClockTime: Codable, Hashable, Sendable, Comparable { var hour: Int; var minute: Int }

enum SegmentKind: String, Codable, Sendable {
    case preMarket, regular, afterHours, openingAuction, closingAuction, maintenanceBreak
}

struct TradingSegment: Codable, Sendable {
    let kind: SegmentKind
    let open: WallClockTime; let close: WallClockTime
    let weekdays: Set<Int>           // 1=Sun … 7=Sat (Calendar convention)
    let wrapsMidnight: Bool
}

struct SessionOccurrence: Sendable, Identifiable {
    let market: MarketID; let kind: SegmentKind
    let openDate: Date; let closeDate: Date      // absolute instants
}

enum KillzoneID: String, Codable, CaseIterable, Sendable { case asia, london, nyAM, londonClose, nyPM }

enum MarketEventKind: Hashable, Sendable {
    case open, close
    case preOpen(leadMinutes: Int), preClose(leadMinutes: Int)
    case overlapStart, overlapEnd
    case killzoneStart(KillzoneID), killzoneEnd(KillzoneID)
    case weekOpen, weekClose
    case econRelease(String)                      // EconEvent.id
}

struct MarketEvent: Identifiable, Hashable, Sendable {
    let id: String                                // stable, deterministic (see 03 doc)
    let kind: MarketEventKind
    let market: MarketID?                         // nil for overlap/killzone/econ
    let date: Date
    let title: String                             // "London opens"
    let subtitle: String                          // "08:00 London · 3:00 AM your time"
}

// THE core pure engine — deterministic, no side effects, fully unit-tested
struct SessionScheduleEngine: Sendable {
    func occurrences(in range: DateInterval, markets: Set<MarketID>, conventions: ConventionSettings) -> [SessionOccurrence]
    func events(in range: DateInterval, settings: AppSettings, econEvents: [EconEvent]) -> [MarketEvent]  // sorted by date
    func nextEvent(after date: Date, settings: AppSettings, econEvents: [EconEvent]) -> MarketEvent?
    func marketStatus(at date: Date, market: MarketID, conventions: ConventionSettings) -> MarketStatus
}
enum MarketStatus: Sendable, Equatable { case open(closesAt: Date), closed(opensAt: Date), preMarket(opensAt: Date), afterHours(endsAt: Date), holiday(name: String, opensAt: Date) }
```

```swift
// Alerts
enum AlertTarget: Codable, Hashable, Sendable {
    case market(MarketID, SegmentKind)
    case overlap
    case killzone(KillzoneID)
    case econ(minImpact: EconImpact)
    case fxWeek
}
enum AlertMoment: Codable, Hashable, Sendable { case atOpen, atClose, before(minutes: Int) }
enum AlertStyle: String, Codable, Sendable { case standard, timeSensitive, criticalAlarm }

struct AlertRule: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var target: AlertTarget
    var moments: Set<AlertMoment>
    var style: AlertStyle
    var enabled: Bool
}

struct NotificationPlanner: Sendable {
    // ≤56 scheduled, 8 reserved; priority: sooner > criticalAlarm-backed > opens > econ high > closes > killzones > overlaps
    func plan(events: [MarketEvent], rules: [AlertRule], now: Date) -> [PlannedNotification]
}
struct AlarmPlanner: Sendable {
    func plan(events: [MarketEvent], rules: [AlertRule], now: Date, horizonDays: Int) -> [PlannedAlarm]  // .fixed dates ONLY
}
```

```swift
// Live Activity (defined in Shared/, identical in app + extension)
struct MarketCountdownAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var eventTitle: String            // "London opens"
        var phase: CountdownPhase         // .countingDown, .inProgress, .marketsClosed
        var targetDate: Date              // what the timer counts to
        var marketTimeLabel: String       // "08:00 LDN"
        var rangeStart: Date              // for ProgressView(timerInterval:)
    }
    let marketRawValue: String            // MarketID.rawValue
    let marketShortName: String
    let colorToken: String
    let symbolName: String
}
enum CountdownPhase: String, Codable, Hashable { case countingDown, inProgress, marketsClosed }
```

```swift
// News & AI
enum EconImpact: String, Codable, Comparable, Sendable { case low, medium, high, holiday }
struct EconEvent: Codable, Identifiable, Hashable, Sendable {
    let id: String; let title: String; let currency: String
    let date: Date; let impact: EconImpact
    let forecast: String?; let previous: String?
}
struct Headline: Codable, Identifiable, Sendable {
    let id: String; let title: String; let source: String
    let url: URL; let publishedAt: Date
    var summary: String?; let related: [MarketID]
}
enum TraderLevel: String, Codable, Sendable { case beginner, pro }
enum SummaryProvider: String, Codable, Sendable { case onDevice, exa, template }

struct Briefing: Codable, Sendable {
    let generatedAt: Date; let traderLevel: TraderLevel
    let headline: String                  // one-sentence "what today is about"
    let bullets: [String]                 // 3–5
    let watchouts: [String]               // 0–3 (econ releases, unusual hours)
    let provider: SummaryProvider
}

protocol Summarizer: Sendable {
    var provider: SummaryProvider { get }
    func isAvailable() async -> Bool
    func makeBriefing(_ input: BriefingInput) async throws -> Briefing
    func summarize(headline: Headline) async throws -> String   // 1–2 sentences
}
// Implementations: FoundationModelsSummarizer, ExaAnswerSummarizer, TemplateSummarizer (never fails)
struct BriefingEngine: Sendable { /* picks first available summarizer in order onDevice → exa → template */ }
```

```swift
// Settings & stores
struct ConventionSettings: Codable, Sendable {   // Pro-editable session hours & killzones
    var sessionOverrides: [MarketID: [TradingSegment]]   // empty = canonical defaults
    var killzoneWindows: [KillzoneID: (open: WallClockTime, close: WallClockTime)]
}
enum TimeDisplayMode: String, Codable, Sendable { case local, market, both }

struct AppSettings: Codable, Sendable {
    var traderLevel: TraderLevel                 // default .beginner
    var enabledMarkets: Set<MarketID>            // default: all seven
    var alertRules: [AlertRule]                  // defaults in 04 doc
    var econCurrencies: Set<String>              // default ["USD","GBP","EUR","JPY","AUD"]
    var briefingTime: WallClockTime              // default 07:30 (device-local)
    var conventions: ConventionSettings
    var timeDisplayMode: TimeDisplayMode         // default .both
    var liveActivityEnabled: Bool                // default true
}
// SettingsStore: App Group UserDefaults, Codable JSON blob + version field
// CacheStore: SwiftData (models: CachedHeadline, CachedEconEvent, CachedBriefing) in App Group container
```

App-target observable layer (`@MainActor @Observable`): `ScheduleStore` (engine facade + now-ticking), `NewsStore`, `AlertsStore`, `ActivityController` (Live Activity lifecycle), `RefreshCoordinator` (BGTask + foreground refresh + system clock/zone change notifications).

---

## 5. Navigation map & signature UI

**Tab shell** (SwiftUI `TabView` with iOS 26 APIs):

| Tab | Icon | Content |
|---|---|---|
| Today | `clock.fill` | Hero next-event countdown card · SessionTimelineView (24h, device-local, "now" needle) · open-markets strip · today's high-impact econ strip · briefing card |
| Markets | `globe` | 7 market rows w/ live status chip → `MarketDetailView` (week schedule, local↔market time toggle, per-market alerts, beginner explainer) |
| News | `newspaper.fill` | Briefing at top, then headlines feed w/ tap-to-expand AI summaries |
| Alerts | `bell.badge.fill` | Rules list grouped by target · Critical alarms section · budget health row ("41 of 64 slots") · permission status |
| Search | `Tab(role: .search)` | Markets, events, glossary terms |

- `.tabBarMinimizeBehavior(.onScrollDown)` on the TabView.
- `.tabViewBottomAccessory`: **persistent mini countdown** — market dot + "LDN opens" + `Text(timerInterval:)`; collapses inline into the tab bar when minimized (adapt via `\.tabViewBottomAccessoryPlacement`). Tapping opens Today. Hidden while `phase == .marketsClosed`.
- Glass is for **controls/navigation only** (tab bar, toolbars, floating buttons, accessory). Content cards use standard materials/backgrounds — never `.glassEffect` on content.
- `SessionTimelineView` is the signature component: horizontal 24h band chart, one lane per enabled market group, colored session bands (tokens above), overlap glow, killzone hatching (Pro only), "now" needle, VoiceOver per-band labels. Reused: Today (interactive), MarketDetail (single lane), SessionTimelineWidget (static render).
- Typography: system SF Pro; countdowns use `.monospacedDigit()` + SF Pro Rounded semibold. Dark-mode-first; full light-mode support; respects Reduce Transparency / Increase Contrast.

**Trader Level gating** (single switch, many effects): Beginner → killzone lane hidden, explainer cards visible, glossary links inline, plain-language notification copy. Pro → killzones on, conventions editor unlocked, denser Today layout, econ strip shows forecast/previous, notification copy terse.

---

## 6. Doc map

| File | Owns |
|---|---|
| `DECISIONS.md` | Requirement + decision log (highest precedence) |
| `00-SPINE.md` | This file — names, types, data, structure |
| `01-PRODUCT-SPEC.md` | Vision, personas, feature inventory, user stories, v1/v1.1 scope |
| `02-ARCHITECTURE.md` | Targets, package, concurrency, data flow, persistence, secrets, entitlements/Info.plist inventory, logging |
| `03-SESSION-ENGINE.md` | Data model detail, seed JSONs (real values), materialization algorithm, overlap/killzones, DST fixtures, engine tests |
| `04-ALERTS-NOTIFICATIONS.md` | Notification pipeline, 64-cap budgeter, AlarmKit integration, permission UX, default rules |
| `05-LIVE-ACTIVITY.md` | MarketCountdown activity, scheduled-LA chaining, Dynamic Island layouts, watch mirroring |
| `06-NEWS-AI.md` | ForexFactory/Finnhub/Exa clients, schemas, BriefingEngine + prompts, fallback chain, caching |
| `07-UI-UX-SPEC.md` | Screen-by-screen spec, SessionTimelineView, Liquid Glass application, onboarding, Learn layer, accessibility |
| `08-WIDGETS.md` | Home/lock widgets, timeline provider strategy, watch smart stack, deep links |
| `BUILD_PROMPT.md` | The master build prompt: constraints, milestones, acceptance criteria, QA |

Research references (verified 2026-07-21, cite rather than re-derive): `research/ios26-liquid-glass-swiftui.md`, `research/ios26-activitykit-alarmkit.md`, `research/market-sessions-and-notifications.md`, `research/news-and-ai-summaries.md`.

## 7. Author rules

1. Spine names verbatim; new vocabulary only via `PROPOSED ADDITIONS` header section.
2. Every Apple API mention must exist in a research file (cite it) — no memory-derived APIs. The iOS 27 exclusion list in `research/ios26-liquid-glass-swiftui.md` §7.4 is binding.
3. Real data (hours, holiday dates, schemas, prices) comes from research files; anything else is marked `UNVERIFIED`.
4. Swift code blocks must compile conceptually against the spine types — no phantom parameters.
5. Beginner/Pro differences stated explicitly wherever a surface differs.

---

## 8. Adopted amendments (2026-07-21, post-authoring reconciliation)

The `PROPOSED ADDITIONS` sections in docs 01–08 are hereby **ADOPTED as canonical**. Highlights (full definitions live in the owning doc):

**From 07 (UI/UX):** component names `NextEventHeroCard`, `OpenMarketsStrip`, `EconStrip`, `CountdownAccessoryBar`, `BudgetHealthRow`, `WeekScheduleTable`, `TimeReadoutChip`, `UpNextList`; new field `AppSettings.dismissedExplainerIDs: [String]`; TipKit usage for coach marks (standard iOS 17+; not research-verified → verify against SDK at build time).

**From 03/04 (Engine/Alerts):** decode structs `SessionsFile`/`MarketRecord`, `HolidaysFile`/`HolidayCalendarRecord`/`HolidayDay`/`ClosureKind`/`HolidayPolicy`, `KillzonesFile`/`KillzoneRecord`; `DayKey`, `SeedData`, constants `occurrenceScanPadding`, `statusLookaheadDays`; `PlannedNotification`/`PlannedAlarm` bodies; budget constants (56 scheduled / 8 reserve / 16-per-day / alarmBudget 16 / horizonDays 14 / 60s merge); category ids `OPEN_MARKET`, `ECON_EVENT`; action ids `VIEW_MARKET`, `MUTE_TODAY`, `MUTE_SERIES`; `MarketAlarmMetadata`, `alarmIDMap`, `muteTodayUntil`.

**From 02/06 (Architecture/News-AI):** `SettingsEnvelope` (versioned settings blob), `KeychainStore`, `settingsSchemaVersion`; `BriefingInput`, `BriefingDraft`, `RSSFallbackClient`, `HeadlineTagger`, `SourceStatus`, `ExaBudgetExceededError`, SettingsStore keys `offset.exa.*` (daily-cap counter, default cap 40/day).

**From 05/08 (Live Activity/Widgets):** `ActivityController` public API (`startOrUpdate(for:)`, `scheduleNextChain()`, `endAll()`, `reconcile()`, `currentPhase`); constants `maxSeamlessGap` (7h30m), `resumePreRoll` (60m), `staleGrace` (120s); `NextEventsPreviewRow`; `ActivityDebugPanel`; `OffsetWidgetEntry`, `WidgetEntryBuilder`, `widgetKind` constants, `DeepLinkRoute` enum, `widgetTimelineHorizon` (36h); concurrent Live Activities self-capped at 2 (system cap undocumented).

**Rulings on flagged conflicts:**
1. **Overlap glow is visible at BOTH Trader Levels** (overlap is beginner-comprehensible and user-selected); **killzone hatching remains Pro-only**. (Resolves 07's flag.)
2. **Overlap durations, canonical:** London–NY overlap = **4h in normal weeks, 5h during DST mismatch windows** (2026: Mar 8–29, Oct 25–Nov 1 · 2027: Mar 14–28, Oct 31–Nov 7) — research-verified; any earlier phrasing implying the reverse is void. Tests in 03 §7 encode these values.
3. **Holiday data horizon:** ships 2026–2027 (+ partial 2028 where verified), `validThrough = 2027-12-31`; app shows a gentle "holiday data expiring" nudge after that date.
4. **CME holidays:** `advisoryOnUSHolidays` policy (banner, no schedule mutation) — per-holiday hours UNVERIFIED.
5. **Duplicate suppression:** when a criticalAlarm and a notification target the same MarketEvent, the alarm wins and the notification slot is freed.
