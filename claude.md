# Project Overview
Highly localized surfing forecast iOS application optimized specifically for Mediterranean conditions and the local surfing community.

**The core product thesis:** a global model number is not a forecast. Open-sea model output is computed 10-25 km offshore in >50 m water at ~9 km resolution; the surfer stands in 1.5 m of water behind a breakwater. Every number this app displays must be transformed to a specific spot and translated into the language surfers actually speak. Shipping a raw model value as "the wave height at the beach" is the single failure mode that kills trust in this product.

---

# Workflow

## Operating Loop
Follow this loop for every feature. It exists because this domain punishes plausible-looking output.

1. **Ground in the research.** `surf_research.md` is the product spec for domain behaviour. Before implementing anything that produces a user-facing number or word, find the rule in that doc. Do not invent thresholds.
2. **Verify the data source before coding against it.** Curl the endpoint, inspect the real payload, check the timestamp. Two of the sources here are undocumented and one of them is currently dead (see Data Sources). Never write a decoder against an assumed schema.
3. **Transform, then translate.** Raw ingest -> spot transformation -> slang/verbal layer. These are three separate, individually testable stages. Never let a raw model value reach a view.
4. **Test the physics with fixtures, not the network.** Every transformation coefficient, slang band, and score weight gets a unit test with a hardcoded input. Network calls are mocked at the protocol boundary.
5. **Fail loud and honest.** Stale, missing, or divergent data is displayed as stale/missing/uncertain. Never interpolate a gap and present it as an observation. Never show a buoy reading without its age.
6. **Sanity-check against reality.** Before calling a forecast feature done, compare its output for a real spot against a live buoy reading and a webcam. If they disagree, the model is wrong until proven otherwise.

## Build Phases
Work strictly in this order. Each phase is independently testable and must be green before the next starts.

- **Phase 0 - Scaffold.** Replace the current Python scaffold (`pyproject.toml`, `src/claudedemo/`) with the Xcode project the build commands below already assume. Nothing else in this repo is load-bearing.
- **Phase 1 - Ingest.** Three API clients behind one `ForecastSource` protocol. `async/await`, `Codable`, no UI. Each returns a normalized `RawMarineSample` in SI units. Deliverable: a test that decodes a checked-in fixture payload from each provider.
- **Phase 2 - Spot model.** The `Spot` catalog with per-spot geometry: coordinates, exposure window, transformation coefficient, break type, basin (`mediterranean` | `gulfOfEilat`). Data-driven from a bundled JSON, not hardcoded in Swift.
- **Phase 3 - Transformation engine.** Pure functions, zero dependencies: open-sea sample + spot -> `SpotConditions`. This is where shoaling, refraction, the 0.78 breaking ratio, the coefficient, and the Eilat synthetic formula live. 100% unit-tested. This is the highest-value code in the app.
- **Phase 4 - Translation layer.** `SpotConditions` -> slang bands, sea-state texture, colour tokens. Pure, table-driven, localized.
- **Phase 5 - Match Score.** Per-sport weighted scoring. Pure function, table-driven weights, unit-tested against hand-computed cases.
- **Phase 6 - Safety.** The offshore-drift alert and its threshold. Non-dismissable, evaluated before any score is shown. Never gated behind a paywall or a settings toggle.
- **Phase 7 - Verification layer.** Live buoy readings and webcams surfaced next to the forecast, with staleness handling.
- **Phase 8 - UI.** Build to the UI/UX section below, in order: Home, then Week, then Detail, then Spots, then Settings. Home and Week are the product; the other three are support.

## Data Pipeline
Each arrow is a testable boundary.

```
3 providers -> normalize (SI) -> reconcile/confidence -> spot transform -> slang translate -> match score -> view
                                        |                                        |
                                  buoy ground truth                       safety override
```

- **Normalize:** everything to SI internally - metres, seconds, degrees true, m/s. Knots are a *presentation* unit only. Convert at the view boundary. 1 kt = 1.852 km/h (the research doc's 1.8 is a field approximation; do not use it in code).
- **Reconcile:** compare the providers per-parameter. Agreement -> high confidence; divergence -> surface the uncertainty rather than silently picking a winner.
- **Cache:** models refresh on fixed cycles (00Z/12Z), buoys hourly. Cache to the source's actual cadence, never per-view. See the rate-limit note under Stormglass.

---

# Data Sources: The Three APIs

| # | Source | Role | Auth | Status |
|---|--------|------|------|--------|
| 1 | Open-Meteo Marine + Forecast | Primary forecast spine | None (non-commercial) | Verified |
| 2 | Stormglass.io | Multi-model cross-check / confidence | API key | Verified via docs |
| 3 | ISRAMAR (IOLR) | Real-time buoy ground truth | None | Verified live, partially degraded |

## 1. Open-Meteo Marine - the forecast spine
- `https://marine-api.open-meteo.com/v1/marine` plus `https://api.open-meteo.com/v1/forecast` for wind/air/weather.
- Chosen because it exposes **swell components separately from wind waves** (primary/secondary/tertiary swell, wind-wave height/period/direction) - mandatory for this app, since a 0.7 m wind chop and a 0.7 m groundswell are completely different products for the user.
- Also supplies `sea_surface_temperature` (wetsuit decisions) and `sea_level_height_msl` (tide).
- **Model: use `best_match`.** Measured against the Israeli coast on a 7-day request: `ewam` (DWD, 5 km) is the highest-resolution model covering the basin but returns **77 nulls out of 168 hours** — it is short-range and expires after ~3.8 days, so it cannot fill the Week screen on its own. `gwam` (25 km) and `ecmwf_wam025` return the full 168 but much coarser. `best_match` blends the best available per step: EWAM resolution near-term, full coverage to day 7. Note `meteofrance_wam` is **not a valid model id** — the API rejects it.
- **The Gulf of Eilat is outside the marine model domain entirely.** The marine endpoint answers **HTTP 400** for those coordinates, not an empty series, so Eilat spots must skip that endpoint and call only the atmospheric one, synthesising waves from wind. Fetching both fails the whole request.
- No key for non-commercial use. A key is required if this ships commercially - flag before any App Store submission.

## 2. Stormglass.io - the confidence engine
- Aggregates ECMWF, NOAA, Meteo France, DWD/ICON, UK Met Office, SMHI, Met.no in a single response, per-parameter, per-source.
- This is what powers the **Model Confidence** feature from the research: the spread between sources *is* the confidence metric. Do not fabricate a confidence percentage from a single model.
- Also the tide/sea-level source if Open-Meteo's proves insufficient.
- **Rate limit is the binding constraint: the free tier is ~10 requests/day.** This absolutely cannot be called from the device per-view. It must be fetched server-side (or by a scheduled job) for a fixed set of spots and cached. Design for this from day one - retrofitting it later means rewriting the networking layer.
- Store the key outside source control. Never commit it.

## 3. ISRAMAR / IOLR - ground truth
Israel's national oceanographic institute. **No official API, no documentation, no SLA, no stability guarantee.** It is scraped JSON. Treat accordingly: wrap every call in a timeout, tolerate schema drift, and never let a failure here degrade the forecast path.

Verified endpoint shape:

```
https://isramar.ocean.org.il/isramar2009/station/data/<STATION>_Hs_Per.json

{"datetime": "YYYY-MM-DD HH:MM UTC",
 "parameters": [{"name": "Significant wave height", "units": "m", "values": [0.66]},
                {"name": "Peak wave period",       "units": "s", "values": [6.2]},
                {"name": "Maximal wave height",    "units": "m", "values": [0.8382]}]}
```

Live status as of 2026-08-25:
- **Hadera (`Hadera_Hs_Per.json`) - LIVE**, updating hourly. Verified: `Hs 0.66 m / Tp 6.2 s @ 2026-08-25 16:00 UTC`.
- **Shikmona / Haifa (`ShikBuoy_HS_Per.json`) - STALE.** Returns HTTP 200 with a payload frozen at `2026-01-09 21:00 UTC` (`Hs 4.09 m / Tp 11.1 s`). The buoy has been offline for months but the endpoint still serves the last reading with a 200.
- Water temperature and CTD data are published as **PNG images, not machine-readable data**. Do not plan on ISRAMAR for water temp - use Open-Meteo `sea_surface_temperature`.

**Therefore: a mandatory staleness gate.** A 200 response from this source is not evidence of fresh data. Parse `datetime`, compute age, and refuse to display any reading older than ~3 hours as current. A months-old 4.09 m storm reading rendered as "live now" during a flat August afternoon is the worst possible bug this app could ship. Note that the 4.09 m / 11.1 s figure quoted in `surf_research.md` as an example of live verification is in fact this dead snapshot.

**Optional 4th source (not core):** the Israel Meteorological Service API (`ims.gov.il`, ~85 automatic stations) for measured coastal wind. Requires a token requested by email. Worth adding later for onshore/offshore wind verification; not a blocker.

---

# Domain Rules
Extracted from `surf_research.md`. These are product requirements, not suggestions. All bands are table-driven and unit-tested.

## Wave height -> local slang
Displayed as metric value **and** anatomical term together, never one alone.

| Adjusted height at spot | Hebrew | English | Audience |
|---|---|---|---|
| 0.20-0.40 m | קרסול עד ברך | Ankle to knee | Beginners, SUP |
| 0.50-0.90 m | מותן עד חזה | Waist to chest | The golden range - core audience |
| 1.00-1.50 m | כתף עד ראש | Shoulder to head | Experienced only |
| >1.50 m (storm) | פעמיים ראש ומעלה | Double overhead+ | Professionals |

> Open spec question: the research jumps from "up to 1.5 m" straight to "double overhead", leaving 1.5-2.5 m unnamed. Working default is an intermediate `overhead / ראש` band at 1.5-2.2 m with `double overhead` above it. Confirm with a local surfer before shipping.

## Sea state -> texture
| State | Hebrew | Condition | Colour |
|---|---|---|---|
| Flat | פלטה | 0-0.1 m, Douglas 0-1 | Neutral / grey |
| Glassy | גלאסי | Swell present + weak or offshore wind | Bright blue - the hero state |
| Choppy | צ'ופי | Brisk onshore wind, whitecaps | Orange / red |

## Wind
Coast runs roughly N-S with the sea to the west, so direction maps directly:
- **West = onshore.** Raises height, destroys shape, hard paddle-out. The default summer afternoon sea breeze.
- **North / South = side-shore.** Weak (especially northerly) leaves it clean; strong is ideal for kite and windsurf.
- **East = offshore.** Grooms the face, delays the break, produces glassy and barrelling conditions - *and is the danger case below.*

Strength bands: 0-10 kt weak (surf/SUP ideal) - 10-15 kt moderate (surf degrading, beginner windsurf ideal) - 15+ kt strong (kite/windsurf/wing foil territory, ideal 12-22 kt).

## Spot transformation coefficients
Multiplier applied to open-sea significant wave height. Data-driven per spot:

| Spot type | Example | Coefficient |
|---|---|---|
| Fully exposed | Palmachim, HaTzuk | 0.90 |
| Typical urban | Tel Aviv, Netanya | 0.85 |
| Structure-protected | Ashdod (breakwaters) | 0.72 |
| Ruin / pier-protected | Caesarea (Roman piers) | 0.70 |
| Enclosed bay | Haifa Bay | 0.50 |

Order of operations in Phase 3 — **sheltering first, breaking cap last**:

```
open-sea Hs → × exposureCoefficient → shoaling (Ks) → refraction (Kr) → cap at 0.78 × depth
```

Breakwaters and headlands block incident energy offshore, before the wave reaches the shoaling zone, so the coefficient belongs at the front. Applying it after the breaking cap would reduce an already-capped height a second time and under-predict every sheltered spot. Refraction returns *nothing* when the swell arrives from behind the shoreline — a south swell at a north-facing beach is shadowed, not merely smaller.

## Gulf of Eilat - special case
Global wave models do not resolve this basin and their output there is meaningless. Detect `basin == .gulfOfEilat` and switch to synthetic wind-chop values:

```
Hs = wind_kt * 0.04
Tp = 3 + (0.15 * wind_kt)
```

Wind waves only, no swell component. Label it in the UI as locally derived, not modelled.

## Safety - the offshore drift alert
**Offshore (easterly) wind above ~10 kt triggers a prominent, non-dismissable warning.** The hazard is an optical illusion: from the shore the sea looks flat and inviting, but past the wind shadow of the buildings and cliffs the wind hits hard and pushes paddlers out to sea faster than they can paddle back. Warn explicitly against beginners, SUP, and kayaks entering the water, and name the drift risk directly.

This alert is evaluated **before** the Match Score and outranks it in the layout. A glassy offshore morning will score highly for experienced surfers and be genuinely life-threatening for beginners simultaneously - both facts must appear together.

## Match Score (0-100), per sport
Sport profile is user-selected: surfing, kitesurfing, wing foil, SUP.

**Surfing:** adjusted shore height 0.6-1.5 m scores full on the height term; period <5 s (wind slop) drops the total sharply; 7-9 s raises it; light easterly adds a bonus; westerly >12 kt subtracts heavily for destroyed shape.

**Kitesurfing / wing foil:** the logic inverts - wind carries the dominant weight. 100 requires stable side- or south-westerly wind at 15-22 kt.

**SUP:** rewards flat and calm, and must be suppressed to near-zero by the offshore-wind hazard regardless of how pleasant the surface looks.

---

# Build & Run Commands

The backend lives in `SurfCore/`, a SwiftPM package the app target depends on. Keeping it a package rather than an app target is what lets the whole engine be built and tested without an iOS simulator — and, in practice, on a non-Mac machine.

- Backend build: `swift build --package-path SurfCore`
- Backend test: `swift test --package-path SurfCore`

## Building the backend on Windows (no Mac required)

`SurfCore` has no Apple-framework dependencies, so it builds and tests on Linux. Verified working: **Swift 6.3.3 on WSL Ubuntu 24.04**, all 105 tests passing.

The toolchain is installed **entirely in userspace — no sudo, no system packages**:

```bash
# 1. Toolchain (~1 GB) into ~/swift
curl -fL -o swift.tar.gz \
  https://download.swift.org/swift-6.3.3-release/ubuntu2404/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE-ubuntu24.04.tar.gz
mkdir -p ~/swift && tar xzf swift.tar.gz -C ~/swift --strip-components=1

# 2. The one missing runtime lib, unpacked without root
mkdir -p ~/localdeps/debs && cd ~/localdeps/debs
apt-get download libncurses6 libtinfo6      # apt-get download needs no sudo
for d in *.deb; do dpkg -x "$d" ~/localdeps; done

# 3. Environment
export PATH="$HOME/swift/usr/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/localdeps/usr/lib/x86_64-linux-gnu:$HOME/localdeps/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"

# 4. Build with the scratch path on ext4, NOT on the /mnt/c 9p mount
swift test --package-path /mnt/c/.../SurfCore --scratch-path ~/build/surfcore
```

**WSL2's network stack drops roughly a quarter of outbound HTTPS requests here.** They hang
until the timeout rather than failing fast, on IPv4 and IPv6 alike, against every host tried.
The same requests from Windows are clean 10/10, so it is the WSL NAT layer, not the provider
and not the client. Two consequences:

- **A failing smoke run means nothing until it fails twice.** Sampling one run per spot produced
  a convincing, entirely false "this spot is broken" diagnosis. Re-run before believing it.
- It is why `RetryingTransport` exists and is on by default. Retries are correct for a phone on
  cellular regardless, but this environment is what surfaced the need.

The `--scratch-path` matters: leaving build artifacts on `/mnt/c` is the difference between an 8-second build and an unusable one. Undo everything with `rm -rf ~/swift ~/localdeps ~/build`.

`scripts/wsl-swift.sh` wraps all of the above — run it from WSL:

```bash
./scripts/wsl-swift.sh test              # hermetic unit suite
./scripts/wsl-swift.sh run smoke hadera  # LIVE smoke test against real APIs
```

## Two kinds of test, and why both are needed

- **`swift test` — hermetic.** Fixtures only, no network, no clock. Proves the logic is self-consistent. It cannot prove a decoder matches what a provider actually sends.
- **`swift run smoke [spot] [sport] [skill]` — live.** Hits the real Open-Meteo and ISRAMAR endpoints, runs the full pipeline, and prints the model's answer beside a real buoy measurement. This is the operating loop's step 6 made runnable.

**The unit suite passed 83/83 while three real bugs were live**, all found only by the smoke test: Eilat 400ing on the marine endpoint, `bestWindowToday` searching the whole week and returning a window that ran backwards across midnight, and `ewam` silently nulling 77 of 168 hours. Green unit tests are necessary and not sufficient — run the smoke test before believing any ingest change.

Every bug it finds should leave a hermetic regression test behind; all three above now have one.

**What still needs a Mac:** Phase 8 (SwiftUI views), the `.xcodeproj`, the simulator, and App Store submission. The iOS SDK is closed-source and Mac-only. Options when that time comes: a GitHub Actions `macos-latest` runner, a cloud Mac, or borrowed hardware. Keeping every non-UI decision inside `SurfCore` is what makes that a small, late problem instead of a blocking one.

**Linux portability rules for `SurfCore`** — these are load-bearing, do not regress them:
- `URLSession` lives in `FoundationNetworking` off-Apple; it is already behind `#if canImport(FoundationNetworking)`.
- No `static let` of a `DateFormatter`/`ISO8601DateFormatter` — they are non-Sendable classes and Swift 6 rejects them as globals. Build one per parse operation and reuse it within that call (`DateParsing.makeUTCFormatter`).
- `Bundle.module` cannot appear in a **default argument** of a public function (it is internal). Take `Bundle? = nil` and resolve it in the body.
- Never import UIKit or SwiftUI into `SurfCore`. The moment it does, the whole off-Mac workflow dies.
- App build: `xcodebuild -project SurfForecast.xcodeproj -scheme SurfForecast -destination 'platform=iOS Simulator,name=iPhone 15' build`
- App test: `xcodebuild -project SurfForecast.xcodeproj -scheme SurfForecast -destination 'platform=iOS Simulator,name=iPhone 15' test`
- Format: `swiftformat .`

**Concurrency settings.** `SurfCore` is a library and deliberately does *not* set `defaultIsolation(MainActor.self)` — libraries expose a nonisolated API and let the client decide what to offload. The **app target** is where "Approachable Concurrency" and "Default Actor Isolation = MainActor" belong.

# UI Architecture: Dual-Layer
Always adhere to the dual-layer interface paradigm for all SwiftUI views:
- **Layer 1 (Glanceable):** Top-level views must prioritize immediate readability. Show only critical data (current wave height, primary swell direction, wind speed). Use clear, high-contrast typography compliant with Apple's HIG.
- **Layer 2 (Analytical):** Detail views are for deep technical metrics. Display complex oceanographic data, wave energy metrics, and detailed time-series charts here.

Per the research, the split is a decision-making split, not a data-volume split. Layer 1 answers "do I get in the car?" in under three seconds: Match Score, wave height plus slang, sea state, wind arrow plus knots, weather icon, and any safety alert. Layer 2 answers "is this model right?": swell period, raw open-sea swell, live buoy readings, webcams, water and air temperature, tide, and model confidence.

# Backend & Data Handling
- **Wave Transformation Logic:** The app relies on custom algorithms to calculate wave transformation from deep water to localized shallow breaks. Do not substitute generic weather formulas.
- **API Integration:** Data is ingested from local oceanographic data APIs. Use modern Swift `async/await` concurrency for all network calls.
- **State Management:** Keep API fetching logic decoupled from the UI. Use `@Observable` (Swift 6) and inject dependencies to allow for easy mocking of local wave conditions during testing.

# Code Style Guidelines
- **Language:** Swift 6.
- **Framework:** SwiftUI strictly for the frontend. Do not use UIKit unless bridging a necessary component not available in SwiftUI.
- **Simplicity:** Prefer the smallest, most direct solution. Avoid over-engineering state wrappers or unnecessary protocol abstractions.
- **Localization:** Ensure all user-facing text is localized using String Catalogs, keeping the primary local demographic in mind. Hebrew is the primary locale - the slang terms above are the actual product vocabulary, not decoration. Design and test **RTL layout from the first view**, not as a retrofit. Wind arrows and directional glyphs must not mirror under RTL.

# UI/UX

## OPEN — simplify what the screen says

The first screen study (`design/screen-study.html`) is correct but reads as too dense. Before Phase 8 builds anything, cut the on-screen data down to what a person can absorb at a glance. The rule: **the glance layer carries the fewest facts that answer "do I go?"** — everything else moves to Layer 2 or disappears.

Engine diagnostics are leaking into the interface. These are all things the app should *know* and not *say*:

| Currently shown | Verdict |
|---|---|
| `חשיפה 0.85 · עומק שבירה 2.0 מ׳` | Cut. Transformation inputs, not conditions. |
| `מודל בים הפתוח 0.54 מ׳ · פער ‎−0.15 מ׳` | Layer 2 only. A delta is analyst language. |
| `×0.50 מהים הפתוח` | Cut from the hero. Say "מפרץ מוגן" in words if anything. |
| Wind bearing in degrees (`259°`) | Cut. The arrow and the word carry it; nobody reads bearings. |
| Period as a pill beside sea state | Layer 2. It shapes the score; it is not a glance fact. |

What survives on Home: the score, height **and** its slang together, the sea-state word, wind strength **and** its direction word, the best window, and any safety banner. That is the whole decision.

Same discipline on the Week rows — a row should read in about a second. Score, height with slang, and the window. Drop the second numeral wherever a word already carries the meaning; prefer one clear number over two precise ones. Precision the user cannot act on is clutter, and clutter is what makes people stop trusting a forecast.

## Navigation
Three tabs. Settings sits behind a toolbar button on Home, not a fourth tab.

| Tab | Hebrew | The question it answers | Layer |
|---|---|---|---|
| **Home** | בית | "Do I get in the car, right now?" | 1 hero + today in full |
| **Week** | שבוע | "Which day this week?" | 1 per row, 2 on tap |
| **Spots** | חופים | "Where should I go?" | 1 per row, 2 on tap |

The sport profile (surf / kite / wing foil / SUP) is global and set once. It changes every Match Score in the app simultaneously. Expose it as a segmented control in the Home toolbar, not buried in Settings - switching sport is a normal daily action for anyone who does two of them, not a preference.

## Home - favourite beach, today in full
One screen, top to bottom. Everything above the fold must survive the three-second test: a user half-awake at 06:00 gets a yes or no without scrolling or tapping.

1. **Safety banner** (conditional). Full-width, above everything including the spot name. See Safety presentation below.
2. **Spot header.** Favourite beach name, large. Tap to switch between favourites; a chevron opens the Spots tab. Users with one favourite never see a picker.
3. **Hero card - Layer 1, the whole decision.**
   - **Match Score** 0-100, the largest element on the screen, coloured by band, with the sport it refers to named beneath it.
   - **Wave height, always paired:** metric and slang on one line - `0.8 מ׳ · מותן עד חזה`. Never the number alone, never the slang alone.
   - **Sea state chip:** גלאסי / צ׳ופי / פלטה, colour-coded, word always present.
   - **Wind:** an arrow drawn relative to the coastline, the value in knots, and the onshore / offshore / side word. The word matters more than the arrow - "offshore" is the thing that changes behaviour.
   - **Weather icon:** sun / cloud / rain. Context only, smallest element in the card.
4. **Best window today.** One sentence derived from the hourly score curve: "the best window today is 06:00-09:00". This falls straight out of Phase 5 and is the highest-value line on the screen - it turns a forecast into a plan. If no hour clears a usable threshold, say so plainly rather than naming the least-bad window.
5. **Hourly timeline.** Horizontally scrolling, the full day. Per hour: score, height, wind arrow + knots. Current hour pinned and anchored on open. The hero answers yes/no; this answers when.
6. **Verification strip.** Live buoy reading with its age in plain words ("measured 40 minutes ago") and a webcam thumbnail. Per the research the community distrusts models by default, so this strip is where the app earns credibility. If the nearest buoy is stale it says the buoy is offline - it does not silently disappear, and it never shows the old number.
7. **Expand to Layer 2.** One clear affordance to the full analytical detail for today.

## Week - seven days, one row each
Each row is the Layer 1 preview set condensed to a single line, scannable in one pass down the screen.

Per row: day name and date · Match Score · height + short slang · wind arrow + knots · sea state chip · safety glyph if that day triggers an alert.

**Do not average the day.** A day that is glassy at dawn and blown out by noon averages to a meaningless middle number that is wrong at every hour it claims to describe. Each row shows the day's **best window** - its peak score and the hours that produce it. The row is a promise about a time of day, not about a calendar day.

Tapping a row opens Day Detail (Layer 2) for that date. Keep the list itself free of technical metrics - swell period and model confidence belong behind the tap, not in the row.

Show the score trend across the seven days as a sparkline or a bar per row, so "Thursday is the day" is visible without reading a single number.

## Day / Spot Detail - Layer 2
The analytical screen, reached from the Home expand affordance or any Week or Spots row. This is where a sceptical surfer checks the app's work.

- Hourly chart: score, height, and wind plotted together across the day.
- **Swell period**, prominently - the research calls it the true measure of wave quality, and it is the metric that separates a real forecast from a weather widget.
- **Raw open-sea swell alongside the transformed spot value**, both labelled. Showing both is the honest move: it proves the app did the transformation rather than reprinting a model, and lets veterans apply their own judgement.
- **Model confidence** from the Stormglass source spread, as a percentage with a plain-language reading. Divergence is shown as uncertainty, never smoothed into a single confident number.
- Live buoy readings with timestamps, and webcams.
- Water and air temperature, with a wetsuit recommendation derived from water temp.
- Tide / sea level - present, but low in the hierarchy, matching its low relevance in the Mediterranean.

## Spots - where should I go
A list of Israeli spots, each showing name, current Match Score, height + slang, and wind. Sort by score by default, offer distance as an alternative. Star to favourite; the first favourite becomes the Home default.

This tab answers a different question from Home. On a marginal day the useful answer is often "not your usual beach, but Palmachim is working" - the transformation coefficients are exactly what make that comparison meaningful, so surface it.

## Settings
Sport profile · **skill level** (beginner / intermediate / advanced) · units · language · favourite management · webcam and buoy toggles.

Skill level is not cosmetic. It modulates both the Match Score and the aggressiveness of safety alerting: the same glassy offshore morning is a career-best session for an advanced surfer and a drowning risk for a beginner on a SUP. Default to beginner and let users opt upward - the failure mode of over-warning is annoyance, the failure mode of under-warning is a rescue.

## Cross-cutting rules

### Safety presentation
The offshore-drift alert is **not a toast, not a badge, and not dismissable.** It renders as a full-width banner at the top of Home and as a glyph on every affected Week row, and it sits above the Match Score in the layout - always. It states the hazard in plain Hebrew, names who it applies to (beginners, SUP, kayak), and explains the illusion: the sea looks calm from the sand because the wind is behind you, and it will push you out faster than you can paddle back.

Never let a high score visually overwhelm an active safety banner. When both are on screen, the banner wins the hierarchy. Both facts are simultaneously true and both must land.

### Data honesty states
Every screen needs four states designed, not three: **loaded · loading · failed · stale.** Stale is the one apps forget and the one this domain punishes.

- Stale data is labelled with its age in words, never silently rendered as current.
- A failed source degrades its own section only - a dead buoy must never blank the forecast.
- Never show a spinner where a last-known value with a timestamp would serve the user better.
- Eilat's synthetic values carry a visible "locally derived, not modelled" label wherever they appear.

### Colour and state
Colour reinforces, it never carries. Every colour-coded state - sea state chip, score band, safety banner - also carries its word or glyph, so a red-green colourblind user loses nothing. Verify each screen in greyscale before calling it done.

The glassy blue is the app's hero moment. Let it be genuinely striking when it appears; it is rare, and users should feel it land.

### Hebrew, RTL, typography
Hebrew is the primary locale and the slang is the product's real vocabulary - `מותן עד חזה` is not a translation of "waist to chest", it is the term, and the English is the secondary rendering.

- Build and test RTL from the first view. Every layout mirrors by default.
- **Wind arrows, compass roses, and swell-direction glyphs must not mirror.** They encode real-world geography. Pin them with `.flipsForRightToLeftLayoutDirection(false)` and cover it with a test.
- Numbers, units, and times stay LTR inside RTL runs. Verify `0.8 מ׳` and `06:00-09:00` render unreversed.
- Use the Hebrew geresh `׳` in `מ׳`, not an ASCII apostrophe.

### Accessibility
- Full Dynamic Type including the accessibility sizes. The hero card reflows rather than truncates - test at AX5 before any screen ships.
- VoiceOver reads meaning, not layout: one coherent label per card - "ציון 82, מותן עד חזה, 0.8 מטר, רוח מזרחית 8 קשר" - not six fragments.
- The safety banner is an accessibility priority element and is announced first on its screen.
- Every tappable row meets the 44pt minimum.

### Motion
Restrained. This is a decision tool used at dawn, not an entertainment surface. Animate state transitions and the score arriving; never animate the wave data itself. Respect Reduce Motion everywhere.
