# CLOUDLINK_LOOP.md — Primary build path: the owner's Mac via CloudLink

**Decided 2026-07-22.** The build agent verifies everything on the owner's Mac through **CloudLink** (the owner's own menubar app: bearer-authenticated HTTPS API over a stable Cloudflare named tunnel → local `git`/`xcodebuild`/`simctl` behind a FIFO job queue). This supersedes GitHub Actions as the loop (`CI_SETUP.md` stays as a backup lane). GitHub remains the source of truth for code.

Verified live 2026-07-22: CloudLink **1.1.0** · macOS **26.5.1** (Apple Silicon) · **Xcode 26.6 (17F113)** · simulators incl. **iPhone 17 Pro (iOS 26.5)**.

## Access

Via the **"CloudLink Mac Bridge" skill** — `RunWithCredentials` injects `CLOUDLINK_URL` + `CLOUDLINK_TOKEN` from the encrypted skill store into `skills/cloudlink-mac-bridge/cloudlink.py`. Full command reference + failure playbook live in the skill documentation. Never place the URL/token in chat, repo files, or logs.

## One-time setup on the Mac (owner)

1. CloudLink **Settings ▸ Projects ▸ +** → select the Offset repo folder (top level contains `Offset.xcodeproj`) → project id becomes **`offset`**.
2. Enable the project's **Writable** toggle (gates remote file writes + stage/commit/push).
3. Remove the stale `cloudlink-testapp` registration (folder no longer exists → `containerNotFound`).
4. Ensure the Offset repo has the GitHub remote configured and the Offset scheme is **Shared** (Xcode ▸ Product ▸ Scheme ▸ Manage Schemes ▸ Shared ✓) — only shared schemes are visible to the API.
5. Keep CloudLink + tunnel running during build sessions (Settings: launch-at-login, tunnel-at-launch). The **Pause API** switch answers 503 — unpause before sessions.
6. After wiring the skill credentials: **regenerate the token** (Settings ▸ Security) and paste the new value into the skill's `CLOUDLINK_TOKEN` credential field — the original token appeared in a chat thread and must be considered exposed.

## The per-milestone loop (agent protocol)

```
git-pull offset                                   # sync Mac working copy with GitHub
→ write files (bridge File API; batch; ≤2 MB each; CAS auto-handled)
→ build offset --scheme Offset --destination "id=<UDID>"      # fix summary.errors, repeat
→ test  offset --scheme Offset --destination "id=<UDID>"      # fix summary.failures, repeat
→ [UI milestones] run offset --scheme Offset --simulator-udid <UDID> --shot m.png
    → inspect the screenshot; iterate until it matches 07-UI-UX-SPEC
→ git-commit offset -m "M{n}: <summary>" --stage-all
→ git-push offset                                  # GitHub stays source of truth
→ BUILDLOG.md entry (via bridge write) → next milestone
```

Rules:
- **One job at a time** (server FIFO): never submit a second build/test/run while one is queued/running.
- **Simulator**: pick the newest iOS-26.x **iPhone Pro** by UDID from `simulators --iphone-only` at session start; reuse that UDID all session.
- Prefer batching file writes before each build; every build is a queued job on real hardware.
- `.pbxproj` edits via the File API are allowed but should be rare (synchronized folder groups) and logged in BUILDLOG.
- Secrets: `Config/Secrets.xcconfig` exists only on the Mac (gitignored). The bridge must never read it into chat/logs; CI and the agent never need real keys.
- Screenshots land as local PNGs in the agent sandbox — view with the Read tool; attach key ones to milestone reports.
- If health fails → tunnel/app down: ask the owner. If auth fails after health passes → token was regenerated: ask the owner to update the skill credential. If `paused` → ask, don't retry-loop.

## What still cannot be verified remotely (manual-QA list, unchanged)

Physical-device behaviors: AlarmKit breaking Silent, Live Activity in the real Dynamic Island + terminated-start test, watch Smart Stack mirroring, Focus behaviors, device DST simulation. These accumulate in BUILDLOG for the owner's iPhone 14 Pro Max sessions (installed via Xcode on the Mac; free-team weekly re-provision applies). Simulator screenshots DO cover: all app screens, widget gallery previews, light/dark, Dynamic Type, and lock-screen Live Activity rendering (simulator supports Live Activities on the lock screen/island rendering — verify fidelity case by case).

## KICKOFF_PROMPT addendum (CloudLink variant — replaces the CI addendum)

> BUILD VERIFICATION runs on the owner's Mac via the "CloudLink Mac Bridge" skill (RunWithCredentials) — there is no local xcodebuild in your sandbox. Project id: `offset`; scheme: `Offset`; destination: `"id=<UDID>"` of the newest iOS-26.x iPhone Pro simulator (discover once per session via `simulators --iphone-only`). Loop per checkpoint: `git-pull` → `write` changed files → `build` → fix `summary.errors` → `test` → fix `summary.failures` → (UI milestones) `run --shot` and inspect the screenshot against 07-UI-UX-SPEC → `git-commit -m "M{n}: …" --stage-all` → `git-push`. ONE job at a time — the Mac queue is FIFO. A milestone is complete only when build + full test suite are green on the Mac. GitHub Actions (`.github/workflows/ci.yml`) is a backup lane, not your loop. Never expose CLOUDLINK_URL/CLOUDLINK_TOKEN or read Config/Secrets.xcconfig. Device-only behaviors go on BUILDLOG's manual-QA list.
