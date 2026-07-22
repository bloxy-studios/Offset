# CI_SETUP.md — Remote build & test via GitHub (Hyperagent-driven)

## Why this exists (and why not SSH)

The Hyperagent build agent runs in a sandbox whose network egress is **HTTPS-only** — SSH/SFTP/raw TCP are blocked, so it can never shell into your Mac. Instead, GitHub mediates: the agent pushes code and reads results over the GitHub API; the build executes on a runner. With a **self-hosted runner on your Mac**, the build effectively *does* run "directly on your Mac" — the runner makes outbound HTTPS calls to GitHub to fetch jobs (no inbound ports, no SSH, nothing exposed).

```
Hyperagent ──push/API (HTTPS)──▶ GitHub ◀──outbound HTTPS poll── your Mac (runner + Xcode 26.6)
```

Device installs to the iPhone 14 Pro Max remain manual on your Mac (Xcode ▸ Run) — free-team signing lives in your local keychain. On the free team this doubles as the required weekly re-provision.

## Option A (recommended): self-hosted runner on your Mac — ~10 minutes

1. Keep the repo **PRIVATE**. (Self-hosted runners on public repos can execute code from fork PRs — never do that.)
2. GitHub repo ▸ **Settings ▸ Actions ▸ Runners ▸ New self-hosted runner ▸ macOS (arm64)** → follow the shown `config.sh` commands in a folder like `~/actions-runner`.
3. When `config.sh` asks for labels, add: `offset` (the workflow targets `[self-hosted, macOS, offset]`).
4. Install it as a background service so it survives reboots:
   ```bash
   cd ~/actions-runner
   ./svc.sh install && ./svc.sh start
   ```
5. Keep the Mac awake for builds: System Settings ▸ prevent sleep on power, or run `caffeinate -s` while a build session is active.
6. Sanity check: repo ▸ Actions ▸ run the **CI** workflow manually (workflow_dispatch) → it should pick up on your Mac, print your Xcode 26.6, and go green on the M0 skeleton.

Hygiene: the runner executes only what this repo's workflows tell it to; Settings ▸ Actions ▸ General → restrict to this repository's workflows, and require approval for outside collaborators (default for private personal repos).

## Option B: GitHub-hosted `macos-latest`

Swap the `runs-on:` line in `.github/workflows/ci.yml` (comment provided in-file). Zero setup, but: macOS minutes bill at **10×** against the free 2,000 min/month on private repos (~200 effective minutes), VMs are cold/slower, and the image's Xcode inventory varies — the workflow's first step prints installed Xcodes and hard-fails with a clear error if no 26.x is present (that failure message is itself the diagnostic).

## The workflow (`.github/workflows/ci.yml`, included in this bundle)

Steps: checkout → select newest Xcode 26.x via `DEVELOPER_DIR` (no sudo) → create `Config/Secrets.xcconfig` from the example if absent (placeholder keys are fine; the app degrades gracefully by design) → auto-pick the newest available iPhone simulator → `xcodebuild build` (unsigned, `CODE_SIGNING_ALLOWED=NO`) → `xcodebuild test` with an `.xcresult` bundle → upload the result bundle as an artifact on failure.

Copy it to the repo at exactly `.github/workflows/ci.yml`.

## How the Hyperagent build loop works

Per milestone (M1→M9 from BUILD_PROMPT.md):
1. Agent edits code in its sandbox clone of the repo.
2. Agent commits + pushes via the GitHub integration (HTTPS) — milestone commits `M{n}: <summary>`, plus intermediate commits as needed since CI is the only build feedback.
3. CI runs on your Mac (or hosted runner). Agent polls the run status and fetches failure logs / the `.xcresult` artifact through the GitHub API.
4. Red → agent fixes and pushes again. Green → BUILDLOG.md entry → next milestone.
5. Items needing a physical device (AlarmKit fidelity, Live Activity terminated-start, watch mirroring, Focus/Silent behavior) accumulate in BUILDLOG's manual-QA list — you run those from Xcode on the phone.

Practical notes for the agent driving this loop:
- Push batching: prefer meaningful checkpoints over per-file pushes; every push costs a CI cycle.
- Simulator-only surfaces (Live Activities render, widget gallery) can't be *seen* from CI — correctness rides on unit tests + compile-time; visual checks join the manual-QA list.
- If the repo uses Xcode 26 synchronized folder groups (it does, per M0), files added on disk join targets automatically — pbxproj edits should be rare; when needed, keep them minimal and log them.

## KICKOFF_PROMPT addendum (remote/Hyperagent builder variant)

When the builder is a Hyperagent agent (not local Claude Code), append this to the kickoff prompt and drop protocol items 2 and 5 (local xcodebuild):

> BUILD VERIFICATION runs via GitHub Actions, not locally. Repo: <owner>/<repo> (private). After each meaningful checkpoint: commit, push, then poll the "CI" workflow run for your commit; on failure, fetch the job logs (and TestResults artifact if present), fix, push again. A milestone is complete only when CI is green for its commit. Do not edit .github/workflows/ci.yml except to fix a genuine workflow defect (log it in BUILDLOG.md). Simulator/device visual checks go on the manual-QA list in BUILDLOG.md.
