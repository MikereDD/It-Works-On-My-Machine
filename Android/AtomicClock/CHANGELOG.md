# Changelog

All notable changes to Atomic Clock are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.1] - 2026-06-22

### Added
- **Background refresh** for the widget via WorkManager: the tile re-syncs time
  and re-fetches weather on its own roughly every 15 minutes, so it stays current
  without opening the app. Scheduled when a widget is placed and on app launch,
  and stopped when the last tile is removed.

### Changed
- The refresh button now also re-fetches weather (forcing a fresh location fix),
  and weather re-pulls whenever the app returns to the foreground. Previously the
  button only re-synced the clock and weather refreshed only every 15 minutes, so
  a reading could lag well behind real conditions.
- Widget weather line now reads `temp · condition … humidity · city` — the city
  trails the humidity, and the line is packed to the left rather than split to
  opposite edges.

### Fixed
- Current condition now reflects what's actually happening rather than the
  hour's forecast. Open-Meteo's `weather_code` covers a whole grid-cell hour, so
  it could announce a "Thunderstorm" while nothing was falling; when there's no
  current precipitation the app now shows the observed sky (clear / partly cloudy
  / cloudy / overcast) from cloud cover instead. Real precipitation still reads
  as drizzle/rain/snow/storm.
- Weather now resolves a **fresh location** instead of reusing a stale cached
  fix, so conditions and city update as you travel. Previously an old fix could
  make a reading like "Thunderstorm" persist from city to city while the actual
  sky had changed.
- The widget no longer blanks to "Weather unavailable" after a transient
  background failure. Snapshot writes now merge over the previous values, so a
  failed time sync or weather fetch keeps the last known reading.
- About dialog "View on GitHub" link corrected to the `Android/AtomicClock` path
  (it previously pointed at the old root path and 404'd).

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
