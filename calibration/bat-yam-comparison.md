# Bat Yam — side-by-side against GoSurf

Calibration ledger. Every row is one hour or one day at Bat Yam, with what we
said, what GoSurf said, and what the ISRAMAR buoy measured. **Nothing here is a
conclusion** — it is the evidence that has to exist before any coefficient moves.

Reproduce with:

```
swift run smoke bat-yam surfing intermediate --explain   # every stage of one hour
swift run smoke bat-yam surfing intermediate --today     # today, hour by hour
```

## What each column actually measures

Half of an apparent disagreement is a definition mismatch, not a physics error.
Tuning our engine to absorb one would make us wrong in a new way, so the
definition stays visible:

| Source | Column | Quantity |
|---|---|---|
| **Ours** | open-sea | Model Hs offshore, untransformed |
| **Ours** | beach | Significant Hs at the break, after exposure/refraction/shoaling, capped at 0.78 × depth |
| **Ours** | set ×1.27 | 1-in-10 set height. **The slang word comes from this**, not from the beach metres printed beside it |
| **GoSurf** | סוואל | Swell height + period. Confirmed below to be the same quantity as our open-sea |
| **GoSurf** | גובה | Beach wave height, as a **range** in cm |
| **GoSurf** | גלים | The descriptive word for that beach height |
| **ISRAMAR Hadera** | — | Measured Hs in open water ~30 km north. Ground truth for the **open sea**, not the beach |

---

## Observation #1 — 2026-08-27, hour by hour

Small clean summer sea, NW wind building through the afternoon.

| Hour | GoSurf סוואל | GoSurf גובה | GoSurf גלים | Ours open-sea | Ours beach | Ours set | Ours band |
|---|---|---|---|---|---|---|---|
| 06 | 52 cm / 6.1 s | 30–50 | ים גלי | 0.58 m / 6.3 s | 0.55 | 0.69 | מותן עד חזה |
| 09 | 54 cm / 6.2 s | 40–60 | **קרסול** | 0.56 m / 6.3 s | 0.51 | 0.65 | מותן עד חזה |
| 12 | 52 cm / 6.1 s | 30–50 | ים גלי | 0.54 m / 6.3 s | 0.48 | 0.61 | מותן עד חזה |
| 15 | 52 cm / 6.1 s | 30–50 | ים גלי | 0.52 m / 6.3 s | 0.50 | 0.64 | מותן עד חזה |
| 18 | 57 cm / 6.0 s | 30–50 | ים גלי | 0.52 m / 6.3 s | 0.48 | 0.61 | מותן עד חזה |
| 21 | 52 cm / 5.9 s | 30–50 | ים גלי | 0.50 m / 6.3 s | 0.44 | 0.56 | מותן עד חזה |

Buoy at 17:00: **0.45 m @ 6.2 s**. Buoy at 16:00 the day before: 0.55 m @ 6.5 s.

Wind cross-check, 18:00: GoSurf 16 km/h NW, ours 14 km/h side-shore from 338°. Agrees.

### Finding 1.1 — the open sea is right. This is settled.

| | 18:00 |
|---|---|
| GoSurf swell | 0.57 m @ 6.0 s |
| Our model input | 0.52 m @ 6.3 s |
| Hadera buoy (measured) | 0.45 m @ 6.2 s |

Three independent sources within 12 cm and 0.3 s. **The ingest layer is not the
problem and should not be touched.** Every remaining disagreement is downstream.

### Finding 1.2 — the slang is two to three bands too generous. This is the complaint.

GoSurf calls a 52 cm swell / 30–50 cm beach **ים גלי** — "wavy sea", not even an
anatomical term — and reserves **קרסול** (ankle) for the 40–60 cm hour.

We call the identical sea **מותן עד חזה**, waist to chest.

Two separate causes, and they compound:

1. The band is chosen from the **set height** (0.48 × 1.27 = 0.61 m), not from
   the 0.48 m we print. Removing that alone moves today from `מותן עד חזה` to
   `קרסול עד ברך` — much closer to GoSurf's `קרסול`.
2. Even after that, the band table itself reads high. `surf_research.md` puts
   0.50–0.90 m at "waist to chest"; the local market leader puts 0.50 m at
   "ankle". Waist-to-chest on GoSurf's scale looks like it starts around 1.0–1.2 m.

### Finding 1.3 — our beach height sits at the top of GoSurf's range

GoSurf publishes a **range** (30–50 cm) where we publish a point (0.48 m). Our
point lands at or just above their maximum — roughly 20% above their midpoint.
Net factor ×0.92: exposure 0.85 and shoaling 1.155 nearly cancel, so "at the
beach" comes out within 8% of the open sea.

---

## Observation #2 — the week, 2026-08-27 → 09-03

GoSurf's 7-day graph against our daily maxima. **Ours now reports the day's max
open-sea and max beach height, so a model disagreement is distinguishable from a
transform error.**

| Day | GoSurf | Our open-sea max | Our beach max | Our band at peak |
|---|---|---|---|---|
| 27/08 | 50 cm | 0.62 m | 0.59 m | Waist to chest |
| 28/08 | 40 cm | 0.48 m | 0.43 m | Waist to chest |
| 29/08 | 90 cm | 1.76 m | **1.60 m** | Overhead |
| 30/08 | **200 cm** | 1.94 m | **1.60 m** | Overhead |
| 31/08 | 130 cm | 1.14 m | 0.99 m | Shoulder to head |
| 01/09 | 100 cm | 0.74 m | 0.63 m | Waist to chest |
| 02/09 | 50 cm | 0.64 m | 0.47 m | Waist to chest |

### Finding 2.1 — the breaking cap flattens the whole top of the week

29/08 and 30/08 both report **exactly 1.60 m** at the beach, from open-sea inputs
of 1.76 m and 1.94 m. Both days are pinned against `0.78 × depth`. The cap has
erased the difference between them.

GoSurf calls those two days **90 cm and 200 cm** — the difference between "don't
bother" and "the day of the week". We show one number twice and rank 29/08
*above* 30/08 on score. **A user reading our week drives out on the wrong day.**

This is the most damaging finding in the ledger. It is not a tuning error; the
cap is a hard ceiling of ~1.56–1.60 m at Bat Yam's 2.0 m nominal depth, so the
app is structurally incapable of reporting a big day.

### Finding 2.2 — the models genuinely disagree about 29/08, and that is separate

Our open sea says 1.76 m on 29/08; GoSurf says 90 cm at the beach. Our swell
arrives roughly a day early and stays big; GoSurf shows a sharp, later onset
peaking on the 30th. GoSurf runs a DWD/GFS/ICON ensemble; we run Open-Meteo
`best_match`. **This one is not fixable by touching the transform** — it is a
model choice, and the honest response is the confidence/spread mechanism that
already exists in `ModelSpread`, not a coefficient.

---

## Open questions, in priority order

1. **Is GoSurf's 7-day number the beach height or the swell?** Today it is 50 cm,
   where their beach range tops out at 50 and their swell is 52 — both fit, so
   today cannot separate them. This decides whether the exposure coefficient
   needs to move at all. Check a day where the two diverge.
2. **What word does GoSurf use on 30/08 (200 cm) and 31/08 (130 cm)?** Three
   points on their band curve — 90, 130 and 200 cm — would pin the whole table
   against local usage instead of against the research doc's guess.
3. **Does the 0.78 cap belong on a displayed height at all?** It is real physics
   for a single wave at a single depth, but Bat Yam's "2.0 m break depth" is one
   nominal number standing in for a whole surf zone. Options: raise the per-spot
   depth, apply the cap to a deeper reference depth, or stop capping the reported
   height and cap only what the score sees.

---

## Changes made 2026-08-27, and their effect

Two changes, both approved after the findings above.

### A. The slang band is chosen from the significant height, not the sets

`SurfRange.bandDefiningMeters` → `significantMeters`. The displayed **range** was
already there — `Translator.present` has always quoted
`heightRange(significant, set)`. Only the band's input was wrong, and the smoke
tool had been printing a bare metre value rather than the product's own line,
which is why it was never obvious.

| | Before | After | GoSurf |
|---|---|---|---|
| 27/08 18:00 | `0.5-0.6 מ׳ · מותן עד חזה` | `0.5-0.6 מ׳ · קרסול עד ברך` | `ים גלי` / `קרסול` |

**We now agree with GoSurf on today's word.**

### B. The breaking cap constrains the score, not the reported height

`waveHeightMeters` is no longer clipped to `0.78 × depth`. The limit travels on
`SpotConditions.breakingLimitMeters`; `rideableHeightMeters` and
`rideableEnergyKilowattsPerMetre` apply it, and the Match Score reads those.
`isDepthLimited` marks a closeout day for the UI.

| Day | GoSurf | Before | After | Score before → after |
|---|---|---|---|---|
| 29/08 | 90 cm | 1.60 m | 1.85 m | 40 → 40 |
| 30/08 | **200 cm** | 1.60 m | **2.09 m** | 69 → **86** |

Two results worth stating plainly:

1. **The week has its shape back.** The two big days are no longer the same
   number, and 30/08 — GoSurf's standout day — now scores 86 against 29/08's 40.
   We and GoSurf now name the same day as the day to go.
2. **On 30/08 we land within 5% of GoSurf** (2.09 m vs 200 cm) having been 20%
   low. That was not tuned for; it fell out of removing the clip.

29/08 remains far apart (1.85 m vs 90 cm). That is finding 2.2 — a genuine model
timing disagreement, not a transform error, and it is not fixable here.

### What B costs, and what still needs deciding

A 5 m open-sea storm at a 2 m nominal spot now reports **6.27 m** at the beach.
That is worse than the 1.56 m it used to report, in the other direction.

Both numbers are wrong for the same underlying reason: the engine shoals every
wave to one nominal depth. A 5 m wave broke a long way offshore and never reached
a 2 m bar; a 0.5 m wave has not broken at 2 m yet. Neither is described by
"shoal to 2.0 m, then decide what to do about the cap".

The fix that dissolves both cases is to **solve for the depth where each train
actually breaks** — iterate `H(d) = H₀ · Ks(d) · Kr(d)` against `0.78 d` until it
converges — and report the height at that depth. Then no cap is needed at all:
the reported height is a breaking height by construction, big waves break in
deeper water and stay big, and small waves break shallow and stay small.

Not done, because it changes small days too: a 0.5 m sea would break at roughly
0.7 m depth with more shoaling than it gets at 1.64 m, so today's reading would
rise slightly — away from GoSurf's 30-50 cm range, not toward it. That trade
needs the band-table calibration settled first.

### Still open

- The band **table** is still the research doc's, not local usage. Today matches
  GoSurf now, but 27/08's 0.59 m peak still reads `מותן עד חזה` where GoSurf
  would say `קרסול`. Needs GoSurf's words for the 90/130/200 cm days.
- The Match Score reads 16/100 today with `size 1.00` and `wind 1.00`, held down
  by `energy 0.19`. `ScoreTuning.surfing.energy` wants 3.2 kW/m for full credit;
  this coast's median sea carries about 0.8. That curve is calibrated for an
  ocean.

---

## Round 2 — GoSurf published their scale, 2026-08-27

GoSurf documented their own vocabulary, which answered the two questions this
ledger had left open:

> גלים נשברים מ-50 ס״מ עם תלות במחזור הגל
> מצבי הים האפשריים הם: פלטה, ים נוח, ים גלי, גלים בגובה —
> קרסול, ברך, מותן, חזה, כתף, ראש, פעמיים ראש

Three things follow, and all three were wrong on our side.

### C. Seven single terms, not four paired bands

`surf_research.md`'s ladder was replaced wholesale. The new table starts only
where waves break, and `ים נוח` / `ים גלי` / `פלטה` cover everything below.

### D. The break point is period-dependent

Keyed to energy so both halves of their sentence are honoured — `SurfBreaking`,
threshold `0.5·H²·T ≥ 0.75 kW/m`, anchored on 0.50 m at 6 s. Gives 0.61 m at
4 s and 0.35 m at 12 s.

One bug this surfaced immediately: the 50 cm anchor was stated *twice*, in
`SurfBreaking` and again as the first row of the band table. A 0.45 m wave at
10 s then both broke and landed in the sub-breaking row. The table no longer
restates it.

### E. `ים נוח` is small **and** smooth, not merely smooth

First attempt keyed it to texture alone, and it over-fired across the whole
morning. GoSurf called Bat Yam `ים גלי` at 06:00 in a **4 km/h wind** — glass by
any texture rule — and again at 21:00, at our 0.46 m and 0.37 m. So the word has
a height ceiling, and it sits below 0.37 m. Set to 0.30 m.

### F. Bat Yam is structure-protected, not typical-urban

GoSurf's two columns finally answered ledger question 1: their `סוואל` runs
52–57 cm while their `גובה` at the beach is 30–50 cm, so **their own transform
runs about ×0.75**. Ours ran ×0.92. Bat Yam is heavily breakwatered and the
coefficient table already had a 0.72 row for exactly that; `spots.json`
0.85 → 0.72, which lands us at ×0.77.

### Result

| Hour | GoSurf | Before round 2 | After |
|---|---|---|---|
| 06 | ים גלי | מותן עד חזה | **ים גלי** ✓ |
| 09 | קרסול | מותן עד חזה | ים גלי ✗ |
| 12 | ים גלי | מותן עד חזה | **ים גלי** ✓ |
| 15 | ים גלי | מותן עד חזה | **ים גלי** ✓ |
| 18 | ים גלי | מותן עד חזה | **ים גלי** ✓ |
| 21 | ים גלי | מותן עד חזה | **ים גלי** ✓ |

**Five of six hours match exactly**, and the displayed range is now
`0.4-0.5 מ׳` against GoSurf's `30-50 ס״מ` — the same numbers, not merely the
same ballpark.

The two misses are the same fact seen twice: GoSurf's day peaks at 09:00 and
ours at 03:00, so both forecasts say "ankle" at their own peak, six hours apart.
That is the model timing disagreement of finding 2.2, not a vocabulary error,
and no coefficient can fix it.

### G. The score's energy plateau

`ScoreTuning.surfing.energy` plateau 3.2 → 2.4 kW/m. It had been anchored on
0.9 m at **8 s**, a period this basin almost never sees, so a good local day
could not reach full energy credit. 2.4 is the same 0.9 m at the coast's
measured 6.3 s median.

Note this is *not* the "the curve is calibrated for an ocean" claim from round 1,
which was wrong. Today scoring 19/100 is correct — GoSurf calls it `ים גלי`,
nobody is surfing it. The `size 1.00` that looked alarming is a deliberate gate,
documented at `ScoreTuning.swift:58`.

### Still open

- The breaker-depth solve. A 5 m storm still reports 6.27 m at a 2 m spot.
  Untouched by this round and it does not affect Bat Yam at any height this week.
- The other 11 spots may be mis-typed the same way Bat Yam was. No GoSurf
  evidence for them yet.
- `surf_research.md` is deliberately **not** edited. It is the research record
  and should keep saying what the research said; `claude.md` now states that it
  overrides the doc on this table, and why.

---

## Observation #3 — 2026-08-29, a session in the water

The first entry in this ledger measured against a **person**, not against
another forecast. A surfer at Bat Yam reported, from the water:

> Today 29.8, I went to surf at 9:30 at Bat Yam beach. The waves were being
> built at around 10:00 but with a little bit of current and wind that made the
> sea bit choppy and wavy, but every few minutes there were good waves that were
> built about 7 meters from the surfline. At around 10:20 the current and the
> wind became much higher and the conditions were not very good — wavy sea with
> lot of current and disorganized waves.

Reproduce with `swift run smoke bat-yam surfing intermediate --at 2026-08-29T10:00`.
The `--at` flag was added for this: the tool could previously only report on the
current hour, so a field report could never be checked against the engine.

### What we said at the time

| Hour | beach | period | sea state | band | score |
|---|---|---|---|---|---|
| 09:00 | 0.62 m | 7.0 s | `סביר` | קרסול | 51 |
| 10:00 | 0.65 m | 7.7 s | `סביר` | קרסול | 55 |
| 11:00 | 0.66 m | 7.7 s | `סביר` | קרסול | ~30 |
| 12:00 | 0.68 m | 7.7 s | `צ׳ופי` | קרסול | — |

Peak window for the day: **07:00–11:00, score 59** — a recommendation that
expires at the hour the session became unsurfable.

### Finding 3.1 — every headline number moved the wrong way

Beach height *rose* 0.62 → 0.66 m and the period *rose* 7.0 → 7.7 s through a
session the surfer watched come apart. Neither is a bug in the arithmetic. The
height is the quadrature sum of both trains, so building chop raises it; the
period is read off the dominant train, and the swell stayed the taller of the
two the whole morning. Both numbers were true and the impression they gave was
false — the failure mode `claude.md` opens by naming.

The split behind them, at the break:

| Hour | swell | chop | total | chop share | wind | gust |
|---|---|---|---|---|---|---|
| 07:00 | 0.583 | 0.115 | 0.594 | 3.7% | 4.7 kt | 9.1 |
| 08:00 | 0.583 | 0.161 | 0.604 | 7.1% | 6.3 kt | 12.2 |
| 09:00 | 0.583 | 0.208 | 0.619 | 11.3% | 8.0 kt | 15.6 |
| **10:00** | 0.590 | 0.280 | 0.653 | **18.4%** | 9.0 kt | 17.7 |
| **11:00** | 0.574 | 0.322 | 0.658 | **23.9%** | 10.6 kt | 20.8 |
| 12:00 | 0.557 | 0.397 | 0.684 | 33.7% | 12.4 kt | 24.3 |

The rideable swell was flat to falling. The entire rise in the displayed number
was 2.5-second slop.

### Finding 3.2 — the wind never looked like the problem

Mean wind ran 8.0 → 10.6 kt, inside the `0-10 kt weak — surf/SUP ideal` band for
almost the whole session, veering 193° → 223°. 15-minutely: 8.5 kt at 09:30,
9.7 kt at 10:30, crossing 10 kt only at about 10:40. Nothing keyed to mean speed
could have fired.

Two things did change and neither was being read: the **gust** reached 17.7 kt by
10:00 (ratio ~1.96), and the **onshore component** of the wind more than doubled,
2.5 → 5.4 kt, while the mean barely moved.

### Finding 3.3 — the share at the beach is not the share offshore

Open-sea chop shares that morning were 18% / 28% / 37%. At the break they are
11% / 18% / 24%. A 7.65 s swell shoals up over a 2 m bar and a 2.45 s chop does
not, so the transform *cleans* the sea by about a third.

This matters for anyone setting a threshold: keyed to the open-sea number, a
"choppy" rule fires an hour early. `SpotConditions.windSeaEnergyShare` is
therefore computed after the transform, not at ingest.

### Finding 3.4 — the two trains were opposed

Swell from 290°, 20° north of the 270° normal. Chop from 220-229°, 41-50° south
of it. They drive longshore current in opposite directions, which is confused
water rather than merely lumpy water — the "disorganized waves" of the report.
No scalar the engine carried could express it.

### Finding 3.5 — the calibration log was recording a false bias

Smoke printed `model 1.10 m vs buoy 0.64 m — MODEL AND BUOY DISAGREE (+0.46 m)`
and wrote that gap to this ledger.

It is not a model error. Pulling Open-Meteo **at the Hadera buoy's own
coordinates** for the same hour:

| | combined | swell partition | buoy |
|---|---|---|---|
| 13:00 local | 1.08 m | **0.66 m @ 5.95 s** | **0.64 m @ 6.5 s** |

The swell channel agrees to **2 cm**. The whole discrepancy is the wind-sea
partition — the same conclusion finding 1.1 reached from GoSurf's swell column,
now reached independently from the buoy. A model's combined `wave_height` and an
ISRAMAR significant height are not the same quantity.

Left alone, thirty of these would have produced a "height bias" of about +0.45 m
and `suggestedHeightCorrection` would have proposed shrinking every spot's
exposure coefficient by roughly a third to cancel an error the transform never
made.

### Changes made

- **H.** `SpotConditions` carries `swellHeightMeters`, `windSeaHeightMeters`,
  `windSeaEnergyShare` and `isCrossSea`. The transform already computed all of
  it per train and discarded it. Displayed height and the slang band are
  **unchanged** — they remain the combined sea, so nothing in rounds 1-2 moves.
- **I.** `SeaStateRules` gains `chopEnergyShare = 0.18` and `gustChopKnots = 18`,
  and `SeaStateClassifier` reads the partition and the gust. First choppy hour
  moves from 12:00 to **10:00**. The glassy short-circuit deliberately stays
  ahead of both, so the hero state is untouched.
- **J.** `ScoreTuning.surfing` gains a `chopShare` curve and `chopFloor = 0.30`,
  emitted as a `chop` component. Before this the 10:00 → 11:00 fall came entirely
  from the wind relation crossing a bin boundary, which happened to land on the
  right hour here and would not on a day the wind held its bearing.
- **K.** New `LongshoreCurrent` — Longuet-Higgins per train, signed by side of
  the normal, plus alongshore wind drift. Surfaced as a readout and wired to the
  **SUP score only**. Not a safety alert: the offshore-drift banner keeps its
  monopoly, and a second, more frequent alert is how people learn to ignore the
  first. **Magnitude is provisional** — one session cannot validate it, and this
  one is a poor calibration case because the opposed trains partly cancel.
- **L.** `CalibrationRecord` gains `modelSwellHeightMeters` /
  `modelSwellPeriodSeconds`, and `suggestedHeightCorrection` now refuses to
  answer until 30 records carry a partition, measuring against the swell channel
  when they do.
- **M.** The ledger path was **CWD-relative**. Running smoke from `SurfCore/`
  silently created a second history at `SurfCore/calibration/observations.jsonl`.
  Now anchored to the repo via `#filePath`.
- **N.** `--at` must not write to the ledger unless the model hour and the buoy
  reading are the same hour. ISRAMAR serves only its latest measurement, so
  asking for 09:00 in the afternoon paired a morning forecast against an
  afternoon observation — and the first seven records this session produced were
  exactly that, discarded before they reached the file. The comparison is still
  printed and labelled; only the *logging* is gated, at one hour.

### Result

09:00 `סביר`, **10:00 `צ׳ופי`**, 11:00 `צ׳ופי` — the first choppy hour is now the
hour it was called choppy from the water.

Live at 14:00 on the day, against the 12Z refresh: chop share 12% / 18% / 25%,
scores **53 / 55 / 24**. The regression suite pins the earlier 06Z numbers it was
written from, so the two differ by a point or two; what is asserted there is the
shape, not the digits — 09:00 and 10:00 within six points of each other, and at
least a fifteen-point fall into 11:00.

Note what is *not* claimed: 09:00 → 10:00 does not fall. A first version of the
regression test demanded a monotone decline and failed, and the report is why
the test was wrong rather than the engine — at 10:00 there were still "good waves
every few minutes", the sea was bigger and longer-period as well as choppier,
and those genuinely trade off. The collapse is reported at **10:20**, between two
model hours. What had to move, and does, is 10:00 → 11:00.

### Still open

- **Everything in K is n=1.** The current model needs more logged sessions before
  its magnitude means anything, and it must not reach the surfing score or an
  alert until then.
- **Does GoSurf's `גובה` column show the combined sea or the swell?** Today would
  discriminate it — the two differ by about 10 cm at Bat Yam — where every
  light-wind day already in this ledger cannot. Not captured on the day.
- The `fair` / `סביר` state still has no home in `claude.md` or the research, and
  its source comment still says "confirm the wording". Now load-bearing: it is
  the state that 09:00 lands in.
- Nothing here revisits the round-2 band table, the break point, or the exposure
  coefficient. This round changed what the engine can *see*, not what it names.
