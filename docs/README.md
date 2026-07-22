# Offset — Documentation Set

**Offset** · Every market. Your time.
A session-aware trading clock for iPhone: market opens/closes/overlaps/killzones in your local time, DST-correct, with reliable alerts, a Dynamic Island countdown, and an AI daily briefing. iOS 26+ · Xcode 26.6 · SwiftUI · zero third-party dependencies.

## How to use this folder

1. **Building the app with a coding agent?** Hand it this entire folder (`docs/` + `research/`) and point it at **`BUILD_PROMPT.md`** — that file is the master instruction set and references everything else in read order.
2. **Reviewing the spec as a human?** Read `DECISIONS.md` → `00-SPINE.md` → `01-PRODUCT-SPEC.md`, then dip into area docs as curiosity demands.

## Contents

| File | Role | Lines |
|---|---|---|
| `BUILD_PROMPT.md` | **Master build prompt**: constraints, M0–M9 milestones, acceptance criteria, QA, Definition of Done | ~230 |
| `DECISIONS.md` | Requirement + decision log (highest precedence) | ~63 |
| `00-SPINE.md` | Canonical contracts: names, types, market data, file tree, amendments (§8) | ~360 |
| `01-PRODUCT-SPEC.md` | Vision, personas, feature inventory, 25 user stories | 250 |
| `02-ARCHITECTURE.md` | Targets, concurrency, persistence, secrets, entitlements inventory | 385 |
| `03-SESSION-ENGINE.md` | Seed JSONs (real 2026–27 data), materialization algorithm, DST fixtures, test plan | 656 |
| `04-ALERTS-NOTIFICATIONS.md` | Notification pipeline, 64-cap budgeter, AlarmKit, default rules | 351 |
| `05-LIVE-ACTIVITY.md` | Dynamic Island layouts, serverless scheduled-LA chaining, watch mirroring | 451 |
| `06-NEWS-AI.md` | ForexFactory/Finnhub/Exa clients, summarizer chain, AI prompts, cost caps | 503 |
| `07-UI-UX-SPEC.md` | Screen-by-screen spec, SessionTimelineView, Liquid Glass rules, copy templates | 414 |
| `08-WIDGETS.md` | Home/lock widgets, provider strategy, deep links | 301 |

Sibling folder `research/` (4 files, ~1,540 lines): API ground truth verified against Apple docs, WWDC25 transcripts, exchange sites, and vendor docs on 2026-07-21. Docs cite it; the build agent treats it as the only permissible source for Apple API claims.

## Known open items (by design, flagged in-doc as UNVERIFIED)

The most build-relevant ones, all carrying defensive designs + device tests:
1. Scheduled Live Activity starting while the app is **terminated** (works backgrounded per Apple docs; terminated is the key device test).
2. Exact Swift 6.2 concurrency build-setting spellings (set via Xcode 26.6 UI).
3. How far ahead a scheduled Live Activity `start:` date may be (Friday→Sunday gap handled by design regardless).
4. CME per-holiday hours (advisory banner policy, no schedule mutation).
5. Whether pending notification triggers re-evaluate after zone changes (moot — we always rebuild).
