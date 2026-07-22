# BUILD_PROMPT.md — Build "Offset" end-to-end

## 0. Mission

You are a senior iOS engineer agent. Build **Offset** — a session-aware trading clock for iPhone — completely, from empty repo to a polished, installable app, following the spec documents in `docs/` exactly.

Offset, in one paragraph: every major market's opens, closes, overlaps and killzones — Forex sessions (Sydney/Tokyo/London/New York), NYSE/Nasdaq with extended hours, LSE, and CME Globex — converted to the user's local time with DST handled *correctly* (including the weeks where New York and London shift on different dates), alerted reliably through notifications and AlarmKit hard alarms, counted down live in the Dynamic Island via a serverless scheduled-Live-Activity chain, with an AI-generated daily briefing and headline summaries. One user, two faces: a Beginner mode that teaches session structure in plain language, and a Pro mode with killzones and editable conventions. iOS 26 Liquid Glass native from the first pixel.

The owner's device is an **iPhone 14 Pro Max** (Dynamic Island: yes; Apple Intelligence: no — the Exa cloud summarizer is the primary AI path at runtime; the on-device FoundationModels path must still be built and auto-selected when available).

## 1. Inputs — read before writing any code

Read in this order. **Precedence on any conflict: `DECISIONS.md` > `00-SPINE.md` > area docs (01–08) > `research/*`. Log every conflict you resolve in `BUILDLOG.md`.**

| # | File | What it gives you |
|---|---|---|
| 1 | `docs/DECISIONS.md` | Requirements + decisions (highest authority) |
| 2 | `docs/00-SPINE.md` | Canonical names, types, market data, file tree, tab map, §8 amendments. **Names are law — verbatim.** |
| 3 | `docs/01-PRODUCT-SPEC.md` | Vision, personas, feature inventory, user stories w/ acceptance criteria |
| 4 | `docs/02-ARCHITECTURE.md` | Targets, package, concurrency, persistence, secrets, entitlements/Info.plist inventory, logging |
| 5 | `docs/03-SESSION-ENGINE.md` | Seed JSONs (real dates — ship verbatim), materialization algorithm, DST rules, engine test plan |
| 6 | `docs/04-ALERTS-NOTIFICATIONS.md` | Notification pipeline, 64-cap budgeter, AlarmKit integration, default rules, permission UX |
| 7 | `docs/05-LIVE-ACTIVITY.md` | MarketCountdown activity, scheduled-LA chaining, Dynamic Island layouts, watch mirroring |
| 8 | `docs/06-NEWS-AI.md` | ForexFactory/Finnhub/Exa clients + schemas, summarizer chain, **the actual AI prompts**, cost caps |
| 9 | `docs/07-UI-UX-SPEC.md` | Screen-by-screen spec, SessionTimelineView, Liquid Glass rules, copywriting templates, a11y bar |
| 10 | `docs/08-WIDGETS.md` | Widget inventory, TimelineProvider strategy, deep links |
| 11 | `research/*.md` (4 files) | Verified API ground truth with sources. Cite-only — do not re-derive from memory. |

## 2. Hard constraints — non-negotiable

1. **Toolchain**: Xcode 26.6, iOS 26.0 deployment target, iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), portrait-primary. Swift 6.2 with **Approachable Concurrency** and **default MainActor isolation** enabled per `02-ARCHITECTURE.md` §2 (exact build-setting names: use the Xcode 26.6 build-settings UI names; the docs' spellings are flagged UNVERIFIED — verify and record in BUILDLOG).
2. **Zero third-party dependencies.** First-party frameworks only: SwiftUI, SwiftData, WidgetKit, ActivityKit, AlarmKit, UserNotifications, BackgroundTasks, FoundationModels, TipKit, OSLog, AppIntents.
3. **iOS 27 API exclusion list is binding** (`research/ios26-liquid-glass-swiftui.md` §7.4). Those symbols do not compile on Xcode 26.6. Never use them.
4. **UNVERIFIED handling**: docs mark claims that couldn't be verified against primary sources. When you hit one, verify against the actual SDK/behavior at hand, adapt *minimally*, and record the resolution (exact symbol found, what you changed) in `BUILDLOG.md`. Never delete a feature because an UNVERIFIED detail differed — redesign the smallest possible surface around reality.
5. **File tree and naming per `00-SPINE.md` §2/§4/§8** — verbatim. `OffsetKit` never imports SwiftUI/WidgetKit. `MarketCountdownAttributes` lives in `Shared/` compiled into both targets, byte-identical.
6. **Liquid Glass discipline**: glass on controls/navigation layer only (tab bar, toolbars, `CountdownAccessoryBar`); content uses standard materials. Zero custom `.glassEffect` on content cards.
7. **Seed data is real data**: ship `sessions.json`, `holidays.json` (2026–2027 NYSE/LSE incl. half-days), `killzones.json` exactly as written in `03-SESSION-ENGINE.md` §2. Do not invent or trim dates.
8. **Time is sacred**: all session math = wall-clock + IANA zone, materialized per-occurrence via `Calendar` with explicit `timeZone`. No fixed UTC offsets anywhere. No `Date` arithmetic across zone boundaries. The DST test fixtures in `03` §7 are the definition of correct.
9. **Secrets**: `Config/Secrets.xcconfig` (gitignored) with `FINNHUB_API_KEY`, `EXA_API_KEY`; commit `Secrets.example.xcconfig`. **The app must run fully with keys absent** — engine, alerts, Live Activity, widgets all work; news/AI surfaces degrade to `TemplateSummarizer` + status rows. Never crash or block on missing keys.
10. **Accessibility is ship-blocking**: Dynamic Type through XL, VoiceOver labels (timeline bands per `07` §4), Reduce Transparency / Increase Contrast fallbacks, color+pattern (never color alone) for market differentiation.
11. **Copy discipline**: notification and UI copy comes from `07` §5 templates (Beginner and Pro variants). AI prompts come from `06` §5 verbatim.
12. **No scope creep.** v1.1 items in `01-PRODUCT-SPEC.md` stay unbuilt. If you're tempted, write it in `BUILDLOG.md` under "Deferred temptations".

## 3. Project setup reality (M0)

Xcode target/capability setup is GUI-bound. If a human is available, hand them this 15-minute checklist and wait; if you can author the `.xcodeproj` yourself, follow the same checklist programmatically and verify with `xcodebuild -list`.

**M0 checklist:**
1. New iOS App project `Offset` (SwiftUI, Swift), org identifier `dev.offsetapp` (owner may substitute — then update `SharedConstants` + App Group + BGTask ids consistently).
2. Add Widget Extension target `OffsetWidgets` (include Live Activity: yes; configuration intent: no).
3. Add local Swift package `OffsetKit` (path `./OffsetKit`); link to both targets.
4. Create `Shared/` group; add to **both** target memberships.
5. Capabilities — app target: App Groups (`group.dev.offsetapp.offset`), Time Sensitive Notifications, Background Modes (Background fetch + Background processing). Widget target: App Groups (same group).
6. Info.plist entries per `02-ARCHITECTURE.md` §7 (NSSupportsLiveActivities, frequent-updates key — exact spelling per research, NSAlarmKitUsageDescription with the user-facing string from 02, BGTaskSchedulerPermittedIdentifiers array, `offset://` URL scheme).
7. Wire `Config/Secrets.xcconfig` into build configurations; add `.gitignore` (Secrets.xcconfig, xcuserdata, build artifacts).
8. Set deployment target 26.0 on all targets; enable the concurrency settings from §2.1.

**M0 acceptance**: project builds; app boots to an empty `RootTabView` with 5 tabs; `xcodebuild -list` shows both targets; OffsetKit test target runs (one placeholder test).

## 4. Milestones

Work strictly in order. Each milestone ends with: all listed acceptance criteria met, tests green, a `BUILDLOG.md` entry, and (if git is available) a commit `M{n}: <summary>`.

### M1 — Models + seed data (OffsetKit)
Build: every type in `00-SPINE.md` §4 + §8 (models, enums, decode structs); bundle and decode the three seed JSONs from `03` §2.
Accept: decode tests pass for all three files; `Market` catalog exposes all 7 markets with correct zones/colors/symbols; `WallClockTime` Comparable behavior tested.

### M2 — SessionScheduleEngine (the heart)
Build: `occurrences(in:markets:conventions:)`, `events(in:settings:econEvents:)`, `nextEvent(after:...)`, `marketStatus(at:...)`, structural `OverlapCalculator`, killzone materialization, `HolidayCalendar` (full + half days), CME `wrapsMidnight` handling, FX week markers, stable deterministic `MarketEvent.id` scheme per `03` §4.
Accept: **the entire named test list in `03` §7 is implemented and green** — including: normal-week London open conversion; 2026 mismatch windows produce **5h** overlap; normal weeks produce **4h**; NYSE holiday drop + 2026-11-27 half-day truncation; LSE 2026-12-24 12:30 half-day; CME Sun open/Fri close/daily break; killzone across a DST boundary; event-id determinism. Engine is pure (no singletons, no I/O) — property verified by tests using injected fixture dates.

### M3 — Stores, settings, refresh skeleton
Build: `SettingsStore` (App Group UserDefaults, `SettingsEnvelope` + `settingsSchemaVersion`), `CacheStore` (SwiftData in App Group container; models per `02` §4), `ScheduleStore` (@MainActor @Observable engine facade), `RefreshCoordinator` (BGTask registration for both ids, foreground refresh, system clock/zone/day-change observers per `02` §5 actions table), `KeychainStore` + secrets pipeline.
Accept: settings round-trip test; migration stub test; BG tasks registered without crash (simulator log line); zone-change simulation recomputes schedule (unit-level).

### M4 — Notifications
Build: `NotificationPlanner` (≤56 + 8 reserve + per-day caps + priority order per spine §4 + dedupe vs alarms), default `AlertRule` set (Beginner defaults per `04` §2), categories/actions, permission priming flow, rebuild-on-every-trigger wiring, `.timeSensitive` usage per `04` §4.
Accept: budgeter unit tests (priority, caps, degradation, idempotent rebuild, identifier = MarketEvent.id); on simulator: schedule + fire a near-term notification with category actions working; AlertsView budget math exposed via `BudgetHealthRow` data (UI lands in M7).

### M5 — Live Activity (Dynamic Island)
Build: `MarketCountdownAttributes` in `Shared/`; `MarketCountdownLiveActivity` widget with ALL presentations per `05` §3 (compact leading/trailing, minimal, expanded regions, lock screen, luminance-reduced, watch `.small` via `supplementalActivityFamilies`); `ActivityController` (@MainActor @Observable; `startOrUpdate/scheduleNextChain/endAll/reconcile`); serverless chaining per `05` §2 (schedule next on background; reconcile on foreground; weekend end behavior; `staleGrace`; self-cap 2 concurrent).
Accept: on simulator — activity starts, compact trailing countdown fits and ticks with zero updates, expanded layout matches spec, stale state renders; chain unit tests (pure planning parts); device-QA checklist from `05` §7 written into BUILDLOG as pending-manual items.

### M6 — AlarmKit critical alarms
Build: `AlarmPlanner` (fixed-date only, horizon 14 days, `alarmBudget` 16), authorization at first critical-alarm creation (never onboarding), countdown pre-alert presentation via widget extension per `05`/`04`, `MarketAlarmMetadata`, cancellation on rule disable, duplicate-suppression (alarm wins, notification slot freed).
Accept: alarm schedules on device/sim without error; auth flow states handled (denied → inline guidance); planner unit tests (fixed dates in market zones, horizon, budget).

### M7 — The app itself (UI)
Build per `07`, in this order: `OffsetTheme` + DesignSystem components → `RootTabView` (`.tabBarMinimizeBehavior(.onScrollDown)`, `Tab(role: .search)`, `CountdownAccessoryBar` via `.tabViewBottomAccessory` with collapse adaptation + hidden-when-closed) → `SessionTimelineView` (full spec `07` §4: lanes, bands, now-needle, overlap glow both levels, killzone hatching Pro, scrub on Pro, VoiceOver semantics, widget-render variant) → TodayView (hero, strips, briefing card) → Markets list/detail → AlertsView + rule editor + `BudgetHealthRow` + permissions dashboard → SettingsView (+ TraderLevelPicker, ConventionsEditorView Pro-gated) → SearchView → OnboardingFlow (4 screens per `07` §3) → Learn/GlossaryView + ExplainerCards + TipKit coach marks → `DeepLinkRouter`.
Accept: every screen's acceptance criteria from `01` user stories that don't require news/widgets; Beginner↔Pro toggle transforms all gated surfaces live; Dynamic Type XL pass; Reduce Transparency pass; dark + light modes; zero glass on content.

### M8 — News + AI
Build per `06`: `ForexFactoryClient` (schema + timezone-pinned parsing + polling + stale tolerance), `FinnhubClient` (throttled), `RSSFallbackClient`, `HeadlineTagger`, `ExaClient` (/search + /answer with outputSchema; daily cap 40 + `ExaBudgetExceededError`), `Summarizer` chain (FoundationModels → Exa → Template; availability-driven; prompts verbatim from `06` §5), `BriefingEngine` + scheduling + "briefing ready" notification, News tab UI + `EconStrip` on Today, `SourceStatus` rows.
Accept: decode-fixture tests for all three sources; chain-selection tests (mock availability: on 14 Pro Max expect `.exa`; keys absent expect `.template`); cap counter tests; UI: briefing renders in both Trader Level voices; app fully functional with no keys.

### M9 — Widgets + final polish
Build per `08`: `NextEventWidget` (S/M), `SessionTimelineWidget` (M/L), `AccessoryWidgets` (circular/rectangular/inline), providers with event-boundary + hourly entries (36h horizon), `WidgetCenter` reload wiring in RefreshCoordinator, `widgetURL` deep links; then polish: haptics vocabulary (`07` §6), empty/error states everywhere, `ActivityDebugPanel` + dev menu (#if DEBUG), app icon via Icon Composer (layered `.icon`; provide the layer design described in `07` §1 — if Icon Composer is unavailable in your environment, generate the flat fallback set and log it), final a11y audit, BUILDLOG completeness.
Accept: all widgets render in gallery + lock screen vibrant mode; deep links route correctly from cold start; full `01` acceptance-criteria sweep; Definition of Done (§7) all checked.

## 5. Verification

- Unit tests: `xcodebuild test -scheme Offset -destination 'platform=iOS Simulator,name=iPhone 16 Pro'` (or the newest available iOS 26.x simulator — record which in BUILDLOG). OffsetKit engine tests must not require the app host.
- Required test inventory: `03` §7 complete list · budgeter suite (`04` §3) · planner/alarm suites · decode fixtures (`06` §8) · summarizer-chain + cap tests · settings round-trip/migration.
- Build hygiene: zero warnings target; no `@unchecked Sendable` without a BUILDLOG justification; OSLog subsystems per `02` §8 (no `print`).

**Manual device QA (owner's iPhone 14 Pro Max) — write as a checklist into BUILDLOG for the owner:**
1. Notification fires at a real London open with correct dual-time subtitle; Mute Today action works.
2. `.timeSensitive` breaks through a Focus; standard doesn't.
3. Critical alarm breaks Silent mode; full-screen presentation; pre-alert countdown appears in the island.
4. Live Activity chain: island countdown → event flips to inProgress → next event chains with app backgrounded; scheduled start with app **terminated** (UNVERIFIED — this is the key device test; record result).
5. Weekend: activity ends at Friday close; "resumes Sunday" state in-app; Sunday chain resumes.
6. DST simulation: set device date to 2026-10-26 (mismatch week) → overlap shows 5h on the timeline, alerts land at shifted local times; then 2026-11-02 → back to 4h.
7. Timezone travel: change device region/zone → in-app schedule + widgets recompute; notifications rebuilt.
8. Watch (if paired): Smart Stack shows the mirrored countdown; `.small` layout legible.
9. Widgets: lock-screen accessories legible in vibrant mode; timeline widget correct across midnight.
10. Accessibility: VoiceOver sweep of Today; Dynamic Type XL; Reduce Transparency.

## 6. Working agreements

- Maintain `BUILDLOG.md`: per-milestone entries — decisions, conflict resolutions (with precedence citation), UNVERIFIED resolutions (exact SDK symbol found), deviations, deferred temptations, pending-manual QA items.
- Ask-or-choose policy: prefer the documented default; if genuinely ambiguous, choose the smallest reversible interpretation and log it. Do not stall.
- Never fabricate data (holiday dates, hours, API schemas). If a needed datum is missing from docs/research, mark the surface "data unavailable" gracefully and log it.
- Respect API budgets in dev: use the fixture JSONs from `06` §8 for tests; hit live endpoints sparingly.

## 7. Definition of Done

- [ ] All M0–M9 acceptance criteria met; all required tests green; zero build warnings
- [ ] App runs correctly with **no API keys** (degraded news/AI, everything else intact)
- [ ] All 7 markets correct on the timeline against `sessions.json` spot-checks in 3 zones (New York, London, Tokyo device zones)
- [ ] DST mismatch fixtures (2026 + 2027 windows) green; manual QA item 6 verified
- [ ] Notification budget never exceeds 64 pending (assertion + test); rebuild triggers all wired
- [ ] Live Activity: all island states + lock screen + stale + watch `.small` implemented; chain works foregrounded and backgrounded; terminated-start result recorded
- [ ] AlarmKit: critical alarm breaks Silent on device; auth-denied path graceful
- [ ] Briefing generates via Exa on the owner's device, via Template with keys absent; prompts match `06` §5 verbatim
- [ ] Widgets: 3 families + 3 accessories shipping; deep links verified from cold start
- [ ] Beginner↔Pro: every gated difference from `07`'s per-screen tables verified by toggling live
- [ ] Accessibility bar (`07` §7) fully passed
- [ ] Liquid Glass discipline audit: glass only on controls/navigation
- [ ] `BUILDLOG.md` complete; `Secrets.example.xcconfig` committed; `Secrets.xcconfig` gitignored
