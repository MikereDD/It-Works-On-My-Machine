# Changelog

All notable changes to Atomic Clock are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-06-20

### Added
- Home-screen widget in two **separately pickable** sizes — a 2x1 and a 4x2 tile
  (both resizable). The time self-updates via `TextClock` (no service), alongside
  date, clock drift, sync source, and a weather line with **condition + humidity icons**.
  Tapping the widget opens the app.
- **Widget background** setting (Solid / Translucent / Clear), defaulting to
  Translucent so it sits lighter over the wallpaper.
- The app pushes a fresh widget snapshot after every time sync and weather refresh,
  and when units/format change; the system also refreshes it periodically.

## [0.2.0] - 2026-06-20

### Added
- Current weather: temperature, conditions, "feels like", humidity, wind (speed + direction), dew point, and city, shown beneath
  the clock. Powered by [Open-Meteo](https://open-meteo.com) — free and keyless.
- Coarse-location lookup via the platform `LocationManager` (no Play Services),
  with a graceful "Tap for weather" prompt when permission isn't granted yet.
- Independent unit toggles: temperature (°C / °F) and wind speed (km/h / mph), each defaulting by locale (US → °F + mph). Tap the temperature to switch °C / °F.
- Automatic weather refresh every 15 minutes.
- About screen with app version, credits (NTP sources, Open-Meteo), and a link to the repo.

### Changed
- Settings sheet now includes the temperature-unit selector.
- Added the `ACCESS_COARSE_LOCATION` permission (weather is fully optional;
  the clock works without it).

## [0.1.0] - 2026-06-20

### Added
- Initial release.
- SNTP (RFC 4330) client anchored to `SystemClock.elapsedRealtime` so corrected
  time stays valid even if the device wall clock is wrong or later changed.
- Best-of-N sampling per sync (keeps the lowest round-trip response) with
  automatic fallback across Google, Cloudflare, NTP Pool, Apple, and NIST.
- Frame-rate-smooth clock face with a sweeping millisecond ring and tabular figures.
- Live stats: clock drift vs. atomic time, estimated accuracy (±round-trip/2),
  and the active source server + stratum.
- Auto re-sync every 10 minutes plus a manual re-sync control.
- Settings (DataStore-persisted): 24-hour toggle, milliseconds toggle, server choice.
- Material 3 dark-first theme with edge-to-edge layout and an adaptive launcher icon.
