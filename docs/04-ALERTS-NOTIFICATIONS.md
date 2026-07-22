# 04 — ALERTS & NOTIFICATIONS: Pipeline, Budget, AlarmKit, Permission UX

Authoritative spec for `OffsetKit/Sources/OffsetKit/Scheduling/` (`NotificationPlanner`, `AlarmPlanner`) and the app-target `AlertsStore` that applies plans to the system. Spine §4 alert types are used verbatim. Apple API claims cite `research/market-sessions-and-notifications.md` ("research-MS §n") and `research/ios26-activitykit-alarmkit.md` ("research-AK §X"); anything outside those files is marked UNVERIFIED.

## PROPOSED ADDITIONS

| Name | Kind | Purpose |
|---|---|---|
| `PlannedNotification` / `PlannedAlarm` fields | struct bodies | Type names are spine §4; field lists are defined in §3.1/§5.6 of this doc (spine: "bodies live in area docs") |
| `notificationBudget = 56`, `reserveSlots = 8`, `perDayCap = 16`, `coincidenceMergeWindow = 60 s` | constants | Planner tuning (OffsetKit/Scheduling) |
| `alarmBudget = 16`, default `horizonDays = 14` | constants | AlarmPlanner tuning |
| `OPEN_MARKET`, `ECON_EVENT` | UNNotificationCategory ids | Category registration (§4.3) |
| `VIEW_MARKET`, `MUTE_TODAY`, `MUTE_SERIES` | UNNotificationAction ids | Actions (§4.3) |
| `MarketAlarmMetadata` | struct | Concrete `AlarmMetadata` payload in `Shared/AlarmMetadata.swift` (spine §2 names the file; the type is named here) |
| `alarmIDMap` | persisted map | `[MarketEvent.id: UUID]` in SettingsStore (App Group), bridges string event ids to `Alarm.ID` UUIDs |
| `muteTodayUntil` | transient store value | Per-market mute set by the MUTE_TODAY action, cleared at next market-zone day change |
| "Pro alert suggestions" | UX concept | One-time sheet shown when Trader Level flips to Pro (§2.3) |

---

## 1. Pipeline overview

```
                 SessionScheduleEngine.events(in:settings:econEvents:)          [OffsetKit/Engine]
                          │  [MarketEvent], sorted, stable ids (03 §4.1)
                          ▼
            match against ENABLED AlertRules (target × moment × style, §3.2)
                          │
        ┌─────────────────┴──────────────────────────────┐
        ▼                                                ▼
NotificationPlanner.plan(events:rules:now:)      AlarmPlanner.plan(events:rules:now:horizonDays:)
  → [PlannedNotification]  (≤ 56)                  → [PlannedAlarm]  (criticalAlarm rules only,
        │                                                │            .fixed dates only, ≤ 16)
        ▼                                                ▼
UNUserNotificationCenter                          AlarmKit AlarmManager.shared
  removeAllPendingNotificationRequests()            diff via alarmIDMap: cancel orphans,
  then add() each request                           schedule new/changed (§5)
        [AlertsStore, app target]                        [AlertsStore, app target]
```

Both lanes are **pure planners in OffsetKit** (deterministic, unit-testable, no OS calls) plus a thin **applier in the app target** (`AlertsStore`, `@MainActor @Observable`) that talks to the system frameworks.

**Rebuild triggers** — `AlertsStore.rebuild()` runs the entire pipeline on every one of these (research-MS §2 signal table):

| Trigger | Source | Why |
|---|---|---|
| App foreground (`scenePhase == .active`) | SwiftUI | Primary refresh; alone keeps a daily-opened app fresh (research-MS §2) |
| `BGAppRefreshTask` `dev.offsetapp.offset.refresh.schedule` | BackgroundTasks | Opportunistic top-up only — "never the primary mechanism" (research-MS §2); re-submit next request at handler start |
| `UIApplication.significantTimeChangeNotification` | UIKit | New day, carrier time update, DST change — wall clocks just moved (research-MS §2) |
| `NSSystemTimeZoneDidChange` | Foundation | Travel/settings; call `TimeZone.resetSystemTimeZone()` first (research-MS §2) |
| `NSCalendarDayChanged` | Foundation | Roll the horizon forward, top up the window (research-MS §2) |

Why *always* full rebuild instead of patching: Apple does **not document** whether an already-pending `UNCalendarNotificationTrigger`'s computed fire date is re-evaluated when the device time zone changes or a DST rule ships mid-flight (research-MS §1, explicitly UNVERIFIED there). Defensive design, per that research: schedule only **non-repeating, fully materialized** triggers and rebuild the whole pending set on every signal. Rebuilds are idempotent (§3.4), so over-triggering is harmless.

---

## 2. Default AlertRule set (ship-ready)

Created once on first launch by `SettingsStore` (persisted; `AlertRule.id = UUID()` at creation). Every rule below exists from day one so AlertsView can show toggleable rows; only `enabled` differs. All moments/styles are spine §4 values.

### 2.1 Beginner defaults (traderLevel == .beginner, set at onboarding)

| # | target | moments | style | enabled |
|---|---|---|---|---|
| R1 | `.market(.fxLondon, .regular)` | `{.atOpen, .before(minutes: 15)}` | `.timeSensitive` | **true** |
| R2 | `.market(.fxNewYork, .regular)` | `{.atOpen, .before(minutes: 15)}` | `.timeSensitive` | **true** |
| R3 | `.market(.usEquities, .regular)` | `{.atOpen, .before(minutes: 15)}` | `.timeSensitive` | **true** |
| R4 | `.econ(minImpact: .high)` | `{.atOpen, .before(minutes: 15)}` | `.timeSensitive` | **true** |
| R5 | `.market(.fxLondon, .regular)` | `{.atClose}` | `.standard` | false |
| R6 | `.market(.fxNewYork, .regular)` | `{.atClose}` | `.standard` | false |
| R7 | `.market(.usEquities, .regular)` | `{.atClose}` | `.standard` | false |
| R8 | `.market(.fxSydney, .regular)` | `{.atOpen}` | `.standard` | false |
| R9 | `.market(.fxTokyo, .regular)` | `{.atOpen}` | `.standard` | false |
| R10 | `.market(.lse, .regular)` | `{.atOpen, .before(minutes: 15)}` | `.standard` | false |
| R11 | `.market(.cmeEquity, .regular)` | `{.atOpen, .before(minutes: 15)}` | `.standard` | false |
| R12 | `.market(.usEquities, .preMarket)` | `{.atOpen}` | `.standard` | false (DECISIONS: extended-hours alerts off by default, budget) |
| R13 | `.market(.usEquities, .afterHours)` | `{.atClose}` | `.standard` | false |
| R14 | `.overlap` | `{.atOpen}` | `.standard` | false |
| R15 | `.killzone(.london)` | `{.atOpen, .before(minutes: 5)}` | `.standard` | false |
| R16 | `.killzone(.nyAM)` | `{.atOpen, .before(minutes: 5)}` | `.standard` | false |
| R17 | `.killzone(.asia)` | `{.atOpen}` | `.standard` | false |
| R18 | `.killzone(.londonClose)` | `{.atOpen}` | `.standard` | false |
| R19 | `.killzone(.nyPM)` | `{.atOpen}` | `.standard` | false |
| R20 | `.fxWeek` | `{.atOpen, .atClose}` | `.standard` | false |

Budget sanity for the enabled set: R1–R3 → 3 targets × (open + 15-min lead) = 6 notifications/weekday = 30/week, plus R4's handful of high-impact releases ≈ **~40/week — comfortably inside 56**, so a Beginner gets full 7-day runway with zero degradation (arithmetic frame: research-MS §5, "realistic personal config … 4 days"; ours is leaner).

### 2.2 What flipping to Pro suggests

Flipping Trader Level to Pro never silently enables anything. It presents the one-time **"Pro alert suggestions"** sheet offering to enable, per tap or "Enable all":

| Suggestion | Rules flipped to enabled | Rationale shown in sheet (07 doc owns copy) |
|---|---|---|
| Killzones: London + NY AM | R15, R16 | The two highest-liquidity ICT windows |
| London–NY overlap | R14 | Structural overlap start; self-adjusts in DST mismatch weeks |
| Closes for the big three | R5, R6, R7 | Session-end discipline |

Enabling all suggestions adds ≈ 8 more notifications/weekday (2 killzones × 2 moments + 1 overlap + 3 closes) → ≈ 70–80 candidates/week → the budget degrades to ≈ 4–5 days of runway and AlertsView's budget row starts reading "scheduled through Thursday" (§3.3). Beginner/Pro also changes notification copy tone (plain-language vs terse, spine §5; templates in 07 doc §copy).

### 2.3 Style semantics

`AlertStyle` maps: `.standard` → `UNNotificationInterruptionLevel.active`; `.timeSensitive` → `.timeSensitive` (capability required, §4.4); `.criticalAlarm` → the AlarmKit lane (§5), no notification for that same event (§3.2 step 3). Research-MS §1: use `.timeSensitive` only for imminent-event alerts — which is exactly the enabled default set; everything suggested later ships `.standard`.

---

## 3. NotificationPlanner

Spine §4: `func plan(events: [MarketEvent], rules: [AlertRule], now: Date) -> [PlannedNotification]` — pure and synchronous. `events` comes from `engine.events(in: DateInterval(now, now + 7 days), settings:, econEvents:)`.

### 3.1 `PlannedNotification` (fields defined here)

```swift
struct PlannedNotification: Identifiable, Hashable, Sendable {
    let id: String            // == MarketEvent.id (merged events: the surviving canonical id, §3.2 step 5)
    let fireDate: Date        // == MarketEvent.date (absolute instant)
    let zoneID: String        // governing IANA zone for trigger components (market zone; America/New_York
                              //   for overlap/killzone/fxWeek; econ uses America/New_York display zone)
    let title: String         // from MarketEvent.title via 07-doc templates (Beginner/Pro variants)
    let body: String          // from MarketEvent.subtitle via 07-doc templates
    let categoryID: String    // "OPEN_MARKET" | "ECON_EVENT"
    let threadID: String      // MarketID.rawValue, or "overlap" / "killzones" / "fx" / "econ"
    let style: AlertStyle     // .standard | .timeSensitive only (never .criticalAlarm here)
    let priorityRank: Int     // §3.2 step 6 rank; kept for AlertsView budget debugging UI
}
```

### 3.2 Algorithm (deterministic)

```
plan(events, rules, now):
1. MATCH — for each event, collect enabled rules admitting it:
     .open           ↔ target matches subject AND .atOpen ∈ moments
     .close          ↔ target matches subject AND .atClose ∈ moments
     .preOpen(m)/.preClose(m) ↔ lead events exist only because an enabled rule asked (03 §4 step 6);
                       they match that generating rule
     .overlapStart/.overlapEnd       ↔ .overlap + .atOpen/.atClose
     .killzoneStart(k)/.killzoneEnd(k) ↔ .killzone(k) + .atOpen/.atClose
     .weekOpen/.weekClose            ↔ .fxWeek + .atOpen/.atClose
     .econRelease(id) ↔ .econ(minImpact:) with event impact ≥ minImpact; .atOpen == "at release"
   Target-subject matching for market rules is (MarketID, SegmentKind) exact — R12 matches
   "open:usEquities:preMarket:…" but not "open:usEquities:…".
2. STYLE — resolved style = max severity among matching rules (standard < timeSensitive < criticalAlarm).
3. ALARM HANDOFF (duplicate suppression) — if resolved style == .criticalAlarm:
   the event belongs to the AlarmPlanner lane. Drop it AND its lead events generated by the same
   rule from the notification lane (the alarm's preAlert countdown covers the lead window, §5.4).
   Alarm wins; notification skipped. Leads from OTHER (non-critical) rules on the same anchor survive.
4. DROP PAST — fireDate ≤ now + 5 s.
5. MERGE COINCIDENT — events within coincidenceMergeWindow (60 s) of each other whose kinds are both
   "start-like" (open/overlapStart/killzoneStart/weekOpen) or both "end-like" collapse into one
   notification: earliest fireDate, combined title ("FX week + Sydney open"), id = lexicographically
   smallest member id. Research-MS §5 point 4 (merge ±1 min, e.g. NYSE 09:30 ≙ NY-forex morning);
   canonical Offset case: fxSydney Monday open == weekOpen instant (03 doc T20).
6. RANK — sort candidates by (fireDate, priorityRank, id). priorityRank encodes spine §4's order:
     sooner (primary sort key is fireDate itself)
     > criticalAlarm-backed leads (rank 0: leads that survived step 3 for alarm-backed anchors)
     > opens (rank 1: open, overlapStart, weekOpen, killzoneStart with .timeSensitive style)
     > econ high (rank 2)
     > closes (rank 3: close, overlapEnd, weekClose)
     > killzones standard (rank 4)
     > overlaps end / remaining (rank 5); leads inherit their anchor's rank
7. PER-DAY CAP — group by device-local calendar day (Calendar.current at plan time; the planner
   receives it as a parameter defaulting to .current to stay pure/testable). If a day holds more
   than perDayCap (16), drop lowest-rank-last-id first within that day. Prevents one loud Pro day
   from draining the whole window.
8. FILL — take the first notificationBudget (56) in fireDate order. Later events simply don't get
   scheduled yet — degradation with distance, nearest-first (research-MS §5 prioritization).
```

The 8 reserved slots (56 + 8 = 64) are NOT filled by `plan()`: they absorb (a) econ events that appear/move between rebuilds via the news BGTask (scheduled immediately by `AlertsStore` without a full replan) and (b) future snooze/ad-hoc requests. Research-MS §1: the 64 cap is the documented `UILocalNotification` number ("the system keeps the soonest-firing 64 … and discards the rest"), enforced in practice by UserNotifications — treat 64 as hard budget.

**Why a budget at all** (cite research-MS §5 math in AlertsView's info sheet): full scope = 7 session tracks × (open+close) = 14 events/weekday; with 2 leads each → 42/weekday → **≈ 216 candidates/week vs the 64 cap — 3.4× oversubscribed**; even events-only is 72 > 64. Seven days at full verbosity is impossible **by design**; the planner's job is choosing the nearest, most important 56.

### 3.3 Degradation UX

- Farthest events are dropped first (step 8) — never the next 24 h.
- AlertsView budget health row (spine §5): "41 of 64 slots · scheduled through Thu". `coverageEnd = plannedNotifications.last?.fireDate`; when `coverageEnd < now + 6 days` the row appends "scheduled through {weekday}" so the user understands why a far-out alert hasn't been scheduled *yet* (it will be, on a later rebuild — research-MS §5 point 5: rolling window + daily app opens keep 24 h+ of runway even if BGTasks never fire).
- Row turns amber when coverage < 48 h (heavy Pro config) with a tip to trim moments/leads (TipKit, 07 doc).

### 3.4 Idempotent apply (`AlertsStore.applyNotificationPlan`)

```swift
let center = UNUserNotificationCenter.current()
center.removeAllPendingNotificationRequests()                  // full reset — ids make re-adds exact
for p in plan {
    var comps = calendar(in: p.zoneID).dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                      from: p.fireDate)
    comps.timeZone = TimeZone(identifier: p.zoneID)            // explicit zone — research-MS §1
    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    let content = UNMutableNotificationContent()
    content.title = p.title; content.body = p.body; content.sound = .default
    content.categoryIdentifier = p.categoryID
    content.threadIdentifier = p.threadID
    content.interruptionLevel = (p.style == .timeSensitive) ? .timeSensitive : .active
    try await center.add(UNNotificationRequest(identifier: p.id, content: content, trigger: trigger))
}
```

- remove-all-then-re-add is the research-MS §1 rolling-window strategy verbatim; deterministic identifiers (== `MarketEvent.id`, 03 §4.1) mean re-adds replace rather than duplicate, and a changed fire time under an unchanged id (e.g. half-day close truncation) updates cleanly.
- Debug builds verify with `pendingNotificationRequests()` (count ≤ 64; ids unique) and assert `trigger.nextTriggerDate() == p.fireDate` (research-MS §1 `nextTriggerDate()`, §3 pitfall 7).
- Triggers are always non-repeating: repeating triggers cannot express "every weekday except holidays", and repeats+DST is undefined-by-docs (research-MS §1).

---

## 4. UNUserNotificationCenter specifics (all research-cited)

### 4.1 Authorization

Requested at onboarding end after the priming screen (§7.1): alert + sound + badge options, per Apple's local-scheduling guide (research-MS source index: `scheduling-a-notification-locally-from-your-app`; the exact `requestAuthorization(options:)` signature is on that page — the research file lists the page but does not quote the prose, so verify the option set name spellings in Xcode). Denied → degraded mode (§7.4).

### 4.2 Triggers

`UNCalendarNotificationTrigger(dateMatching:repeats:)`, non-repeating, with **explicit `DateComponents.timeZone`** — set to the governing market zone so the trigger matches that wall clock with DST handled by tzdata; `nil` would mean floating device-local semantics, wrong for exchanges (research-MS §1, incl. the `UILocalNotification.timeZone` GMT-vs-wall-clock split and the worked NYSE example). Fully materialized year/month/day/hour/minute(/second) components per occurrence.

### 4.3 Categories and actions

Registered once at launch (research-MS §1 categories/actions, `setNotificationCategories`):

| Category | Applied to | Actions |
|---|---|---|
| `OPEN_MARKET` | open/close/preOpen/preClose/overlap/killzone/week events | `VIEW_MARKET` "View market" (foreground; deep-links `offset://market/{id}`, or `offset://today` for market-less events) · `MUTE_TODAY` "Mute today" (background; sets `muteTodayUntil[market]` = next market-zone day change, immediate rebuild excludes that market's remaining events today) |
| `ECON_EVENT` | econRelease events | `VIEW_MARKET` "View calendar" variant (deep-links `offset://news/briefing`) · `MUTE_SERIES` "Mute this series" (research-MS §1 suggested action; disables matching econ alerts until re-enabled in AlertsView) |

### 4.4 Interruption levels

- `.active` for `.standard` rules; `.timeSensitive` for `.timeSensitive` rules only — research-MS §1: time-sensitive "can break through … Notification Summary and Focus", user-revocable per app; "Apple reviews misuse", so Offset restricts it to the imminent set (§2.1/§2.3).
- **Capability**: `.timeSensitive` requires the **"Time Sensitive Notifications"** capability (Signing & Capabilities), entitlement key `com.apple.developer.usernotifications.time-sensitive`; without it the system **silently downgrades to `.active`**. Research-MS §1 flags that Apple's entitlement doc page for this key is currently absent — the toggle lives in Xcode's capability library. BUILD_PROMPT note: verify the exact toggle name in Xcode 26.6 when adding it; treat the toggle name as capability-VERIFIED / doc-page-absent per research.

### 4.5 Foreground presentation

`UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:)` returns `[.banner, .list, .sound]` (`.banner`/`.list` are the iOS 14+ replacements for `.alert`) — without a delegate the system suppresses foreground banners entirely (research-MS §1). Offset suppresses the banner (returns `[]`) only when TodayView is frontmost AND the notification's event is the hero countdown already on screen.

### 4.6 Content templates

`title`/`body` come from the 07-UI-UX-SPEC copy tables, keyed by `MarketEventKind` + `TraderLevel` (e.g. Beginner "London session opens in 15 minutes — usually the day's first big move" vs Pro "LDN open 15m"). Engine-provided `MarketEvent.title`/`subtitle` are the defaults; 07 doc may override per kind. `threadIdentifier` groups by market so a busy morning stacks (research-MS §1 example uses exactly this pattern).

---

## 5. AlarmKit integration ("Critical alarms")

AlarmKit breaks through Silent and Focus (research-AK §G, framework statement + WWDC25 230) — reserved for the sacred (DECISIONS Round 2: "alarms for the sacred, notifications for the routine").

### 5.1 When an alarm is used

Only for events matched by a rule with `style == .criticalAlarm` — surfaced in AlertsView's **CriticalAlarmsSection** (spine §2) as per-event/per-rule "Critical alarm" pins. No default rule ships as `.criticalAlarm`; the user opts in per target. Positioning per research-AK §G.4: AlarmKit is "not a replacement for … time-sensitive notifications" — it is the third, heaviest tier (§6).

### 5.2 Authorization flow

- Info.plist (app target): `NSAlarmKitUsageDescription` — missing/empty means scheduling **always fails** (research-AK §G.1). Copy: "Offset uses alarms so market opens you pin can break through Silent mode and Focus."
- `AlarmManager.shared.requestAuthorization()` (async, returns `.notDetermined/.authorized/.denied`) is called at **first critical-alarm creation, not onboarding**: the user has just expressed intent, so the system prompt lands in context (research-AK §G.1 notes the first `schedule` auto-prompts if you never call it — Offset calls it explicitly to drive its own explainer sheet first). `authorizationState` / `authorizationUpdates` feed the AlertsView status row (§7.3).

### 5.3 Scheduling — `.fixed` dates ONLY

`AlarmManager.shared.schedule(id:configuration:)` with `Alarm.Schedule.fixed(Date)` exclusively. Research-AK §G.2: `.fixed` is "absolute instant, does NOT shift with device timezone (RIGHT choice for market opens)"; `.relative` follows the **device** time zone — wrong for exchange-fixed instants when the user travels or DST diverges (research-AK §H.1 point 5; DECISIONS #10). Weekly-repeating market opens are therefore expressed as *individual* `.fixed` occurrences materialized by the engine, re-planned on every rebuild — never `.relative(.weekly)`.

### 5.4 Pre-alert countdown

For an "opens in 15 min" experience the alarm is scheduled **at the event instant** with a system countdown before it:

```swift
let config = AlarmManager.AlarmConfiguration(
    countdownDuration: .init(preAlert: 15 * 60, postAlert: 5 * 60),   // 15-min system countdown; 5-min repeat
    schedule: .fixed(plannedAlarm.fireDate),                           // e.g. 2026-07-22T09:30:00-04:00 instant
    attributes: AlarmAttributes<MarketAlarmMetadata>(
        presentation: AlarmPresentation(alert: alert, countdown: countdown, paused: paused),
        metadata: MarketAlarmMetadata(eventID: plannedAlarm.id, marketRawValue: plannedAlarm.marketRawValue),
        tintColor: marketTint),                                        // from Market.colorToken
    secondaryIntent: OpenMarketIntent(eventID: plannedAlarm.id),       // LiveActivityIntent, opens app
    sound: .default)
try await AlarmManager.shared.schedule(id: alarmUUID, configuration: config)
```

- `preAlert` renders a guaranteed 15-minute **system countdown Live Activity** (Dynamic Island + Lock Screen + StandBy) with zero pushes and full termination immunity, then fires the Silent/Focus-breaking alert at the open (research-AK §G.2 `Alarm.CountdownDuration`, §H.1 point 5). `preAlert` = the max `.before(minutes:)` in the generating rule, default 15.
- `postAlert: 5*60` powers the secondary "repeat" behavior if the user configures the secondary button as `.countdown` (snooze); Offset's default secondary is `.custom` → `OpenMarketIntent`.

### 5.5 Presentation + widget-extension requirement

- `AlarmPresentation.Alert(title:secondaryButton:secondaryButtonBehavior:)` — title e.g. "NYSE opens"; `AlarmButton(text: "Open", textColor:, systemImageName: "arrow.right.circle.fill")` (the SF Symbol is what shows in the Dynamic Island alert). Note: the older `init(…stopButton:…)` is **deprecated** — the current SDK provides the stop button automatically (research-AK §G.3).
- Because Offset uses `preAlert`, it must supply `AlarmPresentation.Countdown` ("Market opens", pause button) and `.Paused` (resume button) states too (research-AK §G.3).
- `MarketAlarmMetadata` (in `Shared/AlarmMetadata.swift`, compiled into app + extension) conforms to `AlarmMetadata` (`Codable, Hashable, Sendable`) and is marked `nonisolated` under Xcode 26 default-MainActor modules (research-AK §G.3 gotcha).
- **Widget extension is REQUIRED**: "AlarmKit expects a widget extension if an app supports a countdown presentation. Otherwise, the system may unexpectedly dismiss alarms and fail to alert" (research-AK §G.3, verbatim). OffsetWidgets already exists for the Live Activity; `AlarmPresentationSupport.swift` (spine §2) adds `ActivityConfiguration(for: AlarmAttributes<MarketAlarmMetadata>.self)` as a second activity in `OffsetWidgetsBundle`, rendering countdown state from `AlarmPresentationState.mode` (`.countdown` carries `fireDate` → `Text(timerInterval: .now...fireDate)`; research-AK §G.3).

### 5.6 AlarmPlanner, horizon, identifiers, cancellation

Spine §4: `func plan(events: [MarketEvent], rules: [AlertRule], now: Date, horizonDays: Int) -> [PlannedAlarm]` — pure; default `horizonDays = 14`.

```swift
struct PlannedAlarm: Identifiable, Hashable, Sendable {
    let id: String                  // == MarketEvent.id (anchor event)
    let fireDate: Date              // the .fixed instant
    let preAlertSeconds: TimeInterval?   // max lead from the generating rule, nil if none
    let title: String               // AlarmPresentation.Alert title (07-doc copy)
    let marketRawValue: String?     // tint + metadata; nil for overlap/killzone/econ/week targets
}
```

- Selection: events within `now ..< now + horizonDays` matching enabled `.criticalAlarm` rules; one alarm per matched boundary (`.atOpen` → open event, `.atClose` → close event); leads are absorbed into `preAlertSeconds` (§3.2 step 3).
- Cap: `alarmBudget = 16` nearest-first. The AlarmKit numeric limit is **not documented** (`AlarmError.maximumLimitReached` exists; research-AK §G.4 UNVERIFIED, "budget your UX to tens of alarms"; research-AK §H.3: this app needs < 20). 14 days × a few pinned opens stays well under.
- **Identifier scheme**: `Alarm.ID` is a UUID (research-AK §G.2), but Offset ids are strings. `AlertsStore` owns the persisted `alarmIDMap: [MarketEvent.id: UUID]` (SettingsStore, App Group): on apply, reuse the mapped UUID if the event is already scheduled and unchanged; otherwise `UUID()` + record. Deterministic string→UUID hashing is deliberately avoided (would drag in a crypto dependency; spine allows none).
- **Re-plan cadence**: same rebuild triggers as §1, but **diff-based, never remove-all** (alarms are user-visible system objects; thrashing them re-renders countdown UI): cancel map entries absent from the new plan (`cancel(id:)`), schedule new entries, reschedule entries whose `fireDate`/`preAlertSeconds` changed (cancel + schedule). Reconcile against `AlarmManager.alarms` / `alarmUpdates` at every launch — an alarm absent from the stream is no longer scheduled (research-AK §G.2); prune the map accordingly.
- **Cancellation on rule disable/unpin**: flipping the rule off (or style away from `.criticalAlarm`) cancels all mapped alarms for that rule's targets on the next apply (immediate, since toggling triggers rebuild). Alarms survive app termination and device restarts (research-AK §G.4), so cancellation must always go through `AlarmManager`, never just the map.

---

## 6. Contrast table — which tier when

Adapted from research-AK §G.5 (columns re-scoped to Offset's three delivery styles):

| Dimension | AlarmKit alarm (`.criticalAlarm`) | `.timeSensitive` notification | `.standard` notification |
|---|---|---|---|
| Breaks Silent switch | YES (research-AK §G.4) | No | No |
| Breaks Focus | YES | Only if Time Sensitive permitted for Offset | No |
| Permission surface | AlarmKit prompt (`NSAlarmKitUsageDescription`) | Notification permission + capability + user's per-app Time Sensitive setting | Notification permission |
| Fires with app terminated | YES — system-scheduled, survives restart (research-AK §G.4) | YES (research-MS §1) | YES |
| Continuous countdown UI | YES — system countdown Live Activity via OffsetWidgets (research-AK §G.3) | No (static banner) | No |
| Cost of misuse | Heavy-handed fast; hard cap undocumented | Apple reviews misuse (research-MS §1) | Summary/Focus may defer it |
| Offset uses it for | User-pinned can't-miss opens/closes (CriticalAlarmsSection) | Default enabled set: R1–R4 opens, 15-min leads, high-impact econ | Everything else: closes, killzones, overlap, week markers, Sydney/Tokyo/LSE/CME opens |

---

## 7. Permission UX

### 7.1 Staged asks

1. **Notifications — end of onboarding** (screen 4 of the OnboardingFlow): priming screen first ("Offset alerts you before markets move — here's exactly what you'll get", showing the R1–R4 defaults), then the system prompt. Never ask on first launch frame.
2. **Time Sensitive** — no runtime prompt exists; it's a build-time capability (§4.4) plus a user-revocable per-app setting (research-MS §1). Onboarding does not mention it; AlertsView surfaces state (§7.3).
3. **Critical alarms — at first alarm creation** (§5.2): explainer sheet ("Breaks through Silent and Focus. Use for the opens you cannot miss.") → `requestAuthorization()` → on `.denied`, inline guidance to Settings.

### 7.2 Degraded modes

| State | Behavior |
|---|---|
| Notifications denied | No scheduling calls; AlertsView shows a "Notifications are off" banner with a Settings link (§7.3); Today hero countdown, timeline, Live Activity and in-app `TimelineView` ticking still fully work (research-MS §4 patterns) — Offset stays useful as a clock |
| Time Sensitive off (user setting) | System silently delivers at `.active` (research-MS §1 downgrade behavior noted for the missing capability; per-app setting produces the equivalent user-visible result). AlertsView shows an informational row, style pickers keep working |
| Alarms denied | `.criticalAlarm` rules show a warning badge; planner **falls back**: those events re-enter the notification lane at `.timeSensitive` (explicit rule: alarm-denied ⇒ handoff step §3.2.3 is skipped) |

### 7.3 Status dashboard (AlertsView)

Rows: Notifications (authorized / denied / not-determined), Time Sensitive (capability note + user-setting hint), Critical alarms (`AlarmManager.authorizationState`, live via `authorizationUpdates` — research-AK §G.1), budget health row (§3.3). Notification authorization status is read via the notification-center settings query; **UNVERIFIED**: the exact settings-API symbol and the per-setting `timeSensitiveSetting` field are not in the research files — verify names in Xcode before coding. Settings deep-link: `UIApplication.openNotificationSettingsURLString` is **UNVERIFIED** (absent from research files); if it doesn't pan out at implementation time, fall back to plain instructions ("Settings → Notifications → Offset") rather than a link.

---

## 8. Edge cases

1. **Device timezone travel.** `NSSystemTimeZoneDidChange` → `TimeZone.resetSystemTimeZone()` → full rebuild of both lanes (research-MS §2). Market instants are absolute and unchanged; only device-local labels move. Alarms are untouched by the zone change itself (`.fixed` is zone-immune — the reason it was chosen, §5.3), but the rebuild re-renders their titles' local-time strings. In-app, TodayView shows a one-shot toast: "Times updated for your time zone."
2. **FX weekend.** Structural: the engine emits no fx occurrences Saturday, so nothing can be scheduled — no special code. Sunday has exactly `weekOpen` (17:00 America/New_York) + CME Sunday open (17:00 CT) + fxSydney Monday open; the fxSydney open and `weekOpen` are the *same instant* during AEST alignment and merge into one notification (§3.2 step 5; 03 doc T20).
3. **Holiday suppression.** Dropped occurrences (03 §3) never become events, so holiday days are silent automatically. Half days: the close event keeps its id but moves earlier (13:00 ET / 12:30 London); the idempotent rebuild replaces the pending request in place (§3.4). CME advisory days schedule normally (03 §2b policy) — the notification body appends the advisory line, flagged UNVERIFIED-hours in 03.
4. **Notification + alarm on the same event.** Alarm wins; the notification (and same-rule leads) are skipped (§3.2 step 3). The alarm's `preAlert` countdown supplies the lead experience instead (§5.4). If alarms are denied, the fallback in §7.2 restores the notification.
5. **Late-night quiet.** v1 ships no quiet-hours engine: `.standard` alerts already respect Focus/summary, and the default-enabled set contains nothing overnight for a US/EU user except what they opted into. Users who enable the `asia` killzone (20:00–00:00 NY) keep `.standard` style by default so sleep Focus holds it. A per-app quiet window that force-demotes styles is documented as a **v1.1 candidate** (AlertsView footer mentions "Use Focus to silence Offset at night" — 07 doc copy).
6. **Econ events appearing/moving between rebuilds.** New high-impact events from a news refresh are scheduled immediately into the 8 reserved slots without a full replan; a moved release keeps `econ:{EconEvent.id}` and is replaced in place at the next rebuild. If reserve is exhausted, the event waits for the next full rebuild (acceptable: reserve exhaustion implies ≥ 8 near-term econ alerts already).
7. **Mute today.** `MUTE_TODAY` (§4.3) filters that market's remaining events for the current market-zone day and rebuilds; the mute expires at the market's next day change (not device midnight — a Tokyo mute should survive a NY evening).
8. **64-cap race.** Offset never relies on the system's silent discard: it self-limits to 56 + 8 so third-party behavior at the cap (research-MS §1: silently drops beyond 64) is never exercised.
