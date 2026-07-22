# 02 — ARCHITECTURE

Targets, package layout, concurrency, data flow, persistence, background refresh, secrets, entitlements/Info.plist inventory, logging, build configurations. Names/types per `00-SPINE.md` (law). Requirements per `DECISIONS.md`. Apple-API claims cite the research files; anything not found there is marked **UNVERIFIED**.

Research shorthand used below: **[NEWS]** = `research/news-and-ai-summaries.md`, **[MKT]** = `research/market-sessions-and-notifications.md`, **[LA/AK]** = `research/ios26-activitykit-alarmkit.md`, **[GLASS]** = `research/ios26-liquid-glass-swiftui.md`.

---

## PROPOSED ADDITIONS (new vocabulary introduced by this doc)

| Name | Kind | Purpose |
|---|---|---|
| `SettingsEnvelope` | struct (OffsetKit/Storage) | Versioned wrapper persisted by `SettingsStore`: `{ schemaVersion: Int, settings: AppSettings }` |
| `KeychainStore` | type (OffsetKit/Storage) | Reads/writes the two API keys in the Keychain; performs the one-time Info.plist → Keychain migration at first launch |
| `settingsSchemaVersion = 1` | constant | Current `SettingsEnvelope.schemaVersion` |
| `SourceStatus` | enum | Per-source freshness/status surfaced as status rows — defined and owned by `06-NEWS-AI.md`; referenced here for the error philosophy |
| `RSSFallbackClient` | type (OffsetKit/News) | Keyless RSS headlines fallback — defined in `06-NEWS-AI.md` |

---

## 1. Topology

Three build products + one local Swift package, exactly per spine §2. Tree reproduced with responsibilities:

```
Offset/                                  (repo root)
├── Offset.xcodeproj
├── Config/
│   ├── Secrets.xcconfig                 GITIGNORED. FINNHUB_API_KEY, EXA_API_KEY (see §6)
│   └── Secrets.example.xcconfig         Committed template (see §6)
│
├── Offset/                              APP TARGET dev.offsetapp.offset — SwiftUI app.
│   │                                    Owns: all UI, the @MainActor @Observable stores,
│   │                                    BGTask registration, notification/alarm APPLY side,
│   │                                    Live Activity lifecycle (request/update/end).
│   ├── OffsetApp.swift                  @main. Scene setup; registers BOTH BGTask ids before
│   │                                    end of launch ([MKT] HALF2 §2); installs the
│   │                                    UNUserNotificationCenter delegate; runs KeychainStore
│   │                                    secrets bootstrap; reconciles orphan Live Activities
│   │                                    ([LA/AK] §A.5 "reconcile on every app launch").
│   ├── RootTabView.swift                Tab shell + bottom accessory (07 doc owns visuals).
│   ├── Features/
│   │   ├── Today/                       TodayView, dashboard cards, SessionTimelineView (interactive).
│   │   ├── Markets/                     MarketsListView, MarketDetailView.
│   │   ├── News/                        NewsFeedView, BriefingCardView (06 doc owns behavior).
│   │   ├── Alerts/                      AlertsView, AlertRuleEditorView, CriticalAlarmsSection (04 doc).
│   │   ├── Search/                      SearchView — markets, events, glossary.
│   │   └── Settings/                    SettingsView, ConventionsEditorView, TraderLevelPicker.
│   ├── Onboarding/                      OnboardingFlow — 4 screens (07 doc).
│   ├── Learn/                           GlossaryView, ExplainerCard, glossary.json.
│   ├── DesignSystem/                    OffsetTheme.swift, MarketChip, CountdownText, GlassHelpers.
│   └── Support/                         Haptics, Formatters, DeepLinkRouter (offset:// handling).
│
├── OffsetKit/                           LOCAL SPM PACKAGE — pure logic, fully unit-testable,
│   │                                    zero UI imports. This is where correctness lives.
│   ├── Package.swift                    swift-tools for Swift 6.2; default-isolation setting (§2).
│   ├── Sources/OffsetKit/
│   │   ├── Models/                      All spine §4 types. Sendable value types only.
│   │   ├── Engine/                      SessionScheduleEngine, OverlapCalculator, HolidayCalendar.
│   │   │                                Deterministic pure functions; no clocks, no singletons —
│   │   │                                `now` is always a parameter.
│   │   ├── Scheduling/                  NotificationPlanner, AlarmPlanner. PLAN ONLY: they return
│   │   │                                [PlannedNotification] / [PlannedAlarm] values; the app
│   │   │                                target applies them to UNUserNotificationCenter /
│   │   │                                AlarmManager (04 doc owns the apply step).
│   │   ├── News/                        ForexFactoryClient, FinnhubClient, ExaClient
│   │   │                                (+ proposed RSSFallbackClient). Actors owning URLSession
│   │   │                                + throttle/cap state (06 doc).
│   │   ├── AI/                          BriefingEngine, Summarizer protocol + 3 impls (06 doc).
│   │   ├── Storage/                     SettingsStore, CacheStore [SwiftData], AppGroup,
│   │   │                                + proposed KeychainStore, SettingsEnvelope.
│   │   └── Resources/                   sessions.json, holidays.json, killzones.json (03 doc).
│   └── Tests/OffsetKitTests/            Swift Testing: engine, DST fixtures, budgeter, decode tests.
│
├── OffsetWidgets/                       EXTENSION TARGET dev.offsetapp.offset.widgets —
│   │                                    WidgetKit widgets + Live Activity UI + AlarmKit
│   │                                    presentation. One extension hosts all of these
│   │                                    ([LA/AK] §B; §G.3: widget extension REQUIRED for
│   │                                    AlarmKit countdown presentations).
│   ├── OffsetWidgetsBundle.swift        WidgetBundle: widgets + MarketCountdownLiveActivity
│   │                                    + the AlarmAttributes ActivityConfiguration.
│   ├── MarketCountdownLiveActivity.swift  ActivityConfiguration(for: MarketCountdownAttributes.self) (05 doc).
│   ├── NextEventWidget.swift            systemSmall, systemMedium (08 doc).
│   ├── SessionTimelineWidget.swift      systemMedium, systemLarge (08 doc).
│   ├── AccessoryWidgets.swift           circular, rectangular, inline (08 doc).
│   └── AlarmPresentationSupport.swift   AlarmAttributes<…> Live Activity views (04/05 docs).
│
└── Shared/                              SOURCE FILES compiled into BOTH app + extension targets
    │                                    (target membership, not a framework).
    ├── MarketCountdownAttributes.swift  ActivityAttributes — MUST be byte-identical in both
    │                                    targets ([LA/AK] §A.1: "the same type must be compiled
    │                                    into BOTH the app target and the widget-extension target").
    ├── AlarmMetadata.swift              Concrete AlarmKit metadata type (05 doc names it).
    └── SharedConstants.swift            App Group id, BGTask ids, deep-link builders (offset://).
```

**Dependency rules (binding):**

1. `OffsetKit` imports Foundation, SwiftData, UserNotifications, AlarmKit, FoundationModels — **never SwiftUI, never WidgetKit, never ActivityKit** (spine §2). It must build and test on any Mac without a UI host.
2. App target and widget extension both link `OffsetKit`.
3. `ActivityAttributes` types cannot live in OffsetKit (they need `import ActivityKit`, which OffsetKit is forbidden). They live in `Shared/` with dual target membership. Same for the AlarmKit presentation metadata type.
4. UI-facing observable stores (`ScheduleStore`, `NewsStore`, `AlertsStore`, `ActivityController`, `RefreshCoordinator`) live in the **app target** (spine §4 end), each a thin façade over OffsetKit types.
5. The widget extension never talks to the network (Live Activity sandbox has no network — [LA/AK] §B; timeline widgets render from OffsetKit engine output + App Group caches only, 08 doc).
6. iOS 27 APIs are forbidden — the exclusion list in [GLASS] §7.4 is binding for every target.

---

## 2. Concurrency model

Spine §1: Swift 6.2, **Approachable Concurrency**, default `MainActor` isolation as a module setting, Xcode 26.6.

**Build settings.** Enable on the app target, the widget extension target, and the OffsetKit package:

- `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`

**UNVERIFIED:** these exact build-setting spellings are not in the research files. Instruction to the coding agent: set them via the Xcode 26.6 build-settings UI — the settings named **"Approachable Concurrency"** and **"Default Actor Isolation"** (Swift Compiler section) — and let Xcode write whatever the canonical keys are. For `OffsetKit/Package.swift`, use the Swift 6.2 SwiftPM equivalent (a `SwiftSetting` enabling default MainActor isolation; exact SwiftPM API name also **UNVERIFIED** — copy it from an Xcode 26.6 new-package template rather than from memory). Corroboration that default-MainActor modules are the Xcode 26 norm: [LA/AK] §G.3 notes that with "Xcode 26 default-MainActor modules" a cross-actor `AlarmMetadata` type must be marked `nonisolated`.

**What this means practically:**

| Layer | Isolation | Rules |
|---|---|---|
| UI stores (`ScheduleStore`, `NewsStore`, `AlertsStore`, `ActivityController`, `RefreshCoordinator`) | `@MainActor @Observable` (default isolation makes `@MainActor` implicit; write it anyway for clarity) | Own all mutable UI state. Views read them directly. They `await` OffsetKit calls. |
| OffsetKit Models + Engine + Scheduling | `nonisolated` Sendable value types (all spine §4 types are declared `Sendable`) | Pure functions: `(inputs, now) -> outputs`. No hidden clocks, no globals, no side effects. Explicitly mark types/functions `nonisolated` where the module default would drag them onto MainActor. |
| OffsetKit News clients (`ForexFactoryClient`, `FinnhubClient`, `ExaClient`) | `actor` | They hold state (URLSession, ETag/Last-Modified memory, throttle counters, Exa daily cap) → actors, per the "network clients are async/await actors where state is held" rule. |
| OffsetKit Storage (`SettingsStore`, `CacheStore`, `KeychainStore`) | `SettingsStore`/`KeychainStore`: `nonisolated` thin wrappers (UserDefaults/Keychain are their own sync). `CacheStore`: actor or `@MainActor` façade — 06/04 docs call it only via `await`. | Single writer discipline per §3 ownership table. |
| Shared/ ActivityAttributes + alarm metadata | `nonisolated` Codable values | Cross-target, cross-actor payloads ([LA/AK] §G.3 `nonisolated` gotcha). |

**Banned:** `DispatchQueue`, `Timer` for logic, semaphores, completion handlers. Time-driven UI uses `TimelineView` schedules and `Text(timerInterval:)`/`Text(_:style:)` which the system ticks without app runtime ([MKT] HALF2 §4; [LA/AK] §C). Background work is structured concurrency (`async let`, `TaskGroup`) launched from stores; BG task handlers wrap their work in a `Task` and call `setTaskCompleted` when done ([MKT] HALF2 §2 pattern).

**Testing consequence:** everything in OffsetKit is callable from Swift Testing without MainActor hops; engine determinism is asserted by passing fixed `now` values (03 doc fixtures).

---

## 3. Data flow

Two pipelines feed the app; both converge on the stores. Text diagram (arrows = data movement, `[AG]` = crosses the App Group boundary):

```
PIPELINE A — schedule (offline, deterministic)
  sessions.json + killzones.json + holidays.json      (OffsetKit/Resources, bundled)
        │ decode once at startup (03 doc)
        ▼
  SessionScheduleEngine  ◄── ConventionSettings (from AppSettings)
        │ occurrences / events / nextEvent / marketStatus
        ▼
  ScheduleStore (@MainActor, app target; re-derives on refresh signals)
        ├─► UI (Today, Markets, Search; TimelineView ticks)
        ├─► NotificationPlanner ─► [PlannedNotification] ─► apply: UNUserNotificationCenter (≤56, 04 doc)
        ├─► AlarmPlanner ──────► [PlannedAlarm] ─────────► apply: AlarmManager (.fixed only, 04 doc)
        ├─► ActivityController ─► Activity.request / update / end (05 doc)
        └─► WidgetKit timelines: the EXTENSION imports OffsetKit and runs
            SessionScheduleEngine itself from the same bundled JSONs;
            it reads AppSettings via [AG] UserDefaults (no engine output is
            serialized across — the engine is pure, both sides compute alike; 08 doc)

PIPELINE B — news & AI (network, cached, degradable)
  ForexFactory JSON ─► ForexFactoryClient ─► [EconEvent] ─┐
  Finnhub /news, /company-news ─► FinnhubClient ─► [Headline] ─┤
  RSS fallbacks ─► RSSFallbackClient ─► [Headline] ─────────┤
  Exa /search + /answer ─► ExaClient (enrichment + cloud summarizer) ─┤
        ▼                                                   ▼
  NewsStore (@MainActor) ──writes──► CacheStore (SwiftData, [AG] container)
        │                                 │
        │                                 ├─► econEvents feed BACK into Pipeline A:
        │                                 │   SessionScheduleEngine.events(…, econEvents:) → econ alerts
        │                                 ▼
        │                            BriefingEngine ─► Summarizer chain (06 doc) ─► Briefing
        │                                 │                    │
        ▼                                 ▼                    ▼
      News tab UI            CachedBriefing [AG]     "Your Offset briefing is ready"
                                     │                (standard notification, 06 §6)
                                     └─► widget extension reads cache read-only [AG]
```

**Ownership table — who may WRITE what** (single-writer rule; everyone else reads):

| Store / resource | Sole writer | Readers |
|---|---|---|
| `SettingsStore` (App Group UserDefaults) | App target only: Settings/Onboarding UI via `AlertsStore`/settings views; `ExaClient` daily-cap counter keys (06 doc) | All app stores; widget extension (read-only) |
| `CacheStore` (SwiftData, App Group) | `NewsStore` (headlines, econ events) and `BriefingEngine` via NewsStore (briefings) — app target/process only | News UI; `SessionScheduleEngine` inputs; widget extension (read-only, §4) |
| Pending notification set | The apply step invoked by `RefreshCoordinator` (04 doc) | `AlertsStore` budget-health row reads `pendingNotificationRequests()` [MKT] HALF2 §1 |
| AlarmKit alarms | Apply step from `AlertsStore` (04 doc); reconciled via `alarmUpdates` [LA/AK] §G.2 | AlertsView |
| Live Activities | `ActivityController` only (05 doc) | Widget extension renders |
| `KeychainStore` keys | `KeychainStore` bootstrap + Settings paste-in UI | News clients |
| Seed JSONs, `glossary.json` | Nobody at runtime (bundled, read-only) | Engine, Learn |

---

## 4. Persistence

### 4.1 SettingsStore — App Group UserDefaults

- Container: `UserDefaults(suiteName: "group.dev.offsetapp.offset")` (id from spine §1, exposed via `SharedConstants` / `AppGroup`).
- Stored value: **one JSON blob** under key `"offset.settings.v-envelope"`: `SettingsEnvelope { schemaVersion: Int, settings: AppSettings }` encoded with `JSONEncoder`. `AppSettings` is the spine §4 struct, verbatim.
- Plus a small set of flat operational keys (NOT inside the blob, so widget/extension reads stay cheap and the blob stays user-intent-only): Exa daily-cap counters and last-refresh timestamps — key names defined in 06 §4 and 04 doc.
- `schemaVersion` starts at `settingsSchemaVersion = 1`.

**Migration policy:**
1. Decode `SettingsEnvelope`. If `schemaVersion == current` → done.
2. If lower → run stepwise migration functions `migrate1to2`, `migrate2to3`, … (pure functions in OffsetKit/Storage, unit-tested), then re-save.
3. If higher (downgrade) or decode fails → copy the raw blob to key `"offset.settings.quarantine"`, reset to `AppSettings` defaults (spine §4 defaults), log `refresh`-category error, surface a one-line status row in Settings ("Settings were reset"). Never crash, never modal.
4. Widget extension NEVER migrates — if it sees an unknown version it falls back to defaults for that render pass only.

### 4.2 CacheStore — SwiftData in the App Group container

`ModelContainer` whose store URL lives in the App Group container directory (via `AppGroup`), so app and widget extension open the same store. **UNVERIFIED:** exact SwiftData configuration API for placing a store in an App Group and for read-only opening is not in the research files — the coding agent must take the `ModelConfiguration` spelling from Xcode 26.6 SwiftData docs. Enforce read-only in the extension by convention regardless: extension code contains no insert/save calls.

`@Model` classes mirror spine structs; conversion is a pure mapping (SwiftData classes never leak past CacheStore — clients and UI see spine value types only):

```swift
@Model final class CachedHeadline {                 // ↔ Headline (spine §4)
    @Attribute(.unique) var id: String              // UNVERIFIED exact attribute spelling — Xcode 26.6 docs
    var title: String; var source: String
    var urlString: String                           // Headline.url.absoluteString
    var publishedAt: Date
    var summary: String?                            // filled after AI summarization (06 §4/§5)
    var relatedRaw: [String]                        // [MarketID.rawValue]
    var fetchedAt: Date
}
@Model final class CachedEconEvent {                // ↔ EconEvent (spine §4)
    @Attribute(.unique) var id: String              // deterministic id (06 §2)
    var title: String; var currency: String
    var date: Date
    var impactRaw: String                           // EconImpact.rawValue
    var forecast: String?; var previous: String?
    var fetchedAt: Date
}
@Model final class CachedBriefing {                 // ↔ Briefing (spine §4)
    @Attribute(.unique) var key: String             // "yyyy-MM-dd|<traderLevel>" device-local day (06 §6)
    var generatedAt: Date
    var traderLevelRaw: String; var providerRaw: String
    var headline: String
    var bullets: [String]; var watchouts: [String]
}
```

**Retention (pruned by CacheStore on every write pass and on `NSCalendarDayChanged`):**

| Model | Keep | Rationale |
|---|---|---|
| `CachedHeadline` | `publishedAt` within last **3 days** | Feed freshness; keeps store tiny |
| `CachedEconEvent` | events dated from start of **current week** through end of **next week** | Feed horizon is this-week-only ([NEWS] §3 — `nextweek` variant 404s), so future rows beyond that never exist; keeping the full current week preserves "earlier today/this week" context |
| `CachedBriefing` | last **7** by `key` date | Re-open history; pull-to-refresh replaces same-day key |

Failure stance: econ cache remains usable for up to 7 days when fetches fail (06 §2), with a `SourceStatus` stale row — persistence never blocks the schedule pipeline, which is fully offline.

---

## 5. RefreshCoordinator

App-target `@MainActor @Observable` store owning all refresh choreography. Foreground refresh is the **primary** mechanism; BG tasks are opportunistic top-up only — Apple: "the system doesn't guarantee launching the task"; realistic cadence is "a few times/day for a daily-used app; possibly days apart or never for a rarely-used one" ([MKT] HALF2 §2 — cited verbatim; design accordingly, never load-bearing).

### 5.1 BGTaskScheduler registrations

| BGTask id (spine §1) | Request type | Work (must fit ~30 s — BGAppRefreshTask is "for short-duration tasks", [MKT] HALF2 §2) |
|---|---|---|
| `dev.offsetapp.offset.refresh.schedule` | `BGAppRefreshTaskRequest` | 1. Re-submit next request (always first). 2. `ScheduleStore` re-derive. 3. NotificationPlanner → apply ≤56 pending (04 doc). 4. AlarmPlanner reconcile (04 doc). 5. `ActivityController` maintenance: roll Live Activity phase/`staleDate`, pre-schedule next scheduled LA (05 doc; update/end from background is allowed — [LA/AK] §A.4). |
| `dev.offsetapp.offset.refresh.news` | `BGAppRefreshTaskRequest` | 1. Re-submit next request. 2. If econ cache older than 6 h → ForexFactoryClient fetch. 3. If headlines older than 2 h → FinnhubClient fetch (throttled, 06 §3). 4. If now is within ±45 min of `AppSettings.briefingTime` and today's `CachedBriefing` is missing → BriefingEngine generate + post "briefing ready" notification (06 §6). 5. Rebuild econ-dependent notifications if events changed. |

Policy: register both ids in `OffsetApp.swift` **before end of app launch** ([MKT] HALF2 §2); `earliestBeginDate = now + 4 h`; re-submit at the START of each handler and also on every foreground pass (resubmitting replaces the previous request — [MKT] HALF2 §2). Set an expiration handler that cancels in-flight network work and completes.

### 5.2 System change signals → actions

Observed on the root view via `.onReceive(NotificationCenter.default.publisher(for:))` ([MKT] HALF2 §2 table; actions mapped to Offset components):

| Signal | Fires when ([MKT] HALF2 §2) | RefreshCoordinator actions |
|---|---|---|
| `scenePhase == .active` | Foreground (PRIMARY refresh) | Full pass: ScheduleStore re-derive → notification rebuild → alarm reconcile → LA reconcile/start (05 doc) → stale-based news fetch → briefing catch-up (06 §6) → re-submit both BG requests |
| `UIApplication.significantTimeChangeNotification` | New day at midnight, carrier time update, DST change; redelivered on foreground if missed | Everything: occurrences, countdown baselines, full pending-notification rebuild ("DST just moved wall clocks") |
| `NSSystemTimeZoneDidChange` | Device time zone changed (travel/settings) | `TimeZone.resetSystemTimeZone()` first; drop cached Calendars; re-derive all device-local display strings; full pending rebuild; LA content refresh |
| `NSCalendarDayChanged` | Day flip ("no guarantees about timeliness") | "Today/tomorrow" labels; roll 7-day horizon; top-up notification window; CacheStore retention prune; reset Exa daily counter (06 §4) |

---

## 6. Secrets pipeline

Per the research-cited recommendation ([NEWS] §5 "API key storage"): gitignored xcconfig → build settings → Info.plist → read once at startup → Keychain.

1. `Config/Secrets.xcconfig` (gitignored) defines `FINNHUB_API_KEY` and `EXA_API_KEY`. Attached as base configuration to app-target Debug and Release configs.
2. App-target Info.plist declares two keys whose values are build-setting substitutions: `FINNHUB_API_KEY = $(FINNHUB_API_KEY)`, `EXA_API_KEY = $(EXA_API_KEY)` ([NEWS] §5: "inject into Info.plist (`$(EXA_API_KEY)`) → read via `Bundle.main` at launch").
3. First launch: `KeychainStore` bootstrap reads both from `Bundle.main`, writes them to the Keychain with `kSecAttrAccessibleAfterFirstUnlock` ([NEWS] §5), then all clients read exclusively from `KeychainStore`. Subsequent launches skip the bundle read unless the Keychain is empty or the bundle value changed (key rotation path).
4. Missing/blank keys are legal: Finnhub features and Exa summarization silently degrade with `SourceStatus` rows (06 doc). The app must fully function with zero keys (schedule pipeline is offline).

**Tradeoff, documented honestly ([NEWS] §5):** anything in Info.plist/bundle is extractable from an .ipa; Keychain-after-first-read narrows exposure but a proxy is the only true fix and is **overkill for a personal, non-distributed app**. Mitigations instead: dedicated Exa key, dashboard spend/usage alerts, rotate if leaked. The research names an equally-fine alternative — a paste-your-key Settings screen straight to Keychain (keeps keys out of the bundle entirely); Settings SHOULD include this as an override field, which also covers key rotation without rebuilds. Widget extension gets **no** keys (it never networks, §1 rule 5).

`Config/Secrets.example.xcconfig` (committed):

```
// Copy this file to Secrets.xcconfig (same folder) and fill in real values.
// Secrets.xcconfig is gitignored — never commit real keys.
// No quotes. // starts a comment in xcconfig, so keys must not contain //.
FINNHUB_API_KEY = your_finnhub_key_here
EXA_API_KEY = your_exa_key_here
```

---

## 7. Entitlements & Info.plist inventory

Complete inventory for BOTH targets. "Capability" rows are added via Xcode Signing & Capabilities (which writes the .entitlements file).

### 7.1 App target `dev.offsetapp.offset`

| # | Item | Kind | Value | Source / notes |
|---|---|---|---|---|
| 1 | App Groups | Entitlement (capability) | `group.dev.offsetapp.offset` | Spine §1. Add via Xcode capability UI; exact entitlement key string not in research — **UNVERIFIED**, let Xcode write it |
| 2 | Time Sensitive Notifications | Entitlement (capability) | enabled | Required or `.timeSensitive` silently downgrades to `.active` ([MKT] HALF2 §1). Research: capability VERIFIED as the Xcode toggle setting `com.apple.developer.usernotifications.time-sensitive = true`; Apple's entitlements doc index currently has **no standalone page** for this key — do not hunt for one |
| 3 | Background Modes → Background fetch | Capability | enabled | Required for `BGAppRefreshTaskRequest` ([MKT] HALF2 §2) |
| 4 | `NSSupportsLiveActivities` | Info.plist Bool | `YES` | Required or `Activity.request` fails ([LA/AK] §A.6). No special entitlement exists for Live Activities ([LA/AK] §A.6) |
| 5 | `NSSupportsLiveActivitiesFrequentUpdates` | Info.plist Bool | `YES` (optional in v1 — only lifts the **push** update budget; v1 is pushless) | Exact spelling per [LA/AK] §A.6, **with Apple-docs-typo warning**: the `ActivityAuthorizationInfo` overview page misspells it `NSSupportsFrequentLiveActivityUpdates`; the BundleResources reference and push article use `NSSupportsLiveActivitiesFrequentUpdates` — **use that spelling** |
| 6 | `NSAlarmKitUsageDescription` | Info.plist String | `"Offset uses alarms so market events you mark as critical can sound even in Silent mode or a Focus."` | Missing/empty ⇒ AlarmKit scheduling **always fails** ([LA/AK] §G.1) |
| 7 | `BGTaskSchedulerPermittedIdentifiers` | Info.plist Array | `[dev.offsetapp.offset.refresh.schedule, dev.offsetapp.offset.refresh.news]` | Ids from spine §1; key required by BGTaskScheduler ([MKT] HALF2 §2) |
| 8 | URL scheme `offset://` | Info.plist (`CFBundleURLTypes`) | scheme `offset` | Spine §1; deep links `offset://today`, `market/{id}`, `news/briefing`, `alerts` (DECISIONS). Standard key; exact structure not re-verified in research — **UNVERIFIED**, use Xcode's Info tab URL Types editor |
| 9 | `FINNHUB_API_KEY`, `EXA_API_KEY` | Info.plist Strings | `$(FINNHUB_API_KEY)`, `$(EXA_API_KEY)` | §6 pipeline ([NEWS] §5) |
| 10 | ATS | Info.plist | **no `NSAppTransportSecurity` key** (default) | All endpoints are https: `api.exa.ai`, Finnhub, `nfs.faireconomy.media`, RSS hosts ([NEWS] §1–3 probes). No exceptions needed |
| 11 | Push Notifications | Capability | **NOT added** | v1 has no push; only needed for LA push updates ([LA/AK] §A.6) |
| 12 | Notifications permission | Runtime | `UNUserNotificationCenter` authorization at onboarding (04 doc) | Not a plist key; listed to complete the inventory |
| 13 | AlarmKit authorization | Runtime | `AlarmManager.requestAuthorization()` (04 doc) | Prompted lazily; auto-prompts on first `schedule` if never called ([LA/AK] §G.1) |

### 7.2 Widget extension target `dev.offsetapp.offset.widgets`

| # | Item | Kind | Value | Source / notes |
|---|---|---|---|---|
| 1 | App Groups | Entitlement (capability) | `group.dev.offsetapp.offset` (same group) | Reads settings + caches (§4). Same UNVERIFIED-key note as app row 1 |
| 2 | Extension point plumbing (`NSExtension` / WidgetKit extension point) | Info.plist | As generated by the Xcode widget-extension template | Do not hand-edit; not re-verified in research — **UNVERIFIED** beyond "Xcode generates it" |
| 3 | `NSSupportsLiveActivities` | Info.plist | **Not required here** — research documents it for the app target ([LA/AK] §A.6/H.3) | Harmless if the template adds it; do not rely on it |
| 4 | Everything else | — | **None**: no BGTask ids, no AlarmKit usage string (alarms are scheduled by the app; the extension only renders presentations, [LA/AK] §G.3), no URL scheme, no API keys, no Background Modes | §1 rules |

Both targets: bundle ids and Team per spine §1 placeholders (`YOURTEAMID`). DECISIONS note: paid Apple Developer account strongly recommended (free provisioning expires every 7 days and complicates entitlements).

---

## 8. Logging & errors

**OSLog** (framework in spine §1 dependency list). Single subsystem, per-area categories:

| Subsystem | Category | Emitted by |
|---|---|---|
| `dev.offsetapp.offset` | `engine` | SessionScheduleEngine facade, HolidayCalendar (derivation anomalies, seed-decode issues) |
| `dev.offsetapp.offset` | `alerts` | NotificationPlanner/AlarmPlanner apply steps, budget decisions, permission changes |
| `dev.offsetapp.offset` | `activity` | ActivityController lifecycle, scheduled-LA chaining, orphan cleanup |
| `dev.offsetapp.offset` | `news` | ForexFactory/Finnhub/RSS fetches, decode failures, cache prunes |
| `dev.offsetapp.offset` | `ai` | Summarizer selection, FoundationModels availability transitions, Exa calls + `costDollars`, cap events |
| `dev.offsetapp.offset` | `refresh` | BG task submit/launch/expiry, system change signals, migration events |

Rules: one `Logger` per category held by the owning component (standard OSLog usage; no exotic API claims — OSLog specifics are not covered by the research files). Never log secrets, full headline bodies, or user settings blobs; log counts, ids, durations, and error descriptions. Widget extension logs under the same subsystem, category `refresh` prefix `widget:`.

**User-facing error philosophy — silent degradation + status rows:**

- Background failures NEVER present modals, alerts, or badges. The UI always renders from the last good cache/engine state.
- Each degradable source surfaces a one-line `SourceStatus` row where the user would notice the gap (06 doc owns the enum + copy): News tab ("Headlines last updated 07:12", "Daily AI budget used — template briefing"), Today briefing card ("Offline — showing yesterday's briefing"), Alerts tab (budget health + permission status rows, 04 doc).
- Interactive actions (pull-to-refresh, tapping "summarize") may show inline transient failure states on the touched element — still never modal.
- The only modal-ish surfaces allowed: system permission prompts, and onboarding's permission explainers.

**Debug menu** (`#if DEBUG` only, hidden Settings row): force schedule/news refresh, simulate `significantTimeChange`, override "now" for engine preview, summarizer override picker (force onDevice/exa/template), dump pending notifications + alarms + activities, reset Exa daily counter, reset settings (with quarantine), decode-fixture re-run. Never compiled into Release (`#if DEBUG` around the whole feature; the flag ships in the Debug config only, §9).

---

## 9. Build configurations

| Config | Swift flags | Purpose |
|---|---|---|
| Debug | `DEBUG` compilation condition (Xcode default) → enables `#if DEBUG` dev menu §8; assertions on | Day-to-day dev; simulator + device |
| Release | no `DEBUG`; optimizations on | Personal install builds (Xcode → device, DECISIONS distribution) |

- `Config/Secrets.xcconfig` is set as base configuration for both configs of the app target (§6). If missing, the build still succeeds with empty substitutions → app runs keyless-degraded; add an `#warning`-level build-phase script that prints a reminder when the file is absent (script, not a hard error — first-clone friendliness).
- Both configs build all three products; OffsetKit tests run with Swift Testing (`swift test` inside the package, or the Xcode test plan).

**Simulator vs device notes:**

| Area | Simulator | Device (iPhone 14 Pro Max) |
|---|---|---|
| Engine, UI, widgets, snapshot rendering | Fine | Fine |
| Live Activities / Dynamic Island | Basic rendering exists, but scheduled-LA start behavior with the app terminated is **UNVERIFIED** even on device — docs only guarantee background start; research says "test on device" ([LA/AK] §A.2, §H.1 point 2). Treat simulator results as non-evidence | Required for real fidelity: DI presentations, StandBy, Always-On, Watch mirroring (needs paired watch) |
| AlarmKit | Break-through of Silent/Focus, reboot survival, and full-screen alert surfaces are device behaviors ([LA/AK] §G.4). Simulator support level is not in research — **UNVERIFIED**; validate every alarm scenario on device | Required for acceptance tests (04 doc QA) |
| BGAppRefreshTask | Scheduling is usage-pattern driven and opportunistic ([MKT] HALF2 §2); simulator won't exercise realistic cadence | Use the debug menu forced-refresh paths for QA rather than waiting on the scheduler |
| FoundationModels | n/a for runtime behavior on this project's device anyway: iPhone 14 Pro Max returns `.unavailable(.deviceNotEligible)` ([NEWS] §4 device list — 15 Pro+ only) → Exa path is the runtime default. Keep the on-device path compiling for future devices | Same |
| Notifications (time-sensitive) | Delivery/Focus interaction best verified on device | Required for 04 doc QA |

Acceptance stance for the coding agent: anything involving AlarmKit, Live Activity chaining, or time-sensitive delivery gets its final check on the physical device; simulator green is necessary but not sufficient.

---

*Cross-references: 03 (seed JSONs + engine), 04 (apply steps + budgeter + permissions), 05 (ActivityController + chaining), 06 (news/AI clients, SourceStatus, briefing), 07 (UI), 08 (widgets). Research: [NEWS] §1–5, [MKT] HALF2 §1–4, [LA/AK] §A–H, [GLASS] §7.4.*
