# Market Sessions & iOS Notification Scheduling — Research

Compiled 2026-07-21 for a personal iOS 26+ SwiftUI app (device-only scheduling, no server).
Scope confirmed: Forex sessions (Sydney/Tokyo/London/New York), NYSE/Nasdaq incl. extended hours, LSE, CME Globex equity-index futures; opens/closes + lead warnings + London–NY overlap + ICT killzones + high-impact econ events.

**Golden rule used throughout:** every session is expressed as *wall-clock time in its market's own IANA time zone*, never as a fixed UTC offset. Each concrete occurrence is materialized per-date via `Calendar`/`TimeZone`.

Verification legend:
- **VERIFIED** — read directly from an official/primary source during this research pass.
- **VERIFIED (archive)** — read from a Wayback Machine capture of the official page (live page blocks automated access).
- **CONVENTION** — no single authority exists; sourced from multiple trading-education sources; variance noted.
- **UNVERIFIED** — could not confirm from a primary source; flagged for manual check.

---

# HALF 1 — Market session ground truth

## 1. Forex sessions and conventions

Forex is decentralized: there is **no official open/close**; session times are conventions. Two competing convention families exist — you must pick one (see Decisions).

### Convention A — "local business hours" (BabyPips-style; recommended)
Sessions are defined in each hub's local time and therefore drift against each other during DST-mismatch weeks. Source: BabyPips "Forex Trading Sessions" (table gives local times; "Actual open and close times are based on local business hours, with most business hours starting somewhere between 7–9 AM local time"). VERIFIED (archive) — https://www.babypips.com/learn/forex/forex-trading-sessions

| Session  | Local hours (BabyPips) | IANA zone            | Notes / competing sub-conventions |
|----------|------------------------|----------------------|-----------------------------------|
| Sydney   | 07:00 – 16:00          | `Australia/Sydney`   | Others use 08:00–17:00; some anchor "Sydney open" to the weekly 17:00 New York open (which is 07:00/08:00/09:00 Sydney depending on DST mix). CONVENTION |
| Tokyo    | 09:00 – 18:00          | `Asia/Tokyo`         | Japan has no DST, so Tokyo is the only fixed anchor. Some sources use 09:00–17:00. CONVENTION |
| London   | 08:00 – 17:00          | `Europe/London`      | BabyPips table shows 08:00 open, 17:00 close; many desks use 08:00–16:00 or 08:00–16:30 (LSE cash close). CONVENTION |
| New York | 08:00 – 17:00          | `America/New_York`   | 17:00 close = industry-wide FX day roll ("New York close"). Broadly consistent across sources. |

### Convention B — "fixed New York / fixed GMT clock"
Many US retail sites express all sessions in ET (e.g., Sydney 17:00–02:00 ET, Tokyo 19:00–04:00 ET, London 03:00–12:00 ET, NY 08:00–17:00 ET) or in GMT. These are Convention A values frozen at one DST alignment; they silently go wrong for part of the year. Use only for display, never for the engine. CONVENTION.

### The forex trading week — VERIFIED as industry convention
- Opens **Sunday 17:00 `America/New_York`**, closes **Friday 17:00 `America/New_York`**.
- The FX *trading day* also rolls at 17:00 New York (basis of "New York close" 5-day candles).
- Matches CME FX/Globex weekly cycle (Sun 17:00 CT open ↔ 18:00 ET; note retail FX brokers use 17:00 ET — the two differ by venue; retail convention is 17:00 ET).
- BabyPips notes trading technically begins with Wellington/Sydney Monday morning, which *is* Sunday afternoon/evening in New York.
- Market fully closed only on weekends plus, in practice, Christmas Day and New Year's Day (BabyPips).

### London–New York overlap
- Canonical retail definition: **08:00–12:00 `America/New_York`** (BabyPips: "during both summer and winter from 8:00 AM–12:00 PM ET" — a simplification that ignores mismatch weeks). The 12:00 end corresponds to London 17:00 close when London is +5h from New York.
- If you define it structurally as [NY open 08:00 America/New_York → London close 17:00 Europe/London], the overlap **shrinks/stretches by 1h during DST mismatch weeks** (worked example in §5).
- TradingView community scripts commonly annotate it as "approximately 08:30–12:00 ET" or "13:00–17:00 UTC". CONVENTION — pick one definition (see Decisions).

### The Asian range
- ICT usage (the one relevant to this app): consolidation range **20:00–00:00 `America/New_York`** (some ICT materials say 19:00–00:00 or 20:00–04:00 for the "extended" Asian range). CONVENTION.
- Non-ICT usage: high/low of the whole Tokyo session (09:00–18:00 `Asia/Tokyo`) or 00:00–08:00 London time. Distinct concept from ICT's CBDR (Central Bank Dealers Range, 16:00–20:00 New York) — don't conflate.

## 2. ICT killzones (per ICT convention, all in `America/New_York`)

ICT (Michael Huddleston) defines killzones anchored to **New York local time**, so they auto-track US DST but drift ±1h against London/Tokyo wall clocks during mismatch weeks. No single canonical written source exists (primary material is video); values below triangulated from multiple education sources and the dominant TradingView indicator conventions.

| Killzone | Majority convention (America/New_York) | Variants seen in sources |
|---|---|---|
| Asian KZ | **20:00 – 00:00** | 19:00–22:00 (howtotrade.com); 19:00–00:00 |
| London (Open) KZ | **02:00 – 05:00** | 01:00–05:00; 02:00–04:00 |
| NY AM / NY Open KZ | **07:00 – 10:00** | 08:30–11:00 (index/futures-timing variant); 07:00–09:00 |
| London Close KZ | **10:00 – 12:00** | 10:00–11:30; 10:30–12:00 |
| NY PM session | **13:30 – 16:00** | ICT 2022-mentorship session partitions: NY AM session 09:30–11:00/12:00, NY Lunch 12:00–13:00, NY PM 13:30–16:00 |

Sources:
- howtotrade.com "ICT Kill Zones": Asian 7–10 PM, London 2–5 AM, New York 7–10 AM, London Close ~10 AM–12 PM (table typo'd in page; labeled "EST" but means New York time). https://howtotrade.com/blog/ict-kill-zones/
- TradingView killzone-indicator ecosystem (multiple popular script descriptions, incl. LuxAlgo-style defaults): "Default windows, in New York time (America/New_York): Asia 20:00–00:00, London Open 02:00–05:00, New York AM 07:00–10:00, London Close 10:00–12:00 — these are the conventional ICT killzone windows"; session partitions "Asia 20:00–00:00, London 02:00–05:00, NY AM 09:30–11:00, NY Lunch 12:00–13:00, NY PM 13:30–16:00 (all in New York time)". https://www.tradingview.com/scripts/killzones/
- Several dedicated articles (forexbee.co, fxopen.com, daytrading.com, earn2trade.com) are client-rendered and could not be text-verified in this pass. UNVERIFIED for those specific pages.

**Variance is real and expected** — make killzone bounds user-editable with the majority values as defaults, and note in-app that ICT's own videos have used slightly different windows over the years.

## 3. Equities

### NYSE / Nasdaq (all `America/New_York`) — VERIFIED
Official: NYSE "Holidays & Trading Hours" — https://www.nyse.com/markets/hours-calendars ; Nasdaq system hours PDF — https://www.nasdaqtrader.com/content/TechnicalSupport/nasdaq_sys_hours.pdf (doc 0439-26); Nasdaq holiday page — https://www.nasdaqtrader.com/Trader.aspx?id=Calendar

- **Core session (both): 09:30–16:00.** NYSE Tape A: Core Open Auction 09:30; Closing Imbalance Period 15:50–16:00; Closing Auction 16:00.
- **Pre-market (consumer convention): 04:00–09:30.** Official basis: Nasdaq "system hours 4:00 a.m.–8:00 p.m."; NYSE Arca Early Trading 04:00–09:30 (Arca pre-opening from 02:30 for order entry). NYSE Tape A itself has no 4 a.m. session (pre-opening order queue 06:30; Tapes B&C early trading 07:00–09:30) — the app should use the **04:00–09:30 / 16:00–20:00** extended-hours convention, which is what brokers show.
- **After-hours: 16:00–20:00** (Nasdaq system hours to 8 p.m.; NYSE Arca/American Late Trading 16:00–20:00).
- **Early-close days: 13:00 close** (options 13:15); NYSE late sessions end 17:00 on those days.

**NYSE full holiday calendar — 2026** (Nasdaq identical; VERIFIED from both):
| Date | Holiday |
|---|---|
| Thu Jan 1, 2026 | New Year's Day |
| Mon Jan 19, 2026 | Martin Luther King, Jr. Day |
| Mon Feb 16, 2026 | Washington's Birthday / Presidents Day |
| Fri Apr 3, 2026 | Good Friday |
| Mon May 25, 2026 | Memorial Day |
| Fri Jun 19, 2026 | Juneteenth National Independence Day |
| Fri Jul 3, 2026 | Independence Day (observed) |
| Mon Sep 7, 2026 | Labor Day |
| Thu Nov 26, 2026 | Thanksgiving Day |
| Fri Dec 25, 2026 | Christmas Day |
| **Half-days 2026:** Fri Nov 27 (13:00 close) · Thu Dec 24 (13:00 close) | |

**NYSE full holiday calendar — 2027:**
| Date | Holiday |
|---|---|
| Fri Jan 1, 2027 | New Year's Day |
| Mon Jan 18, 2027 | Martin Luther King, Jr. Day |
| Mon Feb 15, 2027 | Washington's Birthday |
| Fri Mar 26, 2027 | Good Friday |
| Mon May 31, 2027 | Memorial Day |
| Fri Jun 18, 2027 | Juneteenth (observed) |
| Mon Jul 5, 2027 | Independence Day (observed) |
| Mon Sep 6, 2027 | Labor Day |
| Thu Nov 25, 2027 | Thanksgiving Day |
| Fri Dec 24, 2027 | Christmas Day (observed) |
| **Half-days 2027:** Fri Nov 26 (13:00 close) only. (Dec 24 is the observed Christmas holiday, so no December half-day; NYSE also publishes 2028 incl. Mon Jul 3, 2028 13:00 early close.) | |

### LSE (all `Europe/London`) — VERIFIED
Official: LSE "Business days" — https://www.londonstockexchange.com/equities-trading/business-days ; hours from the official *Millennium Exchange & TRADEcho Business Parameters* workbook v9.9 (2026-04-07), sheet "Trading Cycles", SETS order book — https://docs.londonstockexchange.com/sites/default/files/documents/20260407-mit-and-te-parameters-version-9-9.xlsx

- Pre-Trading 05:05–07:50
- **Opening Auction Call 07:50–08:00** (uncrossing subject to up to 30 s random end)
- **Continuous trading 08:00–16:30**
- **Closing Auction Call 16:30–16:35** (30 s random end), Closing Price Crossing 16:35–16:40, Post Close →17:15
- **Early-close days ("half days"): continuous trading ends 12:30**, closing auction 12:30–12:35 ("markets closing process commences from 12:30 London time").

LSE closes on England & Wales public/bank holidays (LSE statement on the business-days page). E&W bank holidays cross-checked against the official https://www.gov.uk/bank-holidays (JSON: /bank-holidays.json). VERIFIED.

**LSE holidays & half-days — 2026:**
| Date | Status |
|---|---|
| Thu Jan 1, 2026 | Closed (New Year's Day) |
| Fri Apr 3, 2026 | Closed (Good Friday) |
| Mon Apr 6, 2026 | Closed (Easter Monday) |
| Mon May 4, 2026 | Closed (Early May bank holiday) |
| Mon May 25, 2026 | Closed (Spring bank holiday) |
| Mon Aug 31, 2026 | Closed (Summer bank holiday) |
| Thu Dec 24, 2026 | **Half day — 12:30 close** |
| Fri Dec 25, 2026 | Closed (Christmas Day) |
| Mon Dec 28, 2026 | Closed (Boxing Day substitute) |
| Thu Dec 31, 2026 | **Half day — 12:30 close** |

(Rows from Aug 2026 onward read directly from LSE's table; Jan–May 2026 rows had already scrolled off LSE's forward-looking table as of 2026-07-21 and are reconstructed from LSE's "recognises E&W bank holidays" rule + gov.uk — treat as VERIFIED-by-rule.)

**LSE holidays & half-days — 2027** (all read directly from LSE's table — VERIFIED):
| Date | Status |
|---|---|
| Fri Jan 1, 2027 | Closed (New Year's Day) |
| Fri Mar 26, 2027 | Closed (Good Friday) |
| Mon Mar 29, 2027 | Closed (Easter Monday) |
| Mon May 3, 2027 | Closed (Early May bank holiday) |
| Mon May 31, 2027 | Closed (Spring bank holiday) |
| Mon Aug 30, 2027 | Closed (Summer bank holiday) |
| Fri Dec 24, 2027 | **Half day — 12:30 close** |
| Mon Dec 27, 2027 | Closed (Christmas Day substitute) |
| Tue Dec 28, 2027 | Closed (Boxing Day substitute) |
| Fri Dec 31, 2027 | **Half day — 12:30 close** |

(LSE also already publishes 2028 and Mon Jan 3, 2028 New Year substitute closure.)

## 4. CME Globex equity-index futures (ES/NQ/YM/RTY etc.), `America/Chicago`

- **Weekly cycle: Sunday 17:00 CT open → Friday 16:00 CT close.**
- **Daily maintenance break: 16:00–17:00 CT Monday–Thursday** (60 minutes). Globex "trade date" = next calendar day after the 17:00 reopen.
- **Equity-index-specific daily halt: 15:15–15:30 CT** (= 16:15–16:30 ET, i.e., 15 min after the NYSE cash close), then a 15:30–16:00 CT post-settlement session before maintenance. This is on the ES contract-spec page ("Sunday: 5:00 p.m. – Friday: 4:00 p.m. CT with a trading halt from 3:15 p.m. – 3:30 p.m. CT"). **High confidence but UNVERIFIED in this pass** — cmegroup.com actively blocks automated access and archived copies are client-rendered; verify manually at https://www.cmegroup.com/markets/equities/sp/e-mini-sandp500.contractSpecs.html before hard-coding.
- The general Globex pattern "Sunday 5:00 p.m. – Friday 4:00 p.m. CT with a 60-minute break each day beginning at 4:00 p.m. CT" is VERIFIED (archive) from CME's own trading-hours page (Wayback capture of https://www.cmegroup.com/trading-hours.html, 2026-05-22).
- CME holiday behavior (context): schedules published per-holiday ("finalized approximately two weeks prior to the holiday", per the same page); US-holiday early closes for equity indexes are typically 12:00 CT halts. 2026 CME Globex holiday-schedule dates listed on that page: New Year's (Dec 31 2025–Jan 2), MLK (Jan 18–20), Presidents Day (Feb 15–17), Good Friday (Apr 2–4), Memorial Day (May 24–26), Juneteenth (Jun 18–19), Independence Day (Jul 3–5), Labor Day (Sep 6–8), Thanksgiving (Nov 26–28), Christmas (Dec 24–26), New Year's (Dec 31 2026–Jan 1 2027).
- App simplification: model CME as open Sun 17:00 CT → Fri 16:00 CT with daily 16:00–17:00 CT breaks; optionally surface the 15:15–15:30 CT halt; use the NYSE holiday list to flag "US-holiday altered hours" days rather than modeling CME per-holiday hours precisely.

## 5. DST mismatch mechanics

Transitions verified from the IANA tz database (zdump, tzdata on this system) — authoritative, same data iOS uses:

| Zone | 2026 spring | 2026 autumn | 2027 spring | 2027 autumn |
|---|---|---|---|---|
| `America/New_York` / `America/Chicago` (US) | **Sun Mar 8, 2026** 02:00→03:00 | **Sun Nov 1, 2026** 02:00→01:00 | **Sun Mar 14, 2027** | **Sun Nov 7, 2027** |
| `Europe/London` (UK; EU same dates, 01:00 UTC) | **Sun Mar 29, 2026** 01:00→02:00 | **Sun Oct 25, 2026** 02:00→01:00 | **Sun Mar 28, 2027** | **Sun Oct 31, 2027** |
| `Australia/Sydney` (opposite hemisphere) | DST **ends Sun Apr 5, 2026** 03:00→02:00 | DST **begins Sun Oct 4, 2026** 02:00→03:00 | ends **Sun Apr 4, 2027** | begins **Sun Oct 3, 2027** |

Mismatch windows (London–New York offset is 5h normally, **4h during**):
- **Mar 8 → Mar 29, 2026** (3 weeks) and **Oct 25 → Nov 1, 2026** (1 week)
- **Mar 14 → Mar 28, 2027** (2 weeks) and **Oct 31 → Nov 7, 2027** (1 week)

Sydney–New York offset cycles 14h (AEST/EDT) → 15h (AEDT/EDT, Oct 4–Nov 1 2026) → 16h (AEDT/EST).

**Worked example — London–NY overlap in March 2026.** Define overlap = NY session open (08:00 `America/New_York`) → London session close (17:00 `Europe/London`).
- Normal week (e.g., Mon Mar 2, 2026): London=GMT (UTC+0), NY=EST (UTC−5). London 17:00 = 12:00 NY → overlap 08:00–12:00 NY (4h). London 08:00 open = 03:00 NY.
- Mismatch week (e.g., Mon Mar 9, 2026 — US already on EDT, UK still GMT; offset 4h): London 17:00 = **13:00 NY** → overlap 08:00–13:00 NY (**5h**). London 08:00 open = **04:00 NY**. An ICT London KZ pinned at 02:00–05:00 NY now covers 06:00–09:00 *London* wall clock instead of 07:00–10:00.
- After Mar 29, 2026 (UK on BST): back to 08:00–12:00 NY.
Same 1-hour stretch recurs Oct 26–30, 2026; mirrored weeks in 2027.

**Engineering rule (non-negotiable):** store every session as `(weekday set, wall-clock start, wall-clock end, IANA zone id, holiday calendar id)`. Materialize each occurrence with a `Calendar` whose `timeZone` is that zone, per date. Never store or add fixed UTC offsets; never "convert once and cache across a DST boundary". Derived events (overlap, "X hours until London open") must be computed from two *materialized* instants, not from assumed offsets.

## 6. Ongoing holiday-data sourcing

| Option | Facts | Fit for a personal app |
|---|---|---|
| Official exchange pages | NYSE publishes 3 years ahead (2026–2028 currently); LSE publishes ~2.5 years (through Jan 2028+); CME publishes per-year Globex holiday schedules; gov.uk bank-holidays JSON is free/official | Free, authoritative; manual copy once a year |
| tradinghours.com API | Real-time status, hours, holidays, half-days, timezones; "sourced directly from the exchanges". **No public pricing** — request-a-trial / sales-contact flow (VERIFIED from their pricing/data page); commercial licensing, historically hundreds of $/yr+ | Overkill + ongoing cost + network dependency |
| Free APIs | gov.uk bank-holidays.json (official, free, UK only); Nager.Date (public holidays ≠ market holidays — wrong for Good Friday etc.? actually covers it, but no half-days); finnhub/polygon market-holiday endpoints (API keys, rate limits, ToS) | Public-holiday APIs don't model half-days or exchange-specific rules — insufficient alone |
| OSS rule libraries | Python `exchange_calendars` / `pandas_market_calendars` encode NYSE/LSE/CME rules incl. half-days; can *generate* JSON at build time | Great as a generator/cross-check, not a runtime dependency |
| **Bundled JSON, updated yearly (RECOMMENDED)** | Ship `holidays-{XNYS,XLON,XCME}.json` covering current+next year (data already in hand through 2027/2028 above); regenerate yearly from official pages (optionally cross-checked against `exchange_calendars`); include `validThrough` date; app shows a "holiday data expiring" nudge when within 60 days of `validThrough`; optionally fetch a replacement JSON from a GitHub raw URL you control | **Best fit**: zero server, zero cost, offline, testable |

---

# HALF 2 — iOS scheduling technology (iOS 26 minimum; all APIs long available)

## 1. UserNotifications

### `UNCalendarNotificationTrigger` (iOS 10+)
Docs: https://developer.apple.com/documentation/usernotifications/uncalendarnotificationtrigger and .../init(datematching:repeats:) and .../nexttriggerdate()

- "A trigger condition that causes a notification the system delivers at a specific date and time … you use a `DateComponents` object to specify only the time values that you want the system to use to determine the matching date and time."
- `convenience init(dateMatching dateComponents: DateComponents, repeats: Bool)`; with `repeats: true` "you must explicitly remove the notification request to stop the delivery".
- `func nextTriggerDate() -> Date?` — "the next date at which the trigger conditions are met"; use it in tests to assert your math matches the system's.

**Time zone & DST semantics — what is and isn't documented:**
- `DateComponents.timeZone` docs (https://developer.apple.com/documentation/foundation/datecomponents/timezone): "This value is interpreted in the context of the calendar in which it is used." If you set `dateComponents.timeZone = TimeZone(identifier: "America/New_York")`, the trigger matches that wall clock in that zone — DST handled by tzdata. If you leave it `nil`, components match the **device's current local wall clock** (floating semantics — an "09:30" trigger means 09:30 wherever the user happens to be).
- Apple's clearest official statement of the two semantics is on the legacy `UILocalNotification.timeZone` page (https://developer.apple.com/documentation/uikit/uilocalnotification/timezone): `nil` → "fire date is interpreted as an absolute GMT time" (countdown timers); a time zone set → "fire date is interpreted as a wall-clock time that is automatically adjusted when there are changes in time zones" (alarm clocks). The modern framework mirrors this split: `UNTimeIntervalNotificationTrigger` = absolute, `UNCalendarNotificationTrigger` = wall clock.
- **UNVERIFIED / do not rely on:** whether an *already-pending* calendar trigger's computed fire date is re-evaluated when the device's time zone changes or when a DST rule change ships mid-flight. Apple does not document this for UserNotifications. Defensive design: schedule **non-repeating, fully materialized** triggers (year/month/day/hour/minute + explicit `timeZone`), and rebuild the whole pending set on the refresh signals in §2. This also sidesteps the repeats+DST edge cases (a repeating 02:30 trigger on a spring-forward night is undefined-by-docs).
- Repeating triggers can't express "every weekday 09:30 except holidays" anyway — holiday-aware scheduling forces per-occurrence triggers, which is the recommended pattern here.

```swift
// Next NYSE open, pinned to exchange-local wall clock:
var comps = DateComponents()
comps.timeZone = TimeZone(identifier: "America/New_York")!
(comps.year, comps.month, comps.day, comps.hour, comps.minute) = (2026, 7, 22, 9, 30)
let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
let content = UNMutableNotificationContent()
content.title = "NYSE opening bell"
content.body  = "Core session 09:30–16:00 ET"
content.sound = .default
content.interruptionLevel = .timeSensitive          // iOS 15+
content.categoryIdentifier = "SESSION_EVENT"
content.threadIdentifier = "nyse"                    // groups NYSE alerts
let req = UNNotificationRequest(identifier: "xnys.open.2026-07-22", content: content, trigger: trigger)
try await UNUserNotificationCenter.current().add(req)
```

### `UNTimeIntervalNotificationTrigger` (iOS 10+)
https://developer.apple.com/documentation/usernotifications/untimeintervalnotificationtrigger — "delivers a notification after the amount of time you specify elapses … use this type of trigger to implement timers." Repeating requires interval ≥ 60 s. Use only for absolute-elapsed cases ("15 minutes from now"); for market events always prefer calendar triggers (survive clock/zone edits sanely).

### The 64-pending limit and rolling windows
- Official number: `UILocalNotification` docs (https://developer.apple.com/documentation/uikit/uilocalnotification): "An app can have only a limited number of scheduled notifications; the system keeps the soonest-firing **64** notifications (with automatically rescheduled notifications counting as a single notification) and discards the rest." The modern UserNotifications framework enforces the same cap in practice (silently drops beyond 64); Apple's current UN docs don't restate the number — treat 64 as the hard budget.
- Strategy: **rolling window** — on every refresh signal, (1) `removeAllPendingNotificationRequests()` (or diff by identifier), (2) regenerate the next N events from the engine, (3) `add` the soonest ≤ 56, keeping ~8 slots free (econ-event alerts scheduled on the fly, snoozes). Use deterministic identifiers (`"{market}.{event}.{ISO-date}"`) so re-adds replace rather than duplicate; verify with `pendingNotificationRequests()`.

### Categories / actions (iOS 10+)
https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types — register `UNNotificationCategory` + `UNNotificationAction` at launch; set `content.categoryIdentifier`. Suggested: category `SESSION_EVENT` with actions `OPEN_COUNTDOWN` ("Show countdown"), `MUTE_TODAY` ("Mute this market today", `.destructive`-free), category `ECON_EVENT` with `MUTE_SERIES`.

```swift
let mute = UNNotificationAction(identifier: "MUTE_TODAY", title: "Mute today")
let cat  = UNNotificationCategory(identifier: "SESSION_EVENT", actions: [mute], intentIdentifiers: [])
UNUserNotificationCenter.current().setNotificationCategories([cat])
```

### Interruption levels (iOS 15+)
https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel
- `.active` — default; "presents the notification immediately, lights up the screen, can play a sound"; does **not** break through Focus/scheduled summary.
- `.timeSensitive` — "similar to active … but can break through system controls such as Notification Summary and Focus. The user can turn off the ability for time sensitive notification interruptions."
- **Capability required for `.timeSensitive`:** add the **"Time Sensitive Notifications"** capability in Xcode (Signing & Capabilities), which sets entitlement key `com.apple.developer.usernotifications.time-sensitive` = true. Without it the system silently downgrades to `.active`. Note: Apple's current Entitlements doc index no longer has a standalone page for this key (only critical-alerts and filtering are listed) — the toggle lives in Xcode's capability library; behavior introduced iOS 15 (WWDC21). Mark: capability VERIFIED as Xcode toggle; doc page currently absent.
- Use `.timeSensitive` only for imminent-event alerts (e.g., "NYSE opens in 5 min"), `.active` for everything else; Apple reviews misuse.

### Foreground presentation (iOS 14+ options shown)
https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter(_:willpresent:withcompletionhandler:) — "If your app is in the foreground when a notification arrives, the shared user notification center calls this method … call the completionHandler and specify how you want the system to alert the user." Without a delegate implementation the system suppresses banners in-foreground.

```swift
func userNotificationCenter(_ center: UNUserNotificationCenter,
                            willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]   // .banner/.list are the iOS 14+ replacements for .alert
}
```

## 2. Refresh machinery (keeping the 64-slot window full)

### Primary strategy: recompute on foreground/launch
Every cold launch and `scenePhase == .active` transition: run the engine, rebuild pending notifications. This alone keeps a daily-opened app perfectly fresh; everything below is belt-and-braces.

### `BGTaskScheduler` / `BGAppRefreshTaskRequest` (iOS 13+)
- https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler, https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtaskrequest, https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app, https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app
- Setup: Signing & Capabilities → Background Modes → **"Background fetch"**; add task id to Info.plist `BGTaskSchedulerPermittedIdentifiers`; `register(forTaskWithIdentifier:using:launchHandler:)` **before end of app launch**; `submit(_:)` a `BGAppRefreshTaskRequest` with `earliestBeginDate`; resubmitting replaces the previous request; re-submit the next request at the start of each handler.
- Reliability, per Apple: `earliestBeginDate` — "the system doesn't guarantee launching the task at the specified date, but only that it won't begin sooner." "The system decides the best time to launch your background task" (usage-pattern driven, Low Power Mode suppresses). BGAppRefreshTask is "for short-duration tasks" (~30 s of runtime per the framework guidance; do only: recompute + reschedule notifications).
- **Realistic cadence: a few times/day for a daily-used app; possibly days apart or never for a rarely-used one. Never the primary mechanism — it's opportunistic top-up only.**

```swift
BGTaskScheduler.shared.register(forTaskWithIdentifier: "app.sessions.refresh", using: nil) { task in
    scheduleNextRefresh()                       // always chain the next one
    let ok = rebuildPendingNotifications()      // engine → ≤56 requests
    task.setTaskCompleted(success: ok)
}
func scheduleNextRefresh() {
    let req = BGAppRefreshTaskRequest(identifier: "app.sessions.refresh")
    req.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
    try? BGTaskScheduler.shared.submit(req)
}
```

### System change signals — what to recompute on each
| Signal | Fires when | Recompute |
|---|---|---|
| `UIApplication.significantTimeChangeNotification` (https://developer.apple.com/documentation/uikit/uiapplication/significanttimechangenotification) | "change to a new day (midnight), a carrier time update, or a change to, or from, daylight savings time"; also delivered on foreground return if missed | Everything: session occurrences, countdown baselines, pending notification set (DST just moved wall clocks) |
| `NSNotification.Name.NSSystemTimeZoneDidChange` (https://developer.apple.com/documentation/foundation/nsnotification/name/1387256-nssystemtimezonedidchange) | Device time zone changes (travel, settings). Call `TimeZone.resetSystemTimeZone()` first if you cached `TimeZone.current` | All *device-local display* strings ("opens 14:30 your time"), any `Calendar` instances cached with old zones, and the pending set (floating vs pinned semantics may shift relative times) |
| `NSNotification.Name.NSCalendarDayChanged` (https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/nscalendardaychanged) | Calendar day flips (posted on wake if asleep; "no guarantees about timeliness") | "Today/tomorrow" labels, today's event list, roll the 7-day horizon forward one day, top-up notification window |
| `scenePhase .active` | Foreground | Full engine pass + pending rebuild (primary refresh) |

SwiftUI: observe via `.onReceive(NotificationCenter.default.publisher(for: ...))` on the root view.

## 3. Correct cross-zone date math in Swift

Core API: `Calendar.nextDate(after:matching:matchingPolicy:repeatedTimePolicy:direction:)` — https://developer.apple.com/documentation/foundation/calendar/nextdate(after:matching:matchingpolicy:repeatedtimepolicy:direction:) — "Computes the next date which matches (or most closely matches) a given set of components." (For sequences use `enumerateDates`, per the same doc.) `Calendar.MatchingPolicy`: "a hint to the search algorithm to control the method used for searching for dates."

```swift
// "Next 09:30 in America/New_York", then display in device-local time:
var nyCal = Calendar(identifier: .gregorian)
nyCal.timeZone = TimeZone(identifier: "America/New_York")!   // never TimeZone(abbreviation: "EST")

func nextNYSEOpen(after date: Date = .now, holidays: Set<DayKey>) -> Date? {
    var probe = date
    for _ in 0..<14 {                                        // bounded holiday/weekend skip
        guard let hit = nyCal.nextDate(after: probe,
                                       matching: DateComponents(hour: 9, minute: 30),
                                       matchingPolicy: .nextTime,          // handles nonexistent (spring-forward) times
                                       repeatedTimePolicy: .first,         // dedupe fall-back repeated hour
                                       direction: .forward) else { return nil }
        let wd = nyCal.component(.weekday, from: hit)
        if wd != 1 && wd != 7 && !holidays.contains(DayKey(hit, in: nyCal)) { return hit }
        probe = hit
    }
    return nil
}
// A Date is an absolute instant — display is just formatting with the user's zone:
let d = nextNYSEOpen(after: .now, holidays: xnysHolidays)!
d.formatted(date: .abbreviated, time: .shortened)            // device-local automatically
// Or force a zone: Date.FormatStyle(timeZone: TimeZone(identifier: "Europe/London")!)
```

Pitfalls (each maps to a bug class):
1. **Fixed offsets / abbreviations.** `TimeZone(abbreviation: "EST")` or `TimeZone(secondsFromGMT:)` freeze one DST regime → wrong half the year. Always IANA ids. (`"EST"` is literally UTC−5 year-round.)
2. **Nonexistent times (spring forward).** 02:00–03:00 doesn't exist on Mar 8 2026 (US). `matchingPolicy: .nextTime` resolves to the next valid instant; `.strict` returns nil. Relevant if a user sets a custom 02:30 killzone edge.
3. **Repeated times (fall back).** 01:00–02:00 occurs twice on Nov 1 2026. `repeatedTimePolicy: .first` picks the first pass deterministically.
4. **`Date` vs wall clock.** `Date` has no zone. Never do `date.addingTimeInterval(86400)` to mean "same time tomorrow" — DST days are 23/25 h; use `calendar.date(byAdding: .day, value: 1, to: date)` with the right calendar.
5. **Cached `Calendar`/`TimeZone.current`.** Recompute after `NSSystemTimeZoneDidChange` (and call `TimeZone.resetSystemTimeZone()`).
6. **Deriving one market from another.** Compute London events with a London calendar and NY events with a NY calendar; never "London = NY + 5h".
7. **Testing:** assert engine output equals `UNCalendarNotificationTrigger.nextTriggerDate()` for pinned-zone components; unit-test the four 2026/2027 mismatch windows explicitly.

## 4. Live in-app clocks and countdowns (zero-timer UI)

- `TimelineView` (iOS 15+, https://developer.apple.com/documentation/swiftui/timelineview): "redraws the content it contains at scheduled points in time." Schedules: `.everyMinute` ("updates at the start of every minute" — https://developer.apple.com/documentation/swiftui/timelineschedule/everyminute), `.periodic(from:by:)` ("updates … at dates separated in time by the interval amount" — https://developer.apple.com/documentation/swiftui/timelineschedule/periodic(from:by:)), `.animation`, `.explicit`. The system "might use a cadence that's slower than the schedule's update rate" (e.g., watch always-on) — read `context.date`, don't assume exact ticks.
- `Text(_:style:)` (iOS 14+, https://developer.apple.com/documentation/swiftui/text/datestyle + /text/init(_:style:)): `Text(sessionOpen, style: .timer)` (live countdown, updates every second **without any view invalidation — rendered by the system**), `.relative` ("in 3 hr"), `.time`/`.date`/`.offset`. This is the cheapest possible ticking text: no Timer, no body re-evaluation.
- Pattern: seconds-precision countdowns → `Text(style: .timer)` alone; a grid of session cards showing state (open/closed/next event) → wrap in `TimelineView(.everyMinute)` and recompute card state from `context.date`.
- Energy: prefer `.everyMinute` over `.periodic(by: 1)`; per-second `TimelineView` re-evaluates body every second (measurable battery cost) whereas `Text(.timer)` does not. Cadence auto-degrades when inactive/low-power.

```swift
TimelineView(.everyMinute) { ctx in
    ForEach(engine.nextEvents(after: ctx.date, limit: 6)) { ev in
        HStack {
            Text(ev.title)                       // "London open"
            Spacer()
            Text(ev.fireDate, style: .relative)  // system-ticking, device-local
        }
    }
}
```

## 5. Recommended engine spec + notification budget for the confirmed scope

### `SessionScheduleEngine` (pure, deterministic, UI/OS-free)
```swift
struct SessionDefinition {                 // static data, bundled
    let id: String                         // "forex.london", "xnys.core", "cme.es"
    let zone: TimeZone                     // IANA, e.g. Europe/London
    let openTime: HourMinute               // wall clock in `zone`
    let closeTime: HourMinute              // may cross midnight (CME 17:00→16:00)
    let weekdays: Set<Weekday>             // Mon–Fri; forex handles Sun-open specially
    let holidayCalendarID: String?         // "XNYS", "XLON", "XCME-US", nil for forex
}
struct HolidaySet { let closures: Set<DayKey>; let halfDays: [DayKey: HourMinute]; let validThrough: DayKey }
struct SessionEvent: Comparable { let sessionID: String; let kind: Kind  // .open/.close/.lead(minutes)
                                  let fireDate: Date; let priority: Int }

protocol SessionScheduleEngine {
    /// Pure function: definitions + holidays + window -> ordered events.
    /// Applies half-day close overrides, skips closures/weekends,
    /// materializes each occurrence in the session's own zone.
    func events(in window: DateInterval,
                definitions: [SessionDefinition],
                holidays: [String: HolidaySet],
                leads: [Minutes]) -> [SessionEvent]
    func nextEvents(after: Date, limit: Int) -> [SessionEvent]   // for UI lists
}
```
Derived layers (computed from materialized events, not stored): overlap intervals (NY-open→London-close), killzones (own `SessionDefinition`s pinned to `America/New_York`), Asian range. Notification layer maps `[SessionEvent]` → `UNNotificationRequest`s with deterministic ids and applies the budget below. Econ events: user-imported/curated list (device-only), scheduled from the 8 reserved slots.

### Budget arithmetic under the 64-pending cap (confirmed scope)
Markets: 4 forex sessions + NYSE + LSE + CME = **7 session tracks**.

- Base events: 7 tracks × (open + close) = **14/weekday** (add +2 if NYSE pre-market open 04:00 and after-hours close 20:00 are separate alerts → 16).
- Lead warnings: up to 2 per event → each event costs 1 + 2 = 3 notifications → **42/weekday** (48 with extended hours).
- 7-day horizon ≈ 5 weekdays + Sunday evening (forex-week open + CME reopen ≈ 2 events → 6 notifications).
- **Worst-case candidates: 42 × 5 + 6 = 216** (248 with extended-hours split) vs a **64 cap → 3.4× oversubscribed**. Even events-only (no leads) is 14 × 5 + 2 = 72 > 64. Seven days at full verbosity is impossible — by design, not by tuning.

Coverage math: 64 ÷ 42 ≈ **1.5 days** of full verbosity; a realistic personal config (say London+NY forex, NYSE, CME; opens+closes; 1 lead each = 8 events × 2 = 16/day) gives 64 ÷ 16 = **4 days**.

**Prioritization strategy (degrade with distance, nearest-first):**
1. Generate all candidates for the next 7 days; sort by `fireDate`.
2. Tier rules while filling ≤ **56** slots (reserve 8 for econ events/ad-hoc):
   - 0–24 h: event + all leads (full verbosity);
   - 24–72 h: event notifications only (drop leads);
   - >72 h: schedule only user-starred sessions' opens.
3. Within a tier, drop in order: 2nd lead → 1st lead → closes of unstarred sessions → Sydney/Tokyo before London/NY (configurable priority ranks).
4. Merge coincident events (±1 min) into one notification (e.g., NYSE 09:30 open ≙ NY-forex morning) via shared identifier; group by `threadIdentifier` per market.
5. Rebuild on every refresh signal (§2) — the rolling window plus daily app opens keeps 24 h+ of runway even if BGTasks never fire; if the app is untouched for ~2 days on defaults, farthest-out alerts simply haven't been scheduled yet (acceptable, and the strongest argument for keeping leads to 1 by default).

---

## Source list (primary)
Apple (all under https://developer.apple.com/documentation/): usernotifications/{uncalendarnotificationtrigger, uncalendarnotificationtrigger/init(datematching:repeats:), uncalendarnotificationtrigger/nexttriggerdate(), untimeintervalnotificationtrigger, scheduling-a-notification-locally-from-your-app, unnotificationinterruptionlevel{,/timesensitive,/active}, unnotificationpresentationoptions{,/banner,/list}, declaring-your-actionable-notification-types, unusernotificationcenterdelegate/usernotificationcenter(_:willpresent:withcompletionhandler:)}; uikit/{uilocalnotification, uilocalnotification/timezone, uiapplication/significanttimechangenotification, using-background-tasks-to-update-your-app}; backgroundtasks/{bgtaskscheduler, bgapprefreshtaskrequest, bgapprefreshtask, bgtaskrequest/earliestbegindate, choosing-background-strategies-for-your-app}; foundation/{calendar/nextdate(after:matching:matchingpolicy:repeatedtimepolicy:direction:), calendar/matchingpolicy, datecomponents/timezone, nsnotification/name/1387256-nssystemtimezonedidchange, nsnotification/name-swift.struct/nscalendardaychanged}; swiftui/{timelineview, timelineschedule/periodic(from:by:), timelineschedule/everyminute, text/datestyle, text/init(_:style:)}.
Markets: nyse.com/markets/hours-calendars · nasdaqtrader.com/Trader.aspx?id=Calendar · nasdaqtrader.com/content/TechnicalSupport/nasdaq_sys_hours.pdf · londonstockexchange.com/equities-trading/business-days · docs.londonstockexchange.com …/20260407-mit-and-te-parameters-version-9-9.xlsx · gov.uk/bank-holidays(.json) · cmegroup.com/markets/equities/sp/e-mini-sandp500.contractSpecs.html + cmegroup.com/trading-hours.html (via Wayback 2026-05-22; live site blocks automation) · babypips.com/learn/forex/forex-trading-sessions · howtotrade.com/blog/ict-kill-zones/ · tradingview.com/scripts/killzones/ · tradinghours.com (pricing/data pages).
IANA tzdata via `zdump -v` for all DST transitions.
