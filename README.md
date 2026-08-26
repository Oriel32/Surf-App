# Glassy

A highly localized surf forecast for the Israeli Mediterranean coast and the Gulf of Eilat.

**The thesis:** a global model number is not a forecast. Open-sea model output is computed
10–25 km offshore in >50 m of water at ~9 km resolution; the surfer is standing in 1.5 m of
water behind a breakwater. Every number this app shows is transformed to a specific spot and
translated into the language surfers actually use — `0.8 מ׳ · מותן עד חזה`, not `Hs 0.94`.

## Layout

```
SurfCore/          SwiftPM package — the entire engine. No UIKit, no SwiftUI, builds on Linux.
  Sources/SurfCore/
    Sources/       Three API clients behind one ForecastSource protocol, plus the
                   retry and cache transport decorators.
    Models/        Spot catalog, raw samples, transformed conditions, DataState.
    Rules/         Table-driven bands: slang, sea state, wind, score, wetsuit.
    Engine/        Wave transformation, match score, safety, best-window search.
    Translation/   Conditions -> Hebrew words, colour tokens, VoiceOver labels.
    Repository/    Actor that fetches, assembles, caches.
  Sources/smoke/   Live end-to-end run against the real endpoints.
  Tests/           Hermetic, fixture-driven. 155 tests.
App/               The SwiftUI app. Three tabs; every string comes from Translation.
project.yml        XcodeGen spec. Glassy.xcodeproj is GENERATED, never committed.
.github/workflows/ macOS runner: tests, generates the project, builds an unsigned .ipa.
docs/INSTALL.md    Getting the build onto an iPhone, free, without a Mac.
design/            Screen studies.
scripts/           WSL Swift toolchain wrapper; app-icon generator.
claude.md          The build spec: domain rules, phases, UI architecture.
surf_research.md   The domain research the rules are extracted from.
.claude/skills/    Lazily-loaded reference: screen layouts, data sources, toolchain setup.
```

The engine is a package rather than an app target on purpose: it means the whole forecast
pipeline can be built and tested without an iOS simulator, and in practice without a Mac.
That is what keeps the Mac a small, late problem instead of a blocking one.

## Build and test

On macOS or Linux:

```bash
swift build --package-path SurfCore
swift test  --package-path SurfCore
```

On Windows, via WSL — the toolchain installs entirely in userspace, no sudo. Run the
`wsl-swift-setup` skill for the one-time setup, then:

```bash
./scripts/wsl-swift.sh test              # hermetic unit suite
./scripts/wsl-swift.sh run smoke hadera  # LIVE, hits the real APIs
```

### Two kinds of test, and why both

- **`swift test` — hermetic.** Fixtures only, no network, no clock. Proves the logic is
  self-consistent. It cannot prove a decoder matches what a provider actually sends.
- **`swift run smoke [spot] [sport] [skill]` — live.** Runs the full pipeline against real
  Open-Meteo and ISRAMAR responses and prints the model's answer beside a real buoy reading.

The unit suite was green while three real bugs were live; all three were found only by the
smoke test. Run it before believing any ingest change.

## The app

Five screens behind three tabs — Home and Week are the product, the rest is support.

| Screen | The question it answers | Layer |
|---|---|---|
| Home | "Do I get in the car, right now?" | 1 |
| Week | "Which day this week?" | 1 per row |
| Detail | "Is this model right?" | 2 |
| Spots | "Where should I go?" | 1 per row |
| Settings | Sport, skill, units, favourites | — |

Hebrew is the primary locale and the layout is right-to-left from the first view. Wind arrows
and compass glyphs are pinned against mirroring — they encode real-world geography, and a
flipped arrow would report offshore as onshore.

## Getting it on a phone

There is no Mac in this project and none is needed. `.github/workflows/ios.yml` runs on a
GitHub `macos-latest` runner — free with unlimited minutes on a public repository — and
produces an unsigned `.ipa` as a build artifact. It carries no signing secrets: the app is
signed on-device with a free Apple ID.

```bash
gh run download --name Glassy-unsigned-ipa --dir dist
```

Then follow `docs/INSTALL.md`. Requires iOS 17.0 or later.

## Status

| Phase | | |
|---|---|---|
| 0 | Scaffold | done |
| 1 | Ingest — Open-Meteo, Stormglass, ISRAMAR | done |
| 2 | Spot catalog | done |
| 3 | Transformation engine | done |
| 4 | Translation / slang layer | done |
| 5 | Match Score | done |
| 6 | Safety — offshore drift alert | done |
| 7 | Verification — buoys done, webcams open | partial |
| 8 | SwiftUI app — all five screens, building in CI | done |

Open, and deliberately so:

- **Webcams have no data source.** The Detail screen says none is configured rather than
  faking one.
- **Model confidence is absent.** It needs Stormglass, whose free tier of ~10 requests/day
  cannot be called from a device — it needs a scheduled job for a fixed spot list. The
  screen reports it unavailable rather than fabricating a percentage from one model.
- **Two thresholds are working defaults, not research.** The `overhead` slang band at
  1.5–2.2 m and the score band boundaries at 60/80. Confirm with a local surfer before
  shipping.
- **Distance sorting on Spots** needs CoreLocation and a permission prompt; it sorts by
  score and name for now.

The Stormglass key is never committed.
