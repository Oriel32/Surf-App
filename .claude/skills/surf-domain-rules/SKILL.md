---
name: surf-domain-rules
description: The calibrated domain tables - wave-height slang bands and the break-point energy threshold, sea-state texture, wind direction and strength bands, per-spot transformation coefficients and their order of operations, the Gulf of Eilat synthetic formula, and the per-sport Match Score weights. Use before writing or changing any threshold, coefficient, band boundary or user-facing Hebrew term.
---

# Domain rules - the calibrated tables

Extracted from `claude.md` so it loads only when a number or a term is in play.
The offshore-drift safety alert deliberately stayed in `claude.md`: it is always
in force and must never depend on this file being loaded.

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
| Fair | סביר | Everything in between | Neutral |
| Choppy | צ'ופי | See the three triggers below | Orange / red |

`סביר` is **not** from `surf_research.md`, which names only flat/glassy/choppy.
A binary glassy-or-choppy misdescribes most real days on this coast, so the
middle state uses plain Hebrew rather than invented slang. The wording is still
unconfirmed against a local surfer.

**Choppy has three triggers, and mean wind speed is only one of them.**

1. Onshore or cross-onshore wind at or above 12 kt. *(the obvious one)*
2. **Wind-sea energy share at or above 0.18** — how much of the sea is local
   chop rather than swell, measured **at the break, not offshore**.
3. **Gust at or above 18 kt**, whatever the mean is doing.

Rules 2 and 3 exist because of 2026-08-29 at Bat Yam, where a surfer called the
sea choppy at 10:00 and the app said `סביר` until noon: the mean wind never left
the 0-10 kt "ideal" band all morning while the chop went from 11% of the energy
to 24% and gusts reached 18 kt. Mean speed and direction alone cannot see a sea
being contaminated by a wind that is technically light.

Rule 2 must be evaluated **after** the spot transform. Long swell shoals up over
the bar and short chop does not, so the same hour reads 28% offshore and 18% at
the beach; keyed to the open-sea figure the rule fires an hour early.

The glassy test deliberately runs **before** all three. A calm or offshore
morning stays `גלאסי` even with an old wind sea still running - the hero state is
rare and must not be collateral damage from a chop rule.

Live in `SeaStateRules` (`chopEnergyShare`, `gustChopKnots`) and
`SeaStateClassifier.classify`. Evidence: `calibration/bat-yam-comparison.md`,
observation #3.

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

## Match Score (0-100), per sport
Sport profile is user-selected: surfing, kitesurfing, wing foil, SUP.

**Surfing:** adjusted shore height 0.6-1.5 m scores full on the height term; period <5 s (wind slop) drops the total sharply; 7-9 s raises it; light easterly adds a bonus; westerly >12 kt subtracts heavily for destroyed shape.

**Kitesurfing / wing foil:** the logic inverts - wind carries the dominant weight. 100 requires stable side- or south-westerly wind at 15-22 kt.

**SUP:** rewards flat and calm, and must be suppressed to near-zero by the offshore-wind hazard regardless of how pleasant the surface looks.

**Chop is its own term, separate from period.** Period is read off the dominant
wave train, so while the swell stays the taller of the two it keeps describing
clean groundswell no matter how much chop is building underneath - on 2026-08-29
the reported period *rose* through a session that was falling apart. The score
reads `windSeaEnergyShare` directly: `ScoreTuning.surfing.chopShare`, flat to
0.15 and gone by 0.50, with `chopFloor = 0.30`.

## Longshore current
Water moving *along* the beach: Longuet-Higgins per train,
`V ≈ 1.17·√(g·H_b)·sin θ_b·cos θ_b`, signed by which side of the shore normal
the train arrives from, plus the alongshore wind component at 3% of wind speed.
Lives in `LongshoreCurrent`. Two trains on opposite sides of the normal is
confused water rather than merely lumpy water, flagged as `isCrossSea`.

**This is not the offshore drift hazard and must never be presented as one** -
that alert stays in `claude.md` precisely so it does not depend on this file
being loaded. A longshore current pushes a surfer down the beach; the offshore
one pushes a beginner out to sea. A second, more frequent banner is how people
learn to ignore the first.

Informs the **SUP score only** (`ScoreTuning.sup.current`, flat to 0.25 m/s,
gone by 0.80, `currentFloor = 0.25`) and renders as a Layer 2 readout. **The
magnitude is provisional** - the mechanism is textbook but one session cannot
calibrate it, and 2026-08-29 is a poor case because the opposed trains partly
cancel. It stays off the surfing score until the calibration log has more.
