# Glassy

A highly localized surf forecast for the Israeli Mediterranean coast and the Gulf of Eilat.

**The thesis:** a global model number is not a forecast. Open-sea model output is computed
10–25 km offshore in >50 m of water at ~9 km resolution; the surfer is standing in 1.5 m of
water behind a breakwater. Every number this app shows is transformed to a specific spot and
translated into the language surfers actually use — `0.8 מ׳ · ברך`, not `Hs 0.94`.

The vocabulary is calibrated against the local market leader, not invented: the research
doc's paired bands ran two to three bands generous, and `calibration/bat-yam-comparison.md`
is the side-by-side that settled it.

## Layout

```
SurfCore/          SwiftPM package — the entire engine. No UIKit, no SwiftUI, builds on Linux.
  Sources/SurfCore/
    Sources/       Four API clients behind one ForecastSource protocol, plus the
                   retry and cache transport decorators.
    Models/        Spot catalog, raw samples, transformed conditions, DataState.
    Rules/         Table-driven bands: slang, sea state, wind, score, wetsuit.
    Engine/        Wave transformation, match score, safety, longshore current,
                   best-window search.
    Translation/   Conditions -> Hebrew words, colour tokens, VoiceOver labels.
    Repository/    Actor that fetches, assembles, caches.
    Validation/    The calibration ledgers — model output checked against measurement.
  Sources/smoke/   Live end-to-end run against the real endpoints.
  Tests/           Hermetic, fixture-driven. 278 tests in 46 suites.
App/               The SwiftUI app. Three tabs; every string comes from Translation.
calibration/       Append-only JSON Lines: what the model said vs what was measured.
project.yml        XcodeGen spec. Glassy.xcodeproj is GENERATED, never committed.
.github/workflows/ macOS runner: tests, generates the project, builds an unsigned .ipa.
docs/INSTALL.md    Getting the build onto an iPhone, free, without a Mac.
design/            Screen studies.
scripts/           WSL Swift toolchain wrapper; app-icon generator.
claude.md          The build spec: domain rules, phases, UI architecture.
surf_research.md   The domain research the rules are extracted from.
.claude/skills/    Lazily-loaded reference: screen layouts, data sources, domain tables.
```

The engine is a package rather than an app target on purpose: it means the whole forecast
pipeline can be built and tested without an iOS simulator, and in practice without a Mac.
That is what keeps the Mac a small, late problem instead of a blocking one.

## The four data sources

| # | Source | Role | Auth |
|---|---|---|---|
| 1 | Open-Meteo Marine + Forecast | The forecast spine — waves, wind, SST, tide | none |
| 2 | Stormglass | Model confidence (not yet wired — see Open) | key |
| 3 | ISRAMAR / IOLR | Buoy ground truth — measured wave height and period | none |
| 4 | IMS (`ims.gov.il`) | Measured coastal wind — five coastal masts | token |

Only source 1 produces the forecast. **3 and 4 exist to catch it being wrong**, and both are
displayed beside the model with their age and distance rather than blended into it. Each
degrades its own section only: a dead buoy never blanks a forecast.

Three failure modes are load-bearing enough to name here, because all three return data that
looks fine:

- **A 200 from ISRAMAR is not evidence of fresh data.** The Shikmona buoy has been dead for
  months and still serves its last reading — a 4.09 m storm — with a 200. Hence the
  mandatory staleness gate: 3 h for waves, 1 h for wind, which is far more perishable.
- **The Gulf of Eilat 400s on the marine endpoint** rather than returning an empty series,
  so those spots skip it and synthesise waves from wind, labelled as locally derived.
- **An IMS value can be present, numeric and flagged invalid.** Elat's anemometer serves
  `0.0` with `status:2, valid:false` — a decoder that reads `value` without the flags
  publishes dead calm in the one basin where wind *is* the wave model.

Endpoint shapes, cache policies and the rest live in the `surf-data-sources` skill.

## Build and test

On macOS or Linux:

```bash
swift build --package-path SurfCore
swift test  --package-path SurfCore
```

On Windows the toolchain runs under WSL and installs entirely in userspace, no sudo. Run the
`wsl-swift-setup` skill once, then **from inside WSL** (the wrapper resolves `$HOME` to the
Linux home, so calling it from Git Bash will not find the toolchain):

```bash
./scripts/wsl-swift.sh test              # hermetic unit suite
./scripts/wsl-swift.sh run smoke hadera  # LIVE, hits the real APIs
```

### Two kinds of test, and why both

- **`swift test` — hermetic.** Fixtures only, no network, no clock. Proves the logic is
  self-consistent. It cannot prove a decoder matches what a provider actually sends.
- **`swift run smoke [spot] [sport] [skill]` — live.** Runs the full pipeline against real
  Open-Meteo, ISRAMAR and IMS responses, and prints the model's answer beside a real buoy
  measurement and a real anemometer's wind.
  - `--at <yyyy-MM-ddTHH:mm>` (Israel time) reports on a past hour. A field report is always
    about a time that has already passed; without this, checking the engine against what
    someone saw in the water meant having been running it at that hour.
  - `--today` prints the day hour by hour, with the chop share column.
  - `--explain` shows the transformation's working.

The unit suite passed 83/83 while three real bugs were live, all found only by the smoke
test. Run it before believing any ingest change. Every bug it finds leaves a hermetic
regression test behind.

### The calibration ledgers

The smoke test appends every model-vs-measurement pair to `calibration/`: waves to
`observations.jsonl`, wind to `wind_observations.jsonl`. Two files rather than more columns
in one, because a new non-optional field on an existing record makes every old line fail to
decode and be dropped by the tolerant reader.

This is the only thing a coefficient may ever be tuned against, and the summary reports bias
beside RMSE deliberately: a model that reads 0.2 m high every time has a large bias and is
trivially correctable, while one that is wildly wrong in both directions can have near-zero
bias and be useless.

## API tokens

Nothing in this repo is a credential, and the repo is public — which is exactly why the IMS
token is not wired into the app. A token compiled into a CI-built `.ipa` sits in a
downloadable artifact. Backend tooling reads it from a gitignored `.env`:

```bash
cp .env.example .env      # then paste the token after IMS_API_TOKEN=
```

Request one by email from `ims@ims.gov.il`. Without it the smoke test reports the wind
section unavailable and everything else runs — a missing token degrades its own section,
like a dead station.

## The app

Five screens behind three tabs — Home and Week are the product, the rest is support.

| Screen | The question it answers | Layer |
|---|---|---|
| Home | "Do I get in the car, right now?" | 1 |
| Week | "Which day this week?" | 1 per row |
| Detail | "Is this model right?" | 2 |
| Spots | "Where should I go?" | 1 per row |
| Settings | Sport, skill, units, favourites | — |

Twelve spots from Haifa to Eilat. Hebrew is the primary locale and the layout is
right-to-left from the first view. Wind arrows and compass glyphs are pinned against
mirroring — they encode real-world geography, and a flipped arrow would report offshore as
onshore.

**The offshore-drift alert is not dismissable and outranks the score in the layout.** A
glassy offshore morning scores highly for an experienced surfer and is genuinely
life-threatening for a beginner at the same time; both facts must land together. Measured
IMS wind can *raise* that alert when the model missed it. It can never cancel one.

## Getting it on a phone

There is no Mac in this project and none is needed. `.github/workflows/ios.yml` runs on a
GitHub `macos-latest` runner — free with unlimited minutes on a public repository — and
produces an unsigned `.ipa` as a build artifact. It carries no signing secrets: the app is
signed on-device with a free Apple ID.

```bash
gh run download --name Glassy-unsigned-ipa --dir dist
```

Then follow `docs/INSTALL.md`. Requires iOS 17.0 or later.

That CI run is also the **only** type-check the `App/` target ever gets — the iOS SDK is
Mac-only, so nothing in `App/` compiles locally on this machine.

## Status

| Phase | | |
|---|---|---|
| 0 | Scaffold | done |
| 1 | Ingest — Open-Meteo, Stormglass, ISRAMAR, IMS | done |
| 2 | Spot catalog | done |
| 3 | Transformation engine | done |
| 4 | Translation / slang layer | done |
| 5 | Match Score | done |
| 6 | Safety — offshore drift alert | done |
| 7 | Verification — buoy and wind done, webcams open | partial |
| 8 | SwiftUI app — all five screens, building in CI | done |

Open, and deliberately so:

- **Measured wind only verifies; it does not forecast.** It is logged and displayed, and it
  can raise a safety alert, but it does not feed the sea state, the score or Eilat's
  synthetic waves. Revisit once the wind ledger holds 30+ paired observations per station —
  the first live run already showed the model under-reading the Bat Yam sea breeze by 5 kt.
- **`haifa-backdoor` has no wind station.** Its two nearest IMS masts sit on the Carmel
  ridge, and no station beats a misleading one.
- **`smoke --at` cannot reach past dates for wind comparison.** IMS serves history happily,
  but Open-Meteo's series starts at midnight today, so there is no model hour to pair with.
  Fixing it means adding `past_days` to the forecast request.
- **Webcams have no data source.** The Detail screen says none is configured rather than
  faking one.
- **Model confidence is absent.** It needs Stormglass, whose free tier of ~10 requests/day
  cannot be called from a device — it needs a scheduled job for a fixed spot list. The
  screen reports it unavailable rather than fabricating a percentage from one model.
- **Two thresholds are working defaults, not research.** The `overhead` slang band at
  1.5–2.2 m and the score band boundaries at 60/80. Confirm with a local surfer.
- **Distance sorting on Spots** needs CoreLocation and a permission prompt; it sorts by
  score and name for now.

Before any App Store submission: Open-Meteo requires a paid key for commercial use, and the
IMS terms (`ims.gov.il/sites/default/files/docs/terms_0.pdf`) need reading for attribution
and token-redistribution rules — they could not be text-extracted here.
