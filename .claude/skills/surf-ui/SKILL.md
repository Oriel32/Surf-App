---
name: surf-ui
description: Screen-by-screen UI specification for the Glassy surf forecast app - navigation, and the Home, Week, Day/Spot Detail, Spots and Settings layouts. Use when building, changing or reviewing any SwiftUI view or the screen study in design/.
---

# Glassy - screen specifications

The dual-layer paradigm, the safety-banner hierarchy, data-honesty states, colour
rules, Hebrew/RTL typography, accessibility and motion all live in `claude.md` and
apply always. This file is the per-screen layout detail only.

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
