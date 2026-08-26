---
name: surf-data-sources
description: The three forecast APIs - Open-Meteo Marine, Stormglass and ISRAMAR - with their verified endpoint shapes, auth, rate limits and known failure modes (the Eilat HTTP 400, the ewam nulls, the frozen Shikmona buoy). Use before writing or changing any ingest client, decoder, cache policy or staleness rule.
---

# Data Sources: The Three APIs

Extracted from `claude.md` so it loads only when the data layer is in play.
The rules here are verified against live endpoints; do not write a decoder
against an assumed schema.

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
