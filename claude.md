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

- **Phase 0 - Scaffold.** Done. The Python scaffold is gone and `SurfCore/` is the package the build commands below assume. The Xcode app target is still outstanding and needs a Mac (see Phase 8).
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

Open-Meteo Marine (forecast spine), Stormglass (model confidence, ~10 requests/day) and
ISRAMAR (buoy ground truth, undocumented and partially dead). Endpoint shapes, auth, rate
limits and their verified failure modes live in the `surf-data-sources` skill - read it
before touching any ingest client, decoder or cache policy.

Two rules are load-bearing enough to repeat here: a 200 from ISRAMAR is **not** evidence of
fresh data, and the Gulf of Eilat 400s on the marine endpoint rather than returning an empty
series.

---

# Domain Rules
Extracted from `surf_research.md`. These are product requirements, not suggestions. All bands are table-driven and unit-tested.

## Wave height -> local slang
Displayed as metric value **and** term together, never one alone.

**This table is calibrated against GoSurf, not taken from `surf_research.md`.**
The research doc's four paired bands were measured against the local market
leader on 2026-08-27 at Bat Yam and found two to three bands too generous: it
named a 0.48 m sea `מותן עד חזה` where GoSurf called the same hour `ים גלי`.
Since GoSurf's swell column agrees with our model input and with the ISRAMAR
buoy to within 12 cm, the disagreement was the vocabulary, not the physics.
Evidence and the full side-by-side: `calibration/bat-yam-comparison.md`.

Seven single terms, not paired ranges, and they begin only where waves break:

| Adjusted height at spot | Hebrew | English | Audience |
|---|---|---|---|
| < 0.10 m | פלטה | Flat | Nobody |
| 0.10 m - break point | ים נוח / ים גלי | Calm sea / Wavy sea | Swimmers, not surfers |
| break point - 0.70 m | קרסול | Ankle | Beginners, SUP |
| 0.70-0.95 m | ברך | Knee | Beginners |
| 0.95-1.20 m | מותן | Waist | The golden range - core audience |
| 1.20-1.45 m | חזה | Chest | Core audience |
| 1.45-1.70 m | כתף | Shoulder | Experienced |
| 1.70-2.20 m | ראש | Head | Experienced only |
| > 2.20 m | פעמיים ראש | Double head | Professionals |

`ים נוח` vs `ים גלי` is texture, not height: glassy or flat reads `ים נוח`,
anything else reads `ים גלי`. It never affects which anatomical term is chosen.

### The break point
> גלים נשברים מ-50 ס״מ עם תלות במחזור הגל — GoSurf

Below it there is no wave to name a body part after, and naming one is the
overstatement that started this. Both halves of their sentence are load-bearing:
0.6 m of 4-second slop has nothing to catch, and a 0.4 m 12-second groundswell
stands up and peels. So the threshold is keyed to **energy**, not height:

```
surf exists when  0.5 * H^2 * T  >=  0.75 kW/m
```

anchored so 0.50 m at 6 s — this coast's measured median period — is exactly the
break point. That gives 0.61 m at 4 s, 0.43 m at 8 s, 0.35 m at 12 s.
Lives in `SurfBreaking`, and reuses the same `0.5 H^2 T` the score already uses.

**Never express a safety threshold as a `WaveBand` case.** This table is product
vocabulary and gets re-cut when the vocabulary is wrong; a re-cut must not be
able to move when somebody is warned. See `SkillLevel.largeSurfWarningThresholdMeters`.

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
| Structure-protected | Ashdod, Bat Yam (breakwaters) | 0.72 |
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
- Toolchain setup for Windows/WSL: `scripts/wsl-swift.sh`, or the `wsl-swift-setup` skill.

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
- App project: **generated, never committed.** `xcodegen generate` builds `Glassy.xcodeproj`
  from `project.yml`; a `.xcodeproj` can only be created on a Mac, so committing one would put
  a Mac back on the critical path for every change.
- App build: `xcodebuild -project Glassy.xcodeproj -scheme Glassy -destination 'generic/platform=iOS' build`.
  Needs a Mac, so in practice it runs on the `macos-latest` runner in `.github/workflows/ios.yml`,
  which is also what produces the installable unsigned `.ipa`.

**Concurrency settings.** `SurfCore` is a library and deliberately does *not* set `defaultIsolation(MainActor.self)` — libraries expose a nonisolated API and let the client decide what to offload. The **app target** is where "Approachable Concurrency" and "Default Actor Isolation = MainActor" belong.

# UI Architecture: Dual-Layer

Per the research, the split is a decision-making split, not a data-volume split. Layer 1 answers "do I get in the car?" in under three seconds: Match Score, wave height plus slang, sea state, wind arrow plus knots, weather icon, and any safety alert. Layer 2 answers "is this model right?": swell period, raw open-sea swell, live buoy readings, webcams, water and air temperature, tide, and model confidence.

# Backend & Data Handling
- **Wave Transformation Logic:** The app relies on custom algorithms to calculate wave transformation from deep water to localized shallow breaks. Do not substitute generic weather formulas.
- **State Management:** Keep API fetching logic decoupled from the UI. Use `@Observable` (Swift 6) and inject dependencies to allow for easy mocking of local wave conditions during testing.

# Code Style Guidelines
- **Framework:** SwiftUI strictly for the frontend. Do not use UIKit unless bridging a necessary component not available in SwiftUI.
- **Simplicity:** Prefer the smallest, most direct solution. Avoid over-engineering state wrappers or unnecessary protocol abstractions.
- **Localization:** Ensure all user-facing text is localized using String Catalogs, keeping the primary local demographic in mind. Hebrew is the primary locale - the slang terms above are the actual product vocabulary, not decoration. Design and test **RTL layout from the first view**, not as a retrofit. Wind arrows and directional glyphs must not mirror under RTL.

# UI/UX

Per-screen layouts (Navigation, Home, Week, Detail, Spots, Settings) live in the `surf-ui` skill. The cross-cutting rules below are always in force.

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
