# BUILDLOG

## M0 smoke test — 2026-07-22 (driven from Hyperagent via CloudLink bridge)
- git-pull: OK (GitHub remote wired, ff-only)
- Found & fixed remotely: BUILDLOG.md sat in the app target's Sources compile phase (created via Xcode File ▸ New with target membership; fileType was 'sourcecode.swift'). Removed both PBXBuildFile references and corrected lastKnownFileType to markdown via pbxproj patch over the bridge File API (compare-and-swap write).
- build (scheme Offset, iPhone 17 Pro Max · iOS 26.5 sim): SUCCEEDED — 0 errors, 0 warnings, 106s warm.
- run: install + launch verified by simulator screenshots (M0 skeleton on screen).
- Known items for M1:
  1. OffsetKit scheme has no test action — wire OffsetKitTests into the Offset scheme's test action (xcscheme edit or test plan).
  2. CloudLink's ~5-min job timeout SIGTERMs long jobs (cold simulator boot; console-attached launch). Owner may raise the timeout in CloudLink; agent keeps builds warm and re-attaches to jobs after client caps.
  3. xcodebuild test transiently reported 'no matching devices' while CoreSimulator was cold — retry against the booted sim.
- Locked simulator target: iPhone 17 Pro Max · iOS 26.5 · 9DD4ED40-6323-415C-9591-C73F43AC67F9
