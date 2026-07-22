# 08 — WIDGETS: Home Screen, Lock Screen accessories, timelines, deep links

Home-screen and Lock-Screen widgets for Offset (DECISIONS Round 2 #3: home widgets + lock accessories + Watch Smart Stack via Live Activity mirroring; **no standalone watchOS app**). Names/types per `00-SPINE.md` (law). Widget view *content* reuses 07's components (SessionTimelineView static variant per 07 §4.5); Live Activity surfaces are owned by `05-LIVE-ACTIVITY.md`.

Research shorthand: **[LA/AK]** = `research/ios26-activitykit-alarmkit.md`, **[MKT]** = `research/market-sessions-and-notifications.md` (HALF1/HALF2), **[GLASS]** = `research/ios26-liquid-glass-swiftui.md`. The iOS 27 exclusion list ([GLASS] §7.4) is binding.

**WidgetKit API verification status (read first).** The research files verify the countdown/timer text APIs, `widgetURL`, `keylineTint`, activity families, and the extension sandbox rules ([LA/AK] §B/§C/§F) — but they do **not** cover core home-widget plumbing (`TimelineProvider`, `TimelineEntry`, `Timeline`, reload policies, `WidgetCenter`, `WidgetFamily` cases, `StaticConfiguration`, `containerBackground`, rendering modes). Per spine §7 rules 2–3, every such symbol below is marked **UNVERIFIED-SDK**: these are long-standing WidgetKit fundamentals (iOS 14–17 era, far below our iOS 26 floor, and none appear on the iOS 27 exclusion list, [GLASS] §7.4), but the coding agent MUST confirm exact names/signatures against the Xcode 26.6 SDK rather than trusting this doc's spelling. Where *behavior* (not just spelling) is unconfirmed, it is marked plain **UNVERIFIED** and carried into QA §7.

---

## PROPOSED ADDITIONS (new vocabulary introduced by this doc)

| Name | Kind | Where | Purpose |
|---|---|---|---|
| `OffsetWidgetEntry` | struct (`TimelineEntry` conformance) | OffsetWidgets | Single entry type shared by all widget kinds (§2.2) |
| `WidgetEntryBuilder` | struct | OffsetWidgets | Pure builder: (now, horizon, stores) → `[OffsetWidgetEntry]` via OffsetKit (§2.3) |
| `NextEventProvider`, `SessionTimelineProvider`, `AccessoryProvider` | provider types | OffsetWidgets | One `TimelineProvider` per widget file (§2.1) |
| `widgetKind` constants | `String` constants (`SharedConstants.swift`) | Shared | `"NextEventWidget"`, `"SessionTimelineWidget"`, `"AccessoryCircularWidget"`, `"AccessoryRectangularWidget"`, `"AccessoryInlineWidget"` — stable kind ids (§2.4) |
| `DeepLinkRoute` | enum | app target (`Support/DeepLinkRouter`) | Parsed `offset://` routes; table + parser in §4 (07 already references `DeepLinkRouter`) |
| `widgetTimelineHorizon: TimeInterval = 36 * 3600` | constant | Shared | Entry-generation window (§2.2) |
| `fixtureEntry` | static `OffsetWidgetEntry` | OffsetWidgets | Deterministic placeholder/snapshot/gallery content (§2.5) |
| RefreshCoordinator → `WidgetCenter` reload duty | behavior addition | app target | Extends the 02 §5.2 action table with widget reloads (§2.4) |

No spine-type changes. Widgets are **non-configurable in v1** (§5), so no AppIntent types are introduced here.

---

## 1. Widget inventory

All widgets live in OffsetWidgets (`dev.offsetapp.offset.widgets`), registered in `OffsetWidgetsBundle.swift` alongside `MarketCountdownLiveActivity` and the AlarmKit presentation config (spine §2; [LA/AK] §B — one extension hosts widgets + Live Activities).

| Widget (file, spine §2) | Families | One-line content | Tap (§4) |
|---|---|---|---|
| `NextEventWidget.swift` | `systemSmall`, `systemMedium` | Next-event countdown + market chip; medium adds 2 upcoming rows + econ count pill | `offset://today` |
| `SessionTimelineWidget.swift` | `systemMedium`, `systemLarge` | Static SessionTimelineView render (device-local 24 h, now needle) + high-impact econ count; Large adds econ rows | `offset://today` |
| `AccessoryWidgets.swift` | `accessoryCircular`, `accessoryRectangular`, `accessoryInline` | Ring to next event / next-2 list / one-liner | `offset://today` |

Family enum spellings (`systemSmall` … `accessoryInline`) are UNVERIFIED-SDK; the product-level names above are established vocabulary (spine §2 file tree, 01 §feature table).

### 1.1 NextEventWidget — systemSmall

Content from `entry.nextEvents[0]` (the same engine stream as the Today hero — includes overlap/killzone/econ kinds, §2.2):

```swift
VStack(alignment: .leading, spacing: 6) {
    HStack(spacing: 4) {                                   // market chip
        Circle().fill(chipColor).frame(width: 7, height: 7)
        Text(chipLabel).font(.caption2.weight(.semibold))  // "LDN" / currency for econ
    }
    Text(next.title)                                       // "London opens" (spine §4 MarketEvent.title)
        .font(.headline).lineLimit(2)
    Text(next.date, style: .timer)                         // self-ticking, [LA/AK] §C.2
        .font(.title2.weight(.semibold))
        .monospacedDigit()                                 // [GLASS] §6.2
    HStack(spacing: 4) {                                   // "08:00 LDN · 3:00 AM"
        Text(marketTimeLabel(for: next))                   // Formatters (spine §2 Support/)
        Text("·")
        Text(next.date, style: .time)                      // device-local, [MKT] HALF2 §4
    }.font(.caption2).foregroundStyle(.secondary)
}
```

- Chip rules: events with `market != nil` → market color token + shortName (spine §3); `.overlapStart/.overlapEnd` → dual-dot (londonBlue + newYorkGreen) + "OVL"; `.killzoneStart/.killzoneEnd` (rendered only when `traderLevel == .pro`; Beginner timelines hide killzones per spine §5, so Beginner widgets skip killzone events entirely) → neutral dot + short name from 07 §4.3 (ASIA/LDN/NY AM/…); `.econRelease` → impact-colored dot + currency code ("USD").
- Countdown > 1 h: swap `.timer` for `Text(next.date, style: .relative)` ("2 hr, 32 min" — [LA/AK] §C.2) via a phase check at entry-build time — avoids the huge reserved width of long timers (§3).
- Weekend (`.marketsClosed` window, 05 §1.3): title "Markets closed", `Text(weekOpen, style: .relative)` countdown, subtitle "resumes Sun 5:00 PM".

### 1.2 NextEventWidget — systemMedium

Left half = the systemSmall stack (§1.1). Right half:

```swift
VStack(alignment: .leading, spacing: 8) {
    ForEach(entry.nextEvents.dropFirst().prefix(2)) { ev in   // next 2 after the hero event
        HStack(spacing: 6) {
            Circle().fill(color(for: ev)).frame(width: 6, height: 6)
            Text(ev.title).font(.caption).lineLimit(1)
            Spacer()
            Text(ev.date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
    if entry.econToday.count > 0 {                             // econ count pill
        Label("\(entry.econToday.count) high-impact today", systemImage: "exclamationmark.circle.fill")
            .font(.caption2.weight(.semibold))
    }
}
```

### 1.3 SessionTimelineWidget — systemMedium / systemLarge

Static `SessionTimelineView` render, exactly per 07 §4.5 variant row (verbatim source): *needle drawn at entry date, no interactions, no glow animation; systemMedium = grouped 3-lane summary (Forex group merged into one lane + usEquities + cmeEquity); systemLarge = all enabled lanes; killzone lane only when `traderLevel == .pro`.* Axis = device-local 24 h with hour labels thinned to 00 · 12 · 24 at medium (07 §4.1).

- Header row (both sizes): "Sessions" caption + trailing econ count pill ("2 high-impact today"), omitted when zero or when CacheStore is unreadable (§2.3).
- **systemLarge additions:** beneath the lanes, up to **3** econ event rows for today — `HStack { impactDot; Text(time, style: .time); Text(currency).bold(); Text(title).lineLimit(1) }`; Pro appends "F: … · P: …" when `forecast`/`previous` are present (mirrors the EconStrip trader-level rule, spine §5); Beginner shows title only.
- The needle does not tick between entries — hourly filler entries advance it (§2.2 point 2); the render must therefore never draw second-precision time text tied to `entry.date` (minute precision only, matching 07 §4.1's minute-cadence needle).
- Band rendering rules, VoiceOver labels, and accessibility fallbacks are 07 §4.3/§4.6/§4.7's — the widget passes a `static: true` flag and otherwise reuses the component unchanged. At accessibility type sizes the widget does **not** swap to `UpNextList` (07 §4.7 is an in-app fallback); it simply renders fewer hour labels — widget text is system-scaled and the lanes are color bands.

### 1.4 AccessoryWidgets — circular

```swift
ZStack {
    ProgressView(timerInterval: entry.date...next.date, countsDown: false)
        .progressViewStyle(.circular)                      // classic ring, [LA/AK] §C.3
        .tint(.primary)                                    // vibrant-safe; no color meaning (§3)
    Image(systemName: symbolName(for: next))               // market SF Symbol (spine §3)
        .font(.system(size: 13, weight: .semibold))
}
```

Ring = fraction of the current wait elapsed, self-ticking with zero runtime ([LA/AK] §C.3; "Date-relative progress views don't support custom styles" — tint only). `rangeStart` for the ring is the entry date (the wait as seen from this entry) — honest and monotonic between entries.

### 1.5 AccessoryWidgets — rectangular

Next **2** events, two lines:

```swift
VStack(alignment: .leading, spacing: 2) {
    ForEach(entry.nextEvents.prefix(2)) { ev in
        HStack(spacing: 4) {
            Circle().fill(.primary).frame(width: 5, height: 5)
            Text(shortTitle(for: ev)).font(.caption2.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 2)
            if ev.date.timeIntervalSince(entry.date) < 3600 {
                Text(ev.date, style: .timer)               // live mm:ss inside the hour
                    .font(.caption2.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 44)                   // width clamp, [LA/AK] §C
            } else {
                Text(ev.date, style: .time).font(.caption2.monospacedDigit())
            }
        }
    }
}
```

### 1.6 AccessoryWidgets — inline

Single text line: `Text("\(shortName) opens ") + Text(next.date, style: .time)` → "LDN opens 3:00 AM". Inline is text-only and single-line; keep the prefix ≤ ~14 chars and let the system truncate (inline length limits are **UNVERIFIED**). Close events read "LDN closes 12:00 PM"; weekend reads "Resumes Sun 5:00 PM".

---

## 2. Timeline strategy

### 2.1 Providers

One provider per widget file — `NextEventProvider`, `SessionTimelineProvider`, `AccessoryProvider` — all `TimelineProvider` conformances (UNVERIFIED-SDK) returning `OffsetWidgetEntry`, all delegating to one `WidgetEntryBuilder` so the entry logic exists exactly once. Widgets use `StaticConfiguration` (UNVERIFIED-SDK) in v1 (§5).

```swift
struct NextEventWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedConstants.widgetKind.nextEvent,   // stable id, §2.4
                            provider: NextEventProvider()) { entry in
            NextEventView(entry: entry)
        }
        .supportedFamilies([.systemSmall, .systemMedium])                 // UNVERIFIED-SDK spellings
        .configurationDisplayName("Next Event")
        .description("Countdown to the next market open or close.")
    }
}
```

### 2.2 Entries

```swift
struct OffsetWidgetEntry /* : TimelineEntry (UNVERIFIED-SDK) */ {
    let date: Date                         // entry activation instant
    let nextEvents: [MarketEvent]          // ≤ 4, sorted; [0] = "next" as of `date`
    let occurrences: [SessionOccurrence]   // visible device-local day (SessionTimelineWidget)
    let econToday: [EconEvent]             // high-impact, enabled currencies, today
    let traderLevel: TraderLevel           // killzone lane + econ detail gating
    let timeDisplayMode: TimeDisplayMode   // Formatters behavior (spine §4)
}
```

Entry dates generated over `widgetTimelineHorizon` (36 h — covers the 24–36 h target even if no reload happens for a full day):

1. **Every `MarketEvent` boundary** in the window — `SessionScheduleEngine.events(in:settings:econEvents:)` (spine §4), *all* kinds: widgets display the same stream as the Today hero (03 doc), unlike the Live Activity's restricted eligible set (05 §1.2). An entry exactly at each boundary makes "next up" flip on time.
2. **Hourly filler** entries at the top of each hour — countdown *text* self-ticks between entries (§3) but derived content does not: the timeline needle (07 §4.1 draws it at entry date), open/closed status strings, and `<1 h` display switches (§1.1/§1.5) advance only at entries.
3. Dedupe (±1 s), sort ascending, cap at **64 entries** — a conservative self-imposed cap; real per-timeline entry limits are **UNVERIFIED**. 36 h ≈ up to ~20 boundaries + 36 fillers ≈ ~56 — fits.

Reload policy: `.atEnd` (UNVERIFIED-SDK spelling) — when the last entry is consumed the system re-asks the provider, which regenerates the next 36 h locally. Providers never await network (§2.3), so generation is fast and deterministic.

### 2.3 Data source — everything local

The widget process computes entries **locally**; there is no network in the widget extension, ever (02 §1 rule 5; [LA/AK] §B sandbox):

- **Engine:** OffsetWidgets links OffsetKit (02 §1 rule 2) and calls the pure `SessionScheduleEngine` directly.
- **Settings:** `SettingsStore` (App Group UserDefaults, spine §4) read-only from the extension — App Group `group.dev.offsetapp.offset` on both targets (02 §7.1/§7.2). Missing/undecodable settings → canonical defaults (spine §4 `AppSettings` defaults), never a blank widget.
- **Seed data:** `sessions.json` / `holidays.json` / `killzones.json` from OffsetKit resources (spine §2) — available to both processes.
- **Econ events:** `CachedEconEvent` rows from CacheStore (SwiftData in the App Group container, spine §4) — **read-only**; the app process is the only writer (02 §3 single-writer discipline). Query scope: today ±1 day, `impact == .high`, currencies ∈ `AppSettings.econCurrencies`. SwiftData open failure or empty store → econ content silently hidden (count pill + rows omitted) — never a broken widget (02 §8 error philosophy).
- Never read: headlines, briefings (no v1 widget renders briefing content), API keys (extension has none, 02 §6).

Timezone correctness: entries pre-bake device-local strings at generation time. After a device timezone change, existing entries are stale until a reload; the app triggers one (§2.4). Whether the system re-requests widget timelines on its own after a timezone change is **UNVERIFIED** — do not rely on it; the app-side reload duty is the mechanism of record.

### 2.4 Forced reloads — RefreshCoordinator duty (extends 02 §5.2)

`WidgetCenter.shared.reloadAllTimelines()` (UNVERIFIED-SDK symbol) is called from the **app process** by RefreshCoordinator at the end of:

| Trigger (02 §5.2 signal) | Why widgets care |
|---|---|
| Settings change (any `AppSettings` write: markets, trader level, conventions, currencies, time display mode) | Lanes/killzones/econ filters/copy all derive from settings |
| Schedule rebuild after each foreground pass | Cheap idempotent insurance; keeps the 36 h horizon rolling with daily app opens |
| `NSSystemTimeZoneDidChange` | Pre-baked device-local strings + needle axis are wrong (§2.3) |
| `UIApplication.significantTimeChangeNotification` | DST just moved wall clocks — regenerate everything |
| `NSCalendarDayChanged` | "Today" econ scope + visible-day occurrences roll over |
| Econ cache update (news BG task or foreground fetch, 02 §5.1) | Count pill + Large econ rows |

BGAppRefresh handlers call it after their work too — reload from background app runtime is expected to work but is **UNVERIFIED**; QA §7 item 9. Per-kind targeted reloads (`reloadTimelines(ofKind:)`, UNVERIFIED-SDK — the `widgetKind` constants exist for this) are an optimization to adopt only if reload cost ever observably matters; v1 reloads all.

### 2.5 Placeholder / snapshot / gallery

Providers must return instantly for gallery and redacted contexts: `fixtureEntry` — a deterministic `OffsetWidgetEntry` built from canonical seed data at a fixed fictional instant (a Tuesday 07:18 America/New_York works well: London open, NY pre-market, 42-min countdown) with 2 fixture econ events. Used for the placeholder path, the snapshot path, and Xcode previews. The placeholder/snapshot API names on `TimelineProvider` are UNVERIFIED-SDK — confirm from the protocol; behavior spec: placeholder = `fixtureEntry` with `.redacted`-friendly layout (no empty strings), snapshot = real entry when stores are reachable, else `fixtureEntry`.

---

## 3. Countdown text in widgets

Verified self-ticking primitives ([LA/AK] §C — "The system renders these live in widgets/Live Activities — text advances every second with zero `update()` calls ... and no app runtime"):

- **`Text(_ date, style: .timer)`** — iOS 14+ ([LA/AK] §C.2; in-app corroboration [MKT] HALF2 §4). Primary countdown (§1.1, §1.5).
- **`Text(timerInterval:pauseTime:countsDown:showsHours:)`** — iOS 16+ ([LA/AK] §C.1) where a bounded range reads better.
- **`ProgressView(timerInterval:countsDown:)`** — iOS 16+ ([LA/AK] §C.3), circular for the accessory ring (§1.4).
- **iOS 18 field-count control** — `Text(.currentDate, format: .timer(countingDownIn: range, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))` ([LA/AK] §C.4) wherever horizontal space is tight; `maxFieldCount: 2` renders "1:05" not "1:05:03".

Layout constraints, carried from the research's verified warning ([LA/AK] §C): timer text **reserves the maximum width the string could occupy and left-aligns**. Mitigations applied at every timer site: `.monospacedDigit()` ([GLASS] §6.2), `.multilineTextAlignment(.trailing)` where right-aligned, explicit `.frame(maxWidth:)` clamps (40–50 pt for MM:SS scale — [LA/AK] §C), `maxFieldCount: 2` or `style: .relative` for > 1 h horizons (§1.1), and the ring instead of text where space is tightest (§1.4 — Apple's own Timer-app pattern per [LA/AK] §C).

**Accessory rendering modes (vibrant/accented):** Lock-Screen accessories render desaturated/vibrant; the environment API commonly known as `widgetRenderingMode` is **not covered by the research — UNVERIFIED** (spelling and behavior). Design defensively without it: accessory layouts encode **nothing in color alone** (dot + text always paired — consistent with 07 §4.3's shape-not-color rule), hierarchy via weight/opacity, `.primary`/`.secondary` styles only (§1.4–1.6). If the coding agent confirms the environment value in the SDK, the only enhancement is: full-color mode → market-colored dots; vibrant → as spec'd. QA §7 item 2 covers legibility either way.

`AccessoryWidgetBackground()` and `containerBackground(for: .widget)` (the iOS 17-era background requirement for home widgets): **UNVERIFIED-SDK** — confirm from the SDK; home widgets use a plain dark-first background consistent with 07's content-layer rule — **no `glassEffect` in widget content**; glass is a control/navigation-layer treatment ([GLASS] §1) and widgets are content.

---

## 4. Deep links — `widgetURL` + `DeepLinkRouter`

Every widget sets one `widgetURL(_:)` (modifier verified in the Live Activity context, [LA/AK] §B; identical usage on home/accessory widgets is standard WidgetKit — UNVERIFIED-SDK beyond that citation). URLs come from `SharedConstants` deep-link builders (spine §2; 02 tree) — never interpolated at call sites.

Route table (owned here; `DeepLinkRouter` lives in `Offset/Support/`, spine §2; 07 references it for the `offset://alerts` route):

| URL | `DeepLinkRoute` case | Tab (spine §5) | Navigation target |
|---|---|---|---|
| `offset://today` | `.today` | Today | Pop to root; scroll to hero card |
| `offset://market/{id}` | `.market(MarketID)` | Markets | Push `MarketDetailView(id)`; unknown `{id}` → Markets root (fail soft, no alert — 02 §8 philosophy) |
| `offset://news/briefing` | `.newsBriefing` | News | News root, briefing card expanded |
| `offset://alerts` | `.alerts` | Alerts | Alerts root (rules list) |
| anything else | `.today` fallback | Today | Root |

```swift
enum DeepLinkRoute: Equatable {
    case today, market(MarketID), newsBriefing, alerts
    init(url: URL) {                       // pure, total — unit-tested in app target
        switch (url.host, url.pathComponents.dropFirst().first) {
        case ("today", _):            self = .today
        case ("market", let id?):     self = MarketID(rawValue: id).map(Self.market) ?? .today
        case ("news", "briefing"):    self = .newsBriefing
        case ("alerts", _):           self = .alerts
        default:                      self = .today
        }
    }
}
```

- v1 widget usage: all widgets → `offset://today` (matches 01 S-C4's `offset://today` expectation for widget taps; the Live Activity uses it too, 05 §3.4). `offset://market/{id}` is exercised today by notification routing (04) and reserved for v1.1 configurable widgets (§5); `offset://news/briefing` by the briefing-ready notification (06 §6). One URL per widget in v1 — per-region `Link` areas inside medium/large widgets are a v1.1 nicety (UNVERIFIED-SDK).
- Routing behavior: `DeepLinkRouter` sets the tab selection, then applies the navigation target on that tab's stack; if onboarding (07) is active, the route is stored and replayed after onboarding completes. Scheme registration: 02 §7.1 row 8.
- Parser tests: malformed hosts, bad market ids, trailing segments, uppercase ids (reject — `MarketID` raw values are case-sensitive, spine §4).

---

## 5. Configuration

- **v1: all widgets are non-configurable.** `StaticConfiguration` (UNVERIFIED-SDK) everywhere; widgets show what the app's settings imply (enabled markets, trader level, currencies). One decision, zero configuration UI, no stale-intent states.
- **v1.1 note:** AppIntent-configurable market selection for `NextEventWidget` and the accessories ("pin this widget to `fxLondon`"), via the AppIntents-based widget-configuration mechanism (AppIntents is already a spine §1 dependency; the specific WidgetKit configuration surface — commonly `WidgetConfigurationIntent` + `AppIntentConfiguration` — is **UNVERIFIED-SDK**, not research-covered). The `offset://market/{id}` route (§4) and `marketStatus(at:market:conventions:)` (spine §4) already exist, so a pinned-market widget lands with no data-layer changes. Build none of it in v1.

---

## 6. Watch note

No watchOS app and no watchOS widget target (DECISIONS Round 2 #3). Apple Watch Smart Stack coverage comes **entirely from Live Activity mirroring** — automatic Smart Stack appearance plus the `.small` supplemental-family custom layout — spec'd in `05-LIVE-ACTIVITY.md` §4 ([LA/AK] §F). The widgets in this doc are iPhone-only surfaces. If a future version ships a watch app, the accessory-family layouts here (§1.4–1.6) are the natural seed for complications — out of scope now.

---

## 7. QA checklist

Simulator is fine for widget layout/timeline iteration (02 §9: "Engine, UI, widgets, snapshot rendering — Fine"); device required for Lock-Screen vibrancy, background reload behavior, and memory.

1. **Widget gallery previews:** every family renders `fixtureEntry` content (§2.5) instantly, with no App Group dependency (fresh install, never-launched app → seed-data defaults per §2.3). No empty strings, no "0:00" timers in placeholder state.
2. **Lock-screen legibility (vibrant rendering):** all three accessories readable on bright and photo wallpapers; nothing color-only (§3); ring + symbol legible at minimum size; inline truncation graceful (§1.6).
3. **Timeline correctness across midnight:** entries spanning 23:00–01:00 device-local — SessionTimelineWidget axis flips at the day-boundary entry; `NSCalendarDayChanged` reload corrects econ "today" scope (§2.4); cmeEquity `wrapsMidnight` band shows edge chevrons on both sides (07 §4.1).
4. **Boundary flips with app killed:** place NextEventWidget, let a real boundary pass — title/chip flip within ±1 min (boundary entry), countdown ticked continuously beforehand; `<1 h` timer/relative switch happens at the right filler entry (§1.1).
5. **App Group access from the extension:** after changing enabled markets in-app, widgets reflect it post-reload (§2.4); verify the extension never touches Keychain/API keys (02 §6) — audit via Console logs, subsystem `dev.offsetapp.offset` (02 §8 widget prefix).
6. **Timezone change:** change device zone with app backgrounded → open app once → widgets re-render with new local axis/strings. Also record whether widgets self-corrected *before* the app opened (system-initiated reload is UNVERIFIED, §2.3).
7. **DST mismatch week fixture:** set device date into a spine §3 mismatch week (2026 Mar 8–29) — overlap width and event times remain structurally correct in the static render (07 §4.2; 03 fixtures).
8. **Weekend state:** Saturday — NextEventWidget/accessories show resume state (§1.1/§1.6); SessionTimelineWidget renders the sparse weekend honestly; Monday pre-open shows Sydney/Tokyo correctly.
9. **Reload from background runtime:** trigger the schedule BG task via the debug menu (02 §8/§9) → does `reloadAllTimelines()` from background runtime refresh widgets? (**UNVERIFIED**, §2.4 — record result.)
10. **Memory:** widget-extension memory limits are **UNVERIFIED** (not research-covered; commonly reported as tens of MB — treat as folklore, budget tightly). Discipline regardless: econ query scoped to ±1 day (§2.3), no headline/briefing reads, static timeline render avoids offscreen layers; profile the extension once in Instruments on device.
11. **Deep links:** every widget/family tap lands on its §4 target from cold start, warm start, and mid-onboarding (route deferred + replayed).
12. **Trader level flip:** Beginner ↔ Pro → after reload: killzone lane appears/disappears (§1.3), killzone events appear/disappear from NextEventWidget (§1.1), econ rows gain/lose F/P suffix (§1.3).
13. **Entry budget:** log generated entry counts per provider; assert ≤ 64 (§2.2) across configs (all markets, single market, econ-heavy week).
14. **Redaction:** system privacy redaction on the Lock Screen (if exercised by the device passcode state) shows no misleading frozen countdowns — placeholder layout uses static text (§2.5).

---

*Cross-references: 01 S-C4/S-C5 (acceptance), 02 §1 (extension rules), §4 (stores), §5 (RefreshCoordinator — this doc extends its action table, §2.4), §7 (entitlements), 03 (engine/event stream), 04 (notification routing shares `DeepLinkRouter`), 05 §1.2 (eligible-set contrast), 05 §4 (Watch), 06 (econ cache + briefing notification route), 07 §4 (SessionTimelineView — §4.5 static variant is the verbatim source for §1.3). Research: [LA/AK] §B/§C/§F; [MKT] HALF2 §2/§4; [GLASS] §1, §6.2, §7.4.*
