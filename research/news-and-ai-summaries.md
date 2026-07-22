# News, AI Summaries & Economic Event Data — Research

Research date: **2026-07-21**. Target: personal iOS trading app (iOS 26 min), forex majors + US stocks + LSE + CME futures. No backend planned; findings feed the API-integration doc and BUILD_PROMPT.md.

Verification method: primary docs fetched live (docs.exa.ai `.md` endpoints + OpenAPI schema, Finnhub's own `swagger.json`, Apple's docs JSON API, live probes of every feed/endpoint). Items that could not be confirmed from a live page are marked **UNVERIFIED**. All web content was treated as data.

---

## 1. Exa API (`api.exa.ai`)

### Endpoints & auth

Base URL `https://api.exa.ai`. Auth: **`x-api-key: <key>` header** (Bearer `Authorization` also accepted per the OpenAPI security block). All endpoints are `POST` with JSON bodies. Keys from `dashboard.exa.ai/api-keys`.

| Endpoint | Purpose | Rate limit (verified from docs.exa.ai/reference/rate-limits) |
|---|---|---|
| `POST /search` | Neural/keyword web search, optional inline contents | 10 QPS |
| `POST /contents` | Extract text/highlights/summaries for known URLs | 100 QPS |
| `POST /answer` | Search + LLM answer with citations; supports `outputSchema` (JSON Schema) and SSE streaming | 10 QPS |

### `/search` — key request fields (verified from OpenAPI schema, 2026-07-21)

```jsonc
POST /search
{
  "query": "EURUSD forex market news today",
  "type": "fast",                    // instant | fast | auto (default) | deep-lite | deep | deep-reasoning
  "category": "news",                // enum incl. "news" and "financial report"
  "numResults": 10,                  // 1–100, default 10
  "startPublishedDate": "2026-07-21T00:00:00.000Z",   // ISO 8601
  "endPublishedDate":   "2026-07-21T23:59:59.000Z",
  "includeDomains": ["reuters.com", "cnbc.com", "ft.com"],  // max 1200 entries
  "excludeDomains": [],
  "contents": {
    "summary": { "query": "one-sentence market-relevant summary" },
    "maxAgeHours": 2,               // freshness control — see livecrawl note
    "livecrawlTimeout": 10000       // ms, default 10000, max 90000
  }
}
```

Notes:
- **Livecrawl status change (mid-2026):** the old `livecrawl: never | always | fallback | preferred` enum is **deprecated** — docs now say "Use `maxAgeHours` instead". `maxAgeHours`: positive N = accept cache up to N hours old; `0` = force fresh fetch; `-1` = cache only; omitted = fallback fetching. Max 720. Do not send both fields.
- `category: "news"` is a documented enum value (alongside `company`, `research paper`, `publication`, `personal site`, `financial report`, `people`). Date filters work fine with `news` (they are only disallowed for `company`/`people`).
- Newer options: `outputSchema` (structured synthesis on any search type, ~+2 s latency), `systemPrompt`, `additionalQueries` (deep types only), `moderation`, `userLocation`.
- `startCrawlDate`/`endCrawlDate` are deprecated.

### Trimmed response shapes (from docs examples)

```jsonc
// /search
{
  "requestId": "b5947044…",
  "resolvedSearchType": "neural",
  "results": [{
    "title": "…", "url": "https://…", "id": "https://…",
    "publishedDate": "2026-07-21T09:12:00.000Z",
    "author": "…", "image": "…", "favicon": "…",
    "text": "…",                    // if contents.text
    "summary": "…",                 // if contents.summary
    "highlights": ["…"], "highlightScores": [0.46]
  }],
  "costDollars": { "total": 0.007, "search": { "neural": 0.007 } }
}

// /answer
{
  "answer": "…",                     // or structured JSON if outputSchema given
  "citations": [{ "id": "…", "url": "…", "title": "…", "author": "…",
                  "publishedDate": "…", "text": "…" }],
  "costDollars": { "total": 0.007 }
}
```

### Current pricing (verified live from exa.ai/pricing, 2026-07-21)

| Item | Price |
|---|---|
| Free tier | **$20 credits on sign-up + $10 free credits per month** |
| `/search` (up to 10 results) | **$7 / 1k requests** |
| Deep search / deep-reasoning | $12 / $15 per 1k requests |
| Extra results above 10 | +$1 / 1k requests per result |
| `/contents` | **$1 / 1k pages per content type** (text, highlights each count) |
| AI page summaries | $1 / 1k pages |
| `/answer` | **$5 / 1k requests** |
| Monitors | $15 / 1k requests |

### Direct-from-device sanity check @ 30–50 queries/day

- 40 queries/day ≈ 1,200/mo → `/search` alone: **$8.40/mo**. Add per-result summaries on 10 results/query: +$12/mo. Using `/answer` instead: $6/mo. Realistic blended cost: **~$8–20/mo, of which $10/mo is covered by the recurring free credit → effective ~$0–10/mo.**
- Rate limits (10 QPS) are 5 orders of magnitude above personal needs.
- **Verdict: sane.** Cost and limits are a non-issue. The only real risk of an on-device key is extraction from the app bundle/traffic — for a personal, non-distributed app this is acceptable. A trivial proxy (e.g. free-tier Cloudflare Worker holding the key) buys revocation and spend isolation but is **not warranted** unless the app ever goes to TestFlight/other people. Mitigate instead: dedicated key, dashboard spend/usage alerts, rotate if leaked.
- Practical from-device tips: use `type: "fast"` (or `instant`) for interactive latency; prefer `contents.summary` on `numResults: 5–10` instead of full `text` (cheaper, smaller payloads, and keeps FoundationModels prompts within budget).

---

## 2. Finance-news alternatives — comparison

| API | Free-tier limits | Relevant endpoints | Auth | Licensing / ToS / reliability notes |
|---|---|---|---|---|
| **Finnhub** | Free tier exists; general + company news **are free**; rate limit 60 calls/min (widely documented; pricing page is JS-rendered — **UNVERIFIED live**, but endpoint free/premium flags verified from Finnhub's own swagger.json) | `GET /api/v1/news?category=general|forex|crypto|merger` (free); `GET /api/v1/company-news?symbol&from&to` (free, **North-American symbols only**, 1 yr history); `GET /api/v1/calendar/economic` (**"Premium Access Required"** — verified in swagger); `/news-sentiment` (premium) | `token=` query param or `X-Finnhub-Token` header | Free data intended for personal/evaluation; attribution/link-back requested when displaying. Solid uptime reputation. Forex *news category* free — good fit. LSE company news not on free tier. |
| **Marketaux** | **100 requests/day, only 3 articles per request** (verified live from pricing page) | `GET https://api.marketaux.com/v1/news/all?symbols=TSLA,…&api_token=…`; entity sentiment per article; filters: symbols, exchanges, industries, countries, `published_after` | `api_token` query param | 3-articles/request on free makes a 10–20 headline briefing take 4–7 calls. Global coverage (80+ markets incl. LSE) is the draw. Free tier fine for personal use; attribution expected on public display. |
| **Alpha Vantage `NEWS_SENTIMENT`** | **25 requests/day total** across all endpoints (verified live from support page) | `GET https://www.alphavantage.co/query?function=NEWS_SENTIMENT&tickers=AAPL,FOREX:USD&topics=economy_monetary&time_from=YYYYMMDDTHHMM&sort=LATEST&limit=50` | `apikey` query param | Response verified live (returns 2026 articles on `demo` key): `feed[]` with `time_published` (`YYYYMMDDTHHMMSS`, US/Eastern-naive — treat carefully), per-article + per-ticker sentiment scores/labels (Bearish→Bullish), topic relevance. Great schema; **25 req/day is the killer** — usable only for 1–2 daily briefing pulls. |
| **Polygon.io (rebranded "Massive", mid-2026)** | News endpoint **included in free "Stocks Basic" plan**; free news is **updated hourly**, 2 yr history (verified live from docs); free plan famously 5 API calls/min (**UNVERIFIED live** — pricing page JS) | `GET /v2/reference/news?ticker=AAPL&published_utc.gte=…&limit=100&order=desc` → `results[]` {title, article_url, published_utc (RFC3339 UTC), tickers[], description, publisher, insights[] (per-ticker sentiment + reasoning), keywords} | `apiKey` query param or `Authorization: Bearer` | Rebrand: docs/sample responses now reference `api.massive.com`; `polygon.io` URLs still serve. **Hourly update on free tier = not breaking-news grade.** US-listed tickers; no forex news. Clean API, excellent docs. Benzinga real-time news is a $99/mo partner add-on. |
| **Financial Modeling Prep (FMP)** | Free "Basic": **250 calls/day**, 500 MB/30-day bandwidth cap — but **"Financial Market News" starts at Starter ($22/mo annual)**; corporate calendars at Premium $59/mo (verified live from pricing page) | `stable/news/*`, `stable/fmp-articles`; economics calendar endpoints on paid tiers | `apikey` query param | News effectively **not free**. ToS: displaying/redistributing FMP data requires a Data Display & Licensing Agreement. Skip for this project. |
| **NewsAPI.org** | Developer free: 100 req/day, **articles delayed 24 h**, **dev/testing only — production use prohibited**; paid starts **$449/mo** (verified live) | `GET /v2/everything?q=…`, `/v2/top-headlines` | `X-Api-Key` header | 24 h delay + no-production clause makes it **useless for a trading app**. Exclude. |
| **Tiingo** | Free tier exists; token required for every call (verified: API returns "Please supply a token"). Free limits commonly documented as ~50 req/hr / 1,000 req/day / 500 unique symbols/mo — **UNVERIFIED** (pricing page is fully JS-rendered, unreachable here incl. via archive) | `GET https://api.tiingo.com/tiingo/news?tickers=…&startDate=…` | `token=` param or `Authorization: Token …` | News API historically gated: free accounts must request access / news redistribution prohibited; treat news as effectively paid/approval-only — **UNVERIFIED**. Good reputation for EOD prices; not the news pick. |

### Free feeds (no key)

| Feed | Status (probed 2026-07-21) | Notes |
|---|---|---|
| **ForexFactory weekly calendar JSON** — `https://nfs.faireconomy.media/ff_calendar_thisweek.json` | **200 OK, live, current data** | See §3. `…_thisweek.xml` also 200. **`…_nextweek.json` now returns 404** — the next-week variant is gone; plan around a this-week-only horizon. |
| CNBC RSS — `https://www.cnbc.com/id/100003114/device/rss/rss.html` (Top News; id `20910258` = Markets, also 200) | 200 OK, valid RSS 2.0 | Reliable, fast-updating, no key. Personal-use consumption of public RSS is low-risk; don't republish. |
| Dow Jones/MarketWatch — `https://feeds.content.dowjones.io/public/rss/mw_topstories` | 200 OK | Official public DJ feed set (`mw_realtimeheadlines`, `mw_bulletins` also exist under `/public/rss/`). |
| Yahoo Finance per-ticker RSS — `https://feeds.finance.yahoo.com/rss/2.0/headline?s=AAPL` | 200 OK; **works for LSE tickers too** (`s=VOD.L` verified) | Best free per-symbol option covering US + LSE. Unofficial/undocumented — can change without notice. |
| Investing.com RSS — `https://www.investing.com/rss/news.rss` | 200 OK | ToS discourages automated use; keep as last-resort. |
| Reuters public RSS | Discontinued (historical) | Don't plan on it. |

**Bottom line for headlines:** Finnhub free (`/news?category=general|forex` + `/company-news` for US tickers) is the best keyed source; Yahoo/CNBC/DJ RSS cover LSE symbols and keyless redundancy; Exa `/search` (`category: "news"`, date-filtered, domain-filtered) is the premium "search anything, incl. CME/futures context" layer.

---

## 3. Economic event data (recommendation: ForexFactory JSON)

**Recommended source:** `https://nfs.faireconomy.media/ff_calendar_thisweek.json` — free, no key, includes **impact ratings**, event times, and **currency codes**. This is exactly what alerting needs; no calendar UI required.

### Verified schema (live sample, 2026-07-21; 69 events this week)

```json
[
  {
    "title": "CPI m/m",                          // event name
    "country": "CAD",                            // CURRENCY code, not ISO country (AUD, CAD, CHF, CNY, EUR, GBP, JPY, NZD, USD observed)
    "date": "2026-07-20T08:30:00-04:00",         // ISO 8601 WITH explicit UTC offset
    "impact": "High",                            // "High" | "Medium" | "Low" | "Holiday"
    "forecast": "-0.2%",                         // string; may be "" — units embedded (%, K, M, B)
    "previous": "1.0%"                           // string; may be ""
  }
]
```

- Exactly 6 keys per event (verified across the full feed): `title, country, date, impact, forecast, previous`. **No `actual` field** — the feed is forward-looking; alerts don't need actuals, but post-release surprise display would require another source (e.g. Finnhub premium).
- **Time zone:** timestamps carry an explicit ISO-8601 offset (currently `-04:00` = US Eastern DST; the feed is pinned to America/New_York wall time). Parse with `ISO8601DateFormatter` and convert to the user's zone — never assume UTC, and rely on the offset rather than hard-coding Eastern.
- **Update cadence (observed from HTTP headers):** Cloudflare CDN, `Cache-Control: public, max-age=60`; `last-modified` was ~58 min old at probe time → feed regenerated at least hourly. Pragmatic polling: **2–4 fetches/day + on-app-foreground**, cache locally, schedule local notifications from cache. This also respects Fair Economy's informal courtesy limits (it is a free feed with no SLA; heavy polling has historically gotten IPs throttled).
- ToS: feed is provided by ForexFactory/Fair Economy Media for personal, non-redistributive use. For a personal app: fine. Don't rebroadcast it.
- Coverage check for confirmed markets: USD/EUR/GBP/JPY/CHF/CAD/AUD/NZD + CNY events → covers forex majors, all US macro that moves CME futures & US stocks (FOMC, NFP, CPI), and GBP events relevant to LSE. Verified this week's feed contains High-impact GBP (Claimant Count) and CAD/NZD CPI entries.
- XML mirror (`ff_calendar_thisweek.xml`) verified 200 as a same-data fallback format. **The `nextweek` variant is dead (404)** — late-Sunday fetches will only see the new week once it rolls over (feed rolls on ForexFactory's week boundary).

**Fallbacks if the feed dies:** Finnhub `/calendar/economic` (clean JSON — `{actual, country: "US", estimate, event, impact: "low|medium|high", prev, time: "YYYY-MM-DD HH:MM:SS", unit}` — but **premium-only**, verified via swagger); FMP economics calendar (paid tier); Trading Economics API (expensive). There is no comparably rich *free* keyed source with impact ratings — which is why caching the FF feed defensively matters.

---

## 4. FoundationModels framework (iOS 26+, on-device)

Platform availability (verified from Apple docs metadata): **iOS 26.0, iPadOS 26.0, Mac Catalyst 26.0, macOS 26.0, visionOS 26.0; watchOS 27.0 (beta as of mid-2026)**. Apple ships model updates in OS updates — docs currently list three model versions: OS 26.0–26.3, 26.4, and 27.0.

### Availability check (exact API, verified)

`SystemLanguageModel.default` is the on-device base model. `availability` is `.available` or `.unavailable(UnavailableReason)`; the **three documented `UnavailableReason` cases are exactly: `appleIntelligenceNotEnabled`, `deviceNotEligible`, `modelNotReady`** (plus treat the enum as non-frozen — always keep a `let other` catch-all, as Apple's own sample does):

```swift
import FoundationModels

struct GenerativeView: View {
    private var model = SystemLanguageModel.default
    var body: some View {
        switch model.availability {
        case .available:                                  // show AI briefing UI
        case .unavailable(.deviceNotEligible):            // permanent: fall back to raw headlines
        case .unavailable(.appleIntelligenceNotEnabled):  // prompt: enable AI in Settings
        case .unavailable(.modelNotReady):                // transient: model downloading — retry later
        case .unavailable(let other):                     // unknown reason
        }
    }
}
```

`isAvailable` exists as a Bool convenience. `contextSize` (Int, added 26.4, back-deployed) returns the max context tokens; `tokenCount(for:)` counts tokens for a prompt.

### Sessions, respond, streaming (verified signatures)

```swift
let session = LanguageModelSession(instructions: """
    You are a concise markets analyst. Summarize headlines for a trader. \
    Neutral tone. No advice. Note likely FX/index impact when obvious.
    """)

// One-shot text
let response = try await session.respond(to: prompt)          // response.content: String

// Streaming (AsyncSequence of snapshots)
for try await partial in session.streamResponse(to: prompt) { render(partial) }
```

Also available: `respond(to:generating:includeSchemaInPrompt:options:)` for guided generation, `streamResponse(to:generating:…)` (streams progressively-filled partial structs), `prewarm(promptPrefix:)` to cut first-token latency, `GenerationOptions(temperature:maximumResponseTokens:)`, and `session.isResponding`. Keep instructions trusted-only — the model privileges instructions over prompt content (Apple's stated injection defense); put fetched headlines in the *prompt*, never the instructions.

### Guided generation for the briefing (verified pattern)

```swift
@Generable(description: "A pre-session market briefing")
struct Briefing {
    @Guide(description: "One-line session headline, max 12 words")
    var headline: String
    @Guide(description: "Key market-moving points", .maximumCount(5))
    var bullets: [String]
    @Guide(description: "Overall market sentiment")
    var sentiment: Sentiment          // @Generable enum: bullish/bearish/neutral/mixed — nested Generable types are supported
}

let briefing = try await session.respond(
    to: prompt, generating: Briefing.self
).content
```

Constrained sampling **guarantees** well-formed output (no JSON parsing, no malformed-output path). `@Generable` works on structs, actors, enums (incl. associated values); `@Guide` on stored properties supports descriptions plus constraints like `.range(0...20)`, `.minimumCount/.maximumCount`, patterns. Properties generate in declaration order. Schema tokens count against context — keep `@Guide` descriptions short.

### Context window — VERIFIED: 4,096 tokens

Apple's "Managing the context window" article states verbatim: *"Apple's on-device foundation model has a context window of 4096 tokens per session"* — covering instructions + prompts + tool/schema definitions + all responses in the session. Overflow throws `LanguageModelSession.GenerationError.exceededContextWindowSize`; recover by starting a fresh session (optionally seeded via `init(model:tools:transcript:)` with condensed history). A token ≈ 3–4 chars of English. `contextSize` should be preferred over hard-coding 4096 going forward (newer model versions may differ).

### Prompt-size best practice for 10–20 headlines

Budget for one briefing call: instructions ≤ ~150 tokens + 20 headlines × ~15–25 tokens (~300–500) + Briefing schema (~100–200) + response (cap via `maximumResponseTokens` ≈ 400–600) → **~1,000–1,500 tokens, comfortably inside 4,096** — but only if you: use a **fresh single-turn session per briefing** (never accumulate multiturn history), send **titles + source + timestamp only** (never article bodies/URLs/HTML), truncate each headline to ~120 chars, and cap at 20 headlines. Apple's guidance: imperative, ≤3-paragraph instructions; ask for bounded output ("in three sentences", `.maximumCount`). For 20+ headlines or per-headline summaries, chunk into separate sessions. Profile with Xcode Instruments' **Foundation Models template** (token breakdown per request).

### Supported devices & unsupported-device behavior

Apple Intelligence device list (verified live from apple.com, mid-2026): **iPhone 15 Pro / 15 Pro Max (A17 Pro) and every later iPhone** — 16/16e/16 Plus/16 Pro (A18/A18 Pro), 17/17e (A19), 17 Pro/Air (A19 Pro); iPad mini (A17 Pro), iPad Air/Pro (M1+); Macs M1+; Vision Pro (M2). **Base iPhone 15/15 Plus are NOT eligible.** Important sizing note: iOS 26 itself runs on iPhone 11 and later, so under an "iOS 26 minimum" target every iPhone from 11 through base 15 can install the app **without** Apple Intelligence — the `.deviceNotEligible` fallback path is mandatory, not theoretical.

On an unsupported device the framework **links and runs normally**; `availability` returns `.unavailable(.deviceNotEligible)` and any generation attempt throws. There is no crash path — but you must ship a non-AI fallback UI. Model also requires Apple Intelligence toggled on and the asset downloaded (`.modelNotReady` while downloading; can also appear under storage/thermal pressure — treat as retryable).

### App extensions / widgets

No documented prohibition — FoundationModels is a regular framework with no entitlement (only the separate `PrivateCloudComputeLanguageModel` needs an entitlement). Community + Apple-forum guidance is that it can run in extensions, but **widget timeline extensions are a bad execution environment** for it (tight memory budget — commonly cited ~30 MB — and short runtime vs. multi-second generation). **UNVERIFIED: no explicit Apple doc statement either way was reachable.** Pragmatic design: generate the briefing in the main app (or an App Intent), persist to an App Group container, and have the widget render the cached briefing. This sidesteps the question entirely and is the architecture to put in BUILD_PROMPT.md.

Sources: developer.apple.com/documentation/foundationmodels (SystemLanguageModel, LanguageModelSession, Generable, GenerationOptions, "Managing the context window", "Generating content and performing tasks…"); WWDC25 sessions verified by title: **286 "Meet the Foundation Models framework"**, **301 "Deep dive into the Foundation Models framework"**, **259 "Code-along: Bring on-device AI to your app…"** (plus 248 "Explore prompt design & safety…").

---

## 5. Recommended stack + fallback chain

### Stack (personal app, no backend)

1. **Econ events / alerts:** ForexFactory JSON (`nfs.faireconomy.media/ff_calendar_thisweek.json`) — free, keyless, impact-rated, currency-coded. Fetch 2–4×/day + on foreground; cache in SwiftData/files; schedule local notifications for Medium/High events matching the user's currencies (USD, EUR, GBP, JPY + majors).
2. **Headlines (keyed primary):** Finnhub free — `/news?category=general` + `category=forex`, plus `/company-news` for watchlisted US tickers. 60 calls/min free is generous.
3. **Headlines (keyless redundancy + LSE):** Yahoo per-ticker RSS (`?s=VOD.L` works) + CNBC/Dow Jones RSS parsed with `XMLParser`.
4. **Search & enrichment (paid, tiny spend):** Exa `/search` with `category: "news"`, date filters, `includeDomains`, `contents.summary` — for "what's moving CME crude/ES today"-style queries and briefing enrichment; `/answer` (with `outputSchema`) as the cloud summarizer fallback. ~$0–10/mo net of free credits.
5. **Summaries/briefing:** FoundationModels on-device — `@Generable Briefing` via one fresh `LanguageModelSession` per briefing; streaming for breaking-headline summaries; zero cost, private, offline-capable.

### Fallback chain

```
Daily briefing:
  FoundationModels .available
      → guided Briefing from cached headlines (on-device, free)
  .unavailable(.modelNotReady)
      → retry with backoff; meanwhile show raw grouped headlines
  .unavailable(.deviceNotEligible | .appleIntelligenceNotEnabled)
      → Exa /answer with outputSchema (same Briefing JSON shape), if user enabled Exa
      → else raw headlines list (always works, keyless RSS at minimum)

Headlines:  Finnhub → RSS (Yahoo/CNBC/DJ) → Exa /search(category:"news")
Econ events: FF JSON cache (this-week horizon) → stale-cache banner if fetch fails
             → (paid escape hatch: Finnhub /calendar/economic premium)
```

### API key storage (pragmatic recommendation)

- **Do:** keep keys in a **gitignored `Secrets.xcconfig`** → reference from build settings → inject into `Info.plist` (`$(EXA_API_KEY)`) → read via `Bundle.main` at launch, then **write into Keychain** (`kSecAttrAccessibleAfterFirstUnlock`) and read from Keychain thereafter. This keeps keys out of source control (the real threat for a personal repo) while keeping builds one-step. Alternative equally-fine pattern for a personal app: a one-time paste-your-key settings screen → straight to Keychain (keeps the key out of the bundle entirely — strictly better if the repo or an .ipa might ever be shared).
- **Don't:** hard-code in source, commit xcconfig/plists with real keys, or bother with a proxy for a single-user app. Note honestly: anything in Info.plist/bundle is extractable from an .ipa — Keychain-after-first-read or paste-in-at-runtime narrows that; a proxy is the only true fix and is overkill here. Revisit (Cloudflare Worker, free) only if the app is ever distributed.
- Per-provider: Finnhub/Marketaux/AV keys are free-tier and low-blast-radius; the Exa key has real spend attached — set dashboard alerts and use a dedicated key for the app.

### Cost summary (monthly, personal use)

| Component | Cost |
|---|---|
| ForexFactory JSON, RSS feeds | $0 |
| Finnhub free tier | $0 |
| FoundationModels | $0 (on-device) |
| Exa @ ~30–50 q/day | ~$8–20 gross → **~$0–10 net** of $10/mo free credits |
| **Total** | **≈ $0–10/mo** |
