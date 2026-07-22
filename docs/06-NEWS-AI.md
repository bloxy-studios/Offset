# 06 — NEWS & AI

ForexFactory/Finnhub/Exa clients, schemas, BriefingEngine + Summarizer chain, the actual prompts, fallback behavior, caching, cost guardrails, testing. Names/types per `00-SPINE.md` (law). Every schema, URL, price, limit, and FoundationModels API claim below comes from `research/news-and-ai-summaries.md` (**[NEWS]**, verified 2026-07-21) unless marked **UNVERIFIED**. Architecture context (stores, RefreshCoordinator, CacheStore, secrets): `02-ARCHITECTURE.md`.

Runtime reality (spine §1): the user's iPhone 14 Pro Max has no Apple Intelligence → `FoundationModelsSummarizer` reports unavailable and **`ExaAnswerSummarizer` is the primary summarizer at runtime**. The on-device path is still fully built and auto-selected on a future eligible device.

---

## PROPOSED ADDITIONS (new vocabulary introduced by this doc)

| Name | Kind | Purpose |
|---|---|---|
| `BriefingDraft` | `@Generable` struct (OffsetKit/AI) | Model-generated fields only (`headline`, `bullets`, `watchouts`); BriefingEngine wraps it into the spine `Briefing` by adding `generatedAt`/`traderLevel`/`provider` |
| `BriefingInput` | struct definition (OffsetKit/AI) | Named in spine §4 (`Summarizer.makeBriefing(_:)`) but not defined there; fields defined in §5.1 |
| `RSSFallbackClient` | actor (OffsetKit/News) | Keyless RSS headlines (CNBC/Dow Jones/Yahoo incl. LSE tickers) |
| `HeadlineTagger` | struct (OffsetKit/News) | Deterministic keyword/currency → `[MarketID]` tagging (§3.3) |
| `SourceStatus` | enum (OffsetKit/News) | Per-source freshness/status; rendered as status rows (silent-degradation philosophy, 02 §8) |
| `ExaBudgetExceededError` | error (OffsetKit/News) | Thrown by `ExaClient` when the daily cap is hit |
| SettingsStore flat keys | UserDefaults keys | `offset.exa.dailyCallCount` (Int), `offset.exa.countDay` (String `yyyy-MM-dd`, device-local), `offset.exa.dailyCap` (Int, default **40**), `offset.exa.monthSpendUSD` (Double, accumulated from `costDollars.total`) |

```swift
enum SourceStatus: Sendable, Equatable {
    case fresh(Date)          // last successful fetch
    case stale(Date)          // serving cache beyond the source's freshness window
    case capped               // Exa daily budget reached
    case keyMissing           // API key not configured
    case offline(Date?)       // fetch failing; date of last good data, if any
}
// NewsStore publishes one per source: econ, headlines, ai.
```

---

## 1. Stack overview

Research-verified stack ([NEWS] §5), mapped to Offset components:

| Role | Source | Component | Cost |
|---|---|---|---|
| Econ events (drives econ alerts + strip + briefing) | ForexFactory weekly JSON — free, keyless, impact-rated, currency-coded | `ForexFactoryClient` → `EconEvent` | $0 |
| Headlines, keyed primary | Finnhub free tier — `/news?category=general` + `category=forex`; `/company-news` for US tickers | `FinnhubClient` → `Headline` | $0 |
| Headlines, keyless redundancy + LSE coverage | RSS: CNBC, Dow Jones/MarketWatch, Yahoo per-ticker (works for `.L` LSE tickers — verified) | `RSSFallbackClient` → `Headline` | $0 |
| Search/enrichment + cloud summarizer | Exa — `/search` (category `news`, date filters) + `/answer` (with `outputSchema`) | `ExaClient`; `ExaAnswerSummarizer` | ~$0–10/mo net |
| On-device summarizer (future device) | FoundationModels — `SystemLanguageModel.default` | `FoundationModelsSummarizer` | $0 |
| No-AI floor | deterministic assembly from cached data | `TemplateSummarizer` — **never fails** | $0 |

**Exa pricing** (verified live from exa.ai/pricing, [NEWS] §1) and **limits**:

| Item | Value |
|---|---|
| Free tier | $20 credits on sign-up + **$10 free credits per month** |
| `/search` (≤10 results) | $7 / 1k requests (deep types $12–15/1k; +$1/1k per extra result above 10) |
| `/answer` | $5 / 1k requests |
| `/contents` | $1 / 1k pages per content type; AI page summaries $1 / 1k pages |
| Rate limits | `/search` 10 QPS · `/answer` 10 QPS · `/contents` 100 QPS — 5 orders of magnitude above personal need |

**Finnhub limits** ([NEWS] §2): general + company news free; rate limit **60 calls/min** (widely documented; pricing page is JS-rendered — **UNVERIFIED live**; endpoint free/premium flags verified from Finnhub's own swagger.json). `/company-news` = **North-American symbols only**, 1 yr history. `/calendar/economic` is premium — **not used**.

**Monthly cost estimate** ([NEWS] §1/§5): 40 Exa queries/day ≈ 1,200/mo → `/search` alone $8.40/mo; `/answer` instead $6/mo; realistic blended **~$8–20/mo gross, of which $10/mo is covered by the recurring free credit → effective ~$0–10/mo**. Everything else $0. Total ≈ **$0–10/mo**.

---

## 2. ForexFactoryClient

`actor ForexFactoryClient` (OffsetKit/News). Owns its URLSession + conditional-request memory.

**Endpoint** ([NEWS] §3, probed live 200 OK): `GET https://nfs.faireconomy.media/ff_calendar_thisweek.json` — free, no key. XML mirror `…_thisweek.xml` (200) is a same-data fallback format. **`…_nextweek.json` returns 404** — the next-week variant is gone; the horizon is this-week-only. Late-Sunday fetches only see the new week after ForexFactory's week boundary rolls.

**Verified JSON schema** ([NEWS] §3 — exactly 6 keys per event, verified across the full 69-event feed; **no `actual` field**, the feed is forward-looking):

```jsonc
[{
  "title": "CPI m/m",                    // event name
  "country": "CAD",                      // CURRENCY code, not ISO country (AUD, CAD, CHF, CNY, EUR, GBP, JPY, NZD, USD observed)
  "date": "2026-07-20T08:30:00-04:00",   // ISO 8601 WITH explicit UTC offset
  "impact": "High",                      // "High" | "Medium" | "Low" | "Holiday"
  "forecast": "-0.2%",                   // string; may be "" — units embedded (%, K, M, B)
  "previous": "1.0%"                     // string; may be ""
}]
```

**Decode struct + mapping → `EconEvent`:**

```swift
struct FFEventDTO: Decodable {   // field names exactly as the feed
    let title: String; let country: String; let date: String
    let impact: String; let forecast: String; let previous: String
}
// Mapping (pure function, unit-tested):
//  id        = "ff-" + hex(SHA256("\(title)|\(dateStringAsReceived)|\(country)")).prefix(16)
//              — deterministic across fetches; order-independent; re-fetch upserts, never duplicates
//  title     = title
//  currency  = country                       // it IS a currency code
//  date      = ISO8601DateFormatter (fractional seconds off) parse of `date`
//  impact    = "High" → .high, "Medium" → .medium, "Low" → .low, "Holiday" → .holiday
//              unknown value → .low + OSLog(news) warning (forward-compatible)
//  forecast  = forecast.isEmpty ? nil : forecast
//  previous  = previous.isEmpty ? nil : previous
```

**Timezone pinning gotcha (document in code):** timestamps carry an explicit ISO-8601 offset (currently `-04:00` = US Eastern DST; the feed is pinned to America/New_York wall time). Parse with `ISO8601DateFormatter` and trust the **offset in the string** — never assume UTC, never hard-code Eastern; the explicit offset self-corrects when the feed flips to `-05:00` in winter ([NEWS] §3). The parsed `Date` is an absolute instant; display conversion is formatting only.

**`EconImpact: Comparable`** (spine declares it): ordinal `low < medium < high < holiday`. Alert filter is `impact >= .high && impact != .holiday` — `.holiday` rows are calendar notices, not releases; they render in the econ strip but never become `econRelease` alerts.

**Polling policy:** fetched by `RefreshCoordinator` — foreground pass when cache older than 6 h, plus the `dev.offsetapp.offset.refresh.news` BG task (02 §5) → effectively **2–4 fetches/day + on-foreground**, matching the research-recommended courtesy cadence (feed regenerates ~hourly; `Cache-Control: public, max-age=60`; heavy polling has historically gotten IPs throttled — [NEWS] §3). Conditional requests: a `last-modified` response header was observed ([NEWS] §3) → send `If-Modified-Since` from the remembered value and treat 304 as "cache is current"; **UNVERIFIED** whether ETag is served (not recorded in research) — tolerate plain 200s always.

**Filtering:** decode ALL events into `CachedEconEvent`; filter at read time by `AppSettings.econCurrencies` (default `["USD","GBP","EUR","JPY","AUD"]`) for the strip/briefing, and `impact >= .high` (holiday-excluded, above) for alert planning via `SessionScheduleEngine.events(…, econEvents:)`.

**Failure handling:** on any fetch error, keep serving cached events for up to **7 days** with `SourceStatus.stale(lastFetch)` ("Econ events last updated Mon 07:12"); beyond 7 days → `.offline(lastGood)` and the econ strip shows an empty-state row. No modals ever (02 §8). Fallback escape hatches if the feed dies permanently, per [NEWS] §3: XML mirror (same host), then paid options (Finnhub `/calendar/economic` premium) — out of scope for v1 code, noted for maintenance.

---

## 3. FinnhubClient

`actor FinnhubClient` (OffsetKit/News). Reads its key from `KeychainStore` (02 §6); key absent → `SourceStatus.keyMissing`, client inert.

### 3.1 Endpoints & auth ([NEWS] §2)

- `GET /api/v1/news?category=general` and `?category=forex` — free.
- `GET /api/v1/company-news?symbol={SYM}&from={yyyy-MM-dd}&to={yyyy-MM-dd}` — free, **North-American symbols only**, 1 yr history. Used only if the user adds US tickers (v1: optional, off by default — no watchlist UI in spine; keep the client method built).
- Auth: **`token=` query param or `X-Finnhub-Token` header** (verified from swagger) — use the header (keeps keys out of logged URLs).
- Base host: `https://finnhub.io` — **UNVERIFIED exact host spelling** (research verified paths `/api/v1/…` from Finnhub's own swagger.json but did not restate the host; confirm at implementation).
- Rate limit 60 calls/min (**UNVERIFIED live**, above). Client-side throttle regardless: ≥60 s between calls to the same endpoint, ≤10 calls/min global — orders of magnitude under the documented limit.

### 3.2 Response mapping → `Headline`

**UNVERIFIED response schema:** the research pass verified which endpoints are free but did not capture the `/news` response body. The commonly documented shape is below — the coding agent MUST verify field names against Finnhub's swagger.json before freezing the decoder, and the decoder must be defensive (all fields optional-tolerant, unknown fields ignored):

```jsonc
// UNVERIFIED shape — verify against https://finnhub.io/docs/api (swagger) at implementation
[{ "category": "forex", "datetime": 1784980800, "headline": "…", "id": 7418529,
   "image": "…", "related": "…", "source": "…", "summary": "…", "url": "https://…" }]
```

Mapping (pure, unit-tested): `id = "fh-\(id)"` when present, else `"fh-" + hex(SHA256(url)).prefix(16)`; `title = headline` (truncate 300 chars); `source = source`; `url = URL(string: url)` (row dropped if invalid); `publishedAt = Date(timeIntervalSince1970: datetime)`; `summary = nil` (**`Headline.summary` is reserved for OUR AI output** — Finnhub's own `summary` field is ignored); `related = HeadlineTagger.tags(title:source:)`.

### 3.3 `HeadlineTagger` — `related: [MarketID]` heuristic

Deterministic, case-insensitive keyword map over the title (word-boundary matching); multiple tags allowed; no match → `[]` (renders as general news):

| MarketID | Keywords |
|---|---|
| `fxNewYork` | USD, dollar, Fed, FOMC, Federal Reserve, Treasury, NFP, payrolls, CPI |
| `usEquities` | S&P, S&P 500, Nasdaq, Dow, NYSE, Wall Street, equities |
| `cmeEquity` | futures, E-mini, CME, Globex |
| `fxLondon` | GBP, pound, sterling, BoE, Bank of England, EUR, euro, ECB (EUR/ECB tag London for session relevance) |
| `lse` | FTSE, LSE, London Stock Exchange, UK stocks |
| `fxTokyo` | JPY, yen, BoJ, Bank of Japan, Nikkei |
| `fxSydney` | AUD, aussie, RBA, Reserve Bank of Australia |

Origin overrides: `/company-news` results always include `usEquities`; Yahoo `.L`-ticker RSS items always include `lse` — **LSE company coverage comes via RSS, not Finnhub** (free tier is NA-only; Yahoo per-ticker RSS verified working for `VOD.L` — [NEWS] §2). `RSSFallbackClient` feed list, in priority order ([NEWS] §2 free-feeds table, all probed 200): CNBC Top News `https://www.cnbc.com/id/100003114/device/rss/rss.html` (+ Markets id `20910258`), Dow Jones/MarketWatch `https://feeds.content.dowjones.io/public/rss/mw_topstories` (+ `mw_realtimeheadlines`, `mw_bulletins`), Yahoo per-ticker `https://feeds.finance.yahoo.com/rss/2.0/headline?s={SYM}` (unofficial — may change without notice), Investing.com last-resort only. Reuters RSS is discontinued — do not plan on it. Parse with Foundation `XMLParser` ([NEWS] §5); personal-use consumption only, don't republish.

### 3.4 Dedupe & polling

- Dedupe by `Headline.id` — `CachedHeadline.id` is unique (02 §4); upsert semantics. Cross-source dupes (same story from Finnhub + RSS) additionally collapse on normalized URL host+path.
- No pagination in v1: `/news` returns a latest-window list; each poll upserts and relies on the 3-day retention prune.
- Polling: **on News tab open** (if headlines older than 15 min) + **once per refresh pass** (foreground pass if older than 2 h; `refresh.news` BG task — 02 §5). All calls flow through the throttle in §3.1; a throttled request serves cache silently.

---

## 4. ExaClient

`actor ExaClient` (OffsetKit/News). Base URL `https://api.exa.ai`; auth **`x-api-key: <key>` header** (Bearer `Authorization` also accepted); **all endpoints are `POST` with JSON bodies**; keys from `dashboard.exa.ai/api-keys` ([NEWS] §1).

### 4.1 `/search` — enrichment ("pull-to-deepen")

Request fields used (all verified from the OpenAPI schema, [NEWS] §1):

```jsonc
POST /search
{
  "query": "<headline title>",
  "type": "fast",                              // interactive latency ([NEWS] §1 tips)
  "category": "news",                          // documented enum value; date filters allowed with it
  "numResults": 5,
  "startPublishedDate": "2026-07-19T00:00:00.000Z",
  "endPublishedDate":   "2026-07-21T23:59:59.000Z",
  "includeDomains": ["reuters.com", "cnbc.com", "ft.com", "marketwatch.com"],  // max 1200 entries
  "contents": { "summary": { "query": "one-sentence market-relevant summary" },
                "maxAgeHours": 24 }
}
```

**Livecrawl deprecation note (carry into code comments):** the old `livecrawl: never|always|fallback|preferred` enum is **deprecated** (mid-2026) — docs say "Use `maxAgeHours` instead": positive N = accept cache ≤ N hours old; `0` = force fresh; `-1` = cache only; omitted = fallback fetching; max 720. **Do not send both fields.** Also deprecated: `startCrawlDate`/`endCrawlDate` ([NEWS] §1).

### 4.2 `/answer` — cloud summarizer

`POST /answer` = search + LLM answer with citations; supports **`outputSchema` (JSON Schema)** and SSE streaming ([NEWS] §1). Response: `answer` (string, **or structured JSON when `outputSchema` is given**), `citations[]` (`id/url/title/author/publishedDate/text`), `costDollars.total`. Full briefing request body in §5.4. Note: `systemPrompt` is documented among newer **`/search`** options; its availability on `/answer` is **UNVERIFIED** — therefore instructions are embedded in the `query` text (§5.4), which is verified to work by construction.

Whether a structured answer arrives as a JSON object or a JSON-encoded string is not pinned down in research — **UNVERIFIED**; the decoder accepts both (try object first, then string-containing-JSON).

Cheaper alternative for single-headline summaries: `/contents` with a `summary` request ($1/1k vs $5/1k) — request body field names for `/contents` were not captured in research (**UNVERIFIED**), so v1 uses `/answer` for everything; `/contents` is a marked optimization for later.

### 4.3 Cost guardrails — hard client-side daily cap

- Cap: `offset.exa.dailyCap` (default **40** calls/day, editable in Settings; research sanity check: 40/day ≈ $6–8.40/mo gross, inside the free credit — [NEWS] §1).
- Counter: `offset.exa.dailyCallCount` + `offset.exa.countDay` in SettingsStore flat keys (02 §4.1). `ExaClient` increments **before** each request; when `countDay != today` (device-local) the counter resets — also forced by `NSCalendarDayChanged` (02 §5.2).
- At cap: throw `ExaBudgetExceededError` → callers degrade (BriefingEngine falls to template; headline summarize shows "Daily AI budget used"); `NewsStore.aiStatus = .capped` renders the status row.
- Spend telemetry: accumulate `costDollars.total` from every response into `offset.exa.monthSpendUSD`; log under OSLog `ai`; show in Settings ("Exa this month: $1.73"). Dashboard spend alerts + a dedicated key are still the real guardrail ([NEWS] §1/§5).

### 4.4 When Exa is used

1. **Breaking-headline summaries** — News tab tap-to-expand when FoundationModels is unavailable (the runtime default on the 14 Pro Max). Result written to `CachedHeadline.summary` so each headline is summarized at most once.
2. **Briefing generation fallback** — `ExaAnswerSummarizer` in the chain (§5).
3. **Optional pull-to-deepen** on a headline — `/search` (§4.1) for related fresh coverage, shown inline.

Each of the three debits the same daily cap. Nothing in the schedule/alerts pipeline ever depends on Exa.

---

## 5. BriefingEngine + Summarizer chain

Spine §4: `protocol Summarizer` (provider / `isAvailable()` / `makeBriefing(_:)` / `summarize(headline:)`) with three implementations; `BriefingEngine` picks the **first available in order `onDevice → exa → template`** and additionally falls through the chain when a selected summarizer **throws** mid-flight. `TemplateSummarizer.isAvailable()` is unconditionally `true` and its methods never throw → the chain cannot fail.

Availability predicates:
- `FoundationModelsSummarizer`: `SystemLanguageModel.default.availability == .available`.
- `ExaAnswerSummarizer`: Exa key present in `KeychainStore` AND daily cap not reached.
- `TemplateSummarizer`: always.

### 5.1 `BriefingInput` (definition — name is spine-referenced)

```swift
struct BriefingInput: Sendable {
    let date: Date                    // the "today" anchor (device-local day)
    let traderLevel: TraderLevel
    let econEvents: [EconEvent]       // today's, already filtered to AppSettings.econCurrencies
    let headlines: [Headline]         // newest first; assembler uses top 12, titles only
    let sessionFacts: [String]        // pre-rendered lines from SessionScheduleEngine output, e.g.
                                      // "London opens 03:00 your time", "NYSE closes early 13:00 (half-day)",
                                      // "London–NY overlap 08:00–12:00 your time"
    let localTimeZoneID: String       // device zone, for "your time" phrasing
}
```

`sessionFacts` are rendered by the assembler in `NewsStore`/`BriefingEngine` from engine output so summarizers stay engine-free and the same input feeds all three implementations.

**Input assembly budget** (applies to every provider; sized for the FoundationModels window, [NEWS] §4): instructions ≤ ~150 tokens; **today's events + session summary ≤ ~40 lines**; **top 12 headlines, titles only** (each truncated to ~120 chars; never bodies/URLs/HTML); `BriefingDraft` schema ~100–200 tokens; response capped via `GenerationOptions(maximumResponseTokens: 500)` → ~1,200–1,800 tokens, comfortably inside the verified **4,096-token context** ("Apple's on-device foundation model has a context window of 4096 tokens per session" — [NEWS] §4).

### 5.2 FoundationModelsSummarizer (all API claims from [NEWS] §4)

- **Availability**: `SystemLanguageModel.default.availability` is `.available` or `.unavailable(UnavailableReason)`; the three documented cases are exactly `appleIntelligenceNotEnabled`, `deviceNotEligible`, `modelNotReady` — treat the enum as **non-frozen** and keep a `let other` catch-all, as Apple's own sample does. Handling: `.deviceNotEligible` → permanent on this hardware (**this is what Kai's iPhone 14 Pro Max returns** — eligibility starts at iPhone 15 Pro / A17 Pro); `.appleIntelligenceNotEnabled` → Settings row "Enable Apple Intelligence to use on-device briefings"; `.modelNotReady` → transient (downloading, storage/thermal pressure) — retry with backoff, meanwhile the chain proceeds to Exa. `isAvailable` Bool convenience exists.
- **Session per briefing**: one **fresh single-turn** `LanguageModelSession(instructions:)` per briefing — never accumulate multiturn history. Instructions are **trusted-only** (Apple's stated injection defense privileges instructions over prompt content): the prompt carries fetched headlines/events; instructions never do.
- **Guided generation**: `respond(to:generating:)` with `@Generable`/`@Guide` — constrained sampling **guarantees** well-formed output (no JSON parsing, no malformed-output path). Properties generate in declaration order; schema tokens count against context — keep `@Guide` descriptions short.
- **Context bookkeeping**: `contextSize` (Int, added 26.4, back-deployed) is preferred over hard-coding 4096; `tokenCount(for:)` pre-checks the assembled prompt; overflow throws `LanguageModelSession.GenerationError.exceededContextWindowSize` → recover by halving headlines and retrying once in a fresh session, then fall through the chain.
- **Options**: `GenerationOptions(temperature:maximumResponseTokens:)` — temperature 0.3, max 500; `prewarm(promptPrefix:)` when the News tab appears and availability is `.available`; `session.isResponding` guards double-taps. Streaming (`streamResponse(to:)`) is reserved for tap-to-expand headline summaries; the briefing is one-shot.
- **Never run in the widget extension**: no documented prohibition exists (only `PrivateCloudComputeLanguageModel` needs an entitlement), but widget timeline extensions are a bad execution environment (tight memory budget — commonly cited ~30 MB — and short runtime vs multi-second generation); explicit Apple statement **UNVERIFIED** either way. Design (per research recommendation): generate in the main app, persist `CachedBriefing` to the App Group container, widgets render the cache.

```swift
@Generable(description: "A pre-session market briefing")
struct BriefingDraft {
    @Guide(description: "One sentence, max 20 words: what today is mainly about")
    var headline: String
    @Guide(description: "Short briefing points with times in the reader's local time", .maximumCount(5))
    var bullets: [String]
    @Guide(description: "Risk windows to watch today, each with a time", .maximumCount(3))
    var watchouts: [String]
}
// Engine wrap: Briefing(generatedAt: now, traderLevel: input.traderLevel,
//                       headline: draft.headline, bullets: draft.bullets,
//                       watchouts: draft.watchouts, provider: .onDevice)
// Validation (all providers): headline non-empty; bullets clamped to 3–5 after trimming
// (fewer than 3 non-empty bullets ⇒ throw ⇒ chain falls through); watchouts clamped to ≤3.
```

(Research shows `.minimumCount` also exists; v1 uses `.maximumCount` + instruction wording + engine-side clamping so the same validation covers all three providers.)

### 5.3 The prompts (single source of truth — string constants in `BriefingEngine`, shared verbatim by FoundationModels `instructions:` and the Exa `query` preamble)

**(a) `briefingInstructions(.beginner)`:**

```
You write Offset's morning market briefing for someone still learning to trade.
Write in plain, friendly language. The first time you use any jargon, define it
inline in parentheses — e.g. "CPI (a monthly inflation report)". Never give
trading advice, price targets, or predictions, and never use hype words.
Use ONLY the session facts, economic events, and headlines provided below.
Do not invent events, numbers, or news. All times are already in the reader's
local time; repeat them as given.

Produce:
- headline: one sentence saying what kind of trading day today looks like and why.
- bullets: 3 to 5 short points. Cover, in order of importance: today's
  highest-impact economic events (with times), anything unusual about market
  hours (holidays, early closes), and when the busiest session windows are.
  One plain sentence each.
- watchouts: exactly ONE item — the single event most likely to cause sudden
  price movement today, with its time, phrased as "watch out" guidance.
Keep the whole briefing under 120 words.
```

**(b) `briefingInstructions(.pro)`:**

```
You write a pre-session desk note for an experienced intraday trader.
Terse. Fragments over sentences. No definitions, no filler, no disclaimers,
no advice. Assume full fluency with sessions, killzones, tickers, and macro
releases. Use ONLY the data provided below; never invent numbers or events.
All times are already in the reader's local time.

Produce:
- headline: today's primary catalyst or theme, one line.
- bullets: 3 to 5. Catalysts first: each release with time, forecast vs
  previous when given. Then session structure: opens, London–NY overlap,
  unusual hours (holidays, half-days, DST mismatch weeks). Data-dense.
- watchouts: up to 3 genuine risk windows, each "HH:MM — event — why it bites".
Max 90 words total.
```

**(c) `headlineSummaryInstructions`:**

```
Summarize this market headline in one or two sentences, 45 words maximum.
Neutral and factual. No hype words, no advice, no exclamation marks.
If the story plausibly matters to FX, US stocks, UK stocks, or index futures,
end with a short clause naming which market and why it is relevant; otherwise
say it is general background news. Use only the headline and source given —
do not speculate beyond them.
```

Prompt body assembly (same for FM prompt text and Exa query, after the instructions):

```
TODAY: Tuesday 2026-07-21 (times local to the reader)
SESSION FACTS:
- London opens 03:00 your time · closes 12:00 your time
- London–NY overlap 08:00–12:00 your time
- NYSE regular 09:30–16:00 your time
ECONOMIC EVENTS TODAY (impact · currency · local time · forecast/previous):
- High · GBP · 02:00 — Claimant Count Change (prev 25.9K)
- High · USD · 08:30 — CPI m/m (forecast 0.2%, prev 0.3%)
HEADLINES (titles only, newest first):
- Dollar steadies ahead of CPI (MarketWatch)
- …up to 12…

Write the briefing now, following the rules above.
```

### 5.4 `ExaAnswerSummarizer` — the runtime-primary path

Same instructions + body, sent as the `/answer` `query`, with `outputSchema` mirroring `BriefingDraft`. `/answer` performs its own web search too — its citations enrich beyond the local cache (logged under OSLog `ai`; **not stored** — spine `Briefing` has no citations field).

```jsonc
POST https://api.exa.ai/answer
x-api-key: <EXA_API_KEY>
Content-Type: application/json
{
  "query": "<briefingInstructions(level)>\n\n<assembled prompt body from §5.3>",
  "outputSchema": {
    "type": "object",
    "properties": {
      "headline":  { "type": "string",
                     "description": "One sentence, max 20 words: what today is mainly about" },
      "bullets":   { "type": "array", "items": { "type": "string" },
                     "minItems": 3, "maxItems": 5 },
      "watchouts": { "type": "array", "items": { "type": "string" },
                     "minItems": 0, "maxItems": 3 }
    },
    "required": ["headline", "bullets", "watchouts"],
    "additionalProperties": false
  }
}
```

Decode `answer` into the same `BriefingDraft` value shape (via Codable mirror), run the §5.2 validation, wrap with `provider: .exa`. `summarize(headline:)` uses `/answer` with `headlineSummaryInstructions` + `"HEADLINE: <title> (<source>, <publishedAt>)"` and reads the plain-string `answer`. Every call passes through the §4.3 cap.

### 5.5 `TemplateSummarizer` — deterministic floor, **never fails**

Pure assembly from `BriefingInput`; zero network, zero AI, `isAvailable() == true`, no `throws` paths exercised (errors impossible by construction — every rule has a defined empty-input outcome).

Rules:
1. **headline** — first matching, in priority order: (i) an unusual-hours session fact exists (contains "closed"/"early"/"half-day") → lead with it + high-impact count, e.g. `"3 high-impact USD events today · NYSE closes early 13:00"`; (ii) any high-impact events → `"{N} high-impact {joined currencies} events today"`; (iii) else → `"Quiet calendar — {first sessionFact}"`, e.g. `"Quiet calendar — London opens 03:00 your time"`.
2. **bullets** (fill in fixed order until 5, guaranteed ≥3 because `sessionFacts` is never empty — seven markets): ① next 2–3 session facts verbatim (opens/overlap lines, e.g. `"London opens 03:00 your time"`); ② one econ line per currency with high-impact events, `"USD: 2 high-impact events (08:30 CPI m/m, 14:00 FOMC)"`, max 2 currencies; ③ any remaining unusual-hours fact; ④ beginner only: fixed teaching line `"High-impact events often move prices sharply within minutes of the release."` (pro variant omits ④ and compresses ① to times-only fragments).
3. **watchouts** — up to 3 high-impact econ events today, time-sorted: `"13:30 your time — USD CPI m/m (High)"`. None → empty array (spine allows 0–3).
4. `summarize(headline:)` → `"{source}, {relative time}. Related: {related short names, or 'general market news'}."` — deterministic, never throws.
5. `provider = .template`. BriefingCardView captions the provider ("On-device" / "Exa" / "Offline template") so degradation is visible but quiet.

Worked example (matches the required style): `"3 high-impact USD events today · NYSE closes early 13:00 · London opens 03:00 your time"` — headline rule (i) + bullet ①.

---

## 6. Briefing scheduling

- **Time**: `AppSettings.briefingTime`, default 07:30 device-local (spine §4; DECISIONS: before the NY AM killzone for an ET user).
- **Background path**: the `dev.offsetapp.offset.refresh.news` BG task (02 §5.1) generates the briefing **iff** it happens to land within ±45 min of `briefingTime` and today's `CachedBriefing` is missing — then posts a notification: title `"Your Offset briefing is ready"`, body = `briefing.headline`, standard `.active` interruption level (never time-sensitive; that budget is for market events — 04 doc), delivered via a non-repeating `UNTimeIntervalNotificationTrigger` ([MKT] HALF2 §1; immediate nil-trigger delivery is standard but **UNVERIFIED** in research, so the ~1 s interval trigger is specified). It transiently occupies one of the 8 reserved notification slots (04 doc budget).
- **Foreground path (the reliable one)**: BG tasks are opportunistic ([MKT] HALF2 §2) — on first foreground after `briefingTime` with no cached briefing for today+level, generate inline and render `BriefingCardView` directly; no notification (the user is present).
- **Cache**: `CachedBriefing.key = "yyyy-MM-dd|{traderLevel.rawValue}"` (device-local day). Switching `TraderLevel` lazily generates the other variant on next view. Retention: last 7 (02 §4.2).
- **On demand**: pull-to-refresh on the briefing card regenerates and replaces today's key. Regeneration debits the Exa cap when the Exa path is selected; at cap it silently produces a template briefing with the `.capped` status row.

---

## 7. Sequence diagrams (text)

**7.1 Cold open with cache**

```
user opens app ──► scenePhase .active ──► RefreshCoordinator.foregroundPass()
  ScheduleStore.rebuild(now)                          ← offline, instant
  CacheStore.load: headlines(≤3d) · econ(week) · briefing(today?)
  UI renders IMMEDIATELY from cache (Today, News, strip)
  async ┬ econ stale >6h?  ForexFactoryClient.fetch → upsert → econ notifications rebuild
        ├ headlines >2h?   FinnhubClient.fetch (throttled) → upsert
        └ briefing missing & now ≥ briefingTime?  BriefingEngine.make (7.2) → BriefingCardView
  re-submit both BG task requests
```

**7.2 Briefing generation on the iPhone 14 Pro Max (runtime default)**

```
BriefingEngine.makeBriefing(input)
  FoundationModelsSummarizer.isAvailable()
    SystemLanguageModel.default.availability → .unavailable(.deviceNotEligible)   → skip
  ExaAnswerSummarizer.isAvailable()
    Keychain key ✓ · dailyCallCount 12 < cap 40                                   → selected
  counter 12→13 · POST /answer { query: instructions+body, outputSchema }
  200 → decode structured answer → validate (3–5 bullets) → Briefing(provider: .exa)
  accumulate costDollars.total → offset.exa.monthSpendUSD
  CacheStore.upsert CachedBriefing "2026-07-21|beginner" → UI / "briefing ready" notification
```

**7.3 Exa cap reached → template**

```
BriefingEngine.makeBriefing(input)
  FoundationModels → .deviceNotEligible → skip
  ExaAnswerSummarizer.isAvailable() → dailyCallCount 40 ≥ cap → false
    NewsStore.aiStatus = .capped → status row "Daily AI budget used — template briefing"
  TemplateSummarizer.makeBriefing(input) → deterministic Briefing(provider: .template)   [cannot fail]
```

**7.4 All-offline → stale cache + status rows**

```
FF fetch fails (URLError) ──► econ cache age 2d ≤ 7d → keep serving
                              econStatus = .stale(lastFetch) → "Econ events last updated Mon 07:12"
Finnhub + RSS fail ─────────► headlines cache (≤3d) → headlinesStatus = .stale(…)
FM .deviceNotEligible · Exa request throws URLError ──► chain falls through
TemplateSummarizer(from cached econ + engine sessionFacts) → Briefing(provider: .template)
Schedule pipeline unaffected (fully offline) · zero modals (02 §8) · retry next refresh signal
```

---

## 8. Testing (Swift Testing, in `OffsetKit/Tests/OffsetKitTests/`)

### 8.1 Decode fixtures (`Fixtures/` directory)

`ff_thisweek_trimmed.json` — real-shaped per the verified schema ([NEWS] §3; GBP Claimant Count + CAD CPI are from the verified live feed):

```json
[
  { "title": "CPI m/m", "country": "CAD", "date": "2026-07-20T08:30:00-04:00",
    "impact": "High", "forecast": "-0.2%", "previous": "1.0%" },
  { "title": "Claimant Count Change", "country": "GBP", "date": "2026-07-21T02:00:00-04:00",
    "impact": "High", "forecast": "", "previous": "25.9K" },
  { "title": "Bank Holiday", "country": "JPY", "date": "2026-07-23T00:00:00-04:00",
    "impact": "Holiday", "forecast": "", "previous": "" }
]
```

`finnhub_news_trimmed.json` — **UNVERIFIED shape** (§3.2; regenerate from a real response before freezing the decoder; test doc-comment must carry the marker):

```json
[
  { "category": "forex", "datetime": 1784980800, "headline": "Dollar steadies ahead of CPI data",
    "id": 7418529, "image": "", "related": "", "source": "MarketWatch",
    "summary": "…", "url": "https://www.example.com/a" }
]
```

`exa_answer_briefing.json` — response shape per [NEWS] §1 (`answer` + `citations` + `costDollars`; structured `answer` because `outputSchema` was sent):

```json
{
  "answer": { "headline": "CPI day: one US release dominates.",
              "bullets": ["08:30 your time — USD CPI m/m, forecast 0.2% vs 0.3% prior.",
                          "London–NY overlap 08:00–12:00 your time.",
                          "NYSE regular session 09:30–16:00 your time."],
              "watchouts": ["08:30 your time — USD CPI m/m (High)"] },
  "citations": [ { "id": "https://example.com/cpi", "url": "https://example.com/cpi",
                   "title": "CPI preview", "author": "…",
                   "publishedDate": "2026-07-21T09:12:00.000Z", "text": "…" } ],
  "costDollars": { "total": 0.005 }
}
```

(Plus `exa_search_news.json` trimmed from the [NEWS] §1 `/search` response example — `requestId`, `resolvedSearchType`, `results[]` with `title/url/id/publishedDate/summary`, `costDollars`.)

### 8.2 Test list

| Suite | Cases |
|---|---|
| `FFDecodeTests` | DTO decodes all 6 fields; explicit-offset date parses to the correct instant (assert against a UTC-converted expectation, not device zone); `""` → nil forecast/previous; impact mapping incl. `"Holiday"` and unknown→`.low`; **id determinism** (same event → same id across fetches; differing currency/date/title → different id); alert filter excludes `.holiday` |
| `FinnhubDecodeTests` | Tolerant decode (missing `id` → url-hash id; missing optional fields OK; invalid `url` row dropped); `HeadlineTagger` table cases (multi-tag, no-tag, word-boundary "audit" must NOT match AUD) |
| `ExaDecodeTests` | `/answer` structured-object decode; string-containing-JSON variant decode (UNVERIFIED-shape guard); `costDollars.total` extraction; `/search` results decode |
| `SummarizerChainTests` | Mocked `Summarizer` impls (protocol is spine): FM available → `.onDevice`; FM unavailable + Exa available → `.exa`; both unavailable → `.template`; **selected summarizer throws → chain falls to next**; validation failure (2 bullets) treated as throw; template output for empty `econEvents`/`headlines` still yields ≥3 bullets and valid headline (never-fails fuzz over empty/degenerate inputs) |
| `ExaCapTests` | Counter increments per call; call #41 throws `ExaBudgetExceededError` at default cap 40; `countDay` rollover resets to 0; cap edit respected; `monthSpendUSD` accumulates |
| `TemplateSummarizerTests` | Headline priority rules (i)/(ii)/(iii) each pinned with fixtures; worked example string matches §5.5 exactly; watchouts time-sorted, ≤3; beginner vs pro variant differences explicit |

FoundationModels generation itself is not unit-testable off-device (and returns `.deviceNotEligible` on the dev device) — `FoundationModelsSummarizer` is covered by the availability-driven chain tests via a protocol seam around `SystemLanguageModel.default.availability`, plus a manual on-device QA item once eligible hardware exists.

---

*Cross-references: 02 (CacheStore models, RefreshCoordinator, secrets, SourceStatus philosophy), 03 (engine + `events(…, econEvents:)`), 04 (econ alert rules, reserved notification slots), 07 (NewsFeedView/BriefingCardView UI), 08 (widget reads CachedBriefing read-only). Research: [NEWS] §1–5; [MKT] HALF2 §1–2.*
