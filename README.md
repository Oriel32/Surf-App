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
    Sources/       Three API clients behind one ForecastSource protocol.
    Models/        Spot catalog, raw samples, transformed conditions, slang bands.
    Engine/        Wave transformation, match score, safety, best-window search.
    Repository/    Actor that fetches, assembles, caches.
  Sources/smoke/   Live end-to-end run against the real endpoints.
  Tests/           Hermetic, fixture-driven.
design/            Screen studies.
claude.md          The build spec: domain rules, data sources, phases, UI architecture.
surf_research.md   The domain research the rules are extracted from.
```

The engine is a package rather than an app target on purpose: it means the whole forecast
pipeline can be built and tested without an iOS simulator, and in practice without a Mac.

## Build and test

On macOS or Linux:

```bash
swift build --package-path SurfCore
swift test  --package-path SurfCore
```

On Windows, via WSL — the toolchain installs entirely in userspace, no sudo. See
"Building the backend on Windows" in `claude.md` for the one-time setup, then:

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
| 8 | SwiftUI app | not started — needs a Mac |

The Stormglass key is never committed. The free tier allows ~10 requests/day, so that source
is fetched by a scheduled job for a fixed spot list, never per-view from a device.
