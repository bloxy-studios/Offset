# 07 — UI / UX SPEC: Offset

Status: implementation-ready. Precedence: `DECISIONS.md` > `00-SPINE.md` > this doc. Screen names, stores, and types are spine §2/§4/§5 verbatim.
Citation keys: [LG §n] = `research/ios26-liquid-glass-swiftui.md` · [AK §n] = `research/ios26-activitykit-alarmkit.md` · [MS §n] = `research/market-sessions-and-notifications.md` · [NA §n] = `research/news-and-ai-summaries.md`.
Live Activity / Dynamic Island layouts are owned by `05-LIVE-ACTIVITY.md`; widget timeline providers by `08-WIDGETS.md`. This doc owns everything drawn inside the app plus the visual contract of shared components.

## PROPOSED ADDITIONS

New component vocabulary (app target, `Features/` and `DesignSystem/` per spine §2). The orchestrator should fold these into the spine if adopted:

| Proposed name | What it is | Lives in |
|---|---|---|
| `NextEventHeroCard` | Formal name for spine §5 "hero next-event countdown card" (Today) | Features/Today |
| `OpenMarketsStrip` | Formal name for spine §5 "open-markets strip" (Today) | Features/Today |
| `EconStrip` | Formal name for spine §5 "today's high-impact econ strip" (Today) | Features/Today |
| `CountdownAccessoryBar` | Content view for `.tabViewBottomAccessory` (spine §5 "persistent mini countdown") | RootTabView.swift |
| `BudgetHealthRow` | Formal name for spine §5 "budget health row" (Alerts) | Features/Alerts |
| `WeekScheduleTable` | 7-day open/close table on MarketDetailView | Features/Markets |
| `TimeReadoutChip` | Dual-zone readout shown during Pro timeline scrub | Features/Today (SessionTimelineView) |
| `UpNextList` | Chronological list fallback for SessionTimelineView at accessibility type sizes | Features/Today |
| Timeline sub-terms | `SessionBand` (one rendered segment), `KillzoneLane`, `NowNeedle` — spec vocabulary in §4; may remain private types | SessionTimelineView |

Proposed model addition (requires spine amendment — orchestrator decision): `AppSettings.dismissedExplainerIDs: Set<String>` (default `[]`) to persist `ExplainerCard` dismissals. Until amended, treat as a `SettingsStore`-private key.

APIs used in this doc that are NOT covered by the research files — flagged per spine author rule 2, all long-standing pre-iOS-26 standards; builder may substitute equivalents:

- **TipKit** (coach marks, §3.9): listed as an approved dependency in spine §1 but absent from the research files → UNVERIFIED by research. It is the iOS 17+ standard framework for contextual tips. Usage here is capped and fully degradable (§3.9); if it misbehaves on iOS 26, ship with tips disabled — `ExplainerCard`s carry all teaching load.
- **Rounded font design** for hero numerals (`SF Pro Rounded semibold`, mandated by spine §5): the specific modifier is UNVERIFIED by research; any standard way to select the system rounded design is acceptable.
- **Reduce Motion environment read** (§6): standard SwiftUI environment; UNVERIFIED by research. Needed only to gate decorative symbol animations.
- **Haptic feedback API** (§6): the semantic haptic vocabulary below is the contract; the mapping to a concrete feedback API inside `Support/Haptics` is the builder's choice (standard system feedback generators; UNVERIFIED by research).

---

## 1. Design language

### 1.1 Liquid Glass application — the one rule

**Glass is the functional layer, not the content layer** [LG §1]. In Offset:

| Layer | Surfaces | Treatment |
|---|---|---|
| Glass (system-provided) | Tab bar, toolbars, `.tabViewBottomAccessory` bar, sheets at partial detents, popovers/menus/alerts | Automatic — standard components adopt Liquid Glass with zero code [LG §1, §3.2, §5.3]. Never place opaque backgrounds behind bars (kills scroll edge effect) [LG §6.3, §7.6]. |
| Glass (custom) | **None in v1.** | Offset ships zero custom `.glassEffect` surfaces. This sidesteps the performance and stacking gotchas [LG §7.1] entirely. `GlassHelpers` (spine §2) contains only the accessory placement adapter and stays ready for future glass utilities. Buttons that want glass chrome use `.buttonStyle(.glass)` / `.glassProminent` [LG §2.5] — onboarding CTAs use `.glassProminent`. |
| Content | Every card: `NextEventHeroCard`, timeline, market rows, briefing, headlines, econ strip, rules list | Standard `Material` backgrounds (`.regular` for cards on the scroll surface, `.thin` for chips) — never `.glassEffect` on content [LG §1, spine §5]. |

Both user glass looks must be tested: iOS 26.1 added Settings > Display & Brightness > Liquid Glass **Clear vs Tinted** [LG §7.3]. Never rely on seeing content through a bar; the accessory and tab bar must read correctly at both opacities.

### 1.2 Palette — dark-mode-first

Dark mode is the design target; light mode is fully supported and derived (spine §5). Backgrounds: system background stack + materials, no custom chrome colors. The seven market color tokens (spine §3, defined in `OffsetTheme`):

| Token | Hex | Market |
|---|---|---|
| `.sydneyAmber` | #FFB340 | fxSydney |
| `.tokyoRose` | #FF5E7A | fxTokyo |
| `.londonBlue` | #4DA3FF | fxLondon |
| `.newYorkGreen` | #30D158 | fxNewYork |
| `.usIndigo` | #6E7CFF | usEquities |
| `.lseCyan` | #40C8E0 | lse |
| `.cmeOrange` | #FF9F0A | cmeEquity |

Usage rules: market tokens color **identity surfaces only** — timeline bands, `MarketChip` dots, Live Activity `colorToken`, alarm `tintColor`. They never color text longer than a chip label (contrast) and never tint toolbars (monochrome toolbar icons; tint conveys meaning, not decoration [LG §1]). Semantic colors: system red is reserved for destructive + holiday strikethrough; system yellow for stale-data banners; status "open" uses the market's own token, not a global green.

### 1.3 Typography

- System SF Pro with semantic text styles everywhere; no fixed point sizes [LG §6.2].
- **Countdowns**: `CountdownText` (spine §2 DesignSystem) wraps system timer text with `.monospacedDigit()` — mandatory on every ticking or time-like numeral to prevent width jitter [LG §6.2].
- **Hero numerals** (`NextEventHeroCard`, accessory expanded state): SF Pro Rounded semibold (spine §5; API note in PROPOSED ADDITIONS).
- Dimensions that should track type size use `@ScaledMetric` [LG §6.2].
- List/section headers written in Title Case (iOS 26 no longer uppercases them) [LG §7.6].

### 1.4 Iconography — SF Symbols 7

- Per-market symbols are spine §3 verbatim (`globe.asia.australia.fill`, `sunrise.fill`, `globe.europe.africa.fill`, `globe.americas.fill`, `building.columns.fill`, `building.2.fill`, `chart.line.uptrend.xyaxis`). Tab icons per spine §5 (`clock.fill`, `globe`, `newspaper.fill`, `bell.badge.fill`).
- **drawOn/drawOff** [LG §6.1]: used only where listed in §6 (onboarding hero, permission-granted confirmation, empty states). Decorative; gated on Reduce Motion.
- **Variable draw** [LG §6.1]: `hourglass` with a variable value in `NextEventHeroCard` renders session progress along the symbol path (`in-progress` state) — the research example is literally this use case.
- **Magic replace** [LG §6.1]: `bell` ↔ `bell.fill` content transition on alert-rule toggles.
- Icon-only toolbar buttons always get accessibility labels [LG §7.2].

### 1.5 App icon

Built with Icon Composer as a single layered `.icon` file (replaces the asset catalog); ≤4 layer groups; no baked-in shadows/blur; previewed in Default/Dark/Clear/Tinted appearances [LG §6.4]. Motif: a 24h band with a needle — the timeline itself.

---

## 2. App shell — RootTabView

Five tabs per spine §5. Snippet-level contract (all APIs [LG §3.4], [LG §4], [LG §8]):

```swift
// RootTabView.swift
TabView {
    Tab("Today",   systemImage: "clock.fill")      { NavigationStack { TodayView() } }
    Tab("Markets", systemImage: "globe")           { NavigationStack { MarketsListView() } }
    Tab("News",    systemImage: "newspaper.fill")  { NavigationStack { NewsFeedView() } }
    Tab("Alerts",  systemImage: "bell.badge.fill") { NavigationStack { AlertsView() } }
    Tab(role: .search)                             { NavigationStack { SearchView() } }
}
.tabBarMinimizeBehavior(.onScrollDown)                    // [LG §3.4]
.tabViewBottomAccessory { CountdownAccessoryBar() }       // [LG §3.4]
.searchable(text: $searchText)                            // scoped to the search tab [LG §4]
```

Notes: the search tab is automatically separated at the trailing end; selecting it replaces the tab bar with the search field [LG §3.4]. Tab bars minimize; **toolbars do not** on iOS 26 — do not attempt a toolbar minimize API (iOS 27 only, excluded) [LG §3.2, §7.4]. No custom `scrollEdgeEffectStyle` overrides in v1; `.automatic` everywhere.

### 2.1 CountdownAccessoryBar (bottom-accessory countdown)

```swift
struct CountdownAccessoryBar: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement  // [LG §3.4]
    // Bindings: ScheduleStore → next structural MarketEvent, CountdownPhase,
    //           market colorToken/symbolName/shortName, targetDate, rangeStart
    var body: some View {
        switch placement {
        case .inline: /* collapsed variant */ ...
        default:      /* expanded variant (.expanded / nil) */ ...
        }
    }
}
// Ticking text everywhere: Text(timerInterval: rangeStart...targetDate, countsDown: true)
//   .monospacedDigit()        // zero-timer system rendering [MS §4], [LG §6.2]
```

| State | Content | Trigger |
|---|---|---|
| Expanded | Market dot (`colorToken`) · event label "LDN opens" · `CountdownText` (h:mm:ss) · market-time caption "08:00 LDN" | `placement == .expanded` or nil |
| Inline | Market dot · `CountdownText` (mm:ss or h:mm) only | Tab bar minimized on scroll → `placement == .inline` [LG §3.4] |
| In progress | Dot · "LDN open" · time-until-close `CountdownText` | `CountdownPhase.inProgress` |
| Hidden | No accessory bar at all | `CountdownPhase.marketsClosed` (spine §5) — weekend/holiday-wide gap |

- Data source: the same `CountdownPhase` value `ScheduleStore` derives for the Live Activity (spine §4 `MarketCountdownAttributes.ContentState.phase`) — one truth, two surfaces.
- Hide mechanism: apply the accessory conditionally so no empty glass bar remains. Whether an empty content closure collapses the bar is UNVERIFIED — builder must verify on device and prefer conditional modifier application.
- Tap (any state, any tab): switch selection to Today. Accessibility: one button element, label "Next: London opens in 42 minutes. Opens Today tab." Value updates at minute cadence, not per second.
- The bar itself is system glass; content is plain labels — no nested `.glassEffect` [LG §1].

---

## 3. Screen-by-screen

Template per screen: Purpose · Layout (top→bottom) · Components · Data · Interactions · States · Beginner/Pro table · Accessibility.

### 3.1 TodayView

- **Purpose**: answer "what's open, what's next, what should I know today" in one screen. Default tab.
- **Layout**: `NavigationStack`, title "Today", dynamic `navigationSubtitle` ("3 markets open · overlap in 2h") [LG §3.1]; toolbar trailing gear button → SettingsView (push). ScrollView: ① `NextEventHeroCard` ② `SessionTimelineView` (full interactive, §4) ③ `OpenMarketsStrip` ④ `EconStrip` ⑤ `BriefingCardView` (compact; "Read more" → News tab).
- **NextEventHeroCard**: event title ("London opens"), hero `CountdownText` in rounded semibold, subtitle per spine `MarketEvent.subtitle` ("08:00 London · 3:00 AM your time"), `MarketChip`, and during an in-progress session the variable-draw `hourglass` progress symbol (§1.4). Counts to the next **structural** event (open/close/overlapStart/weekOpen) — `preOpen`/`preClose` leads are alert-only and never hero targets (01 §S-A1; filtering owned by 03 doc). Weekend: card swaps to "Markets closed · resumes Sun 17:00 ET" + date-styled countdown (DECISIONS).
- **OpenMarketsStrip**: horizontally scrolling `MarketChip`s for all `enabledMarkets`, each with status word and minutes-to-transition, sorted open-first.
- **EconStrip**: today's remaining High-impact `EconEvent`s for `econCurrencies`; chips show currency, title, relative time.
- **Data**: `ScheduleStore` (nextEvent, marketStatus, occurrences, phase), `NewsStore` (briefing, econEvents), `SettingsStore` (`AppSettings`). Status recomputation wrapped in minute-cadence timeline updates [MS §4] — never per-second.
- **Interactions**: hero tap → MarketDetailView of the event's market (nil market → GlossaryView "overlap"/"FX week" entry). Band tap → MarketDetailView. Econ chip tap → half-height detail sheet (`presentationDetents`) [LG §5.3]. Briefing tap → News tab.
- **States**: engine content renders instantly from local data — no loading state, ever, including offline. Briefing/econ slots show redacted placeholders while `NewsStore` refreshes; failures show cached content + stale banner (timestamped). Empty (`enabledMarkets.isEmpty`): full-screen prompt "Pick your markets" → Settings.
- **Beginner vs Pro**:

| Surface | Beginner | Pro |
|---|---|---|
| Layout density | Comfortable spacing, one card per row | Denser: hero compressed, strip + econ share a row where width allows (spine §5) |
| Timeline | Simple grouped lanes + overlap glow | Adds `KillzoneLane` + scrub (§4) |
| EconStrip | Event name + time only | Adds forecast/previous values |
| Explainer | First-run `ExplainerCard` under timeline ("How to read this") | Hidden |

- **Accessibility**: cards are single VoiceOver elements with composed labels ("Next event: London opens in 42 minutes, 8:00 AM London, 3:00 AM your time"). Timeline semantics in §4.6. Gear button labeled "Settings".

### 3.2 MarketsListView

- **Purpose**: index of all seven markets with live status.
- **Layout**: title "Markets"; `List` of 7 rows in `MarketID.allCases` order: `MarketChip` (symbol on token-color disc), display name + `shortName`, trailing status chip ("Open · closes 16:00" / "Pre-market" / "Holiday") with relative time. Disabled markets dimmed with caption "Off — not on timeline".
- **Data**: `ScheduleStore.marketStatus` per market; `SettingsStore.enabledMarkets`. Minute-cadence refresh [MS §4].
- **Interactions**: row push → MarketDetailView with zoom transition — row is the matched transition source, detail declares the zoom [LG §5.1]. No reordering (canonical order fixed).
- **States**: no loading (local engine). No empty state (always 7 rows).
- **Beginner vs Pro**: identical except status chip wording (Beginner "Open — busiest hours" annotation during overlap; Pro plain "Open").
- **Accessibility**: each row one element: "London Session, open, closes in 2 hours 14 minutes, your time 12:00 PM."

### 3.3 MarketDetailView

- **Purpose**: everything about one market; the teaching surface.
- **Layout**: large title = display name; `navigationSubtitle` = live status ("Open · closes in 2h 14m") [LG §3.1]. Then: ① header row: market symbol (token color), `Market.kind` label, market-local clock (ticking, minute cadence) ② single-lane `SessionTimelineView` (§4.5) ③ time-toggle segmented control: Local / Market / Both (seeds from `AppSettings.timeDisplayMode`, per-screen override, not persisted) ④ `WeekScheduleTable`: next 7 days × segments with open/close in the chosen zone(s), half-day badge "½ 13:00", holiday rows struck through with name ⑤ Alerts section: this market's `AlertRule`s (same row UI as AlertsView) + "Add alert" ⑥ Beginner `ExplainerCard` ("Why London matters — the most liquid hours…") ⑦ Pro + forexSession only: Killzones section listing overlapping `KillzoneID` windows ⑧ Enable/disable market toggle (writes `enabledMarkets`).
- **Data**: `ScheduleStore` (occurrences over next 7 days, marketStatus), `AlertsStore` (rules filtered by `AlertTarget.market`), `SettingsStore`.
- **Interactions**: rule rows → AlertRuleEditorView sheet (§3.5); explainer links → GlossaryView; killzone row → glossary entry + (Pro) "Edit window" → ConventionsEditorView.
- **States**: none async. Disabling the market shows an inline note "Hidden from timeline and alerts paused" (rules kept, planner skips).
- **Beginner vs Pro**:

| Surface | Beginner | Pro |
|---|---|---|
| ExplainerCard | Visible until dismissed | Hidden |
| Killzones section | Hidden | Visible for forexSession markets |
| WeekScheduleTable | Regular segment emphasized; extended segments collapsed behind "Show extended hours" | All segments expanded, auction rows included |
| Copy | Plain-language segment names ("Pre-market — thin, jumpy") | Canonical `SegmentKind` names + times only |

- **Accessibility**: schedule table rows read date, segment, times, badges ("Friday November 27, regular, 9:30 AM to 1:00 PM your time, half day"). Time toggle announces selection.

### 3.4 NewsFeedView (+ BriefingCardView)

- **Purpose**: briefing first, then headlines with on-demand AI summaries.
- **Layout**: title "News". ① `BriefingCardView` (expanded) ② filter menu (All · per-market via `Headline.related`) ③ headline rows: title (2-line max), source + relative `publishedAt`, related `MarketChip` dots. Pull-to-refresh.
- **BriefingCardView spec**: headline sentence (headline style), 3–5 bullets, watchouts list with warning icon per item, footer: `generatedAt` (relative) + provider badge — `.onDevice` "On-device" / `.exa` "Exa" / `.template` "Offline summary" — + regenerate button (disabled while generating). States: generating (redacted card + "Writing your briefing…"), ready, failed→template (card always renders; per spine §4 TemplateSummarizer never fails), stale (>24 h → "Regenerate" emphasized).
- **Data**: `NewsStore` (headlines from `CacheStore`, `Briefing`, refresh + summarize actions), `SettingsStore.traderLevel`.
- **Interactions**: headline tap → row expands inline: progress line, then 1–2 sentence summary + "Open article" link (external browser). Summary cached in `CacheStore` (01 §S-D3). Second tap collapses.
- **States**: initial-empty: "No headlines yet — pull to refresh." Offline: cached rows + stale banner with last-fetch time. Per-row summary failure: raw headline retained + retry.
- **Beginner vs Pro**:

| Surface | Beginner | Pro |
|---|---|---|
| Briefing tone | Plain language, defines terms, glossary links on jargon | Terse, assumes vocabulary (Briefing.traderLevel) |
| Watchouts | "Big US jobs report at 8:30 AM your time" | "USD NFP 08:30 ET · F: 180K · P: 175K" |
| Filters | All + kind groups (Forex/Stocks/Futures) | Adds per-market filters |

- **Accessibility**: expanded summary announced after loading; provider badge included in card label ("Briefing, generated 7:31 AM via Exa").

### 3.5 AlertsView (+ AlertRuleEditorView)

- **Purpose**: every alert rule, the critical alarms, and an honest budget.
- **Layout**: title "Alerts"; toolbar trailing "+" (new rule). ① `BudgetHealthRow`: "41 of 64 slots" + gauge; tap → half sheet explaining the 56+8 budget and degradation order (spine §4; [MS §1] 64-cap) ② permission status rows: Notifications (granted/denied/not-determined; denied → "Open Settings" guidance) and, only once any `.criticalAlarm` rule exists, AlarmKit status [AK §G.1] ③ rule sections grouped by target family, in spine priority vocabulary: Session Opens & Closes · Pre-Event Warnings (rendered as moment chips on their parent rules) · Overlap · Killzones · Econ Events · FX Week ④ `CriticalAlarmsSection` (spine §2): all rules with `style == .criticalAlarm` + next planned alarm dates from `AlarmPlanner`.
- **Data**: `AlertsStore` (rules, planned counts, permission states), `ScheduleStore` (next occurrence preview per rule).
- **Interactions**: row toggle = `AlertRule.enabled` (magic-replace bell animation §1.4). Row tap and "+" open **AlertRuleEditorView** as a sheet morphing out of its control [LG §5.2] with `presentationDetents([.medium, .large])` [LG §5.3].
- **AlertRuleEditorView spec**: form — target picker (market+segment / overlap / killzone / econ min-impact / fxWeek), moments (atOpen, atClose, before-minutes preset chips 5/10/15/30/60 per DECISIONS 5–60), style picker `standard` / `timeSensitive` / `criticalAlarm` with one-line consequences ("Time Sensitive can break through Focus" [MS §1]; "Critical alarm rings through Silent" [AK §G]), enabled toggle, and a **live notification preview** rendering §5 templates for the current `traderLevel`. Selecting `criticalAlarm` for the first time runs the deferred AlarmKit flow (explainer → system prompt; deny → fall back to `.timeSensitive` + inline warning; 01 §S-B5).
- **States**: notifications denied → banner pinned above all sections. Budget ≥56 → `BudgetHealthRow` switches to "Full — nearest events win" with info sheet. No rules (user deleted all) → empty state "No alerts yet" + Add.
- **Beginner vs Pro**:

| Surface | Beginner | Pro |
|---|---|---|
| Killzones group | Visible, default-off rules, header ExplainerCard link "What's a killzone?" | Default-on (starts), no explainer |
| Econ rules | Impact shown as words ("Big news only") | `EconImpact` values + forecast/previous toggle |
| Editor preview | Plain-language template | Terse template |
| CriticalAlarmsSection footer | "Use for the one or two events you can't sleep through" | Count of planned alarms only |

- **Accessibility**: `BudgetHealthRow` reads "41 of 64 notification slots used". Toggles read full rule ("London Session open alert, on"). Editor preview is one readable element.

### 3.6 SearchView

- **Purpose**: `Tab(role: .search)` — find markets, upcoming events, glossary terms (spine §5).
- **Layout**: landing (empty query): Browse sections — Markets (7 chips), Today's Events (next 6 from engine), Glossary (featured terms). With query: result sections Markets · Events (next 7 days) · Glossary, each row with kind icon.
- **Data**: `ScheduleStore.events` (7-day window), static `Market` list, `glossary.json`. All local; search is instant, no network.
- **Interactions**: market → MarketDetailView; event → its market detail (or glossary for overlap/killzone/econ kinds); term → GlossaryView entry. Search field behavior is system-managed (field replaces tab bar on selection) [LG §4].
- **States**: no results → "No matches for '{query}'" + nearest glossary suggestion.
- **Beginner vs Pro**: identical mechanics; Beginner ranks glossary results first, Pro ranks events first.
- **Accessibility**: results grouped under spoken section headers; event rows include absolute + relative time.

### 3.7 SettingsView (+ ConventionsEditorView, TraderLevelPicker)

- **Purpose**: all of `AppSettings`, entry to Learn and conventions. Reached from Today's toolbar gear (Settings is not a tab, spine §5).
- **Layout** (grouped list, Title Case headers [LG §7.6]): ① Trader Level row → TraderLevelPicker ② Markets: 7 toggles (`enabledMarkets`) ③ Time Display: `TimeDisplayMode` picker (Local/Market/Both; default Both) ④ Briefing: `briefingTime` time picker (default 07:30 device-local) + Econ Currencies multi-select (default USD GBP EUR JPY AUD) ⑤ Live Activity: `liveActivityEnabled` toggle + footnote "Countdown appears in the Dynamic Island" ⑥ Conventions: Pro → ConventionsEditorView; Beginner → locked row "Session Conventions — switch to Pro to edit" ⑦ Learn: Glossary, Replay Onboarding ⑧ About: version, holiday-data coverage note ("Holiday calendar bundled through 2028"), research/data credits.
- **TraderLevelPicker**: two selectable cards — "Beginner: plain language, explainers, simple timeline" / "Pro: killzones, editable conventions, dense layout" — with a bullet diff of what changes (spine §5 gating list). Used at onboarding screen 2 and here; change applies instantly (01 §S-E2).
- **ConventionsEditorView (Pro)**: two sections. Sessions: per forex market, editable `TradingSegment` open/close wall-clock pickers (writes `ConventionSettings.sessionOverrides`; empty = canonical, spine §4). Killzones: per `KillzoneID`, window pickers (writes `killzoneWindows`). Every modified row gets a "Modified" badge + per-row Reset; footer Reset All. Validation: open < close unless the segment `wrapsMidnight`; edits recompute engine output immediately with the warning "Changes retime your alerts and timeline now." Nonexistent local times on DST nights are handled by the engine's matching policy — no UI error needed [MS §3 half 2].
- **Data**: `SettingsStore` (whole `AppSettings`), `ScheduleStore` recompute hooks.
- **States**: none async. Deep-link `offset://alerts` etc. handled by `DeepLinkRouter`, not Settings.
- **Beginner vs Pro**: table above (Conventions locked row is the only structural difference; wording of footers shifts).
- **Accessibility**: locked Conventions row announces "locked, switch to Pro to edit". Pickers all standard controls.

### 3.8 OnboardingFlow (4 screens)

Full-screen pager, page dots, Back allowed, completion persists before Today appears (01 §S-E4).

| # | Screen | Content | Notes |
|---|---|---|---|
| 1 | Value promise | Wordmark + "Every market. Your time." + animated timeline motif (symbols draw on [LG §6.1], skipped under Reduce Motion) + one line: "Opens, overlaps and killzones — in your timezone, on your Lock Screen." CTA Continue (`.glassProminent` [LG §2.5]) | No data collected |
| 2 | Trader Level pick | TraderLevelPicker cards; `.beginner` preselected; caption "Change anytime in Settings" | Writes `traderLevel` |
| 3 | Market pick | 7 `MarketChip` toggle cards, all preselected; kind group captions | Writes `enabledMarkets` |
| 4 | Notification priming | Explains exactly what will be sent ("session opens, your warnings, big econ releases — you control every one") + example rendered notification, THEN button "Enable Notifications" triggers the system prompt; secondary "Not now" | **AlarmKit is NOT requested here** — deferred to first `.criticalAlarm` rule creation (§3.5, [AK §G.1]). Live Activities need no prompt [AK §A.5] |

Decline path: "Not now" completes onboarding; AlertsView shows the permission banner. After screen 4 the app lands on Today with live engine data and (if enabled) starts the Live Activity.

### 3.9 GlossaryView + ExplainerCard pattern (+ coach marks)

- **GlossaryView**: searchable list from `glossary.json` (Learn/, spine §2), grouped by topic — Sessions · Overlap & Liquidity · Killzones (ICT) · Econ Events · Using Offset. Entry page: term, 2–4 sentence definition, "Where you'll see this" deep links, related terms. Reached from: Search tab, Settings > Learn, every ExplainerCard "Learn more", killzone/overlap taps.
- **ExplainerCard**: reusable inline card — icon, 2–3 sentences, optional "Learn more" → glossary, dismiss (X). Dismissal persists via `dismissedExplainerIDs` (PROPOSED ADDITIONS). Beginner: shown by default at the placements named in §3.1/§3.3/§3.5. Pro: all hidden (glossary remains reachable).
- **Coach marks**: TipKit (PROPOSED ADDITIONS — not research-verified; iOS 17+ standard; spine §1 lists TipKit as a dependency). Maximum three tips, each shown once: ① Today timeline "Tap a band for market details" ② accessory bar "This countdown is always with you — tap for Today" ③ after first Pro switch, "Long-press the timeline to scrub". Rules: never two tips on one screen visit; all dismissible; if TipKit is dropped, ship without coach marks — no popover fallback needed because ExplainerCards already teach.
- **Beginner vs Pro**: tips ① ② Beginner-only; tip ③ Pro-only.

---

## 4. SessionTimelineView — signature component

One implementation, three variants (spine §5): Today (full interactive), MarketDetailView (single lane), SessionTimelineWidget (static render).

### 4.1 Geometry

- Horizontal 24h band chart; x-axis = **device-local day, midnight → midnight** (spine §5). Fixed width = container width; no horizontal scrolling.
- Hour grid: hairline ticks every 3 h; labels at 00 · 06 · 12 · 18 (device-local, locale hour style). At narrow widths or large type, labels thin to 00 · 12 · 24.
- `NowNeedle`: full-height hairline (≤2 pt) in primary color with a time chip at top ("14:41"). Position derives from the current date supplied by a minute-cadence timeline update [MS §4] — it **glides in minute steps**; never per-second (§6).
- Occurrences from `SessionScheduleEngine.occurrences(in:markets:conventions:)` for the visible device-local day; bands crossing midnight (cmeEquity `wrapsMidnight`) clip at the edges with a small chevron indicating continuation.

### 4.2 Lanes

- One lane per enabled market, top-to-bottom in `MarketID.allCases` order, visually grouped by `MarketKind` with tiny group captions (Forex · Stocks · Futures).
- **Beginner**: grouped simple lanes as above — nothing else.
- **Pro**: adds `KillzoneLane` beneath the Forex group — a single lane containing the five `KillzoneID` windows (killzones are cross-market, America/New_York-anchored, spine §3) — plus the scrub interaction (§4.4).
- Overlap glow renders at **both** levels (spine §5 lists overlap glow as core band rendering; teaching the overlap is a Beginner goal per DECISIONS): where fxLondon and fxNewYork regular bands vertically coincide, a soft shared glow spans the two lanes with a small "Overlap" caption. Width comes from the structural computation `max(opens)..<min(closes)` — 4 h normal, 5 h in mismatch weeks [MS §5].
- Row height: semantic, `@ScaledMetric`-driven [LG §6.2]; total tappable row ≥44 pt.

### 4.3 Band rendering rules (`SessionBand`)

| Case | Rendering |
|---|---|
| `regular` segment | Market color token at **80% opacity fill**, fully rounded caps (capsule ends) |
| `preMarket` / `afterHours` | Same token at 35% opacity + hairline outline (shape difference, not color alone — §7) |
| `openingAuction` / `closingAuction` | Thin full-height slivers in token color (LSE 07:50–08:00, 16:30–16:35) |
| `maintenanceBreak` | Gap in the band (CME 16:00–17:00 CT) — visibly open on both sides |
| Half-day | Band truncated at early close + "½" badge at the cap; short label on wide layouts ("13:00 close") |
| Holiday | Hollow band (outline only) with strikethrough line + holiday name caption |
| Killzone window (Pro) | Diagonal **hatching** in neutral foreground over a faint token-free fill, label = short name (ASIA · LDN · NY AM · LDN CL · NY PM) |
| Overlap | Shared glow + caption as §4.2; under Reduce Transparency the glow becomes a solid outline (§4.7) |

FX week markers (`weekOpen`/`weekClose`, Sunday/Friday only): flag-post tick at the instant with caption "FX week opens 17:00 NYC".

### 4.4 Interactions

- **Tap a band** (both levels): push MarketDetailView for that market. Tap overlap glow → GlossaryView "London–New York overlap". Tap killzone span (Pro) → glossary entry with "Edit window" link → ConventionsEditorView.
- **Long-press scrub (Pro only)**: touch-and-hold raises a vertical scrub line + `TimeReadoutChip` showing the scrubbed instant **in both zones** — device-local and the zone of the topmost band under the finger ("14:30 your time · 19:30 London"); empty-lane areas show device-local + America/New_York (killzone anchor). Selection haptic tick at each band edge crossed (§6). Release dismisses. Beginner: long-press does nothing.
- Scrub must not conflict with vertical scrolling: activate after the system long-press delay, then own horizontal movement.

### 4.5 Variants

| Variant | Differences |
|---|---|
| Today (full) | All enabled lanes, interactions on, needle live |
| MarketDetailView (single lane) | That market's lane only + overlap glow if fxLondon/fxNewYork + `KillzoneLane` (Pro, forexSession only); same rendering rules; tap disabled (already on detail), scrub (Pro) enabled |
| SessionTimelineWidget (static) | Rendered once per WidgetKit timeline entry (strategy owned by 08 doc): needle drawn at entry date, no interactions, no glow animation; systemMedium = grouped 3-lane summary (Forex group merged into one lane + usEquities + cmeEquity), systemLarge = all enabled lanes; killzone lane only when `traderLevel == .pro`; tap = `widgetURL` `offset://today` |

### 4.6 VoiceOver semantics

- The component is a container announced "Session timeline, today, your time". Lanes are grouped elements headed by market name.
- **Per-band label format (canonical)**: "{Display name}, {segment phrase}, {open}–{close} your time{, badge phrase}{, status phrase}". Examples: "London Session, regular hours, 3:00 AM to 12:00 PM your time, open now, closes in 2 hours 14 minutes." · "US Stocks, regular hours, 9:30 AM to 1:00 PM your time, half day." · "London Stock Exchange, holiday, closed today, Christmas Day."
- Killzone spans (Pro): "London Killzone, 2:00 AM to 5:00 AM your time." Overlap: "London–New York overlap, 8:00 AM to 12:00 PM your time, the most liquid window." Needle: "Now, 2:41 PM."
- Reading order: lane by lane, chronological within a lane. Scrub is not exposed to VoiceOver (equivalent info available via band elements); band taps work as standard activations.

### 4.7 Type scaling & accessibility fallbacks

- Dynamic Type: captions/labels use semantic styles; lane heights scale via `@ScaledMetric` [LG §6.2]. At accessibility sizes where 7 lanes cannot fit legibly, swap the chart for `UpNextList` — a chronological list of today's events ("London opens · 3:00 AM") — selected structurally with `ViewThatFits` [LG §6.2].
- Reduce Transparency: overlap glow → solid 1.5 pt outline; band fills already opaque colors (no material) so they hold [LG §7.2].
- Increase Contrast: fills go 100% opacity + hairline border on every band; killzone hatching thickens [LG §7.2].
- Color-blind safety: no meaning by hue alone — segment kinds differ by opacity + outline + shape, killzones by hatching, overlap by glow/outline + caption, holidays by strikethrough (§7 checklist).

---

## 5. Notification & alert copywriting

Copy is generated by `Formatters` (spine §2) from `MarketEvent` + `TraderLevel`. Rules:

- **Notification subtitle** is always spine `MarketEvent.subtitle` verbatim format: "{HH:mm} {market city} · {local time} your time" → "08:00 London · 3:00 AM your time". Market side is always 24 h; device side follows the user's locale hour cycle. Cities: Sydney, Tokyo, London, New York, Chicago (CME).
- Titles ≤ ~40 characters; bodies one sentence (Beginner) or one dense fragment line (Pro). No emoji, no exclamation marks. `threadIdentifier` groups by market [MS §1].
- Pro open bodies append structural context when applicable: "· overlap in {n}h" (next overlapStart today), "· half day, closes {time}".

Templates per `MarketEventKind` (title / body). {M} = short name, {t} = market-local time:

| Kind | Beginner | Pro |
|---|---|---|
| `open` | "London is opening" / "The most liquid hours of the day start now." | "LDN open 08:00" / "· overlap in 5h" (suffix rule) |
| `close` | "New York has closed" / "The trading day is winding down." | "NYC close 17:00" / "FX day rolls at 17:00 NYC." |
| `preOpen(m)` | "London opens in {m} minutes" / "Get set — liquidity picks up fast at the open." | "LDN open in {m}m" / "08:00 LDN." |
| `preClose(m)` | "New York closes in {m} minutes" / "Volatility often picks up into the close." | "NYC close in {m}m" / "17:00 NYC." |
| `overlapStart` | "London and New York are both open" / "The busiest, most liquid window of the day — worth watching." | "LDN·NYC overlap start" / "{n}h window." |
| `overlapEnd` | "The overlap is over" / "London is done — liquidity thins from here." | "Overlap end" / "LDN closed." |
| `killzoneStart(kz)` | "{Killzone name} is starting" / "A window many traders watch for setups. Tap to learn why." | "{KZ short} start" / "07:00–10:00 NYC." |
| `killzoneEnd(kz)` | "{Killzone name} is over" / "Window closed." | "{KZ short} end" / — |
| `weekOpen` | "The forex week is open" / "Sydney kicks things off. See what's ahead today." | "FX week open" / "17:00 NYC." |
| `weekClose` | "The forex week has closed" / "Markets rest until Sunday 5 PM New York time." | "FX week close" / "Resumes Sun 17:00 NYC." |
| `econRelease(id)` | "Big {currency} news in {m} minutes" / "{title} — expect volatility around the release." | "{currency} {title} {t}" / "F: {forecast} · P: {previous}" (omit missing values) |

Half-day/holiday variants: Beginner "US Stocks close early today — 1:00 PM New York time." / Pro "US half day · close 13:00."

**Critical alarm presentation** (AlarmKit template, [AK §G.3]): alert title = terse regardless of level ("London opens now" — full-screen UI, no room for prose); secondary button "Open" (deep link Today); `tintColor` = the market's color token; countdown presentation title = "{Display name} opens". Alarm metadata carries `MarketID` raw value via `AlarmMetadata` (spine §2 Shared/).

Live Activity strings reuse `eventTitle` ("London opens") and `marketTimeLabel` ("08:00 LDN") from `MarketCountdownAttributes.ContentState` (spine §4); layout owned by 05 doc.

## 6. Motion & haptics

**Symbol animation placements (research-verified only, [LG §6.1]):**

| Effect | Where | Never |
|---|---|---|
| drawOn / drawOff | Onboarding screen 1 hero motif; notification-permission-granted checkmark; empty-state icons | On countdowns or status chips (they change too often) |
| Variable draw (`.draw` value mode) | `hourglass` session-progress symbol on `NextEventHeroCard` while `inProgress` | — |
| Magic replace | `bell` ↔ `bell.badge`/`bell.fill` on rule toggles and the Alerts tab icon badge state | — |
| bounce (iOS 18 effects) | `MarketChip` in `OpenMarketsStrip` at the moment its market opens while the app is foreground | Repeating/looping bounces |
| Gradient symbol rendering | Hero market symbol on MarketDetailView header | Body/text symbols |

Zoom navigation transition for Markets → detail [LG §5.1]; sheet-morph for AlertRuleEditorView out of its "+" button [LG §5.2]; partial-detent sheets keep the system inset glass (no custom presentation background) [LG §5.3]. No custom glass morphing (`glassEffectID`) in v1 — no custom glass exists (§1.1).

**What NEVER animates (performance contract):**

- The `NowNeedle` glides in minute steps via minute-cadence timeline updates [MS §4]; there is no per-second needle animation and no per-second view invalidation anywhere in the app.
- Countdown digits tick via system-rendered timer text (`Text(timerInterval:)` — zero view invalidation) [MS §4], [AK §C]; never a Timer-driven re-render.
- Timeline bands never animate position/size on data refresh (state changes swap without implicit animation); only the scrub line and readout are transient.
- In the Live Activity, animations are system-controlled (explicit animation calls are ignored; numeric roll via content transition where supported) [AK §B, §C].

**Haptic vocabulary** (semantic API of `Support/Haptics`, spine §2; concrete feedback API is builder's choice — PROPOSED ADDITIONS):

| Event | Pattern |
|---|---|
| Session open (app foreground at the instant) | Success pattern |
| Session close | Single light tap |
| Pre-event / econ warning arriving in-foreground | Double tap |
| Timeline scrub band-edge crossing (Pro) | Selection tick |
| Rule toggle / level switch | Standard toggle feedback |
| Critical alarm | None from the app — AlarmKit owns the alert experience [AK §G] |

Reduce Motion: system already tones down glass and morph transitions [LG §7.2]; Offset additionally disables decorative drawOn/bounce effects (gate on the Reduce Motion setting — PROPOSED ADDITIONS note) while keeping magic-replace state changes (they communicate state, reduced by the system).

## 7. Accessibility & quality bar checklist

Ship-blocking checklist — every item verified on device before v1 is "done":

- [ ] **Dynamic Type**: all screens usable at XL; at accessibility sizes, SessionTimelineView swaps to `UpNextList` (§4.7), no truncated countdowns (`monospacedDigit` + semantic styles [LG §6.2]), no fixed-height rows.
- [ ] **VoiceOver full pass**: every screen navigable; timeline per-band labels match §4.6 format; accessory bar is one labeled button (§2.1); icon-only toolbar buttons labeled [LG §7.2]; briefing/provider and budget row values spoken.
- [ ] **Reduce Transparency**: system glass frosts automatically [LG §7.2]; verify overlap glow → outline fallback and that no information lives in translucency alone.
- [ ] **Increase Contrast**: band borders appear, fills go opaque (§4.7); chips and status text pass contrast in both color schemes.
- [ ] **Reduce Motion**: decorative symbol effects off (§6); zoom/sheet transitions acceptable as system-reduced.
- [ ] **Color-blind-safe bands**: killzones hatched, extended hours outlined + dimmed, overlap glowed + captioned, holidays struck through — pattern + shape + label, never color alone (§4.3).
- [ ] **Liquid Glass modes**: correct and legible under both iOS 26.1 user looks, Clear and Tinted [LG §7.3], in dark and light mode.
- [ ] **Hit targets**: every interactive element ≥44 pt including timeline rows (§4.2) and accessory bar.
- [ ] **Hour-cycle & locale**: device-side times respect the user's 12/24 h setting everywhere; market-side times fixed 24 h (§5).
- [ ] **Energy**: Instruments shows no recurring per-second main-thread work while idle on Today (needle at minute cadence, system timer text) [MS §4].
- [ ] **Both Trader Levels**: every screen's Beginner/Pro table in §3 verified by flipping TraderLevelPicker live — no relaunch required (01 §S-E2).
- [ ] **Edge cases rendered**: DST-mismatch week (5 h overlap), NYSE half-day, LSE holiday, CME midnight wrap + maintenance break, weekend `marketsClosed` state — all four visual cases from §4.3 checked against fixture dates [MS §3, §5].
