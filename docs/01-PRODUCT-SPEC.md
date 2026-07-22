# 01 — PRODUCT SPEC: Offset

Status: implementation-ready. Precedence: `DECISIONS.md` > `00-SPINE.md` > this doc.
Citation keys: [LG §n] = `research/ios26-liquid-glass-swiftui.md` · [AK §n] = `research/ios26-activitykit-alarmkit.md` · [MS §n] = `research/market-sessions-and-notifications.md` · [NA §n] = `research/news-and-ai-summaries.md`.

## PROPOSED ADDITIONS

- **Persona labels** "Kai" (Beginner persona, the actual user) and "Pro Kai" (future-state persona). Doc-local narrative names only; they introduce no code vocabulary.
- No new type, store, or component names are introduced in this doc. UI phrases used below ("hero next-event countdown card", "open-markets strip", "econ strip", "budget health row") are spine §5 phrases verbatim; their formal component names are proposed in `07-UI-UX-SPEC.md`.
- **Default alert-rule table** (§4, footnote a): this doc fixes family-level defaults; `04-ALERTS-NOTIFICATIONS.md` must encode the per-`AlertRule` set to match this table exactly.

---

## 1. Vision & positioning

Offset is a session-aware trading clock for one person. It answers, at a glance and in Kai's own timezone, the only questions that matter before price does anything: which markets are open right now, what happens next, and how long until it does — Sydney, Tokyo, London, New York forex sessions, US equities with extended hours, the LSE, and CME Globex futures, each materialized per-day in its own IANA zone so DST-mismatch weeks are correct by construction, never by lookup table. The next event counts down in the Dynamic Island and the tab-bar accessory without the app running; the sacred few events ring through Silent mode via AlarmKit; the routine rest arrive as budgeted local notifications that never silently saturate. **Every market. Your time.**

The second job is the differentiator: Offset teaches session structure while it alerts. Kai is still learning — so every alert, timeline band, and card can explain itself in plain language (why the London–New York overlap is the most liquid window, what a killzone is, why the open matters), with a Trader Level switch that swaps the same surfaces into terse, dense, convention-editable Pro mode as he grows. Offset is not a charting app, not a broker front-end, and not a news terminal; it shows no prices at all. It is the structural clock those tools assume you already have in your head — plus an AI briefing before you sit down, generated on-device when the hardware allows and via Exa when it doesn't.

## 2. Personas

### 2.1 Kai — Beginner (the actual user)

| Facet | Detail |
|---|---|
| Device | iPhone 14 Pro Max — Dynamic Island YES, Apple Intelligence NO (DECISIONS Round 2 #1). Consequence: `ExaAnswerSummarizer` is his runtime summary path; `FoundationModelsSummarizer` is built but reports unavailable on this device [NA §4]. |
| Profile | Still learning, no fixed trading style yet (DECISIONS Round 1). Curious about ICT concepts but not fluent. Trades around a day job — checks the phone between sessions, not a chart wall. |
| Core wants | (1) Never miss a session open — especially London and New York — even with the phone on Silent overnight for the sacred ones. (2) Understand WHY sessions matter: what the overlap is, why Tokyo is quiet for GBP, what a half-day does. |
| Defaults | `traderLevel = .beginner`, all seven `enabledMarkets`, plain-language notification copy, explainer cards visible, killzone layer hidden (spine §5). |
| Frustrations to solve | Timezone math ("is London open now or in an hour?"), DST-mismatch weeks silently breaking mental models, alert apps that either spam or drop events, jargon with no glossary. |

### 2.2 Pro Kai — the future-state persona

Same human, six months later (DECISIONS Round 1: "aspires to pro/ICT concepts"; Round 2 #4: Trader Level is a setting, changeable anytime). Pro Kai flips `traderLevel = .pro` and expects: killzone lane and killzone alerts on (`asia`, `london`, `nyAM`, `londonClose`, `nyPM` — spine §3 defaults, majority ICT convention), the conventions editor unlocked (session hours and killzone windows editable, per the "editable defaults" philosophy in DECISIONS), a denser Today layout, forecast/previous values on the econ strip, terse notification copy ("LDN open 08:00 · overlap in 5h"), and long-press scrubbing on the timeline with dual-zone readout. Nothing is a separate app or paywall — one switch, many effects (spine §5).

## 3. Jobs-to-be-done

1. When a major session open is approaching while I am away from my desk, I want a reliable, timezone-correct heads-up on my phone, so I never miss an open I care about.
2. When I glance at my phone (Lock Screen, Dynamic Island, tab bar, widget, watch), I want to see what is open and what is next without launching anything, so market awareness costs me zero effort.
3. When clocks shift in one hub but not another (DST-mismatch weeks), I want every displayed time, band, overlap, and alert to stay correct automatically, so I never do — or botch — the math myself.
4. When I sit down before my session, I want a short AI briefing of what today is about and what to watch out for, so I start oriented instead of doomscrolling headlines.
5. When a high-impact economic release is imminent for a currency I trade, I want an advance warning, so volatility never ambushes me.
6. When Offset shows me a term or structure I don't know (overlap, killzone, auction, half-day), I want a plain-language explanation one tap away, so the app makes me a better trader while I use it.
7. When one specific event is absolutely can't-miss, I want an alarm that breaks through Silent mode and Focus, so my sleep settings can't cost me the open.

## 4. Feature inventory

Column key: B = default with `traderLevel == .beginner`, P = default with `.pro`. "On" for an alert family means its default `AlertRule`s ship `enabled == true`.

| Feature | Description | Tab / surface | B default | P default | Version |
|---|---|---|---|---|---|
| Session dashboard | Hero next-event countdown card, open-markets strip, econ strip, briefing card (spine §5) | Today | On | On (denser layout) | v1 |
| SessionTimelineView | 24h horizontal band chart, device-local axis, "now" needle; signature component | Today · Market detail · widget | Grouped simple lanes, overlap glow | Adds killzone hatching lane + scrub | v1 |
| Market detail | Week schedule, local↔market time toggle, per-market alerts, beginner explainer | Markets → MarketDetailView | Explainer visible | Explainer hidden, denser | v1 |
| Alerts: opens & closes (family 1) | `market(id, .regular)` at `atOpen`/`atClose` for enabled markets | Alerts | On | On | v1 |
| Alerts: pre-event warnings (family 2) | `before(minutes:)` leads, 5–60 min; default single 15-min lead on opens | Alerts | On (15 min) | On (15 min) | v1 |
| Alerts: London–NY overlap (family 3) | `overlap` target; `overlapStart` on, `overlapEnd` available | Alerts | On (start only) | On (start only) | v1 |
| Alerts: ICT killzones (family 4) | `killzone(id)` targets, all five `KillzoneID`s | Alerts | Off (rules visible, toggleable) | On (starts only) | v1 |
| Alerts: high-impact econ (family 5) | `econ(minImpact: .high)`, 15-min lead, currencies from `econCurrencies` | Alerts | On | On (+ forecast/previous in body) | v1 |
| FX week markers | `weekOpen` Sun 17:00 / `weekClose` Fri 17:00 America/New_York; display always, alert optional | Today · Alerts | weekOpen alert on, weekClose off | Same | v1 |
| Extended-hours boundary alerts | `preMarket`/`afterHours`/auction segment events (DECISIONS Decided #5) | Alerts | Off (shown on timeline) | Off (shown on timeline) | v1 |
| Critical alarms | `AlertStyle.criticalAlarm` → AlarmKit `.fixed` alarms; breaks Silent/Focus [AK §G] | Alerts → CriticalAlarmsSection | Off (opt-in per rule) | Off (opt-in per rule) | v1 |
| Live Activity auto countdown | One MarketCountdown activity to next event; self-ticking; scheduled-LA chaining [AK §A.2, §C] | Dynamic Island · Lock Screen | On (`liveActivityEnabled = true`) | On | v1 |
| Bottom-accessory countdown | Persistent mini countdown in tab shell; hidden while `.marketsClosed` (spine §5) | App shell | On | On | v1 |
| News feed + AI summaries | Headlines (Finnhub + RSS) with tap-to-expand 1–2 sentence summaries [NA §2, §5] | News | On | On | v1 |
| Daily briefing | `Briefing` (headline, 3–5 bullets, 0–3 watchouts) at `briefingTime` 07:30 device-local | News top · Today card | On, plain-language | On, terse | v1 |
| Econ strip | Today's high-impact releases for selected currencies; minimal, not a calendar tab | Today | On (High only) | On (+ forecast/previous) | v1 |
| Home widgets | `NextEventWidget` (systemSmall/Medium), `SessionTimelineWidget` (systemMedium/Large) | Home Screen | Available | Available (killzones rendered per level) | v1 |
| Lock widgets | `AccessoryWidgets` (circular, rectangular, inline) | Lock Screen | Available | Available | v1 |
| Watch smart stack mirroring | Live Activity mirrors via `supplementalActivityFamilies([.small])`; no watch app [AK §F] | Apple Watch | On (automatic) | On | v1 |
| Onboarding | 4 screens: value promise → Trader Level pick → market pick → notification priming. No AlarmKit prompt here | First run | `.beginner` preselected | — | v1 |
| Learn / glossary | `GlossaryView` + `ExplainerCard` pattern + `glossary.json` | Search · Settings · inline | Inline links on | Inline links off, glossary reachable | v1 |
| Trader Level | Single switch, many effects (spine §5); set at onboarding, changeable anytime | Onboarding · Settings | `.beginner` | `.pro` | v1 |
| Conventions editor | Edit session hours + killzone windows (`ConventionSettings`) | Settings → ConventionsEditorView | Hidden (locked row) | Unlocked | v1 |
| Settings | Markets, time display, briefing time, currencies, Live Activity toggle, level, Learn, About | Today toolbar → SettingsView | — | — | v1 |
| Manual countdown timer | User-defined ad-hoc countdown (explicitly excluded from v1, DECISIONS Round 1) | — | — | — | v1.1 candidate |
| CME 15:15–15:30 CT equity halt band | Omitted pending official verification (DECISIONS Decided #6; [MS §4 half 1] UNVERIFIED) | — | — | — | v1.1 candidate |
| Remote holiday JSON refresh | Fetch replacement `holidays.json` from a user-controlled URL [MS §6] | — | — | — | v1.1 candidate |
| Notification quick actions | e.g. "Mute this market today" category actions [MS §1] | — | — | — | v1.1 candidate |
| Econ actuals / surprise display | Requires a source beyond ForexFactory feed (no `actual` field) [NA §3] | — | — | — | v1.1 candidate |

Footnote a: the per-rule default set (exact `AlertRule` values, styles, moments) is owned by `04-ALERTS-NOTIFICATIONS.md` and MUST match this table. Product-level style guidance: pre-event leads and econ warnings use `.timeSensitive`; at-moment opens/closes use `.standard` ([MS §1] recommends `.timeSensitive` only for imminent-event alerts); `.criticalAlarm` is never a default.

## 5. User stories

All stories are testable; engine-level assertions run against `SessionScheduleEngine` fixtures in `OffsetKitTests` (see 03 doc).

### Epic A — Sessions & Time

**S-A1 · Glanceable status for all seven markets**
Given a fresh install with default `AppSettings` (all seven `enabledMarkets`),
When Kai opens the Today tab,
Then the open-markets strip shows one chip per market whose status equals `SessionScheduleEngine.marketStatus(at:market:conventions:)` for the current instant, and the hero card counts down to the next structural event (`open`/`close`/`overlapStart`/`weekOpen` — never a `preOpen`/`preClose` lead) matching `nextEvent(after:settings:econEvents:)` filtered per 03 doc.

**S-A2 · DST-mismatch correctness (the flagship correctness story)**
Given the device zone is Europe/London and the simulated date is Mon 2026-03-09 (US already on EDT, UK still on GMT — mismatch window Mar 8–29, 2026, spine §3),
When the timeline and MarketDetailView render,
Then the London–NY overlap band spans 12:00–17:00 London wall clock (5 hours, computed structurally as `max(opens)..<min(closes)` — never the hardcoded 4-hour normal), fxNewYork's band starts at 12:00 London wall clock, and every `MarketEvent.subtitle` shows both zones (e.g. "08:00 New York · 12:00 PM your time") [MS §5 worked example].

**S-A3 · Travel / timezone change**
Given a computed schedule and pending notifications built while the device was in America/New_York,
When the device timezone changes to Asia/Tokyo (system timezone-change signal [MS §2]),
Then `RefreshCoordinator` triggers a full engine pass: the timeline re-axes to the new device-local day, all "your time" strings update, and the pending notification set is rebuilt — with no stale wall-clock strings anywhere.

**S-A4 · Holidays and half-days**
Given `holidays.json` covering 2026 (NYSE closed Thu 2026-11-26, half-day Fri 2026-11-27 with 13:00 ET close; LSE half-day Thu 2026-12-24 with 12:30 close) [MS §3],
When Kai views usEquities on those dates,
Then Thu shows `MarketStatus.holiday(name:opensAt:)` with a strikethrough band and the holiday name, and Fri shows a truncated band with a half-day badge, after-hours truncated to 13:00–17:00 (spine §3), and no open/close alerts fire for suppressed segments.

**S-A5 · CME wraps midnight**
Given cmeEquity enabled on a Tuesday,
When the timeline renders,
Then the CME lane shows a band entering from midnight (Monday 17:00 CT session), a `maintenanceBreak` gap at 16:00–17:00 CT rendered as a break (not a close), and the band continuing to the right edge — with `wrapsMidnight` handled by clipping to the visible day, and Sunday shows open at 17:00 CT only.

### Epic B — Alerts

**S-B1 · Open alert, correct in local time**
Given the default rule `market(fxLondon, .regular)` with `atOpen` enabled,
When London opens at 08:00 Europe/London,
Then a notification is delivered within one minute of the instant, with Beginner copy per 07 §5 ("London is opening — the most liquid hours of the day start now") and subtitle "08:00 London · 3:00 AM your time" format per spine `MarketEvent.subtitle`, scheduled via a non-repeating calendar trigger with explicit market timezone [MS §1].

**S-B2 · Pre-event lead is adjustable 5–60 min**
Given Kai edits the fxNewYork open rule in AlertRuleEditorView and sets `before(minutes: 30)`,
When the rule saves,
Then `AlertsStore` persists `moments` containing `.before(minutes: 30)`, the planner reschedules, and the next NY open produces a warning exactly 30 minutes before the materialized open instant; offered presets are 5/10/15/30/60 within the DECISIONS 5–60 range.

**S-B3 · 64-cap degradation is honest and prioritized**
Given all seven markets and all five alert families enabled (worst case >200 candidates over 7 days [MS §5 half 2]),
When `NotificationPlanner.plan(events:rules:now:)` runs,
Then at most 56 notifications are scheduled with 8 slots reserved (spine §4), every enabled event within the next 24 h is scheduled, farther events degrade by the spine priority order "sooner > criticalAlarm-backed > opens > econ high > closes > killzones > overlaps", and the Alerts tab budget health row reports the real count (e.g. "41 of 64 slots").

**S-B4 · Critical alarm breaks Silent (the sacred path)**
Given Kai sets the fxLondon open rule's style to `.criticalAlarm`, AlarmKit authorization is granted, and the device is in Silent mode with a Focus active overnight,
When the open instant arrives,
Then an AlarmKit alarm fires full-screen with sound, breaking Silent and Focus [AK §G, §G.4], planned by `AlarmPlanner` as a `.fixed` date materialized in the market zone (never `.relative`, spine §4 + [AK §G.2]), with a Stop button and an "Open" secondary action deep-linking to Today.

**S-B5 · AlarmKit permission is deferred, never at onboarding**
Given a fresh install where onboarding completed,
Then AlarmKit authorization state is still not-determined [AK §G.1];
When Kai first switches any rule's style to `.criticalAlarm`,
Then an in-app explainer sheet appears first ("this rings through Silent"), then the system AlarmKit prompt; if denied, the rule falls back to `.timeSensitive` with an inline warning row and a path to system Settings.

**S-B6 · High-impact econ warning**
Given the default `econ(minImpact: .high)` rule with a 15-minute lead and "USD" in `econCurrencies`, and the cached ForexFactory feed contains a High-impact USD event at 08:30 America/New_York [NA §3],
When the lead instant arrives,
Then a `.timeSensitive` warning fires; Beginner body is plain-language ("Big US news in 15 minutes…"), Pro body appends forecast/previous when present ("F: -0.2% · P: 1.0%"); Medium/Low events never alert by default.

### Epic C — Glance (Live Activity + widgets)

**S-C1 · Auto countdown starts itself**
Given `liveActivityEnabled == true` and no active activity,
When the app foregrounds,
Then `ActivityController` requests one MarketCountdown Live Activity for the next structural event, whose countdown ticks every second with zero updates or pushes via system-rendered timer text [AK §C], showing `eventTitle`, `marketTimeLabel`, and progress from `rangeStart`.

**S-C2 · Scheduled-LA chaining (best effort, honest fallback)**
Given the current activity counts to London open and the app was foregrounded at least once today,
When the open passes,
Then the activity's phase updates to `.inProgress` (on next app runtime or pre-baked state), and a pre-scheduled activity for the following event (created earlier via the iOS 26 scheduled request with `start:` date and mandatory alert configuration [AK §A.2]) becomes active at its start date.
And because terminated-app behavior of scheduled activities is UNVERIFIED [AK §A.2], the guaranteed fallback is: next foreground always reconciles `Activity.activities`, ends orphans, and starts the correct activity.

**S-C3 · Weekend gap state**
Given Friday 17:00 America/New_York (`weekClose`) has passed,
Then no Live Activity attempts to count across the ~48 h gap (8 h max active window [AK §D]); the bottom accessory is hidden (`phase == .marketsClosed`, spine §5); Today's hero card shows "Markets closed · resumes Sun 17:00 ET" with a date-styled countdown; and a scheduled activity targets the Sunday reopen window (DECISIONS micro-decisions).

**S-C4 · Home widgets**
Given `NextEventWidget` (systemSmall) and `SessionTimelineWidget` (systemLarge) are placed,
When the Home Screen renders,
Then NextEventWidget shows the next event title, market chip, and a self-updating countdown; SessionTimelineWidget shows the static timeline render (no needle animation, killzone lane only when `traderLevel == .pro`); tapping deep-links via `offset://today` / `offset://market/{id}` (spine §1, DECISIONS).

**S-C5 · Lock Screen + Watch**
Given the accessory rectangular widget is on the Lock Screen and an Apple Watch is paired,
Then the rectangular accessory shows event title + countdown; the inline accessory shows "LDN opens 3:00 AM"; and the Live Activity appears in the watch Smart Stack using the `.small` supplemental family with a custom compact layout [AK §F] — with no standalone watchOS app (DECISIONS Round 2 #3).

**S-C6 · Accessory collapse behavior**
Given Kai scrolls down a long News feed (tab bar minimizes, spine §5 + [LG §3.4]),
When the tab bar collapses,
Then the accessory renders its `.inline` variant (market dot + mm:ss only) per the accessory placement environment [LG §3.4], re-expands on scroll up, and tapping it in either state switches to the Today tab.

### Epic D — News & AI

**S-D1 · Daily briefing before the session**
Given `briefingTime == 07:30` device-local and cached headlines/econ events exist,
When Kai opens the app at 07:45,
Then BriefingCardView shows a `Briefing` generated for today: one-sentence headline, 3–5 bullets, 0–3 watchouts (unusual hours, high-impact releases), labeled with its `SummaryProvider` and `generatedAt`, matching `traderLevel` tone.

**S-D2 · Fallback chain on iPhone 14 Pro Max (mandatory path)**
Given Kai's device does not support Apple Intelligence, so the on-device model reports unavailable(.deviceNotEligible) [NA §4],
When `BriefingEngine` runs,
Then `FoundationModelsSummarizer.isAvailable()` returns false, `ExaAnswerSummarizer` produces the briefing, and `Briefing.provider == .exa`;
And given the Exa key is missing or the request fails,
Then `TemplateSummarizer` produces a deterministic non-AI briefing from cached headlines and econ events with `provider == .template` — the card never renders an error-only state (spine §4: TemplateSummarizer "never fails").

**S-D3 · Tap-to-expand headline summaries**
Given the News feed lists `Headline` rows without summaries,
When Kai taps a headline,
Then the row expands with a progress state, `Summarizer.summarize(headline:)` fills `summary` (1–2 sentences), the result is cached in `CacheStore` (no re-generation on next expand), and on failure the row shows the raw headline with a retry affordance and working source link.

**S-D4 · Econ strip freshness**
Given the ForexFactory this-week feed was last fetched successfully,
When Today renders,
Then the econ strip shows today's remaining High-impact `EconEvent`s for `econCurrencies` in chronological order with relative countdowns;
And given the last successful fetch is older than 24 h,
Then the strip shows a stale-data banner with the fetch timestamp (feed is this-week-only; no next-week variant exists [NA §3]).

### Epic E — Learn & Levels

**S-E1 · Explainers teach in context**
Given `traderLevel == .beginner`,
When Kai opens MarketDetailView for fxLondon,
Then an `ExplainerCard` explains the session in plain language with inline glossary links; tapping a linked term opens the matching `GlossaryView` entry; dismissing the card persists (it does not reappear on next visit).

**S-E2 · Trader Level switch is instant and total**
Given `traderLevel == .beginner`,
When Kai switches to `.pro` in TraderLevelPicker,
Then without relaunch: the killzone hatching lane appears on the timeline, killzone alert rules become default-on (existing user toggles preserved), the conventions editor row unlocks, econ strip gains forecast/previous, notification copy switches to terse templates for newly planned notifications, and Today adopts the denser layout (spine §5 gating list).

**S-E3 · Conventions editing (Pro, "editable defaults")**
Given `traderLevel == .pro`,
When Kai edits the `london` killzone window from 02:00–05:00 to 01:00–05:00 in ConventionsEditorView,
Then `ConventionSettings.killzoneWindows[.london]` updates, the engine recomputes occurrences and events, timeline and planned alerts reflect the new window on next plan pass, the row shows a "modified" badge with per-item reset, and canonical defaults (spine §3) are restorable at any time.

**S-E4 · Onboarding produces a working app**
Given a fresh install,
When Kai completes the 4 onboarding screens (value promise → Trader Level pick → market pick → notification permission priming),
Then `traderLevel` and `enabledMarkets` are persisted, the system notification prompt was shown only after the priming screen (and a decline still lands in a working app with a status row in Alerts), no AlarmKit prompt occurred, and Today renders live engine data immediately — the session engine requires no network, no account, no permission.

## 6. Non-goals / out of scope for v1

- **No charts and no price data.** Offset never renders a candle, quote, or spread. Structure only.
- **No broker integration** — no order routing, positions, or P&L.
- **No accounts, no sync, no backend.** Single user, on-device state. Consequently: no APNs server, no push-to-start or remote Live Activity updates [AK §E, §H.2] — all Live Activity behavior is local/scheduled.
- **No Android, no web app.** iPhone-only; iPad runs in compatibility mode (spine §1).
- **No manual countdown timer** in v1 (DECISIONS Round 1; v1.1 candidate).
- **No crypto markets** (DECISIONS Round 1).
- **No full economic calendar tab** — only the minimal high-impact strip plus alerts (DECISIONS Round 1).
- **No standalone watchOS app** — Smart Stack mirroring only (DECISIONS Round 2 #3).
- **No CME per-holiday hours modeling** — US-holiday days are flagged as "altered hours", not precisely modeled [MS §4 half 1].
- **No App Store distribution** — personal Xcode install (spine §1).
- **No third-party SPM dependencies** — first-party frameworks only (spine §1).

## 7. Success criteria (personal app — subjective but checkable)

1. **Zero missed opens.** Across 30 consecutive days that include at least one DST-mismatch week (e.g. 2026 Oct 25–Nov 1), Kai receives every enabled open alert at the correct local instant. Checkable: alert log vs engine fixtures.
2. **Two-second glance.** From Lock Screen or Dynamic Island, "what's open and what's next" is answerable without unlocking. Checkable: Live Activity or accessory widget visible whenever markets are open.
3. **The sacred never fails.** A `.criticalAlarm`-marked open rings through Silent + Focus on a real device, including after a reboot [AK §G.4]. Checkable: overnight device test.
4. **Correct through the calendar.** Thanksgiving 2026, NYSE half-day Nov 27, LSE Dec 24 half-day, and both 2026 mismatch windows all render and alert correctly. Checkable: fixture dates in `OffsetKitTests` plus manual spot checks.
5. **Briefing worth reading on a 14 Pro Max.** The Exa-generated briefing is specific to today (mentions at least today's high-impact releases) and costs ≈$0–10/month net of free credits [NA §1]. Fallback template briefing appears within 1 s when offline.
6. **The app teaches.** After two weeks of Beginner use, Kai can explain the overlap and each killzone unaided — the glossary and explainers earn their place. Checkable: every jargon surface has an explainer path.
7. **Honest alert budget.** The budget health row never shows saturation without the degradation rules of S-B3 holding; no notification is ever silently dropped inside the 24 h window. Checkable: pending-requests audit vs planner output.
8. **Battery-invisible.** No per-second UI timers or layout thrash; countdowns are system-rendered [MS §4]. Checkable: Instruments pass shows no recurring 1 Hz main-thread work from Offset while idle.
