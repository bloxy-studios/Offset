# CI_SETUP.md — Remote build & test via GitHub Actions (backup lane)

> **SUPERSEDED as the primary path (2026-07-22, same day):** the build loop now runs on the owner's Mac via **docs/CLOUDLINK_LOOP.md** (CloudLink Mac Bridge). This GitHub Actions workflow remains as an optional backup / public-repo CI badge — keep it, but the agent's verification loop is CloudLink.

**Earlier decided configuration (2026-07-22): PUBLIC repo · GitHub-hosted `macos-latest` runner.** The owner's local Mac is Intel-based and is used only for device installs/signing via Xcode; all build/test verification happens on GitHub's Apple Silicon runners — free and unlimited for public repos.

## Why this shape (and why not SSH)

The Hyperagent build agent runs in a sandbox whose network egress is **HTTPS-only** — SSH/SFTP/raw TCP are blocked, so it can never shell into a local machine. GitHub mediates instead: the agent pushes code and reads results over the GitHub API; builds execute on GitHub-hosted macOS runners.

```
Hyperagent ──push/API (HTTPS)──▶ GitHub ──▶ hosted macOS runner (Apple Silicon, Xcode 26.x)
     ▲                              │
     └────── run status / logs ◀────┘        Owner's Mac: device installs + signing only (Xcode ▸ Run)
```

Device installs to the iPhone 14 Pro Max remain manual on the owner's Mac — free-team signing lives in the local keychain. On the free team this doubles as the required weekly re-provision.

## The workflow (`.github/workflows/ci.yml`, included in this bundle)

Copy to the repo at exactly `.github/workflows/ci.yml`. Steps: checkout → select newest Xcode 26.x via `DEVELOPER_DIR` (no sudo; **hard-fails with a clear error if the image lacks 26.x** — that failure message is the diagnostic) → create `Config/Secrets.xcconfig` from the example if absent (placeholder keys are fine; the app degrades gracefully by design) → auto-pick the newest available iPhone simulator → `xcodebuild build` (unsigned, `CODE_SIGNING_ALLOWED=NO`) → `xcodebuild test` with an `.xcresult` bundle → upload the result bundle as an artifact on failure.

`runs-on: macos-latest` is the default. A commented self-hosted alternative remains in-file; if it is ever used, the repo must go PRIVATE first (self-hosted runners on public repos can execute fork-PR code).

## Public-repo hygiene checklist

1. **Secrets are sacred**: `Config/Secrets.xcconfig` is gitignored and must never be committed — on a public repo a leaked key is compromised within minutes. CI never needs real keys. If a key ever lands in history: rotate it at the provider immediately, then rewrite history.
2. **No personal information in committed docs** — the spec docs have been scrubbed; keep it that way (no names, emails, device serials).
3. **Fork-PR defaults**: Settings ▸ Actions ▸ General — keep "Require approval for first-time contributors" (default). PR workflows from forks run with read-only tokens.
4. **License**: a public repo without a LICENSE file is "all rights reserved" (visible but not legally reusable). Add MIT if sharing is intended; add nothing to keep default rights. Owner's call — either is fine.
5. Optional: enable Dependabot alerts (Settings ▸ Security) — low value here (zero third-party dependencies by spec), but harmless.

## How the Hyperagent build loop works

Per milestone (M1→M9 from BUILD_PROMPT.md):
1. Agent edits code in its sandbox clone of the repo.
2. Agent commits + pushes via the GitHub integration (HTTPS) — milestone commits `M{n}: <summary>`, plus intermediate checkpoints (each push costs a CI cycle; batch meaningfully).
3. CI runs on `macos-latest`. Agent polls the run status and fetches failure logs / the `TestResults` artifact through the GitHub API.
4. Red → fix and push again. Green → BUILDLOG.md entry → next milestone.
5. Anything needing a physical device or visual inspection (AlarmKit fidelity, Live Activity terminated-start, watch mirroring, Focus/Silent behavior, widget gallery rendering) accumulates in BUILDLOG's manual-QA list — the owner runs those from Xcode on the phone.

Notes for the agent driving the loop:
- Hosted runners are ephemeral — no state persists between runs; the workflow is self-contained by design.
- Simulator-only surfaces can't be *seen* from CI; correctness rides on unit tests + compile-time checks. Visual checks join the manual-QA list.
- The repo uses Xcode 26 synchronized folder groups (per M0) — files added on disk join targets automatically; pbxproj edits should be rare, minimal, and logged.

## KICKOFF_PROMPT addendum (remote/Hyperagent builder variant)

When the builder is a Hyperagent agent (not local Claude Code), append this to the kickoff prompt and drop protocol items 2 and 5 (local xcodebuild):

> BUILD VERIFICATION runs via GitHub Actions on the hosted macOS runner — there is no local xcodebuild. Repo: <owner>/<repo> (PUBLIC — secrets discipline is absolute; never commit Config/Secrets.xcconfig or any credential, and no personal information in committed files). After each meaningful checkpoint: commit, push, then poll the "CI" workflow run for your commit; on failure, fetch the job logs (and the TestResults artifact if present), fix, push again. A milestone is complete only when CI is green for its commit. Do not edit .github/workflows/ci.yml except to fix a genuine workflow defect (log it in BUILDLOG.md). Simulator/device visual checks go on the manual-QA list in BUILDLOG.md.
