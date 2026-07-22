# iOS 26 Liquid Glass + Modern SwiftUI — Implementation Reference

Researched 2026-07-21 against developer.apple.com (doc JSON endpoints), WWDC25 transcripts (sessions 219, 323, 337), Apple HIG, and third-party corroboration (Donny Wals). Target: iOS 26 minimum, Xcode 26.6, SwiftUI-first.

**Verification status:** Every API below was fetched from Apple's live documentation on 2026-07-21 with exact availability strings. Items I could not verify are explicitly marked UNVERIFIED.

**Critical version note:** WWDC26 (June 2026) introduced iOS 27 beta APIs that look tempting but are NOT available on iOS 26 / Xcode 26.x. See §7.4 for the exclusion list.

---

## 1. Liquid Glass fundamentals (HIG)

Source: https://developer.apple.com/design/human-interface-guidelines/materials and https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass

- **Glass is the functional layer, not the content layer.** "Liquid Glass forms a distinct functional layer for controls and navigation elements — like tab bars and sidebars — that floats above the content layer." **"Don't use Liquid Glass in the content layer"** — use standard `Material` (`.ultraThin`/`.thin`/`.regular`/`.thick`) for in-content differentiation (e.g., cards, chart overlays). Exception: content-layer controls with transient interaction (slider/toggle knobs) take on glass only while being manipulated — the system does this automatically.
- **Use glass effects sparingly.** Standard components (bars, sheets, popovers, controls) adopt it automatically. Custom `glassEffect` is for "the most important functional elements" only. Never stack/overlap custom glass on glass.
- **Regular variant** (default): blurs + adapts luminosity of background for legibility; use whenever there is meaningful text or unpredictable backgrounds (alerts, sidebars, toolbars). Most system components use regular.
- **Clear variant**: highly translucent; only over visually rich media backgrounds (photos/video). Legibility rule: if the underlying content is bright, add a dark dimming layer of ~35% opacity beneath the glass (HIG: "consider adding a dark dimming layer of 35% opacity").
- **Legibility helpers:** scroll edge effects blur/fade content under bars automatically; remove any custom backgrounds/darkening behind bar items or they interfere. Use monochrome toolbar icons; tint only to convey meaning (e.g., a call to action), not decoration.
- Appearance "can differ in response to certain system settings" — accessibility Reduce Transparency / Increase Contrast, and the user's preferred Liquid Glass look (see §7.3).

**Trading-app translation:** session cards, price tables, and charts = content layer (standard materials/backgrounds). Tab bar, toolbars, countdown accessory bar, floating "session filter" buttons = glass layer.

---

## 2. Core Liquid Glass APIs (all iOS 26.0 unless noted)

### 2.1 `glassEffect(_:in:)` — View modifier
`nonisolated func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View`
iOS 26.0 / iPadOS 26.0 / macOS 26.0 / tvOS 26.0 / watchOS 26.0.
Default: `.regular` variant in a `Capsule`. Material anchors to the view's bounds (includes padding). Apply after all appearance-affecting modifiers.
https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)

```swift
Text("NYSE • Open").padding().glassEffect()                       // regular, capsule
Image(systemName: "bell").padding().glassEffect(in: .rect(cornerRadius: 16))
Button { } label: { Image(systemName: "plus").padding() }
    .glassEffect(.regular.tint(.green).interactive())             // tinted + touch-reactive
```

### 2.2 `Glass` configuration struct — iOS 26.0
Type properties: `.regular`, `.clear`, `.identity` (no glass; useful for conditional removal). Instance methods: `.tint(_ color: Color?) -> Glass`, `.interactive(_ isEnabled: Bool = true) -> Glass` (adds the same touch/pointer reaction standard buttons have).
Clear-variant legibility (from `Glass.clear` doc): place e.g. `.background(.black.opacity(0.3))` beneath.
https://developer.apple.com/documentation/swiftui/glass

### 2.3 `GlassEffectContainer` — iOS 26.0
`struct GlassEffectContainer<Content: View>` — `init(spacing:content:)`.
Combines multiple glass shapes into one render pass: **required for performance with multiple effects** and for blending/morphing. `spacing` controls when nearby shapes start to melt together (container spacing > inner stack spacing ⇒ blended at rest).
https://developer.apple.com/documentation/swiftui/glasseffectcontainer

```swift
GlassEffectContainer(spacing: 40) {
    HStack(spacing: 40) {
        Image(systemName: "scribble.variable").frame(width: 80, height: 80).glassEffect()
        Image(systemName: "eraser.fill").frame(width: 80, height: 80).glassEffect()
    }
}
```

### 2.4 `glassEffectID(_:in:)` — morphing, iOS 26.0
`func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View`
Inside a `GlassEffectContainer`, IDs let shapes morph into/out of each other during inserts/removals with `withAnimation`. Default transition `.matchedGeometry` when within container spacing; use `GlassEffectTransition.materialize` for distant elements. Related: `glassEffectUnion(id:namespace:)` (iOS 26.0) merges multiple views into one glass shape at rest.
https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)
https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views

```swift
@State private var isExpanded = false
@Namespace private var ns
GlassEffectContainer(spacing: 40) {
    HStack(spacing: 40) {
        Image(systemName: "chart.bar").frame(width: 80, height: 80)
            .glassEffect().glassEffectID("chart", in: ns)
        if isExpanded {
            Image(systemName: "bell").frame(width: 80, height: 80)
                .glassEffect().glassEffectID("alerts", in: ns)   // morphs out of "chart"
        }
    }
}
Button("Toggle") { withAnimation { isExpanded.toggle() } }.buttonStyle(.glass)
```

### 2.5 Button styles — iOS 26.0
`.buttonStyle(.glass)` → `GlassButtonStyle`; `.buttonStyle(.glassProminent)` → `GlassProminentButtonStyle` (analog of `.borderedProminent`; combine with `.tint(...)`). Prefer these over hand-rolled `glassEffect` buttons.
https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass
https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent

### 2.6 `ToolbarSpacer` — iOS 26.0 (iOS/iPadOS/Mac Catalyst/macOS only)
`struct ToolbarSpacer` — `init(_ sizing: SpacerSizing = .flexible, placement: ToolbarItemPlacement = .automatic)`. Splits toolbar items into separate shared-glass groups (`.fixed`) or pushes groups apart (`.flexible`).
https://developer.apple.com/documentation/swiftui/toolbarspacer

```swift
.toolbar {
    ToolbarItem { ShareLink(item: url) }
    ToolbarSpacer(.fixed)                       // new glass group boundary
    ToolbarItem { FavoriteButton() }
    ToolbarItem { CollectionsButton() }         // shares glass with Favorite
}
```

### 2.7 `sharedBackgroundVisibility(_:)` — ToolbarContent modifier, iOS 26.0
`func sharedBackgroundVisibility(_ visibility: Visibility) -> some ToolbarContent`
Hides the shared glass behind a single toolbar item, placing it in its own group — e.g., a status/badge item that shouldn't sit on glass.
https://developer.apple.com/documentation/swiftui/toolbarcontent/sharedbackgroundvisibility(_:)

```swift
.toolbar {
    ToolbarItem(placement: .principal) { MarketStatusBadge() }
        .sharedBackgroundVisibility(.hidden)
}
```

---

## 3. Navigation & structure

### 3.1 NavigationStack + title + subtitle
`navigationSubtitle(_:)` — **iOS 26.0 / iPadOS 26.0** (pre-existing on macOS 13 / Mac Catalyst 16). Renders under the title in the nav bar — ideal for "NYSE closes in 2h 14m"-style context lines.
https://developer.apple.com/documentation/swiftui/view/navigationsubtitle(_:)

```swift
NavigationStack {
    SessionList()
        .navigationTitle("Sessions")
        .navigationSubtitle("3 markets open")
}
```

### 3.2 Toolbar grouping + scroll behavior (WWDC25 session 323, verified transcript)
- Toolbar items are "placed on a Liquid Glass surface that floats above your app's content and automatically adapts to what's beneath it"; items are automatically grouped by placement, with the system back button kept separate.
- On scroll, the bar itself never gains an opaque background; legibility comes from the automatic **scroll edge effect** (subtle blur+fade under bars). Large titles collapse to inline as before; glass adapts light/dark to content beneath.
- Badges on toolbar buttons: `Button(...).badge(count)`.
- There is **no** toolbar-minimize-on-scroll API in iOS 26 (that's iOS 27's `toolbarMinimizeBehavior(_:for:)` — see §7.4). Tab bars minimize; toolbars do not.
Source: https://developer.apple.com/videos/play/wwdc2025/323/

### 3.3 `scrollEdgeEffectStyle(_:for:)` — iOS 26.0
`func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set) -> some View`
Styles: `.automatic`, `.soft` (blurred gradient, default look), `.hard` (opaque-ish linear boundary — Apple recommends for "denser UIs with a lot of floating elements"). `scrollEdgeEffectHidden(_:for:)` removes it.
https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:)

```swift
ScrollView { PriceGrid() }.scrollEdgeEffectStyle(.hard, for: .top)
```

### 3.4 TabView: minimize + search role + bottom accessory
- `tabBarMinimizeBehavior(_:)` — iOS 26.0. Values (`TabBarMinimizeBehavior`): `.automatic`, `.never`, `.onScrollDown`, `.onScrollUp`. Tab bar shrinks to a small pill on scroll; re-expands on opposite scroll.
  https://developer.apple.com/documentation/swiftui/view/tabbarminimizebehavior(_:)
- `Tab(role: .search)` — `TabRole.search` is **iOS 18.0**; on iOS 26 the search tab is automatically separated at the trailing end of the tab bar, and selecting it makes "a search field take the place of the tab bar" (session 323 + SwiftUI updates page).
  https://developer.apple.com/documentation/swiftui/tabrole/search
- `tabViewBottomAccessory(content:)` — **iOS 26.0, iOS/iPadOS/Mac Catalyst only.** Mini-player-style bar above the tab bar. When the tab bar minimizes, the accessory collapses **inline into the tab bar area** — adapt via environment `\.tabViewBottomAccessoryPlacement` (`TabViewBottomAccessoryPlacement` enum: `.inline`, `.expanded`).
  https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)
  https://developer.apple.com/documentation/swiftui/tabviewbottomaccessoryplacement

```swift
TabView { /* tabs */ }
    .tabBarMinimizeBehavior(.onScrollDown)
    .tabViewBottomAccessory { CountdownBar() }

struct CountdownBar: View {
    @Environment(\.tabViewBottomAccessoryPlacement) var placement
    var body: some View {
        switch placement {
        case .inline:   CompactCountdown()   // collapsed into tab bar
        default:        FullCountdown()      // .expanded / nil
        }
    }
}
```

### 3.5 `backgroundExtensionEffect()` — iOS 26.0
Mirrors + blurs a view outward into adjacent safe areas so it appears to extend under sidebars/inspectors (hero images in `NavigationSplitView` detail). Use on a single background element; it clips to avoid overlapping copies. Mostly an iPad/Mac pattern; on iPhone useful for edge-to-edge hero headers.
https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect()

### 3.6 Bonus: `safeAreaBar(edge:alignment:spacing:content:)` — iOS 26.0
Like `safeAreaInset` but registers the content as a bar so scroll views beneath get the proper scroll edge effect. Use for custom non-tab bottom bars.
https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)

---

## 4. Search patterns on iOS 26

Source: WWDC25 323 (verified transcript), HIG search-fields (https://developer.apple.com/design/human-interface-guidelines/search-fields).

- **Toolbar search, bottom-aligned on iPhone:** `.searchable(text:)` placed on `NavigationStack`/`NavigationSplitView` "automatically adapts to bring the search field at the bottom of the display" on iPhone; top-trailing on iPad/Mac. No special placement value needed — `.automatic` does this on iOS 26.
- The system may auto-minimize the field into a toolbar button "depending on device size, number of toolbar buttons, and other factors"; tapping it expands a full-width field above the keyboard.
- **Explicit opt-in to minimized:** `.searchToolbarBehavior(.minimize)` — iOS 26.0. NOTE: the type property is **`.minimize`** (`SearchToolbarBehavior`: `automatic`, `minimize`); Apple's modifier-page sample showing `.minimized` is stale.
  https://developer.apple.com/documentation/swiftui/view/searchtoolbarbehavior(_:)
- **Search tab pattern (multi-tab apps):** `Tab(role: .search)` + `.searchable` on the `TabView`; the search field replaces the tab bar when selected. HIG: two styles — "standard tab" (dedicated landing page, good for browse/discovery) vs "button appearance" (keyboard appears immediately).

```swift
TabView {
    Tab("Markets", systemImage: "globe") { MarketsView() }
    Tab(role: .search) { NavigationStack { SearchLanding() } }
}
.searchable(text: $searchText)     // scoped to search tab because of the role
```

- `SearchFieldPlacement` (iOS 15+) still exists (`.toolbar`, `.navigationBarDrawer`, `.sidebar`, plus newer `.toolbarPrincipal`); prefer `.automatic` on iOS 26.

---

## 5. Transitions

### 5.1 Zoom navigation transition — iOS 18.0
`navigationTransition(_:)` + `NavigationTransition.zoom(sourceID:in:)` + `matchedTransitionSource(id:in:)` (all iOS 18.0).
https://developer.apple.com/documentation/swiftui/view/navigationtransition(_:)

```swift
@Namespace private var ns
NavigationLink {
    SessionDetailView(session)
        .navigationTransition(.zoom(sourceID: session.id, in: ns))
} label: {
    SessionCard(session).matchedTransitionSource(id: session.id, in: ns)
}
```

### 5.2 Sheets morphing out of buttons (iOS 26 behavior, iOS 18 API)
Verified WWDC25 323 sample ("Sheet morphing", 6:5x): make the presenting toolbar button the `matchedTransitionSource`, mark the sheet content with `.navigationTransition(.zoom(...))`. Menus, alerts, popovers, and confirmation dialogs morph out of their glass controls **automatically** on iOS 26.

```swift
.toolbar {
    ToolbarItem {
        Button("Map", systemImage: "map") { isPresented = true }
            .matchedTransitionSource(id: "map-sheet", in: ns)
    }
}
.sheet(isPresented: $isPresented) {
    MapSheetContent()
        .navigationTransition(.zoom(sourceID: "map-sheet", in: ns))
}
```

### 5.3 Detents + glass sheets
`presentationDetents(_:)` is iOS 16.0. On iOS 26, **partial-height sheets automatically get an inset Liquid Glass background** with corners nesting into the display curve; on transition to `.large` the background becomes opaque and anchors edge-to-edge. Remove custom `presentationBackground` to let this work (session 323: "consider removing that and let the new material shine").

```swift
.sheet(isPresented: $showBrief) {
    NewsBriefView().presentationDetents([.height(280), .large])
}
```

---

## 6. "Native feel" polish checklist

### 6.1 SF Symbols 7 (WWDC25 session 337; Symbols framework docs)
- **Draw On / Draw Off** — iOS 26.0. `SymbolEffect.drawOn: DrawOnSymbolEffect` / `.drawOff: DrawOffSymbolEffect`; both conform to `TransitionSymbolEffect` + `IndefiniteSymbolEffect`. Playback options: `.byLayer` (default, staggered), `.wholeSymbol`, `.individually`.
  https://developer.apple.com/documentation/symbols/drawonsymboleffect
  ```swift
  Image(systemName: "bell.badge")
      .symbolEffect(.drawOn, isActive: isVisible)        // indefinite usage
  // or as a transition when the view is inserted/removed:
  Image(systemName: "checkmark.seal").transition(.symbolEffect(.drawOn.individually))
  ```
- **Variable draw** — iOS 26.0. `symbolVariableValueMode(_:)` with `SymbolVariableValueMode.draw` (or `.color`); renders the symbol path partially along its draw annotation — progress indication (e.g., session progress ring icons).
  https://developer.apple.com/documentation/swiftui/view/symbolvariablevaluemode(_:)
  ```swift
  Image(systemName: "hourglass", variableValue: sessionProgress)
      .symbolVariableValueMode(.draw)
  ```
- **Magic Replace** — iOS 18.0 (`ReplaceSymbolEffect.magic(fallback:)`); iOS 26 enhances it (enclosure matching, integrates Draw animations) with no API change.
  ```swift
  Image(systemName: isAlerting ? "bell.fill" : "bell")
      .contentTransition(.symbolEffect(.replace.magic(fallback: .replace.downUp)))
  ```
- **Gradient rendering** — iOS 26.0: `symbolColorRenderingMode(.gradient)` (`SymbolColorRenderingMode`: `.flat`, `.gradient`) — linear gradient generated from source color.
  https://developer.apple.com/documentation/swiftui/view/symbolcolorrenderingmode(_:)
- Existing effects (`.bounce`, `.wiggle`, `.breathe`, `.rotate` — iOS 18; `.pulse`, `.variableColor` — iOS 17) via `symbolEffect(_:options:value:)`.

### 6.2 Dynamic Type
- Use semantic text styles (`.font(.headline)`), never fixed point sizes; `@ScaledMetric(relativeTo: .body) var iconSize = 20` for dimensions that should track type size.
- No fixed-height rows; use `ViewThatFits` or layout that reflows at accessibility sizes; test at `.accessibility3`+.
- Trading specifics: `.monospacedDigit()` on all countdown/price `Text` to prevent width jitter; `Text(timerInterval:countsDown:)` (iOS 16) gives system-driven countdowns that update without timers (also the pattern used in Live Activities).
- Reference: https://developer.apple.com/design/human-interface-guidelines/typography

### 6.3 Safe areas / edge-to-edge
- Content scrolls edge-to-edge under bars by default; never place opaque backgrounds behind system bars (kills scroll edge effect + glass adaptation).
- `ignoresSafeArea()` only for full-bleed backgrounds; keep interactive content inside safe areas.
- Custom bottom bars: `safeAreaBar` (§3.6) or `safeAreaInset`, not manual padding.
- `backgroundExtensionEffect()` for hero content extending under sidebars (iPad/Mac).

### 6.4 App icon: Icon Composer + `.icon` file
Source: https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer + HIG app-icons.
- Icon Composer ships with Xcode 26 (Xcode > Open Developer Tool > Icon Composer). Produces a single multilayer **`.icon`** file; drop it in the project and set it as the app icon — it **replaces the AppIcon asset catalog**; Xcode auto-generates flattened icons for pre-26 OS versions at build time.
- Layers: import SVG (preferred; convert text to outlines) or PNG; organize into **max 4 groups** rendered back-to-front; system applies specular highlights, refraction, translucency, shadows dynamically — do NOT bake in your own blurs/shadows/highlights.
- Appearance variants to annotate/preview: **default (light), dark, clear (light/dark), tinted (light/dark)** — in Icon Composer these are Default / Dark / Mono (with Clear + Tinted options). Users pick the style on their Home Screen; iOS 26 added the "Clear" theme.
- Canvas 1024×1024 (iPhone/iPad/Mac); the system masks corners — deliver square unmasked layers, keep content centered.
- WWDC25: "Say hello to the new look of app icons" (219→220), "Create icons with Icon Composer" (361).

---

## 7. Gotchas

### 7.1 Performance
- "Creating too many Liquid Glass effect containers and applying too many effects to views outside of containers can degrade performance" — group all simultaneous custom effects into as few `GlassEffectContainer`s as possible; limit on-screen effect count (Apple: "Limit these effects to the most important functional elements"). (Applying-Liquid-Glass-to-custom-views + Adopting Liquid Glass.)
- Morphing only works within a single container; effects in different containers can't blend.
- `backgroundExtensionEffect`: single instance per screen, "apply with discretion" (renders mirrored copies + blur).

### 7.2 Accessibility fallbacks
- System settings **Reduce Transparency** (glass → frosted/mostly opaque), **Increase Contrast** (borders, stronger contrast), and **Reduce Motion** (morph animations toned down) all modify Liquid Glass automatically — for system components AND `glassEffect` — no code needed, but Apple explicitly says to test custom elements/colors under these settings (Adopting Liquid Glass). Don't encode meaning in translucency alone.
- Provide accessibility labels for icon-only toolbar buttons (icon-only is the iOS 26 toolbar norm).

### 7.3 iOS 26.x point releases that affect design decisions (verified)
- **iOS 26.1 (2025-11-03): user-facing Liquid Glass toggle** — Settings > Display & Brightness > Liquid Glass: **Clear** (default, original look) vs **Tinted** ("increases opacity of the material in apps and notifications on the Lock Screen" — Apple release notes). Consequence: your glass surfaces (system bars and, per Apple's note, "the material in apps") must look correct at BOTH opacity levels — never rely on seeing content through a bar, and test both modes. Sources: https://9to5mac.com/2025/11/03/apple-releases-ios-26-1/ ; https://www.macrumors.com/2025/11/03/apple-releases-ios-26-1/
- **iOS 26.2 (2025-12): Lock Screen clock Liquid Glass opacity slider** — Lock Screen-only; no in-app impact. Source: https://www.macrumors.com/2025/12/08/apple-releases-ios-26-2/
- **iOS 26.3–26.5:** no Liquid-Glass appearance/toggle changes found in sources checked — UNVERIFIED / assume none; re-check release notes before ship.
- There is no per-app API to read or override the user's Clear/Tinted preference — UNVERIFIED (none found in SwiftUI docs); design for both.

### 7.4 iOS 27 beta APIs — DO NOT USE (target is iOS 26 / Xcode 26.6)
From Apple's SwiftUI updates page (June 2026 section, https://developer.apple.com/documentation/updates/swiftui): `toolbarMinimizeBehavior(_:for:)` (toolbar minimize on scroll), `Tab` `prominent` role, `ToolbarOverflowMenu`, `visibilityPriority(_:)`, sheet `crossFade` transition, `reorderable()`, AsyncImage caching inits. All require Xcode 27 / iOS 27.

### 7.5 Availability quick table
| API | Min iOS |
|---|---|
| `.glassEffect`, `Glass`, `GlassEffectContainer`, `.glassEffectID`, `.glassEffectUnion` | 26.0 |
| `.buttonStyle(.glass)` / `.glassProminent` | 26.0 |
| `ToolbarSpacer`, `sharedBackgroundVisibility` | 26.0 |
| `.navigationSubtitle` (iPhone/iPad) | 26.0 |
| `.scrollEdgeEffectStyle`, `.tabBarMinimizeBehavior`, `.tabViewBottomAccessory`, `.backgroundExtensionEffect`, `.safeAreaBar`, `.searchToolbarBehavior` | 26.0 |
| `.symbolEffect(.drawOn/.drawOff)`, `.symbolVariableValueMode`, `.symbolColorRenderingMode` | 26.0 |
| `.navigationTransition(.zoom)`, `.matchedTransitionSource`, `Tab(role: .search)`, magic replace, `.wiggle/.breathe/.rotate` | 18.0 |
| `.presentationDetents`, `Text(timerInterval:)` | 16.0 |
| `.searchable` + `SearchFieldPlacement` | 15.0 |

### 7.6 Misc traps
- `SearchToolbarBehavior` value is `.minimize`, not `.minimized` (Apple's own modifier sample is stale).
- `UIDesignRequiresCompatibility` Info.plist key opts an app OUT of Liquid Glass; it is ignored when building with iOS 27+ SDKs. Irrelevant for a new iOS 26 app — do not set it.
- `ToolbarSpacer` and `tabViewBottomAccessory` are not on watchOS/visionOS (accessory also absent on tvOS); guard any shared code.
- Section headers in lists are now title-case (no auto-uppercasing) — write headers in Title Case.
- Half sheets are inset with rounded glass; check content near sheet corners and behind the inset gap.
- Custom nav/tab/toolbar `background`/`toolbarBackground` overrides fight the material and scroll edge effect — delete them.

---

## 8. Recommended app shell (trading-sessions app)

Verified pattern composition: TabView with 4 tabs + search role tab, minimize-on-scroll, countdown bottom accessory that collapses into the tab bar, glass-grouped toolbar with subtitle, zoom transition to detail. All APIs §2–§5.

```swift
struct RootView: View {
    @State private var search = ""
    @Namespace private var zoomNS

    var body: some View {
        TabView {
            Tab("Sessions", systemImage: "clock") {
                NavigationStack {
                    SessionListView(zoomNS: zoomNS)                    // rows: .matchedTransitionSource(id:in:)
                        .navigationTitle("Sessions")
                        .navigationSubtitle("Next: NYSE opens in 2h 14m")   // iOS 26
                        .toolbar {
                            ToolbarItem { AlertsButton().badge(3) }
                            ToolbarSpacer(.fixed)                      // own glass group
                            ToolbarItem { CalendarButton() }
                        }
                        .scrollEdgeEffectStyle(.soft, for: .top)
                }
            }
            Tab("Markets", systemImage: "globe.americas") { MarketsView() }
            Tab("News", systemImage: "newspaper") { NewsBriefsView() }
            Tab(role: .search) { NavigationStack { SearchLandingView() } }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { NextSessionBar() }   // reads \.tabViewBottomAccessoryPlacement:
                                                       // .inline → "NYSE 2:14" mono digits; else full row
        .searchable(text: $search)                     // search-tab scoped; bottom field on iPhone
    }
}
// Detail push: SessionDetailView(...).navigationTransition(.zoom(sourceID: session.id, in: zoomNS))
// Alert sheet: presenting button .matchedTransitionSource + sheet content .navigationTransition(.zoom(...))
//              .presentationDetents([.height(280), .large])   // inset glass half-sheet for free
// Countdown text everywhere: Text(timerInterval: ..., countsDown: true).monospacedDigit()
// Custom glass ONLY for: floating "jump to next session" button → .glassEffect(.regular.interactive())
```

---

## Primary sources
- HIG Materials: https://developer.apple.com/design/human-interface-guidelines/materials
- HIG App icons: https://developer.apple.com/design/human-interface-guidelines/app-icons
- HIG Search fields: https://developer.apple.com/design/human-interface-guidelines/search-fields
- Adopting Liquid Glass: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- Applying Liquid Glass to custom views: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- Landmarks sample: https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass
- SwiftUI updates (iOS 26 + iOS 27 deltas): https://developer.apple.com/documentation/updates/swiftui
- WWDC25: 219 Meet Liquid Glass; 323 Build a SwiftUI app with the new design; 256 What's new in SwiftUI; 356 Get to know the new design system; 337 What's new in SF Symbols 7; 220 Say hello to the new look of app icons; 361 Create icons with Icon Composer — https://developer.apple.com/videos/play/wwdc2025/{id}/
- Icon Composer: https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer
- iOS 26.1/26.2 release notes coverage: 9to5Mac + MacRumors links in §7.3
- Corroboration: https://www.donnywals.com/exploring-tab-bars-on-ios-26-with-liquid-glass/
