# 05 — LIVE ACTIVITY: MarketCountdown, scheduled-LA chaining, Dynamic Island, Watch mirroring

The one Live Activity in Offset: an **auto** countdown to the next market event (DECISIONS Round 1: "AUTO countdown to next market event. No manual timer in v1"). Names/types per `00-SPINE.md` (law) — `MarketCountdownAttributes` and `CountdownPhase` are used **verbatim** from spine §4. Every Apple-API claim below cites `research/ios26-activitykit-alarmkit.md`; anything the research does not verify is marked **UNVERIFIED** and carried into the QA plan.

Research shorthand: **[LA/AK]** = `research/ios26-activitykit-alarmkit.md`, **[MKT]** = `research/market-sessions-and-notifications.md` (HALF1/HALF2 numbering), **[GLASS]** = `research/ios26-liquid-glass-swiftui.md`. Doc cross-refs: 02 (architecture/RefreshCoordinator), 03 (engine/events), 04 (notifications/alarms), 07 (UI), 08 (widgets). The iOS 27 exclusion list ([GLASS] §7.4) is binding.

---

## PROPOSED ADDITIONS (new vocabulary introduced by this doc)

| Name | Kind | Where | Purpose |
|---|---|---|---|
| `ActivityController.startOrUpdate(for: MarketEvent)` | method | app target | Reducer entry point: make the live activity represent this event (§6) |
| `ActivityController.scheduleNextChain()` | method | app target | Pre-schedule the single pending scheduled activity (§2.3) |
| `ActivityController.endAll()` | method | app target | End every activity in `Activity<MarketCountdownAttributes>.activities` (§2.7) |
| `ActivityController.reconcile()` | method | app target | Launch/foreground pass: end orphans/stale, correct active + pending (§6) |
| `ActivityController.currentPhase: CountdownPhase?` | property | app target | Read by `CountdownAccessoryBar` (07 §2) — `nil`/`.marketsClosed` hides the accessory (spine §5) |
| `ActivityController.areActivitiesEnabled: Bool` | property | app target | Observable mirror of `ActivityAuthorizationInfo.areActivitiesEnabled` for AlertsView status rows (§6) |
| `activityEligible(_ kind: MarketEventKind) -> Bool` | free function (OffsetKit/Engine) | OffsetKit | Filters the engine event stream to LA-worthy kinds (§1.2) |
| `maxSeamlessGap: TimeInterval = 27_000` (7 h 30 m) | constant | `Shared/SharedConstants.swift` | Longest countdown leg we allow inside the verified 8 h active window (§2.3) |
| `resumePreRoll: TimeInterval = 3_600` (60 m) | constant | `Shared/SharedConstants.swift` | Pre-roll for gap-jumping scheduled starts (weekend/holiday) (§2.3) |
| `staleGrace: TimeInterval = 120` | constant | `Shared/SharedConstants.swift` | `staleDate = targetDate + staleGrace` (§2.6) |
| `NextEventsPreviewRow` | SwiftUI view | OffsetWidgets | Expanded-bottom "next 2 events" row, derived extension-side (§3.4) |
| `ActivityDebugPanel` | SwiftUI view (`#if DEBUG`) | app target | Live-Activity rows of the hidden debug menu (02 §8) (§7.3) |

No changes to spine types. `MarketCountdownAttributes`/`CountdownPhase` are used exactly as defined in spine §4; the expanded-layout "next 2 events" preview deliberately does **not** add ContentState fields — it is derived in the extension (§3.4).

---

## 1. Concept

### 1.1 One activity type, auto-only

- Exactly one `ActivityAttributes` type: `MarketCountdownAttributes` (spine §4), defined in `Shared/MarketCountdownAttributes.swift` and compiled into **both** the app target and OffsetWidgets — [LA/AK] §A.1: "the same type must be compiled into BOTH the app target and the widget-extension target".
- At most **one active** MarketCountdown activity at a time, plus **at most one pending** scheduled successor (§2.3). There is no user-facing "start a timer" affordance anywhere (DECISIONS Round 1; manual timer is a v1.1 candidate, 01 §backlog).
- The activity is Offset's ambient market clock. Alerting is owned elsewhere: notifications (04), AlarmKit hard alarms (04 §5). The activity never replaces either — [LA/AK] §G.5 contrast table.

### 1.2 Which events drive the activity

The activity consumes the same engine stream as the Today hero card — `SessionScheduleEngine.events(in:settings:econEvents:)` (spine §4, 03 doc) — filtered by `activityEligible`:

| `MarketEventKind` | Eligible? | Rationale |
|---|---|---|
| `.open`, `.close` | YES | Session boundaries are the clock. All segments the engine emits for enabled markets count (incl. `preMarket`/`afterHours` boundaries when enabled — DECISIONS Decided #5 shows them on the timeline). |
| `.weekOpen`, `.weekClose` | YES | FX week markers (spine §3). Presented with `fxNewYork` tokens — both markers are defined at 17:00 America/New_York (spine §3), so the NYC color/symbol is the honest chip. |
| `.preOpen`/`.preClose` | NO | The `.countingDown` phase **is** the pre-open countdown; a lead-time event would retarget the timer to itself. Leads stay notifications (04). |
| `.overlapStart/.overlapEnd`, `.killzoneStart/.killzoneEnd` | NO | `market == nil` (spine §4) — `MarketCountdownAttributes` requires one market's tokens; no honest chip exists. Notifications cover them (04). |
| `.econRelease` | NO | Same `market == nil` problem, plus econ data lives in CacheStore and would drag SwiftData freshness into activity correctness. Econ stays notifications (04) + widgets (08). |

`activityEligible` lives in OffsetKit/Engine (pure, testable): `kind ∈ {.open, .close, .weekOpen, .weekClose}`.

### 1.3 States per `CountdownPhase` (spine §4, verbatim)

| Phase | Meaning | Example copy | `targetDate` | `rangeStart` |
|---|---|---|---|---|
| `.countingDown` | Next eligible event is an open; waiting | "London opens in 42:07" | the `openDate` | instant the countdown began (request time, or scheduled `start:` date) |
| `.inProgress` | A session is open; counting to its close | "London open · closes in 6:12:44" | the `closeDate` | the session's `openDate` → `ProgressView(timerInterval:)` = true session progress |
| `.marketsClosed` | Weekend/holiday gap | "Markets closed · resumes Sun 17:00 ET" | the reopen instant (`weekOpen` date) | the close instant |

`.marketsClosed` is primarily an **app** state: during the weekend gap the activity is **not running** (§2.5 — the gap exceeds the 8 h active window, [LA/AK] §D). It appears in ContentState only as the *final* content passed to `end` at `weekClose` (§2.7), so the lingering Lock Screen card reads correctly. In-app, Today's hero card and the tab accessory show the resume state instead (01 S-C3; spine §5 hides the accessory while `phase == .marketsClosed`).

`eventTitle`, `marketTimeLabel`, `subtitle` copy: built by `Formatters` (spine §2 Support/) from the `MarketEvent` — Beginner/Pro copy differences do **not** apply here (the strings above are level-neutral; level gating is a notification-copy concern, 04).

---

## 2. Lifecycle state machine — serverless chaining

The design goal: a countdown that keeps rolling **without a push server**, using only (a) foreground runtime, (b) iOS 26 scheduled Live Activities, (c) opportunistic BGAppRefresh. This section is normative.

### 2.1 Definitions

- **Boundary** — the `date` of an eligible event. When a boundary passes, the activity's content is wrong until something retargets it.
- **E1** — next eligible event after `now` (what the active activity shows). **E2** — next eligible event after E1 (what the pending scheduled activity will show).
- **Same-market step** — E1 and E2 share `market` (e.g. London open → London close): the transition is a content **update** (attributes unchanged). **Cross-market step** — different `market`: attributes are static for an activity's lifetime ([LA/AK] §A.1), so the transition requires **end + new request**.

### 2.2 While the app is foregrounded

On every foreground pass (`scenePhase == .active`, driven by RefreshCoordinator — 02 §5.2 row 1):

1. `ActivityController.reconcile()`: enumerate `Activity<MarketCountdownAttributes>.activities` — reconcile on every launch and end orphans ([LA/AK] §A.5 "reconcile on every app launch, end orphans").
2. Compute E1. If `now` is inside a gap `> maxSeamlessGap` (weekend/holiday), end everything with `.marketsClosed` final content (§2.7) and go to step 4.
3. `startOrUpdate(for: E1)`:
   - No matching activity → `Activity.request(attributes:content:pushType: nil)` ([LA/AK] §A.2; foreground start is always legal).
   - Activity exists with `attributes.marketRawValue == E1.market.rawValue` → `await activity.update(ActivityContent(state: newState, staleDate: E1.date + staleGrace))` ([LA/AK] §A.4).
   - Activity exists for a different market → `end(..., dismissalPolicy: .immediate)` then request fresh ([LA/AK] §A.4, §A.2).
4. While foregrounded, an app-side observer (ScheduleStore tick) crosses each boundary in real time and re-runs step 3 — so a user watching the phone sees phase flips immediately (01 S-C2).

### 2.3 Scheduled chaining (iOS 26) — the serverless handoff

**API.** `Activity.request(attributes:content:pushType:style:alertConfiguration:start:)` — iOS 26.0: "The system starts the Live Activity at the specified date, even if the app is in the background." A scheduled-not-yet-started activity has `ActivityState.pending`, an `AlertConfiguration` is **mandatory**, and scheduled activities count toward the concurrency limit ([LA/AK] §A.2).

**When we schedule.** `ActivityController.scheduleNextChain()` runs:

- on every transition to `scenePhase == .background` (primary trigger — last guaranteed runtime before the system owns the timeline);
- at the end of every foreground pass (belt-and-braces — covers kill-from-app-switcher without a `.background` tick);
- inside the `dev.offsetapp.offset.refresh.schedule` BGAppRefresh handler (02 §5.1 step 5; update/end **and** a new scheduled request are legal from background — starting is the restricted operation, and the scheduled variant is precisely the sanctioned background-start path, [LA/AK] §A.2/§A.4).

**What we schedule.** Exactly **one** pending activity, representing the world immediately after the next boundary:

```
E1 = next eligible event after now          // what the active activity shows
E2 = next eligible event after E1.date     // what the pending activity will show
gap = E2.date - E1.date                     // ...between consecutive boundaries

pending.attributes  = attributes(E2.market)
pending.contentState= state(for: E2, rangeStart: startDate)
pending.start       = (gap <= maxSeamlessGap) ? E1.date                       // seamless: takes over at the boundary
                                              : (E2.date - resumePreRoll)      // gap-jump: weekend/holiday
pending.alertConfiguration = AlertConfiguration(title: E2-derived ("London opens soon"),
                                                body:  marketTimeLabel + local time,
                                                sound: .default)
pending.style       = .standard             // .transient lives only while app in use — wrong here ([LA/AK] §A.2)
```

- **Seamless case** (`gap ≤ maxSeamlessGap = 7 h 30 m`): the pending activity starts at the very instant the current target fires, so the Dynamic Island rolls from "London opens in 0:01" to the successor with no app runtime. 7 h 30 m keeps every leg safely inside the verified **8 h** max active window ([LA/AK] §D) with 30 m margin.
- **Gap-jump case** (`gap > maxSeamlessGap`: FX weekend, single-market configs, holidays): nothing runs during the dead zone; the pending activity starts `resumePreRoll` (60 m) before the reopen. DECISIONS micro-decision: "next LA pre-scheduled for Sunday reopen window".
- The mandatory start alert is not a duplicate of 04's notifications in kind: on iPhone a Live Activity alert "doesn't show a classic banner — it lights the screen and shows the expanded DI presentation" ([LA/AK] §A.4); on a paired Watch the title/body surface as a real alert ([LA/AK] §A.4/§F). Keep the copy short and informational; 04 remains the alerting channel of record.
- **Why only one pending:** the concurrent-activity cap is undocumented (`targetMaximumExceeded`/`globalMaximumExceeded`, community-observed ≈ 5 per app, UNVERIFIED — [LA/AK] §D) and scheduled activities count toward it ([LA/AK] §A.2). One active + one pending = 2, far from any plausible cap, and bounds how much pre-baked (potentially invalidated) state exists. v1.1 may try 2 pendings; treat any deepening as UNVERIFIED tuning.

**How far ahead may `start:` be?** **UNVERIFIED** — [LA/AK] §A.2: "How far in advance `start:` may be ... is not documented." The Friday→Sunday schedule (~46 h ahead) may be rejected or silently dropped. Defensive design: attempt it, log the thrown `ActivityAuthorizationError` if any, and rely on the reconcile-on-next-open fallback (§2.5). QA §7.2 tests this on device.

**Does a scheduled start fire if the app was force-quit/terminated?** **UNVERIFIED** — [LA/AK] §A.2: docs guarantee background only ("even if the app is in the background"); §H.1 point 2 says "test on device". The state machine never depends on it: every path has a foreground-reconcile fallback. Flagged in QA §7.2.

**Collision policy — live activity vs. its pending successor.** The research documents that scheduled activities coexist with active ones (they share the concurrency limit) but does **not** document any auto-replacement when a pending activity starts while the predecessor is still active — **UNVERIFIED**. Defensive design, three layers:

1. **relevanceScore ordering.** `ActivityContent.relevanceScore` decides which of *your* activities owns the Dynamic Island; highest wins, ties go to first-started ([LA/AK] §A.3). Rule: `relevanceScore = targetDate.timeIntervalSinceReferenceDate / 1_000_000` — strictly increasing along the chain, so a just-started successor always outranks its stale predecessor without needing runtime to demote the old one.
2. **End-before-start when we have runtime.** Whenever `scheduleNextChain()` runs with an active predecessor whose `targetDate ≤ pending.start`, the predecessor's replacement plan is recorded; at the next runtime moment at-or-after `pending.start` (foreground or BGAppRefresh), `reconcile()` ends the superseded activity with `.immediate` dismissal. We cannot end it *at* the boundary without runtime — that limitation is honest and mitigated by layer 1 + staleness (§2.6).
3. **Stale treatment on the loser.** The superseded activity hits its `staleDate` seconds after the boundary and renders the stale UI (§2.6) until ended, so even if it lingers on the Lock Screen it never lies.

**User opens the app before the scheduled start.** `reconcile()` sees one `.active` + one `.pending` in `Activity.activities` (`ActivityState.pending` — [LA/AK] §A.5) and:

- both still correct (E1/E2 unchanged) → keep both, no-op;
- world changed (settings/market toggled, conventions edited, holiday shifted the boundary, timezone change re-derivation — 02 §5.2) → end the pending one and re-run `scheduleNextChain()`. Ending a `.pending` activity via `end(nil, dismissalPolicy: .immediate)` is **UNVERIFIED** (research documents `end` on activities generally, [LA/AK] §A.4, but never specifically pending ones); if it proves ineffective on device, fallback: let it start and end it at first runtime after `start` (layer-2 above). QA §7.2.

### 2.4 Transition table (normative)

| # | From | Trigger | Runtime available? | Action | To |
|---|---|---|---|---|---|
| T1 | no activity | foreground pass, E1 exists, gap to E1 ≤ maxSeamlessGap | fg | `request` (countingDown or inProgress per E1.kind) | active(E1) |
| T2 | active(E1, same market as boundary) | boundary passes (open reached) | fg or BG task | `update` → `.inProgress`, targetDate = closeDate, rangeStart = openDate | active(E1′) |
| T3 | active(E1) | boundary passes, E2 cross-market | fg or BG task | end(`.immediate`) + `request`(E2) *(BG task: end + rely on pending — background cannot `request` without `start:`, [LA/AK] §A.2)* | active(E2) |
| T4 | active(E1) + pending(E2) | boundary passes, **no runtime** | none | system starts pending at `start:`; relevanceScore promotes it; predecessor goes stale | active(E2) + zombie(E1) |
| T5 | zombie(E1) | next runtime (fg or BG task) | any | `reconcile()` ends zombie `.immediate` | active(E2) |
| T6 | active(any) | `weekClose` passes / gap > maxSeamlessGap | fg or BG task | end with final `.marketsClosed` content, `.after(now + 30 min)`; `scheduleNextChain()` gap-jump | none + pending(reopen) |
| T7 | none + pending(reopen) | `pending.start` reached | none needed (background verified; terminated UNVERIFIED) | system starts reopen countdown | active(weekOpen/Sydney) |
| T8 | any | `liveActivityEnabled` set false, or `areActivitiesEnabled` flips false | fg | `endAll()` (`.immediate`) | none |
| T9 | any state, 8 h cap hit | system | none | system ends + removes from DI ([LA/AK] §D) | none until next runtime/pending |

### 2.5 Honest limitations — what serverless cannot do

Stated per [LA/AK] §H.2, binding for BUILD_PROMPT:

- **No terminated-app cold start.** Locally, an activity can only start from: the foreground app, a user-invoked `LiveActivityIntent`, or an earlier-scheduled `request(...start:)`. Fully hands-off indefinite auto-start (app never opened again) requires APNs **push-to-start** (iOS 17.2+, [LA/AK] §E) — out of scope for v1 (02 §7.1 row 11: no Push capability).
- **No timed background runtime.** Between app runs, activity *data* is frozen — which is why every displayed element self-ticks (`Text(timerInterval:)`, `ProgressView(timerInterval:)` — [LA/AK] §C) and phase rollovers are pre-baked into the pending activity or `staleDate`-guarded ([LA/AK] §H.2).
- **Hard windows:** **8 h** max active duration (system ends + removes from DI), **up to 4 more hours** on the Lock Screen after end ⇒ **12 h absolute max** on the Lock Screen ([LA/AK] §D — exact verified numbers). Never request an activity whose target is > maxSeamlessGap away; that is what the gap-jump schedule is for.
- **Weekend:** the FX gap (Fri `weekClose` 17:00 America/New_York → Sun `weekOpen` 17:00, spine §3) is ~48 h — cannot be spanned ([LA/AK] §D practical implication). T6/T7 own this: end at `weekClose`, nothing runs Saturday, pending starts Sunday `weekOpen − 60 m`. If the Friday-scheduled Sunday request is rejected (advance-limit UNVERIFIED, §2.3), the first Sunday/Monday app open rebuilds everything.
- **Chain depth without app opens:** one active + one pending means ambient coverage degrades after roughly two chain steps if the user never opens Offset and no BGAppRefresh fires. BGAppRefresh re-extends the chain opportunistically ([LA/AK] §A.4 background update/end; 02 §5.1 step 5) but is never load-bearing: "the system doesn't guarantee launching the task"; realistic cadence "a few times/day for a daily-used app; possibly days apart or never" ([MKT] HALF2 §2). The app's own dogma (02 §5): foreground refresh is primary.
- **Live Activity alerts at arbitrary future instants** can't be raised locally while terminated; the scheduled-activity `AlertConfiguration` covers only the start moment ([LA/AK] §H.2). Event alerting = 04's notifications/alarms.
- The widget extension **cannot** fetch network data or self-refresh (no timeline for Live Activities; sandbox has no network — [LA/AK] §B, §H.2).

### 2.6 staleDate policy

Every `ActivityContent` sets `staleDate = state.targetDate + staleGrace` (120 s). Reaching it flips `activityState` to `.stale` and `context.isStale == true` in the widget UI; nothing is dismissed ([LA/AK] §A.3/§D).

Stale UI treatment (all presentations): countdown/progress replaced by the frozen event line + footer **"Open Offset to refresh"** at `.secondary` opacity; compactTrailing swaps the timer for `Image(systemName: "arrow.trianglehead.2.clockwise")`-style glyph (asset TBD in 07 token pass); minimal dims the dot. Rationale: after `targetDate + grace`, `Text(timerInterval:)` sits at "0:00" ([LA/AK] §C.1 "shows 0:00 at end") — visibly dead content is worse than an honest refresh prompt. The 120 s grace absorbs the T2/T4 handover so the stale UI never flashes during a healthy chain.

BGAppRefresh maintenance re-extends `staleDate` when it rolls content (02 §5.1 step 5; [LA/AK] §H.1 point 3).

### 2.7 End policy — `ActivityUIDismissalPolicy` ([LA/AK] §A.4)

| Situation | Final content | Policy | Rationale |
|---|---|---|---|
| Superseded (T3/T5), settings change, market disabled | none (`nil`) | `.immediate` | A successor already occupies the DI/Lock Screen; a lingering duplicate card is clutter |
| `weekClose` / gap entry (T6) | `.marketsClosed` state: eventTitle "Markets closed", targetDate = `weekOpen` date, marketTimeLabel "17:00 NYC", rangeStart = `weekClose` date | `.after(.now + 30 * 60)` | HIG: 15–30 min custom dismissal "adequate for most summaries" ([LA/AK] §A.4); a half-hour "resumes Sunday" card is useful, all weekend is not. Always pass final content so the lingering card is correct ([LA/AK] §A.4) |
| `endAll()` (toggle off / auth revoked / debug) | none | `.immediate` | User asked for silence |
| 8 h cap (T9) | n/a — system-ended | n/a | System removes from DI immediately ([LA/AK] §D); next runtime reconciles |

Never use `.default` (up to 4 h lingering) — every end path above has a deliberate choice.

---

## 3. Dynamic Island & Lock Screen layout

Widget-extension side, in `OffsetWidgets/MarketCountdownLiveActivity.swift`, per the verified skeleton `ActivityConfiguration(for: MarketCountdownAttributes.self) { context in ... } dynamicIsland: { context in DynamicIsland { ... } }` ([LA/AK] §B). Only research-verified APIs appear below. Color/symbol come from `context.attributes.colorToken`/`symbolName` resolved via `OffsetTheme` (07); `state` = `context.state`.

Sandbox rules ([LA/AK] §B): no network, no location; `withAnimation` ignored (system timing, ≤ ~2 s); interactivity only via `Button(intent:)`/`Toggle(intent:)` (iOS 17+) — v1 ships **zero** buttons in the activity; tap-through uses `widgetURL`.

Device note: iPhone 14 Pro Max is a 6.7″ device — expanded DI width 408 pt, compact leading/trailing ≈ 52.33–62.33 × 36.67 pt, minimal 36.67–45 × 36.67 pt, DI corner radius 44 pt, Lock Screen height 84–160 pt (may truncate above 160 pt) — [LA/AK] §B layout constraints.

### 3.1 compactLeading — market dot + short name

```swift
compactLeading: {
    HStack(spacing: 3) {
        Circle().fill(theme.color(context.attributes.colorToken))
            .frame(width: 7, height: 7)
        Text(context.attributes.marketShortName)   // "LDN"
            .font(.caption2.weight(.semibold))
    }
}
```
Three-char short names (spine §3) fit the ~52–62 pt compact slot; HIG: content sits snug against the camera without padding, keep it as narrow as possible ([LA/AK] §C width constraints).

### 3.2 compactTrailing — the countdown

The compact slot is ~52–62 pt wide, and `Text(timerInterval:)` reserves the maximum width the string could occupy and left-aligns — community-verified gotcha with sanctioned mitigations ([LA/AK] §C). We use the iOS 18 verified fix — `maxFieldCount: 2` renders "1:05" instead of "1:05:03", "the sanctioned fix for compact-DI width" ([LA/AK] §C.4):

```swift
compactTrailing: {
    Text(.currentDate,
         format: .timer(countingDownIn: context.state.rangeStart..<context.state.targetDate,
                        showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
        .monospacedDigit()                              // [GLASS] §6.2 countdown rule
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 50)                            // clamp per [LA/AK] §C (tune 40–50 pt)
        .contentTransition(.numericText(countsDown: true))   // [LA/AK] §B/§C
        .foregroundStyle(theme.color(context.attributes.colorToken))
}
```
`TimeDataSource.currentDate` + `SystemFormatStyle.Timer` are iOS 18.0 ([LA/AK] §C.4) — fine on the iOS 26 floor. When `context.isStale`, swap the timer for the stale glyph (§2.6).

### 3.3 minimal — dot with symbol

```swift
minimal: {
    Image(systemName: context.attributes.symbolName)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(theme.color(context.attributes.colorToken))
}
```
Minimal slot is 36.67–45 × 36.67 pt; oversized images can make `request` **fail** (minimal image ≤ 45 × 36.67 pt) — [LA/AK] §B/§D images row. SF Symbols at explicit small sizes are safe; never place rasterized assets here.

### 3.4 expanded — four regions

Regions per `DynamicIslandExpandedRegion` (`.leading`, `.trailing`, `.center`, `.bottom`; highest-priority region gets full width) — [LA/AK] §B.

```swift
DynamicIsland {
    DynamicIslandExpandedRegion(.leading) {
        Label {
            Text(context.attributes.marketShortName).font(.headline)
        } icon: {
            Image(systemName: context.attributes.symbolName)
                .foregroundStyle(theme.color(context.attributes.colorToken))
        }
        .dynamicIsland(verticalPlacement: .belowIfTooWide)      // [LA/AK] §B
    }
    DynamicIslandExpandedRegion(.trailing) {
        Text(timerInterval: context.state.rangeStart...context.state.targetDate,
             countsDown: true)                                   // [LA/AK] §C.1
            .font(.title2.weight(.semibold))
            .monospacedDigit()                                   // [GLASS] §6.2
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 92)
    }
    DynamicIslandExpandedRegion(.center) {
        VStack(spacing: 2) {
            Text(context.state.eventTitle).font(.subheadline.weight(.semibold))  // "London opens"
            HStack(spacing: 4) {                                  // "08:00 LDN · 3:00 AM local"
                Text(context.state.marketTimeLabel)               // "08:00 LDN" (spine §4)
                Text("·")
                Text(context.state.targetDate, style: .time)      // device-local, [MKT] HALF2 §4 / [LA/AK] §C.2
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
    }
    DynamicIslandExpandedRegion(.bottom) {
        VStack(spacing: 6) {
            ProgressView(timerInterval: context.state.rangeStart...context.state.targetDate,
                         countsDown: false)                       // [LA/AK] §C.3
                .tint(theme.color(context.attributes.colorToken))
            NextEventsPreviewRow(state: context.state)            // §3.4.1
        }
    }
} compactLeading: { ... } compactTrailing: { ... } minimal: { ... }
.widgetURL(SharedConstants.deepLink(.today))                      // offset://today — [LA/AK] §B widgetURL
.keylineTint(theme.color(context.attributes.colorToken))          // [LA/AK] §B keylineTint
```

- Progress semantics: `.inProgress` → `rangeStart = openDate`, so the bar is true session progress; `.countingDown` → fraction of the wait elapsed. `countsDown: false` fills left-to-right. Date-relative progress views don't support custom styles ([LA/AK] §C.3) — tint only.
- `keylineTint` = the market color (subtle DI border tint in Dark Mode, [LA/AK] §B). The DI background is always opaque black and cannot be changed ([LA/AK] §B) — the dark-first palette (spine §5) is designed for this.
- Stale: hide the progress bar, footer "Open Offset to refresh" (§2.6) via `context.isStale` ([LA/AK] §B `ActivityViewContext`).

**3.4.1 `NextEventsPreviewRow` — next-2-events, derived extension-side.** `ContentState` (spine, verbatim) carries no next-event fields, so the row derives them locally: OffsetWidgets links OffsetKit (02 §1 rule 2) and reads App Group `SettingsStore` + bundled seed data — the exact pattern 08 widgets use; App Group reads are not network and are sandbox-legal (02 §1 rule 5). Computation: `SessionScheduleEngine.events(in: DateInterval(start: state.targetDate, duration: 48*3600), settings: snapshot, econEvents: [])`, filter `activityEligible`, `prefix(2)`; render as two `MarketChip`-style dots + short title + `Text(date, style: .time)`. Deterministic in `state.targetDate` (never `Date.now`), so render timing cannot skew it. Memoize per `targetDate` in a static cache; on any decode/read failure the row renders `EmptyView` — the activity never breaks over a preview. Econ events are deliberately excluded (no CacheStore/SwiftData in the LA render path — §1.2).

### 3.5 Lock Screen / banner presentation

The first `ActivityConfiguration` closure ([LA/AK] §B). Mirrors expanded content in a single card:

```swift
ActivityConfiguration(for: MarketCountdownAttributes.self) { context in
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            Label(context.attributes.marketShortName,
                  systemImage: context.attributes.symbolName)
                .font(.headline)
                .foregroundStyle(theme.color(context.attributes.colorToken))
            Spacer()
            Text(timerInterval: context.state.rangeStart...context.state.targetDate,
                 countsDown: true)
                .font(.title3.weight(.semibold)).monospacedDigit()
        }
        Text(context.state.eventTitle).font(.subheadline)
        HStack(spacing: 4) {
            Text(context.state.marketTimeLabel)
            Text("·")
            Text(context.state.targetDate, style: .time)
        }.font(.caption2).foregroundStyle(.secondary)
        ProgressView(timerInterval: context.state.rangeStart...context.state.targetDate,
                     countsDown: false)
            .tint(theme.color(context.attributes.colorToken))
        if context.isStale { Text("Open Offset to refresh").font(.caption2).foregroundStyle(.secondary) }
    }
    .padding(14)                                            // standard Lock Screen margin 14 pt, [LA/AK] §B
    .activityBackgroundTint(Color.black.opacity(0.25))      // [LA/AK] §B — Lock Screen bg only
    .activitySystemActionForegroundColor(.white)            // "Clear" affordance color, [LA/AK] §B
}
```
Dark-first: near-black tint + white system-action color; market color is the only saturation. Height budget 84–160 pt — the stack above fits comfortably; never exceed 160 pt (truncation, [LA/AK] §B).

### 3.6 Always-On display & StandBy

- **Always-On:** system renders Lock Screen activities dimmed; **no animations are performed**; read `@Environment(\.isLuminanceReduced)` and raise contrast / drop bright fills ([LA/AK] §F). Adaptation: market color fills drop to 60% opacity strokes, progress bar renders its static track+fill (it is system-rendered anyway; do not add custom animation), shadows off. Community reports that timer text may tick at reduced frequency in AOD — **UNVERIFIED** ([LA/AK] §F); acceptable, countdown precision is not safety-critical.
- **StandBy:** shows the minimal presentation; tap expands the Lock Screen presentation scaled 2× full-screen; detect with `@Environment(\.isActivityFullscreen)` to raise sizes; Night Mode applies a red tint — verify contrast of the market colors under it ([LA/AK] §F). QA §7.2.

---

## 4. Apple Watch Smart Stack

No standalone watchOS app (DECISIONS Round 2 #3). Coverage comes from automatic mirroring plus one supplemental family:

- **Automatic:** Live Activities auto-appear at the top of the Smart Stack (iOS 18 + watchOS 11+); the default view composites compactLeading + compactTrailing; alert updates forward `AlertConfiguration.title/body` as a real Watch alert ([LA/AK] §F). Our compact pair (dot+LDN | mm:ss) already reads well composited.
- **Customization:** `.supplementalActivityFamilies([.small])` on the `WidgetConfiguration` ([LA/AK] §F; also §B skeleton), then branch on `@Environment(\.activityFamily)` — `.small` = Watch/CarPlay, `.medium` = iPhone/iPad Lock Screen ([LA/AK] §F):

```swift
struct MarketCountdownLockView: View {
    @Environment(\.activityFamily) private var family     // [LA/AK] §F
    let context: ActivityViewContext<MarketCountdownAttributes>
    var body: some View {
        switch family {
        case .small: SmallStackView(context: context)      // Watch / CarPlay
        default:     LockScreenView(context: context)      // §3.5
        }
    }
}
```

- **`.small` layout spec:** one tight HStack — market color dot (6 pt) · event short title (`eventTitle` truncated tail, `.caption.weight(.semibold)`) · compact countdown `Text(timerInterval: rangeStart...targetDate, countsDown: true, showsHours: false).monospacedDigit().frame(maxWidth: 44)` (width mitigation per [LA/AK] §C). No progress bar, no preview row — the Smart Stack card is a glance, and the same layout serves CarPlay where interactive elements are deactivated anyway ([LA/AK] §F: shared layout — design accordingly).
- Tapping on Watch: no watchOS app present → the system shows a full-screen view with an "open on iPhone" button ([LA/AK] §F). Accepted v1 behavior.
- CarPlay (iOS 26) shows the combined compact presentation automatically and adopts the `.small` family layout where offered ([LA/AK] §F) — free, no extra work; verify sizes listed there if CarPlay matters later.

---

## 5. Budgets & constraints (verified numbers)

All from [LA/AK] §D (plus §A.2/§A.6 where noted). BUILD_PROMPT should copy this table.

| Constraint | Value | Offset consequence |
|---|---|---|
| Content size | Static attributes + dynamic state (incl. any push content-state) **combined ≤ 4 KB**; `attributesTooLarge` error text: "exceeded the maximum size of 4KB" | `MarketCountdownAttributes` + ContentState ≈ a few hundred bytes ([LA/AK] §H.1 "~200 bytes"); assert encoded size < 1 KB in debug |
| Max active duration | **8 hours**, then the system ends it and removes it from the DI immediately | `maxSeamlessGap = 7 h 30 m` cap on any countdown leg (§2.3); weekend is gap-jumped, never spanned |
| Post-end Lock Screen persistence | up to **4 more hours** (user removal wins) ⇒ **12 h absolute max** on Lock Screen | `.after(.now + 30*60)` for `weekClose`; `.immediate` elsewhere (§2.7) |
| Dismissal policies | `.default` ≤ 4 h; `.after(date)` clamped to the 4 h window; `.immediate` | §2.7 table |
| Lock Screen height | 84–160 pt; may truncate > 160 pt; 14 pt standard margin | §3.5 layout budget |
| Compact / minimal widths | compact leading & trailing ≈ 52.33–62.33 × 36.67 pt; minimal 36.67–45 × 36.67 pt | §3.1–3.3; timer width clamps |
| Update throttling (push) | Hourly APNs budget exists, **exact number not published (UNVERIFIED)**; `apns-priority: 5` exempt | v1 is pushless — local in-process updates are not budget-limited by APNs rules; limited only by app runtime ([LA/AK] §D "Local (in-process) updates") |
| Frequent-updates plist key | `NSSupportsLiveActivitiesFrequentUpdates` — note the Apple-docs typo: one page misspells it `NSSupportsFrequentLiveActivityUpdates`; the BundleResources reference is authoritative — **use `NSSupportsLiveActivitiesFrequentUpdates`** ([LA/AK] §A.6) | Optional in v1 (lifts only the *push* budget); 02 §7.1 row 5 sets it YES with the same warning |
| Concurrent activities | **No published number.** Signals: `targetMaximumExceeded` (per-app), `globalMaximumExceeded` (device-wide); "the exact number may depend on a variety of factors"; scheduled count toward it; community ≈ 5/app **UNVERIFIED — do not rely** | Never > 2 (1 active + 1 pending). Error handling §6 |
| Images | Asset resolution > presentation size can make `request` **fail** (minimal ≤ 45 × 36.67 pt) | SF Symbols only, explicit point sizes (§3.3) |
| staleDate | Pure UI/logic signal; nothing dismissed | §2.6 |

Plist prerequisites (02 §7.1): `NSSupportsLiveActivities = YES` in the **app target** or `request` fails; no special entitlement exists for Live Activities ([LA/AK] §A.6).

---

## 6. ActivityController spec

App target, `@MainActor @Observable` (spine §4 end; 02 §2 isolation table). Thin lifecycle brain over ActivityKit; all schedule math delegated to OffsetKit (engine is pure — 02 §1).

```swift
@MainActor @Observable
final class ActivityController {
    // Observable surface (read by CountdownAccessoryBar + TodayView, 07)
    private(set) var currentPhase: CountdownPhase?        // nil or .marketsClosed → accessory hidden (spine §5)
    private(set) var areActivitiesEnabled: Bool           // mirror of ActivityAuthorizationInfo

    // Public API
    func startOrUpdate(for event: MarketEvent) async      // §2.2 reducer step 3
    func scheduleNextChain() async                        // §2.3
    func endAll() async                                   // §2.7 (.immediate)
    func reconcile() async                                // §2.2 step 1 + §2.3 pending checks
}
```

Behavioral contract:

- **Authorization gating.** Construct one `ActivityAuthorizationInfo`; consult `areActivitiesEnabled` synchronously before any `request`, and observe `activityEnablementUpdates` (AsyncSequence<Bool>) for the app's lifetime ([LA/AK] §A.5) — on `false` → `endAll()`; on `true` → full reducer pass. There is no runtime permission prompt for Live Activities — only the per-app Settings toggle ([LA/AK] §A.5), so Offset never shows a pre-prompt; AlertsView surfaces a status row when disabled (04 §7 pattern).
- **Settings gating.** `AppSettings.liveActivityEnabled` (spine §4, default true): `false` → `endAll()` and every entry point becomes a no-op. Toggle observed via SettingsStore change notifications (02 §3).
- **Inputs.** `startOrUpdate(for:)` receives the next eligible event from the caller (ScheduleStore/RefreshCoordinator computes it via `nextEvent(after:settings:econEvents:)` + `activityEligible` filter). For `.close` events it asks ScheduleStore for the enclosing `SessionOccurrence` to obtain `rangeStart = openDate` (spine §4 `occurrences(in:markets:conventions:)`).
- **Content building.** attributes ← `Market` row (spine §3 tokens); state ← §1.3 table; `staleDate = targetDate + staleGrace`; `relevanceScore = targetDate.timeIntervalSinceReferenceDate / 1_000_000` (§2.3 collision layer 1; [LA/AK] §A.3).
- **Error handling** (`ActivityAuthorizationError`, [LA/AK] §A.2): `.denied`/`.unsupported` → set `areActivitiesEnabled = false` mirror, silent (02 §8 error philosophy); `.unentitled` → `assertionFailure` (missing `NSSupportsLiveActivities`, config bug); `.attributesTooLarge` → `assertionFailure` (cannot happen at our sizes); `.targetMaximumExceeded` → `endAll()` then retry the request once; `.globalMaximumExceeded` → log (OSLog category `activity`, 02 §8) and skip — next pass retries. Scheduled-request throws additionally logged with the requested `start:` lead for the UNVERIFIED advance-limit finding (§2.3).
- **RefreshCoordinator interaction** (02 §5): foreground pass calls `reconcile()` → `startOrUpdate(for:)` → `scheduleNextChain()`; the `dev.offsetapp.offset.refresh.schedule` BG handler calls the same trio — update/end from background is allowed, starting is not (except the scheduled variant) — [LA/AK] §A.4/§A.2; `scenePhase == .background` transition calls `scheduleNextChain()` (§2.3). System change signals (timezone/significant time, 02 §5.2) funnel into `reconcile()`.
- **Observation streams.** Besides enablement: `Activity.activityUpdates` to notice the pending activity starting while the app happens to be alive, and per-activity `activityStateUpdates` for `.stale`/`.ended` bookkeeping ([LA/AK] §A.5). No `pushTokenUpdates` in v1 (pushless).
- **Logging.** OSLog subsystem `dev.offsetapp.offset`, category `activity` (02 §8): every request/schedule/update/end with activity id, phase, target, and thrown errors. Never log settings blobs.

---

## 7. Test & QA plan

### 7.1 Simulator

- Basic Live Activity rendering works in the simulator per 02 §9 ("Basic rendering exists"), but the research contains **no simulator-specific guarantees for ActivityKit at all — UNVERIFIED**; specifically scheduled-start behavior, staleness timing, AOD/StandBy, and Watch mirroring are **not** simulator-testable evidence (02 §9: "Treat simulator results as non-evidence").
- Use the simulator only for: layout iteration of §3 views (Xcode previews of the extension views with fixture `ActivityViewContext` data where the toolchain allows — preview support for activity contexts is **UNVERIFIED**, fall back to fixture-driven plain-View wrappers), and reducer unit tests (below).
- Unit tests (OffsetKitTests, Swift Testing — spine §1): `activityEligible` filter; chain-step computation (E1/E2, seamless vs gap-jump start dates, weekend T6/T7 fixtures around `weekClose`/`weekOpen`, DST mismatch weeks from spine §3); relevanceScore monotonicity; ContentState builder (phase/targetDate/rangeStart per §1.3); encoded-size assertion < 1 KB (§5). The ActivityKit calls themselves are wrapped behind a protocol so the reducer is testable without the framework.

### 7.2 On-device checklist (iPhone 14 Pro Max — has Dynamic Island, spine §1)

1. Compact presentation: dot+LDN leading, timer trailing fits without ellipsis at "59:59" and "7:29:59" (maxFieldCount: 2 → "7:29") — §3.2.
2. Long-press DI → expanded: four regions render, keyline tint = market color, progress bar animates only via system timer, next-2 preview row correct and stable across expand/collapse.
3. Minimal presentation: run a second app's activity (e.g. a Timer) to force minimal; symbol legible at 36.67 pt.
4. Lock Screen: banner ≤ 160 pt, background tint correct in dark + light wallpapers, "Clear" button legible.
5. Staleness: let a boundary pass with the app killed and no pending scheduled (debug toggle §7.3) → stale UI "Open Offset to refresh" appears ≤ staleGrace + 1 min after target.
6. Chain, backgrounded: foreground app → background it → wait for boundary → pending activity starts and wins the DI (relevanceScore), predecessor stale → open app → zombie ended (T4/T5).
7. Chain, **terminated**: force-quit after backgrounding → does the pending scheduled activity still start? **UNVERIFIED per [LA/AK] §A.2 — this is the single most important device test.** Record the result in DECISIONS; if it fails, the honest coverage story (§2.5) already holds.
8. Scheduled-start advance limit: Friday evening schedule targeting Sunday reopen (~46 h) — accepted or thrown? **UNVERIFIED** (§2.3). Also test a ~10 min and a ~8 h advance.
9. Collision: while an activity is active, let the pending start (device idle) — verify no duplicate DI fight (higher relevanceScore wins per [LA/AK] §A.3) and Lock Screen shows both cards at worst until next app runtime.
10. Weekend: Friday 17:00 America/New_York passes → activity ends with `.marketsClosed` card, card auto-clears ≤ 30 min later, accessory bar hidden, Today hero shows resume state (01 S-C3); Sunday ~16:00 ET the reopen countdown appears (if test 8 passed) or on first app open.
11. Watch (paired): Smart Stack shows the activity; `.small` custom layout renders (not the composited default); start-alert title/body arrive as a Watch alert ([LA/AK] §F).
12. Always-On: dim rendering, no animation artifacts, market colors legible; note observed timer tick cadence (UNVERIFIED reduced frequency, §3.6). StandBy: minimal → 2× full-screen on tap; Night Mode red tint contrast.
13. Authorization: Settings → Offset → Live Activities off → `endAll` fires (enablement stream); re-enable → next foreground restarts.
14. 8 h cap: single-market config (only `fxLondon` enabled) so a leg approaches the cap — verify T9 system end and next-runtime recovery.
15. `AppSettings.liveActivityEnabled` toggle off in-app → everything ends `.immediate`; on → resumes.

### 7.3 Debug screen — `ActivityDebugPanel`

Rows added to the hidden `#if DEBUG` menu (02 §8, which already dumps activities/alarms/notifications):

| Row | Action |
|---|---|
| Force-start activity | Run reducer with `now = Date.now` regardless of gates; show thrown error inline |
| Simulate next 3 chain events | Run the reducer three times with `now` advanced past each successive boundary (uses 02 §8 "override now"); prints each transition (T-numbers §2.4) |
| Schedule pending in +2 min | `scheduleNextChain()` variant with `start = now + 120` — device test for §7.2 items 6–9 without waiting for a real boundary |
| Mark current stale | Rewrites content with `staleDate = now` to preview §2.6 treatment |
| End all | `endAll()` |
| Dump activities | id, state (`active/ended/dismissed/stale/pending` — [LA/AK] §A.5), phase, target, relevanceScore |

Never compiled into Release (02 §9).

---

*Cross-references: 01 Epic C (acceptance stories S-C1…S-C3, S-C5), 02 §5 (RefreshCoordinator choreography), 02 §7 (plist/entitlements), 03 (event stream + occurrence lookup), 04 (notifications/alarms complement; AlarmKit's own countdown Live Activity is spec'd there and in `AlarmPresentationSupport.swift`), 07 §2 (CountdownAccessoryBar reads `currentPhase`), 08 §6 (Watch coverage note). Research: [LA/AK] §A–§F, §H; [MKT] HALF2 §2/§4; [GLASS] §6.2, §7.4.*
