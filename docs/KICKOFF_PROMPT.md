# KICKOFF_PROMPT.md — Paste into Claude Code at repo root (M0 complete)

Usage: run Claude Code from the repo root, paste the block below as the first message. Between milestones run /compact if the session grows. To resume in a fresh session: "Read CLAUDE.md and BUILDLOG.md, then continue at M{n}."

---

You are building "Offset", a session-aware trading clock for iPhone (iOS 26), end-to-end in this repo. The complete spec exists in docs/ — your job is disciplined execution, not re-design.

## Read first, in this order
1. docs/BUILD_PROMPT.md — your master instructions: constraints, milestones M1→M9, acceptance criteria, Definition of Done. Follow it exactly.
2. docs/DECISIONS.md — highest-precedence facts. Its "Setup facts (M0)" section contains THIS repo's real identifiers and signing constraints (they supersede the dev.offsetapp placeholders used elsewhere in the docs).
3. The rest as BUILD_PROMPT.md directs (00-SPINE.md is the naming law; research/*.md is the only permissible source for Apple API claims).

## Repo state — M0 is DONE and verified. Do not redo it.
- Targets exist: Offset (app), OffsetWidgets (widget extension, Live Activity enabled). Local package OffsetKit is linked to both. Shared/ group is dual-membership (app + extension).
- Capabilities wired: App Groups on both targets, Background Modes (fetch + processing) on app. All Info.plist keys from docs/XCODE_SETUP.md §7 are in place. Secrets.xcconfig plumbing works; the app must run with placeholder keys.
- docs/, research/, BUILDLOG.md are at repo root. Deployment target 26.0, Swift 6 / Approachable Concurrency / MainActor default isolation on both targets.
- Do NOT touch signing settings, do NOT add third-party dependencies, do NOT create new targets.

## This repo's identifiers (case-sensitive — capital "O" in Offset)
- App bundle id: com.bloxy-studios.Offset
- Widget bundle id: com.bloxy-studios.Offset.widgets
- App Group: group.com.bloxy-studios.Offset
- BGTask ids: com.bloxy-studios.Offset.refresh.schedule and com.bloxy-studios.Offset.refresh.news
- URL scheme: offset://
Use these in SharedConstants.swift and everywhere the docs say dev.offsetapp.

## Signing constraint — free Personal Team (per DECISIONS "Setup facts")
- The com.apple.developer.usernotifications.time-sensitive entitlement is NOT present and must NOT be added.
- Keep AlertStyle.timeSensitive in the model, but gate delivery behind a single flag: Capabilities.timeSensitiveEntitlementPresent (default false). While false, timeSensitive-styled rules deliver at .active interruption level; everything else about them behaves normally. Flipping the flag + re-adding the entitlement later must be the ONLY change needed.
- Never request the deprecated UNAuthorizationOptions.timeSensitive.
- There is no push server and never will be — serverless designs only, as the docs already specify.

## Working protocol
1. FIRST ACTION: write CLAUDE.md (≤60 lines) — build/test commands, identifier root, doc-precedence chain (DECISIONS > 00-SPINE > area docs > research), milestone protocol, "no iOS 27 APIs (research/ios26-liquid-glass-swiftui.md §7.4)". Distill, don't duplicate the docs.
2. Detect a simulator: `xcrun simctl list devices available` → pick the newest iOS 26.x iPhone; record it in CLAUDE.md and BUILDLOG.md. Use it everywhere:
   - Build: `xcodebuild -scheme Offset -destination 'platform=iOS Simulator,name=<SIM>' -quiet build`
   - Tests: `xcodebuild -scheme Offset -destination 'platform=iOS Simulator,name=<SIM>' -quiet test`
3. New-file pickup: the project uses Xcode 26 synchronized folder groups — files created on disk inside target folders should join automatically. VERIFY this on your first M1 build (especially Shared/ dual-membership and OffsetKit/Sources/OffsetKit/Resources/). If something doesn't attach, edit project.pbxproj minimally and log it; if a change would require Xcode GUI clicks, stop and tell me exactly what to click.
4. Milestones M1→M9 strictly in order, per BUILD_PROMPT.md §4. Per milestone: implement → all listed tests green → BUILDLOG.md entry (decisions, UNVERIFIED resolutions with the exact SDK symbol found, deviations) → `git commit -m "M{n}: <summary>"` → one short status report → continue.
5. Build after every meaningful change, not just at milestone ends. Fix warnings as you go — zero-warning target.
6. Conflicts: DECISIONS.md > 00-SPINE.md > area docs > research. UNVERIFIED items: verify against the actual SDK, adapt minimally, log. Never invent data (hours, dates, schemas) — it all exists in the docs.
7. Scope discipline: v1.1 items in 01-PRODUCT-SPEC.md stay unbuilt. Tempting extras go in BUILDLOG under "Deferred temptations".
8. Anything requiring a physical device (AlarmKit fidelity, Live Activity terminated-start, watch mirroring) goes on the manual-QA list in BUILDLOG for me — don't block on it.

Begin now with M1 (models + seed data). Report when M1's acceptance criteria pass.
