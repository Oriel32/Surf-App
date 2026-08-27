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
