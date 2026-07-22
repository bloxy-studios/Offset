# Decision Log — Trading Sessions iOS App

Working log of confirmed requirements and open questions. Feeds the docs set + BUILD_PROMPT.md.
Research references live in /agent/workspace/research/ (4 files, 1,544 lines, verified 2026-07-21).

## Confirmed (Round 1 — user, 2026-07-21)

**Platform & toolchain**
- Personal app, single user. iOS 26 minimum. Xcode 26.6. SwiftUI-first.

**Markets in scope** (no crypto)
1. Forex sessions — Sydney, Tokyo, London, New York
2. US stocks — NYSE/Nasdaq incl. pre-market + after-hours
3. London Stock Exchange (LSE)
4. Futures — CME Globex (equity index)

**User profile**
- Still learning, no fixed style yet → beginner-first defaults, aspires to pro/ICT concepts. The app should TEACH session structure while alerting.

**Alerts (all selected, individually toggleable)**
- Opens & closes · pre-event warnings (5–60 min lead) · London–NY overlap · ICT killzones · high-impact econ events

**News**
- Daily AI briefing before user's session + breaking headlines with AI summaries.
- Minimal "high-impact events" strip (data needed for alerts anyway); no full calendar tab.

**Live Activity / Dynamic Island**
- AUTO countdown to next market event. No manual timer in v1.

## Decided (research-informed, 2026-07-21) — "editable defaults" philosophy

1. **Session conventions**: local-business-hours forex convention — Sydney 07:00–16:00 Australia/Sydney, Tokyo 09:00–18:00 Asia/Tokyo, London 08:00–17:00 Europe/London, NY 08:00–17:00 America/New_York. All stored as wall-clock + IANA zone, materialized per-occurrence. User-editable in Pro settings.
2. **London–NY overlap**: computed STRUCTURALLY per-day = max(London open, NY open) → min(London close, NY close). Self-adjusts during DST mismatch weeks instead of hardcoding 08:00–12:00 ET.
3. **ICT killzones** (majority convention, America/New_York, editable): Asia 20:00–00:00, London 02:00–05:00, NY AM 07:00–10:00, London Close 10:00–12:00, NY PM 13:30–16:00.
4. **FX week open**: display convention Sunday 17:00 America/New_York (retail).
5. **Extended-hours boundaries (US pre/after-market)**: shown on timeline; alerts OFF by default (budget), toggleable.
6. **CME 15:15–15:30 CT equity halt**: omit v1 (unverified vs official source).
7. **Holidays**: bundled JSON for NYSE + LSE 2026–2028 (verified from official pages), refreshed with app updates. No holiday API dependency.
8. **Notification budget**: 64-cap strategy — schedule nearest ≤56 events, reserve 8 slots, rebuild on foreground/BGAppRefresh/significantTimeChange/timezone-change/day-change. Non-repeating UNCalendarNotificationTriggers with explicit DateComponents.timeZone.
9. **Live Activity**: one MarketCountdown activity; iOS 26 scheduled Live Activities (Activity.request with start date) for serverless chaining; Text(timerInterval:) for zero-push ticking; handle 8h max window (weekend gap can't be spanned — show "market resumes Sun 17:00" state instead).
10. **AlarmKit**: use .fixed schedules only (relative follows device tz — wrong for exchanges); requires widget extension (shared with LA); breaks Silent/Focus — reserve for user-pinned critical events only.
11. **News stack**: ForexFactory JSON (econ events, free, verified) + Finnhub free tier (/news general+forex, /company-news) + RSS fallbacks. Exa /search + /answer as enrichment AND cloud-summary fallback (~$0–10/mo with free credits).
12. **AI summaries**: FoundationModels on-device (iPhone 15 Pro+ w/ Apple Intelligence enabled); mandatory fallback chain → Exa /answer → raw headlines. Fresh session per briefing, @Generable structured output, 4096-token context. Never run the model in widget extensions; cache briefings via App Group.
13. **Toolchain**: Swift 6.2, Approachable Concurrency (default MainActor isolation), Swift Testing for tests.
14. **Persistence**: SwiftData for cached news/briefings/econ events; UserDefaults (App Group) for settings shared with widget extension.
15. **API keys**: gitignored xcconfig → Info.plist at build → moved to Keychain at first run. No proxy (personal app).
16. **iOS 27 API exclusion list** (uncompilable on Xcode 26.6) documented in research §7.4 — BUILD_PROMPT must forbid them.

## Confirmed (Round 2 — user, 2026-07-21)
1. **Device: iPhone 14 Pro Max** → HAS Dynamic Island; does NOT support Apple Intelligence (needs 15 Pro+). Consequence: ExaAnswerSummarizer is the PRIMARY summary path on the user's device; FoundationModelsSummarizer still implemented (future device) and selected automatically when available.
2. **AlarmKit hard alarms: IN for v1** — surfaced as per-event "Critical alert" style; alarms for the sacred, notifications for the routine.
3. **Widgets: (a)+(b)** — home-screen widgets (next event + session timeline) + lock-screen accessory widgets + Apple Watch Smart Stack mirroring of the Live Activity (supplementalActivityFamilies .small). NO standalone watchOS app.
4. **Beginner→Pro UX: "Trader Level"** setting (Beginner/Pro) chosen at onboarding, changeable anytime in Settings.
5. **App name: Offset** (user's own). Tagline direction: "Every market. Your time."

## Micro-decisions (final, orchestrator, 2026-07-21)
- iPhone-only target (iPad runs in compatibility mode); portrait-primary.
- Econ event currency filter default: USD, GBP, EUR, JPY, AUD (matches market scope); editable.
- Daily briefing default time: 07:30 device-local (before NY AM killzone for an ET user); editable.
- Half-day handling: NYSE half-days close 13:00 ET (after-hours truncated); LSE half-days close 12:30 local.
- Distribution: personal install via Xcode. NOTE for setup: a paid Apple Developer account is strongly recommended (free provisioning expires every 7 days and complicates entitlements).
- Weekend gap: Live Activity cannot span the FX weekend (8h max active window) → show "Markets closed · resumes Sun 17:00 ET" app state; next LA pre-scheduled for Sunday reopen window.
- Deep link scheme: offset:// (today, market/{id}, news/briefing, alerts).

## Setup facts (M0, confirmed from user's Xcode — 2026-07-22)
- **Identifier root: `com.bloxy-studios`** (supersedes the docs' `dev.offsetapp` placeholder everywhere). Actual values: app `com.bloxy-studios.Offset` · widget `com.bloxy-studios.Offset.widgets` · App Group `group.com.bloxy-studios.Offset` (registered + working) · BGTask ids `com.bloxy-studios.Offset.refresh.schedule` / `com.bloxy-studios.Offset.refresh.news`. Note capital "O" in Offset — these strings are case-sensitive; `SharedConstants.swift` and all Info.plist entries must match exactly.
- **Signing: FREE Personal Team as of 2026-07-22.** Confirmed: personal teams do not support the Time Sensitive Notifications capability → the `com.apple.developer.usernotifications.time-sensitive` entitlement is REMOVED from Offset.entitlements for now. Build agent: keep `AlertStyle.timeSensitive` in the model, but gate delivery — apply `interruptionLevel = .timeSensitive` only behind a single `Capabilities.timeSensitiveEntitlementPresent` flag (default false); everything else about the rule behaves normally at `.active` level. When the user upgrades to the paid Developer Program, the entitlement row returns and the flag flips — zero other changes. Do NOT request the deprecated `UNAuthorizationOptions.timeSensitive`.
- Free-team consequences acknowledged: 7-day provisioning expiry (user must rebuild weekly until paid), no TestFlight. AlarmKit, Live Activities, App Groups, widgets, BG tasks all confirmed available on the personal team.

## CI & repo decisions (2026-07-22)
- **Repo: PUBLIC on GitHub.** CI runs on **GitHub-hosted `macos-latest`** (Apple Silicon; free and unlimited for public repos). NO self-hosted runner — the owner's local Mac is Intel-based and is used ONLY for device installs/signing via Xcode.
- Consequences: `.github/workflows/ci.yml` targets `macos-latest`; the workflow's Xcode-26.x check is the compatibility gate on image updates. Secrets discipline is absolute — `Config/Secrets.xcconfig` stays gitignored, CI builds with placeholder keys (app degrades gracefully by design), and real keys exist only on the owner's machines. No personal information belongs in committed docs.
- Build agent note: the push → CI → read-logs loop (docs/CI_SETUP.md) is the ONLY build-verification path; there is no local xcodebuild available to the agent. *(Superseded same day — see below.)*

## Build-execution decision (2026-07-22, later — SUPERSEDES the CI-only note above)
- **Primary build path: CloudLink Mac Bridge** (docs/CLOUDLINK_LOOP.md) — the owner's own CloudLink menubar app exposes the Mac's toolchain over a stable HTTPS tunnel. Verified live: CloudLink 1.1.0, macOS 26.5.1 (Apple Silicon), **Xcode 26.6 (17F113)**, iOS 26.2 + 26.5 simulators (incl. iPhone 17 Pro). The agent drives it via the "CloudLink Mac Bridge" skill (RunWithCredentials; creds in the skill store, never in chat/repo).
- Loop: write files via bridge File API (2 MB cap, CAS) or git → build → test → for UI milestones `run --shot` simulator screenshots (the agent can SEE the app) → git-commit + git-push from the Mac. FIFO queue, one job at a time.
- **GitHub remains source of truth** (public repo); `.github/workflows/ci.yml` stays as an optional backup/CI-badge lane, NOT the loop.
- Prereqs on the Mac: register the Offset repo folder in CloudLink Settings > Projects (id will be `offset`), enable its **Writable** toggle, keep CloudLink + tunnel running during build sessions, repo has the GitHub remote configured. Remove the stale `cloudlink-testapp` registration (containerNotFound).
- Simulator target: newest iOS-26.x iPhone Pro simulator by UDID (currently iPhone 17 Pro, iOS 26.5).
- Device installs on the iPhone 14 Pro Max remain manual via Xcode (free-team signing; weekly re-provision).
