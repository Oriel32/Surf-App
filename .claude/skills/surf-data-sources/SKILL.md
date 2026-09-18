---
name: surf-data-sources
description: The four forecast and observation APIs - Open-Meteo Marine, Stormglass, ISRAMAR and IMS - with their verified endpoint shapes, auth, rate limits and known failure modes (the Eilat HTTP 400, the ewam nulls, the frozen Shikmona buoy, the IMS standard-time timestamps and its flagged-invalid zeros). Use before writing or changing any ingest client, decoder, cache policy or staleness rule.
---

# Data Sources: The Four APIs

Extracted from `claude.md` so it loads only when the data layer is in play.
The rules here are verified against live endpoints; do not write a decoder
against an assumed schema.

| # | Source | Role | Auth | Status |
|---|--------|------|------|--------|
| 1 | Open-Meteo Marine + Forecast | Primary forecast spine | None (non-commercial) | Verified |
| 2 | Stormglass.io | Multi-model cross-check / confidence | API key | Verified via docs |
| 3 | ISRAMAR (IOLR) | Real-time buoy ground truth | None | Verified live, partially degraded |
| 4 | IMS (`ims.gov.il`) | Measured coastal wind | ApiToken (email request) | Verified live 2026-09-18 |

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

## 4. IMS (Israel Meteorological Service) - measured coastal wind
The wind counterpart to ISRAMAR, and the only measurement this app has of the
parameter the drift alert turns on. ~85 automatic stations reporting every ten
minutes; 77 of them were active with WS and WD on 2026-09-18.

```
https://api.ims.gov.il/v1/envista/stations/<ID>/data/latest
https://api.ims.gov.il/v1/envista/stations/<ID>/data/daily/YYYY/MM/DD
Authorization: ApiToken <token>

{"data": [{"datetime": "2026-09-18T10:50:00+03:00",
           "channels": [{"id": 4, "name": "WS",    "value": 8.2,  "status": 1, "valid": true},
                        {"id": 5, "name": "WD",    "value": 266,  "status": 1, "valid": true},
                        {"id": 2, "name": "WSmax", "value": 10.5, "status": 1, "valid": true}]}],
 "stationId": 178}
```

- **Auth on everything.** Station metadata included: no token, HTTP 401. The
  token is requested by email from `ims@ims.gov.il` and lives in the gitignored
  `.env` as `IMS_API_TOKEN`. It is **not** wired into the iOS app: the repo is
  public, so a token baked into a CI-built `.ipa` would be downloadable.
- **Timestamps are local *standard* time all year, and the `+03:00` suffix is a
  lie for half of it.** Verified live: `2026-09-18T10:50:00+03:00` was served at
  09:10 IDT. Believing the offset dates every summer reading 1 h 20 min into the
  past, which fails any freshness gate silently. The offset is discarded and
  `DateParsing.imsStandardOffsetSeconds` (+02:00) applied to the wall clock.
- **Channel ids differ per station** — the IMS PDF highlights this. Match on
  `name` (`WS`, `WD`, `WSmax`, `TD`), never on id.
- **A value can be present, numeric and invalid.** `status: 2` or
  `valid: false` means the sensor is bad. Elat (station 64) served `WS: 0.0`
  with both flags bad on all 65 slices of 2026-09-18: its anemometer is dead.
  A decoder that reads `value` without the flags publishes dead calm in the one
  basin where wind *is* the wave model.
- Units are already SI: WS and WSmax in m/s, WD in degrees true.
- Cadence is 10 minutes, so the cache is `.hourlyObservation` (10 min TTL) and
  the freshness gate is **1 hour**, not the buoy's three: a land breeze dies and
  a sea breeze fills in within the hour.
- `daily/YYYY/MM/DD` returns the whole day in 10-minute slices and reaches
  further back than Open-Meteo's forecast series does, which is what lets
  `smoke --at` check a past field report against measured wind.
- Coastal masts only. The nearest station is frequently the wrong one: Haifa's
  two nearest sit on the Carmel ridge, and Bet Dagan is inland of Bat Yam.
  Mapped in `ImsClient.stations` and per spot in `spots.json`; `haifa-backdoor`
  deliberately has none.
- **Scope: it verifies and it can raise a safety alert; it never overrides the
  model.** Measured wind is displayed with its age and distance, logged to
  `calibration/wind_observations.jsonl`, and can fire the offshore-drift alert
  the model missed - but it can never cancel one, and it does not feed the sea
  state, the score or Eilat's synthetic waves until that ledger shows a station
  tracks its beach.

---
