# XCODE_SETUP.md — Local setup before the agent starts (Xcode 26.6)

This is the human-performed **M0** from `BUILD_PROMPT.md`, as exact Xcode 26.6 steps. Time: ~15–20 minutes. When you finish the checklist at the bottom, the coding agent starts at **M1**.

> Menu names below are Xcode 26.x. If a setting moved in a point release, search Build Settings by the setting name.

---

## 0. Prerequisites

| Item | Requirement |
|---|---|
| Mac | Xcode 26.6 installed (macOS version per its release notes), iOS 26.x SDK + at least one iOS 26 simulator runtime downloaded (Xcode ▸ Settings ▸ Components) |
| Apple Developer account | **Paid strongly recommended.** Free provisioning expires every 7 days and complicates capability signing. Sign into Xcode ▸ Settings ▸ Accounts |
| iPhone 14 Pro Max | Updated to iOS 26.x · Developer Mode ON (Settings ▸ Privacy & Security ▸ Developer Mode ▸ restart) · trusted with the Mac |
| API keys (optional now) | Finnhub free key (finnhub.io) · Exa key (dashboard.exa.ai). The app must run without them — you can add keys later |
| Icon Composer (optional until M9) | Apple's Icon Composer app (developer.apple.com downloads) for the layered Liquid Glass `.icon` file |

### Identifier decision — pick once, use everywhere

The docs use the root `dev.offsetapp`. Either keep it, or substitute your own reverse-DNS (e.g. `com.yourname`) **consistently in all five places**:

| # | Identifier | Default |
|---|---|---|
| 1 | App bundle id | `dev.offsetapp.offset` |
| 2 | Widget extension bundle id | `dev.offsetapp.offset.widgets` |
| 3 | App Group | `group.dev.offsetapp.offset` |
| 4 | BGTask id (schedule) | `dev.offsetapp.offset.refresh.schedule` |
| 5 | BGTask id (news) | `dev.offsetapp.offset.refresh.news` |

If you substitute: tell the agent in your kickoff message — it must mirror your choice in `SharedConstants.swift` and the Info.plist entries.

---

## 1. Create the project

1. **File ▸ New ▸ Project ▸ iOS ▸ App** → Next.
2. Product Name: `Offset` · Team: *your team* · Organization Identifier: `dev.offsetapp` (or yours) · Interface: **SwiftUI** · Language: **Swift** · Testing System: **Swift Testing** · Storage: **None**. Leave "Host in CloudKit" & Core Data off.
3. Save at your repo root. Check "Create Git repository" (or `git init` later).

## 2. App target settings

Select the project ▸ target **Offset**:

- **General ▸ Minimum Deployments**: iOS **26.0**.
- **General ▸ Supported Destinations**: delete iPad / Mac / Vision rows — keep **iPhone** only.
- **General ▸ Deployment Info ▸ iPhone Orientation**: Portrait only (uncheck both landscape).
- **Build Settings** (filter "swift"):
  - *Swift Language Version* = **Swift 6**
  - *Approachable Concurrency* = **Yes**
  - *Default Actor Isolation* = **MainActor**
  (New Xcode 26 templates usually preset the last two — verify. These implement `02-ARCHITECTURE.md` §2; the agent records the exact resolved setting names in BUILDLOG.)

## 3. Widget extension target

1. **File ▸ New ▸ Target ▸ Widget Extension** → name `OffsetWidgets`.
2. ✅ **Include Live Activity** · ❌ Include Configuration App Intent → Finish → **Activate** the scheme when prompted.
3. On the **OffsetWidgets** target: Minimum Deployments **iOS 26.0**; same three Swift build settings as §2.

## 4. Local Swift package `OffsetKit`

1. **File ▸ New ▸ Package… ▸ Library** → name `OffsetKit` → Save **inside the repo root** → "Add to" project **Offset**, Group: top-level.
2. Replace its `Package.swift` with:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OffsetKit",
    platforms: [.iOS(.v26)],
    products: [.library(name: "OffsetKit", targets: ["OffsetKit"])],
    targets: [
        .target(name: "OffsetKit", resources: [.process("Resources")]),
        .testTarget(name: "OffsetKitTests", dependencies: ["OffsetKit"])
    ]
)
```

3. Create the folder `OffsetKit/Sources/OffsetKit/Resources/` (empty for now — seed JSONs land here in M1) and make sure `Sources/OffsetKit/OffsetKit.swift` exists (any placeholder type).
4. Link the library to **both** targets: each target ▸ General ▸ *Frameworks, Libraries, and Embedded Content* ▸ **+** ▸ `OffsetKit`.

## 5. `Shared/` sources (compiled into BOTH targets)

1. **File ▸ New ▸ Group** at repo root → `Shared`.
2. Add a placeholder `SharedConstants.swift`; in the File Inspector, check Target Membership for **Offset** AND **OffsetWidgets**. (The agent adds `MarketCountdownAttributes.swift` etc. here — same dual membership.)

## 6. Capabilities (Signing & Capabilities tab)

**Offset (app) target** — click **+ Capability** and add:
1. **App Groups** → **+** → `group.dev.offsetapp.offset`
2. **Time Sensitive Notifications** — search "time" in the capability library with the APP target selected. **If it doesn't appear**, add the entitlement manually (fully equivalent — the capability button just writes this key): open `Offset/Offset.entitlements` (created when you added App Groups) → Add Row → raw key `com.apple.developer.usernotifications.time-sensitive` → Boolean → YES. App target only; no Apple approval needed (that's Critical Alerts, which Offset intentionally does not use — AlarmKit covers silent-breaking). If a DEVICE build later fails with "provisioning profile doesn't include … time-sensitive" on a free team, remove the row and proceed — the agent gates `.timeSensitive`; alerts simply won't break Focus until the entitlement returns on a paid team.
3. **Background Modes** → check **Background fetch** + **Background processing**

> Agent note (time-sensitive runtime model): it is entitlement + per-app user toggle (Settings ▸ Notifications ▸ Offset). Do NOT request the deprecated iOS 15-era `UNAuthorizationOptions.timeSensitive` at runtime; just set `interruptionLevel = .timeSensitive` on content when the rule's style calls for it.

**OffsetWidgets target**:
1. **App Groups** → same group `group.dev.offsetapp.offset`

Signing: Automatically manage signing, your team selected, on **both** targets. Build once — Xcode registers the App IDs/App Group with your team.

## 7. Info.plist entries (app target ▸ Info tab)

Add these keys (right-click ▸ Add Row; raw key names shown):

| Key | Type | Value |
|---|---|---|
| `NSSupportsLiveActivities` | Boolean | YES |
| `NSSupportsLiveActivitiesFrequentUpdates` | Boolean | YES *(note: this spelling; an Apple doc page has a typo variant)* |
| `NSAlarmKitUsageDescription` | String | `Offset uses alarms so critical market opens can break through Silent mode when you ask them to.` |
| `BGTaskSchedulerPermittedIdentifiers` | Array of String | item 0: `dev.offsetapp.offset.refresh.schedule` · item 1: `dev.offsetapp.offset.refresh.news` |
| URL scheme | — | Info tab ▸ **URL Types** ▸ + ▸ Identifier `dev.offsetapp.offset.links`, URL Schemes `offset` |

(Notification permission strings are requested at runtime — no plist key needed. The widget target's plist needs nothing extra.)

## 8. Secrets plumbing

1. Create folder `Config/` at repo root with two files:

`Config/Secrets.example.xcconfig` (committed):
```
// Copy to Secrets.xcconfig and fill in. Secrets.xcconfig is gitignored.
FINNHUB_API_KEY = your_finnhub_key_here
EXA_API_KEY = your_exa_key_here
```

`Config/Secrets.xcconfig` (gitignored) — same two lines with real values, or leave placeholders (app degrades gracefully).

2. Attach: Project (blue icon) ▸ **Info** ▸ **Configurations** → expand Debug and Release → set **Offset** project row's configuration file to `Secrets` for both. 
3. App target ▸ Info tab → add two String rows: `FINNHUB_API_KEY` = `$(FINNHUB_API_KEY)` and `EXA_API_KEY` = `$(EXA_API_KEY)`.

## 9. .gitignore

At repo root:
```
Config/Secrets.xcconfig
xcuserdata/
DerivedData/
build/
*.xcuserstate
```

## 10. Put the spec in the repo

Copy the **`docs/`** and **`research/`** folders from the spec bundle into the repo root, and create an empty `BUILDLOG.md`. The agent reads `docs/BUILD_PROMPT.md` first.

---

## ✅ M0 acceptance checklist (run before inviting the agent)

- [ ] `xcodebuild -list` shows targets `Offset` and `OffsetWidgets`
- [ ] App builds & runs on an iOS 26 simulator (template screen is fine)
- [ ] OffsetWidgets scheme builds
- [ ] OffsetKit test target runs (⌘U on the package — placeholder test passes)
- [ ] Both targets: deployment 26.0, Swift 6 / Approachable Concurrency / MainActor default isolation
- [ ] App Group present on BOTH targets; Time Sensitive + Background Modes on app
- [ ] All §7 Info.plist keys present; `offset` URL scheme registered
- [ ] Secrets xcconfig wired (build succeeds even with placeholder values)
- [ ] One successful **device** build to the iPhone 14 Pro Max (proves signing + capabilities)
- [ ] `docs/`, `research/`, `BUILDLOG.md` in repo; `Secrets.xcconfig` NOT tracked by git

## Kickoff message to the agent (template)

> Repo is at M0 per docs/XCODE_SETUP.md — targets, capabilities, package, secrets are wired and verified. Read docs/BUILD_PROMPT.md and execute M1→M9. Identifier root is `dev.offsetapp` [or: I substituted `com.<yours>` — mirror it in SharedConstants]. Simulator available: <name>. Ask nothing you can resolve from the docs; log decisions in BUILDLOG.md.
