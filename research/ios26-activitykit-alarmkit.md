# ActivityKit Live Activities + Dynamic Island + AlarmKit — iOS 26 Implementation Reference

Scope: personal trading-sessions app (market open/close alerts, AUTO countdown in Dynamic Island, hard alarms). Target: iOS 26 minimum, Xcode 26.6, SwiftUI. Researched 2026-07-21 against developer.apple.com documentation JSON (current, post-WWDC25; HIG page last updated 2025-12-16), WWDC25 session 230 transcript, and corroborating blogs. Everything not marked UNVERIFIED was confirmed against an Apple source. All availability annotations are from Apple's doc metadata.

---

## A. ActivityKit lifecycle (app-side)

Framework: `import ActivityKit` — iOS 16.1+, iPadOS 16.1+, Mac Catalyst 16.1+. visionOS does NOT support Live Activities (requests fail). Live Activities can only be started from iPhone/iPad apps; they then mirror to Watch/Mac/CarPlay automatically.
Source: https://developer.apple.com/documentation/activitykit

### A.1 `ActivityAttributes` + `ContentState`

```swift
protocol ActivityAttributes : Decodable, Encodable            // iOS 16.1+
// required: associatedtype ContentState : Decodable, Encodable, Hashable
```

- The outer struct = static data (fixed for the activity's lifetime). The nested `ContentState` = dynamic data you send with every update. `ContentState` must be `Codable & Hashable`; the attributes struct itself only needs `Codable` (Apple's samples write `struct ContentState: Codable, Hashable`).
- Apple's canonical example (pizza app) — note `ClosedRange<Date>` is Codable and is the idiomatic way to ship a timer interval in state:

```swift
import ActivityKit

struct PizzaDeliveryAttributes: ActivityAttributes {
    public typealias PizzaDeliveryStatus = ContentState   // optional readability alias
    public struct ContentState: Codable, Hashable {
        var driverName: String
        var deliveryTimer: ClosedRange<Date>
    }
    var numberOfPizzas: Int
    var totalAmount: String
    var orderNumber: String
}
```
Source: https://developer.apple.com/documentation/activitykit/activityattributes

- The same type must be compiled into BOTH the app target and the widget-extension target (shared Swift file in both targets, or a shared framework/package).
- Do not use custom JSON encoding strategies if you ever push-update: the system decodes `content-state` payloads with default strategies only.

### A.2 Requesting (starting) an activity

```swift
// iOS 16.2+
static func request(attributes: Attributes,
                    content: ActivityContent<Activity<Attributes>.ContentState>,
                    pushType: PushType? = nil) throws -> Activity<Attributes>

// iOS 18.0+ — adds style
static func request(..., pushType: PushType? = nil, style: ActivityStyle) throws -> Activity<Attributes>
// ActivityStyle: .standard | .transient  (transient = lives only in expanded DI while app in use)

// iOS 26.0+ — SCHEDULED Live Activity (starts later, even if app is backgrounded)
static func request(attributes: Attributes,
                    content: ActivityContent<...>,
                    pushType: PushType? = nil,
                    style: ActivityStyle,
                    alertConfiguration: AlertConfiguration,
                    start: Date) throws -> Activity<Attributes>
// A sibling spelling request(...alertConfiguration:startDate:) also exists in the docs; the
// "ActivityKit updates" page references the `start:` variant as the June 2025 addition.
```

- Throws `ActivityAuthorizationError` (`.denied`, `.attributesTooLarge`, `.targetMaximumExceeded`, `.globalMaximumExceeded`, `.unentitled`, `.unsupported`, …).
- **You can only call `request` while the app is in the foreground**, unless the call happens inside an App Intent conforming to `LiveActivityIntent` (iOS 17+) — then the system launches your app process in the background, runs `perform()`, and starts the activity (e.g. from a Control Center control, App Shortcut, or Action button).
- Scheduled variant (iOS 26): "The system starts the Live Activity at the specified date, even if the app is in the background." You MUST pass an `AlertConfiguration` so the user is notified when it starts. `ActivityState` for a scheduled-not-yet-started activity is `.pending`. "The system limits the number of simultaneous ongoing Live Activities. Scheduled Live Activities count towards this limit." How far in advance `start:` may be, and whether it still fires if the app is force-quit/terminated, is not documented — UNVERIFIED (docs only say "in the background").
Sources:
https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:)
https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:style:alertconfiguration:start:)
https://developer.apple.com/documentation/updates/activitykit

### A.3 `ActivityContent`

```swift
struct ActivityContent<State> where State: Codable & Hashable      // iOS 16.2+
init(state: State, staleDate: Date?, relevanceScore: Double)       // relevanceScore has a default (samples call .init(state:staleDate:))
```
- `staleDate`: when reached, `activityState` becomes `.stale` and `context.isStale == true` in the widget UI — render an "outdated" treatment. Does NOT end or hide the activity.
- `relevanceScore`: relative ordering among YOUR app's multiple activities — highest score wins the Dynamic Island and sorts first on the Lock Screen; ties go to the first-started activity. Apple suggests e.g. 100 vs 50.
Source: https://developer.apple.com/documentation/activitykit/activitycontent

### A.4 Update / end

```swift
func update(_ content: ActivityContent<ContentState>) async                                    // iOS 16.2+
func update(_ content: ActivityContent<ContentState>, alertConfiguration: AlertConfiguration?) async
func update(_:alertConfiguration:timestamp:) async
func end(_ content: ActivityContent<ContentState>?, dismissalPolicy: ActivityUIDismissalPolicy = .default) async
func end(_:dismissalPolicy:timestamp:) async
```
- Update/end are allowed from the **background** (e.g. BackgroundTasks / BGAppRefreshTask) — only *starting* requires foreground/intent/push.
- `AlertConfiguration(title:body:sound:)` (`AlertConfiguration.AlertSound.default` / `.named(String)`): on iPhone/iPad an "alert" doesn't show a classic banner — it lights the screen and shows the expanded DI presentation (or Lock-Screen-presentation banner on non-DI devices); on Apple Watch the `title`/`body` are used for a real alert.
- Always pass final content to `end` so the (up to 4 h) lingering Lock Screen card shows correct final data.

```swift
struct ActivityUIDismissalPolicy      // iOS 16.1+
static let `default`: ...   // stays on Lock Screen until user removes it or up to 4h
static let immediate: ...   // removed immediately
static func after(_ date: Date) -> ...  // custom, clamped to a 4h window after end
```
HIG recommendation: 15–30 min custom dismissal is adequate for most summaries.
Sources:
https://developer.apple.com/documentation/activitykit/activity/end(_:dismissalpolicy:)
https://developer.apple.com/documentation/activitykit/activityuidismissalpolicy

### A.5 Observation & authorization

```swift
final class ActivityAuthorizationInfo {                       // iOS 16.1+
    var areActivitiesEnabled: Bool                            // synchronous gate before showing "start" UI
    let activityEnablementUpdates: ActivityEnablementUpdates  // AsyncSequence<Bool>
    var frequentPushesEnabled: Bool                           // iOS 16.2+
    let frequentPushEnablementUpdates: FrequentPushEnablementUpdates
}
```
- Users can switch Live Activities off per app in Settings; there is no runtime permission prompt for Live Activities themselves.

```swift
enum ActivityState { case active, ended, dismissed, stale, pending }   // pending = scheduled (iOS 26)
Activity.activities              // [Activity<Attributes>] — reconcile on every app launch, end orphans
Activity.activityUpdates         // new activities appear (incl. push-to-start)
activity.activityStateUpdates    // life-cycle stream
activity.contentUpdates          // state stream
activity.pushTokenUpdates        // per-activity APNs token stream
Activity.pushToStartToken(Updates) // iOS 17.2+
```
Source: https://developer.apple.com/documentation/activitykit/activityauthorizationinfo , https://developer.apple.com/documentation/activitykit/activity

### A.6 Info.plist

- `NSSupportsLiveActivities` (Boolean, YES) — in the **app target** (iOS 16.1+). Required or `request` fails.
  https://developer.apple.com/documentation/bundleresources/information-property-list/nssupportsliveactivities
- `NSSupportsLiveActivitiesFrequentUpdates` (Boolean, YES) — opt-in to frequent push updates (iOS 16.2+). NOTE: one Apple page (`ActivityAuthorizationInfo` overview) misspells this key as `NSSupportsFrequentLiveActivityUpdates`; the BundleResources reference and the push article both use `NSSupportsLiveActivitiesFrequentUpdates` — use that.
  https://developer.apple.com/documentation/bundleresources/information-property-list/nssupportsliveactivitiesfrequentupdates
- No special entitlement is needed for Live Activities (Push Notifications capability only if you use push updates).

---

## B. Widget-extension side (WidgetKit UI)

Live Activity UI lives in a **widget extension** (create one with "Include Live Activity" checked; Xcode generates the bundle). One extension can host widgets + Live Activities.

```swift
import WidgetKit
import SwiftUI

@main
struct TradingWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // MarketWidget()               // optional home-screen widgets
        MarketCountdownLiveActivity()   // the Live Activity
    }
}

struct MarketCountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MarketCountdownAttributes.self) { context in
            // LOCK SCREEN / banner presentation (context: ActivityViewContext)
            LockScreenView(attributes: context.attributes,
                           state: context.state,
                           isStale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.25))          // Lock Screen bg (iOS 16+)
                .activitySystemActionForegroundColor(Color.white)           // "Clear" button color
        } dynamicIsland: { context in
            DynamicIsland {
                // EXPANDED (long-press or alert) — four regions:
                DynamicIslandExpandedRegion(.leading)  { MarketBadge(context) }
                DynamicIslandExpandedRegion(.trailing) { CountdownText(context) }
                DynamicIslandExpandedRegion(.center)   { Text(context.attributes.marketName) }
                DynamicIslandExpandedRegion(.bottom)   { SessionTimeline(context) }
            } compactLeading: {
                Image(systemName: "chart.line.uptrend.xyaxis")   // one Live Activity active
            } compactTrailing: {
                CountdownText(context)                            // keep VERY narrow (see C)
            } minimal: {
                CountdownText(context)                            // >1 activity on device: tiny circle
            }
            .widgetURL(URL(string: "tradingapp://market/\(context.attributes.marketId)"))
            .keylineTint(Color.cyan)
        }
        .supplementalActivityFamilies([.small])   // iOS 18+: custom Watch/CarPlay layout (see F)
    }
}
```

Exact symbols and availability:
- `ActivityConfiguration<Attributes>` — `init(for:content:dynamicIsland:)`, iOS 16.1+.
  https://developer.apple.com/documentation/widgetkit/activityconfiguration
- `ActivityViewContext<Attributes>`: `.attributes`, `.state`, `.isStale`, `.activityID`.
- `DynamicIsland` — `init(expanded:compactLeading:compactTrailing:minimal:)`, iOS 16.1+; modifiers `widgetURL(_:)`, `keylineTint(_:)` (subtle border tint of the island in Dark Mode), `contentMargins(_:_:for:)` with `DynamicIslandMode` (`.expanded`, `.compactLeading`, `.compactTrailing`, `.minimal`).
  https://developer.apple.com/documentation/widgetkit/dynamicisland
- `DynamicIslandExpandedRegion<Content>` — `init(_ position: DynamicIslandExpandedRegionPosition, priority: Double = ..., content:)`; positions `.leading`, `.trailing`, `.center` (below camera), `.bottom` (below everything). Region with highest `priority` gets full DI width. `func dynamicIsland(verticalPlacement: .belowIfTooWide)` (view modifier) drops too-wide leading content below the camera. Per-region `contentMargins(_:_:)` also exists.
  https://developer.apple.com/documentation/widgetkit/dynamicislandexpandedregion
- `activityBackgroundTint(_:)` (SwiftUI, iOS 16+) — Lock Screen background only; DI background is always opaque black and CANNOT be changed. `activitySystemActionForegroundColor(_:)` colors the system "Clear/end" affordance.
  https://developer.apple.com/documentation/swiftui/view/activitybackgroundtint(_:)
  https://developer.apple.com/documentation/widgetkit/dynamicisland/keylinetint(_:)
  https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities

Layout constraints (Apple docs + HIG, HIG updated 2025-12-16):
- Lock Screen presentation may be **truncated above 160 pt height**; height range 84–160 pt; standard Lock Screen margin 14 pt.
- Expanded DI width 371 pt (6.1") / 408 pt (6.7/6.9"); height 84–160 pt; DI corner radius 44 pt.
- Compact leading & trailing each ≈ 52.33×36.67 pt (230 pt-wide island) to 62.33×36.67 pt (250 pt island); minimal 36.67–45 × 36.67 pt.
- Images larger than the target presentation can make `request` FAIL (e.g. minimal image ≤ 45×36.67 pt).
- Live Activities run sandboxed: **no network, no location** in the extension; buttons/toggles only via AppIntents initializers (`Button(intent:)`/`Toggle(intent:)`, iOS 17+); `withAnimation` is ignored (system timing, max ~2 s, `numericText(countsDown:)` for timers).
Sources: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities , https://developer.apple.com/design/human-interface-guidelines/live-activities

---

## C. Countdown timers that tick WITHOUT push/app updates

The system renders these live in widgets/Live Activities — text advances every second with **zero** `update()` calls, zero pushes, and no app runtime. This is the backbone of the AUTO market countdown.

1) `Text(timerInterval:pauseTime:countsDown:showsHours:)` — iOS 16.0+ (also macOS 13/watchOS 9)
```swift
init(timerInterval: ClosedRange<Date>, pauseTime: Date? = nil,
     countsDown: Bool = true, showsHours: Bool = true)
// e.g. Text(timerInterval: Date.now...marketOpenDate)  → "1:27:03" counting down; shows "0:00" at end
```
`pauseTime` freezes the display at a given date (pausable without updates — set once in state).
https://developer.apple.com/documentation/swiftui/text/init(timerinterval:pausetime:countsdown:showshours:)

2) `Text(_ date: Date, style: Text.DateStyle)` — iOS 14.0+
Styles: `.timer` (counts up/down to/from date, "2:32"), `.relative` ("2 hr, 32 min"), `.offset` ("+2 hours"), `.date`, `.time`.
https://developer.apple.com/documentation/swiftui/text/init(_:style:) , https://developer.apple.com/documentation/swiftui/text/datestyle

3) `ProgressView(timerInterval:countsDown:label:currentValueLabel:)` — iOS 16.0+
Auto-progressing determinate bar/ring across a `ClosedRange<Date>`; `.progressViewStyle(.circular)` gives the classic DI ring. "Date-relative progress views don't support custom styles."
https://developer.apple.com/documentation/swiftui/progressview/init(timerinterval:countsdown:label:currentvaluelabel:)

4) iOS 18.0+ additions — `TimeDataSource` + `SystemFormatStyle` (best formatting control):
```swift
Text(.currentDate, format: .timer(countingDownIn: start..<marketOpen,
                                  showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
// also: .stopwatch(startingAt:...), .reference(to:), .offset(to:)
// TimeDataSource.currentDate / .dateRange(endingAt:) / .durationOffset(to:)
```
`struct TimeDataSource<Value>` — iOS 18.0+: "provides Text with live and automatically updating values in Widgets, Live Activities, watchOS Complications". `SystemFormatStyle.Timer.timer(countingDownIn:showsHours:maxFieldCount:maxPrecision:)` — iOS 18.0+ (Foundation). `maxFieldCount: 2` renders "1:05" instead of "1:05:03" — the sanctioned fix for compact-DI width. No newer iOS 26-specific timer-text API was found in the docs (UNVERIFIED that none exists, but none is documented under SwiftUI/Foundation updates).
https://developer.apple.com/documentation/swiftui/timedatasource
https://developer.apple.com/documentation/foundation/formatstyle/timer(countingdownin:showshours:maxfieldcount:maxprecision:)

Width/formatting constraints in the compact Dynamic Island (verified HIG + community practice):
- HIG: compact trailing is ~52–62 pt wide; "keep content as narrow as possible… use shortened units or less precise data"; content must sit snug against the camera without padding.
- Known behavior (community-verified, e.g. Apple Dev Forums & nilcoalescing sample; not in API docs): `Text(timerInterval:)` reserves the maximum width the string could occupy and left-aligns, which looks broken in compactTrailing. Standard mitigations:
```swift
Text(timerInterval: Date.now...state.eventDate, showsHours: false)
    .monospacedDigit()
    .multilineTextAlignment(.trailing)
    .frame(width: 44)            // clamp; tune 40–50pt for "MM:SS"
// or on iOS 18+: Text(.currentDate, format: .timer(countingDownIn: range, maxFieldCount: 2))
// or sidestep text entirely: ProgressView(timerInterval:) ring in compactTrailing (Apple's Timer app pattern)
```
- For countdowns > 1 h in compact, prefer the ring or "≥1h"-style coarse text; switch to MM:SS via a single scheduled `update()` when you cross 1 h, or just rely on `showsHours: true` with `maxFieldCount: 2`.
- Animations: request numeric roll with `.contentTransition(.numericText(countsDown: true))`; on Always-On display animations are suppressed (see F).

---

## D. Constraints & budgets (verified current numbers)

| Constraint | Value (iOS 26 docs) | Source |
|---|---|---|
| Content size | Static attributes + dynamic state (incl. push payload content-state) **combined ≤ 4 KB**; `end` final content ≤ 4 KB; `ActivityAuthorizationError.attributesTooLarge` = "exceeded the maximum size of 4KB" | displaying-live-data article (Important box); activityauthorizationerror/attributestoolarge |
| Max active duration | **8 hours** — then system ends it and removes it from the DI immediately | displaying-live-data article, "Understand constraints" |
| Lock Screen persistence after end | up to **4 more hours** (user removal wins) ⇒ **12 h absolute max on Lock Screen** | same article |
| Post-end dismissal | `.default` ≤ 4 h; `.after(date)` clamped to 4 h window; `.immediate` | activityuidismissalpolicy |
| Lock Screen height | 84–160 pt; may truncate > 160 pt | same article + HIG Specifications |
| Push update budget | "The system allows for a certain budget of ActivityKit push notifications per hour" — **exact number not published** (UNVERIFIED community folklore ranges; do not design to a number). `apns-priority: 5` does NOT count toward the budget; `10` does; exceed ⇒ throttling | starting-and-updating…push-notifications article |
| Frequent updates | `NSSupportsLiveActivitiesFrequentUpdates` = YES lifts the budget; user can disable per app (`frequentPushesEnabled`, `frequentPushEnablementUpdates`) | same article; bundleresources page |
| Local (in-process) updates | Not budget-limited by APNs rules; limited only by your app's runtime (foreground, or background e.g. BGAppRefreshTask — scheduling of which is opportunistic and NOT time-guaranteed) | activity/end + displaying article |
| staleDate | At `staleDate`: `activityState → .stale`, `context.isStale → true`. Pure UI/logic signal; nothing is dismissed | displaying article, "Configure the Live Activity" |
| Max concurrent activities | No published number. Official signals: `targetMaximumExceeded` ("app has already started the maximum number of concurrent Live Activities") and `globalMaximumExceeded` (device-wide max). Docs: "An app can start or schedule several Live Activities… the exact number may depend on a variety of factors"; scheduled ones count. Community-observed ≈ 5 per app — UNVERIFIED, do not rely | activityauthorizationerror cases; displaying article note |
| Images | Asset resolution must be ≤ presentation size or `request` may fail (minimal ≤ 45×36.67 pt) | request(…) discussion |

Practical implication for this app: a "next market event" countdown ≤ 8 h always fits the active window (longest gap between majors is well under 8 h on weekdays; weekend gap Fri 22:00 UTC → Sun 21:00/22:00 UTC does NOT fit — the Live Activity cannot span the weekend; schedule a weekend activity to start Sunday, or start on app open).

---

## E. Remote / push updates (optional for v1)

**Per-activity push token.** Start with `Activity.request(..., pushType: .token)`, then consume `activity.pushTokenUpdates` (token arrives async and can rotate; receiving a new one grants brief background runtime) and register each token with your server. Send APNs HTTP/2 requests with headers `apns-push-type: liveactivity`, `apns-topic: <bundleID>.push-type.liveactivity`, `apns-priority: 5|10`, and payload `{"aps": {"timestamp": <unix>, "event": "update"|"end", "content-state": {…mirror of ContentState…}, "stale-date": …, "dismissal-date": …, "relevance-score": …, "alert": {…}}}`. The system wakes the widget extension to re-render; content-state is decoded with default Codable strategies only. iOS 16.1+ (tokens), testable via curl/Push Notifications Console.
https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications

**Broadcast channels (iOS 18+).** For one-to-many events (e.g. "NYSE open" for all users): create a channel via APNs channel-management API (capability enabled only on developer.apple.com, not in Xcode), app subscribes with `pushType: .channel(channelId)`, server sends one notification per channel with header `apns-channel-id`. Cannot *start* an activity via broadcast; update/end only.

**Push-to-start (iOS 17.2+).** Obtain `Activity<Attr>.pushToStartToken` / `pushToStartTokenUpdates` without any running activity; server sends `"event": "start"` with `attributes-type` (the Swift type name, e.g. `"MarketCountdownAttributes"`), `attributes`, `content-state`, and a mandatory `alert`. The system starts the Live Activity **with the app terminated**, wakes the app with background runtime, and issues update tokens (iOS 18+ can instead request `input-push-token: 1` or `input-push-channel`). This is the only fully-automatic terminated-app start mechanism — requires a server.

---

## F. Where Live Activities surface beyond iPhone

- **Apple Watch Smart Stack** (iOS 18 + watchOS 11+): activities auto-appear at the top of the Smart Stack; default view = compact leading + trailing composited. Alert updates forward `AlertConfiguration.title/body` as a Watch alert. Customize with `supplementalActivityFamilies(_:)` (`WidgetConfiguration` modifier, iOS 18+) passing `[.small]`, then branch on `@Environment(\.activityFamily)` (`ActivityFamily.small` = Watch/CarPlay, `.medium` = iPhone/iPad Lock Screen). Tapping opens your watchOS app if present, else a full-screen view with an "open on iPhone" button. Interactive elements work on Watch but are deactivated in CarPlay (shared layout — design accordingly). WWDC24 "Bring your Live Activity to Apple Watch" (10068).
  https://developer.apple.com/documentation/swiftui/widgetconfiguration/supplementalactivityfamilies(_:)
  https://developer.apple.com/documentation/widgetkit/activityfamily
- **CarPlay (iOS 26, June 2025)**: Live Activities now appear automatically on the CarPlay Dashboard using the combined compact presentation; buttons/toggles do nothing in CarPlay; opt into `.small` family for a custom larger layout. Sizes to verify: 240×78, 240×100, 170×78 pt.
  https://developer.apple.com/documentation/updates/activitykit , HIG live-activities CarPlay section
- **Mac (iOS 26)**: auto-appears in the menu bar of a paired Mac (compact/minimal/expanded unchanged); click launches iPhone Mirroring.
- **StandBy (iPhone charging, landscape)**: shows the minimal presentation; tap expands to the Lock Screen presentation scaled 2× full-screen. Detect with `@Environment(\.isActivityFullscreen)` (iOS 16.1+ symbol, `@backDeployed(before: iOS 17)`, always false on iOS 16) to provide higher-res layout; Night Mode applies a red tint — check contrast.
  https://developer.apple.com/documentation/swiftui/environmentvalues/isactivityfullscreen
- **Always-On display**: system renders Lock Screen activities dimmed/dark; NO animations are performed; read `@Environment(\.isLuminanceReduced)` (iOS 16+) and raise contrast / drop bright fills. (Community reports say timer text may tick at reduced frequency in AOD — UNVERIFIED.)
  https://developer.apple.com/documentation/swiftui/environmentvalues/isluminancereduced

---

## G. AlarmKit (new in iOS 26)

`import AlarmKit` — iOS 26.0+, iPadOS 26.0+, Mac Catalyst 26.0+. "Schedule prominent alarms and countdowns… It overrides both a device's focus and silent mode, if necessary." WWDC25 session 230 "Wake up to the AlarmKit API": "When it fires, the alert breaks through the silent mode and the current focus."
https://developer.apple.com/documentation/alarmkit , https://developer.apple.com/videos/play/wwdc2025/230/

### G.1 Authorization
- Info.plist: `NSAlarmKitUsageDescription` (string shown in the system prompt). Missing/empty ⇒ scheduling always fails.
  https://developer.apple.com/documentation/bundleresources/information-property-list/nsalarmkitusagedescription
- `AlarmManager.shared` (class `AlarmManager`):
```swift
func requestAuthorization() async throws -> AlarmManager.AuthorizationState  // .notDetermined / .authorized / .denied
var authorizationState: AlarmManager.AuthorizationState                      // synchronous check
var authorizationUpdates: some AsyncSequence<AuthorizationState, Never>
```
If you never call it, the first `schedule` auto-prompts. Users can revoke in Settings.
https://developer.apple.com/documentation/alarmkit/alarmmanager

### G.2 Scheduling
```swift
func schedule<Metadata: AlarmMetadata>(id: Alarm.ID /*UUID*/,
    configuration: AlarmManager.AlarmConfiguration<Metadata>) async throws -> Alarm

struct AlarmManager.AlarmConfiguration<Metadata: AlarmMetadata> {
    init(countdownDuration: Alarm.CountdownDuration? = nil,
         schedule: Alarm.Schedule? = nil,
         attributes: AlarmAttributes<Metadata>,
         stopIntent: (any LiveActivityIntent)? = nil,
         secondaryIntent: (any LiveActivityIntent)? = nil,
         sound: AlertConfiguration.AlertSound = .default)
    static func alarm(schedule:attributes:stopIntent:secondaryIntent:sound:) -> Self
    static func timer(duration: TimeInterval, attributes:stopIntent:secondaryIntent:sound:) -> Self
    // + appEntityIdentifier: EntityIdentifier? variants for App Intents entity linking
}
```
- `Alarm.Schedule` (enum): `.fixed(Date)` — absolute instant, does NOT shift with device timezone (RIGHT choice for market opens, which are fixed instants in exchange time); `.relative(Alarm.Schedule.Relative)` — wall-clock time that follows the device timezone:
```swift
let time = Alarm.Schedule.Relative.Time(hour: 9, minute: 30)
let sched = Alarm.Schedule.relative(.init(time: time,
              repeats: .weekly([.monday, .tuesday, .wednesday, .thursday, .friday])))
// Recurrence: .never | .weekly([Locale.Weekday])
```
- `Alarm.CountdownDuration(preAlert: TimeInterval?, postAlert: TimeInterval?)` — `preAlert`: system shows a **countdown Live Activity** for this duration BEFORE the alert fires; `postAlert`: snooze/repeat interval after tapping the repeat/snooze button. "If you provide both a countdownDuration and a schedule, the system shows a countdown UI before the alarm alerts, possibly on a repeating schedule."
  https://developer.apple.com/documentation/alarmkit/alarmmanager/schedule(id:configuration:)
- Lifecycle control: `cancel(id:)`, `stop(id:)`, `pause(id:)`, `resume(id:)`, `countdown(id:)` (all `throws`, non-async); `alarms: [Alarm]`; `alarmUpdates: AsyncSequence<[Alarm], Never>` — an alarm absent from the stream is no longer scheduled; state survives while your app isn't running.
- `Alarm.State`: `.scheduled`, `.countdown`, `.paused`, `.alerting`. `Alarm` exposes only `id`, `state`, `schedule`, `countdownDuration` (no live remaining-time — that flows to the widget via `AlarmPresentationState`).

### G.3 Presentation (system template + your widget)
```swift
// ALERT (required)
let alert = AlarmPresentation.Alert(
    title: "NYSE opens in 15 min",
    secondaryButton: AlarmButton(text: "Open", textColor: .white, systemImageName: "arrow.right.circle.fill"),
    secondaryButtonBehavior: .custom)          // .countdown = snooze/repeat; .custom = run secondaryIntent
// NOTE: init(title:stopButton:secondaryButton:secondaryButtonBehavior:) is now DEPRECATED —
// current SDK provides the stop button automatically (WWDC25 sample code still shows stopButton).

// COUNTDOWN + PAUSED (optional; needed if you use preAlert countdown)
let countdown = AlarmPresentation.Countdown(title: "Market opens", pauseButton: .init(text: "Pause", textColor: .cyan, systemImageName: "pause"))
let paused    = AlarmPresentation.Paused(title: "Paused", resumeButton: .init(text: "Resume", textColor: .cyan, systemImageName: "play"))

let attributes = AlarmAttributes<MarketAlarmData>(
    presentation: AlarmPresentation(alert: alert, countdown: countdown, paused: paused),
    metadata: MarketAlarmData(marketId: "nyse"),        // your custom payload
    tintColor: .cyan)                                    // tints title/countdown/secondary button everywhere
```
- `AlarmButton(text:textColor:systemImageName:)` — the SF Symbol is what shows in the Dynamic Island alert.
- `protocol AlarmMetadata: Codable, Hashable, Sendable` — can be an empty struct; it's generic on `AlarmAttributes`, so a concrete type is mandatory (compile error "Generic parameter 'Metadata' could not be inferred" otherwise). With Xcode 26 default-MainActor modules mark it `nonisolated` (nilcoalescing, 2025-07-03).
- `AlarmAttributes` conforms to `ActivityAttributes`; its `ContentState == AlarmPresentationState` (system-managed): `state.mode` is `.countdown(Mode.Countdown)` / `.paused(Mode.Paused)` / `.alert(Mode.Alert)`; `Mode.Countdown` carries `fireDate`, `startDate`, `totalCountdownDuration`, `previouslyElapsedDuration` — render with `Text(timerInterval: Date.now...countdown.fireDate)`.
- **Widget extension is REQUIRED if the alarm supports a countdown presentation**: "AlarmKit expects a widget extension if an app supports a countdown presentation. Otherwise, the system may unexpectedly dismiss alarms and fail to alert." Reuse the same extension as the market Live Activity; add `ActivityConfiguration(for: AlarmAttributes<MarketAlarmData>.self)` as a second activity in the bundle.
  https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit
  https://developer.apple.com/documentation/alarmkit/alarmpresentationstate

### G.4 Behavior facts (verified)
- **Breaks through Silent mode and Focus** — yes (framework article + WWDC25). Positioning: "not a replacement for other prominent notifications, like critical alerts or time-sensitive notifications" (WWDC25).
- **Presentation surface**: prominent system alert with title + app name + buttons — full-screen style on the Lock Screen, compact banner/Dynamic Island presentation when unlocked (AlarmButton `systemImageName` used in the DI; nilcoalescing: "small banner when the timer ends while the device is unlocked and a larger one on the lock screen"). Countdown/paused states appear on Lock Screen, Dynamic Island, StandBy.
- **Paired Apple Watch**: "The system forwards the alert presentation to a paired watch (if any)".
- **App terminated**: alarms are system-scheduled/system-presented; they alert and update state "even if the alarm state updated while the sample app isn't running", and survive device restarts — before first unlock your Live Activity can't render, so the system falls back to the templated countdown presentation (`AlarmPresentation.Countdown`/`.Paused`). Explicit "fires after force-quit" wording does not appear in docs, but the restart guarantee implies it — effectively VERIFIED by the restart case.
- **Sounds**: `sound:` default system sound, or `AlertConfiguration.AlertSound.named("file")` with the file in the app's main bundle or `Library/Sounds` of the app's data container (WWDC25). Max duration not documented (UNVERIFIED).
- **Limits**: `AlarmManager.AlarmError.maximumLimitReached` — "A maximum number of alarms is already scheduled." The numeric cap is NOT documented (UNVERIFIED; budget your UX to tens of alarms, not hundreds; the trading app needs < 20).
- **Custom actions**: `stopIntent` / `secondaryIntent` are `LiveActivityIntent`s; set `static var openAppWhenRun = true` to open the app (encode the alarm UUID as an `@Parameter`). Secondary button behaviors: `.countdown` (repeat/snooze using `postAlert`) or `.custom` (run your intent).

### G.5 Contrast table — "market opens in 15 minutes"

| Dimension | AlarmKit alarm (iOS 26) | Time-sensitive local notification | Live Activity |
|---|---|---|---|
| Breaks Silent switch | YES | No (only Critical Alerts entitlement does, rarely granted) | No (alert = screen lights + DI expand) |
| Breaks Focus | YES | Only if app allowed by the Focus / time-sensitive permitted | No |
| User permission | AlarmKit prompt (`NSAlarmKitUsageDescription`) | Notification permission + Time-Sensitive setting | None (Settings toggle only) |
| Fires with app terminated | YES (system-scheduled, survives reboot) | YES | Only via push-to-start or pre-scheduled `start:`; local start needs foreground/intent |
| Continuous countdown UI | YES (system countdown Live Activity via your widget ext) | No (static banner) | YES (self-ticking timer text) |
| Repeat weekly | `.relative(repeats: .weekly([...]))` (device-TZ) | `UNCalendarNotificationTrigger(repeats:)` | n/a (re-request each time) |
| Snooze/custom buttons | Built-in stop + secondary (`.countdown`/`.custom` intent) | Notification actions | AppIntents Button/Toggle in layout |
| Best for | Can't-miss opens (hard alarm, full-screen, sound) | Ordinary "15-min warning" nudges | Ambient AUTO countdown + session status |
| Risk | Heavy-handed if overused; iOS 26 only | Silenced by Silent switch/Focus | Won't exist unless started while app alive |

Recommendation: default channel = time-sensitive notification; per-market "hard alarm" toggle = AlarmKit `.fixed` alarm with `preAlert: 15*60` countdown; ambient countdown = your own Live Activity.

---

## H. Recommended architecture for the trading-sessions app

### H.1 One Live Activity type: `MarketCountdown`

```swift
// Shared file: app target + widget extension target
import ActivityKit

struct MarketCountdownAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: Phase                    // .preOpen, .open, .preClose, .closed
        var eventDate: Date                 // the instant being counted to (open or close)
        var eventLabel: String              // "NYSE Open", "London Close", "CME Globex Open"
        var nextEventDate: Date?            // for the "then: LSE close 17:30" secondary line
        var nextEventLabel: String?
        enum Phase: String, Codable, Hashable { case preOpen, open, preClose, closed }
    }
    // static
    var marketId: String                    // "nyse", "lse", "cme", "fx-london"…
    var marketDisplayName: String
    var symbol: String                      // SF Symbol or flag emoji key
    var timeZoneID: String                  // exchange TZ for footnote display
}
```
Keep it comfortably under 4 KB (this is ~200 bytes). The countdown itself needs NO updates: views use `Text(timerInterval: Date.now...context.state.eventDate)` / `ProgressView(timerInterval:)`. You only `update()` at phase boundaries (open reached → switch to counting the close), and even that can be pre-baked: set `staleDate = eventDate` so the UI can show a stale treatment if the app never got a chance to roll the phase.

Lifecycle policy (all local, no server):
1. **Start**: on app foreground (`scenePhase == .active`), compute the next market event from the local calendar engine and `Activity.request(attributes:content:pushType: nil)` if none active (`Activity<MarketCountdownAttributes>.activities.isEmpty`). Keep ONE activity ("AUTO" mode) and use `relevanceScore` if you ever run several.
2. **Chain with iOS 26 scheduled activities**: while foregrounded, also pre-schedule the following event with `Activity.request(..., style: .standard, alertConfiguration: AlertConfiguration(title:body:sound:), start: nextEventDate - leadTime)`. This lets the NEXT countdown appear even if the user doesn't reopen the app (state `.pending` until start). Scheduled activities count against the concurrency cap, so schedule at most 1–2 ahead. (Terminated-app behavior of `start:` is UNVERIFIED — docs guarantee background only; test on device.)
3. **Update**: on every foreground pass + a `BGAppRefreshTask` that rolls phase/eventDate and re-extends `staleDate`. Treat BG refresh as opportunistic, never load-bearing for timing.
4. **End**: `await activity.end(finalContent, dismissalPolicy: .after(.now + 15*60))` once the event fires and no follow-up countdown is wanted; always end orphans found in `Activity.activities` at launch. Respect the 8 h cap: never start a countdown to an event > 8 h away (e.g. over the weekend) — schedule it instead (point 2) or defer to next open.
5. **Hard alarms**: for user-flagged "can't miss" opens, schedule an AlarmKit alarm `.fixed(openDate - 15*60)`… or better `.fixed(openDate)` with `countdownDuration: .init(preAlert: 15*60, postAlert: 5*60)` — the system then renders a guaranteed 15-minute countdown (your `AlarmAttributes` widget UI) in the DI/Lock Screen with zero pushes and full termination immunity, then fires a Silent-mode-breaking alert at the open. Weekly repeating market opens: prefer computing concrete `.fixed` dates per occurrence over `.relative(.weekly)` because `.relative` follows the DEVICE timezone — wrong for exchange-fixed instants when the user travels or DST diverges (NYSE 09:30 America/New_York ≠ fixed local time in Europe). Re-schedule the next occurrences whenever the app runs; `alarmUpdates` reconciles.

### H.2 What is NOT possible without a push server (be explicit in BUILD_PROMPT)

- **Auto-starting a Live Activity while the app is terminated** is impossible locally. Local starts require: foreground app, a user-invoked `LiveActivityIntent` (Control Center control, App Shortcut, Action button), or an iOS 26 pre-scheduled `request(...start:)` made earlier while the app was alive. Fully hands-off, indefinite auto-start (e.g. every session open, forever, app never opened) requires APNs **push-to-start** (iOS 17.2+) from a server.
- **No background runtime = no rolling updates**: apps get no guaranteed timed wakeups. Without pushes, a Live Activity's *data* is frozen between app runs — which is why every displayed element must be self-ticking (`Text(timerInterval:)`, `ProgressView(timerInterval:)`) and why phase rollovers should be pre-encoded or `staleDate`-guarded.
- Live Activity **alerts** (screen light-up) at exact future times can't be triggered locally while terminated — pair with local notifications or AlarmKit for the alerting job. The scheduled-activity `AlertConfiguration` covers only the activity's start moment.
- The widget extension itself can never fetch network data or self-refresh on a timeline (Live Activities have no timeline; sandbox has no network).
- Everything else in this app is achievable serverless: countdowns tick by themselves for ≤ 8 h, AlarmKit covers terminated-app alerting, and scheduled activities + app-open refreshes cover continuity.

### H.3 Targets & plist checklist

- App target: `NSSupportsLiveActivities` = YES; `NSAlarmKitUsageDescription` = "…"; Background Modes → Background fetch (for BGAppRefreshTask) optional; no push capability needed for v1.
- Widget extension target: contains `WidgetBundle` with `MarketCountdownLiveActivity` (ActivityConfiguration for `MarketCountdownAttributes`) AND `MarketAlarmLiveActivity` (ActivityConfiguration for `AlarmAttributes<MarketAlarmData>`); shared model file in both targets; `.supplementalActivityFamilies([.small])` for Watch/CarPlay.
- Test push flows later via Push Notifications Console / curl with `apns-push-type: liveactivity`.

---

## Source index (primary)

- ActivityKit framework: https://developer.apple.com/documentation/activitykit
- Displaying live data with Live Activities (constraints, lifecycle): https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- Push notifications article: https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications
- Custom views / families / margins / colors: https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities
- ActivityKit updates (iOS 26 changes): https://developer.apple.com/documentation/updates/activitykit
- HIG Live Activities (dimensions, CarPlay/Watch/StandBy): https://developer.apple.com/design/human-interface-guidelines/live-activities
- AlarmKit framework: https://developer.apple.com/documentation/alarmkit
- AlarmKit sample "Scheduling an alarm with AlarmKit": https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit
- WWDC25 #230 "Wake up to the AlarmKit API": https://developer.apple.com/videos/play/wwdc2025/230/
- WWDC23 #10184 "Meet ActivityKit", #10185 "Update Live Activities with push notifications"; WWDC24 #10068 "Bring your Live Activity to Apple Watch" (background)
- SwiftUI timers: Text(timerInterval:) / ProgressView(timerInterval:) / TimeDataSource / SystemFormatStyle.Timer (URLs inline in §C)
- Corroboration: nilcoalescing.com "Schedule a countdown timer with AlarmKit" (2025-07-03) — Xcode 26 `nonisolated` AlarmMetadata gotcha, alarm banner sizes, `alarmUpdates` reconciliation pattern
