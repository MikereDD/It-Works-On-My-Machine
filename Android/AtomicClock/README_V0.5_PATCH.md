# Atomic Clock v0.5.1 patch

This source pack builds on v0.4.2, which confirmed that widget refresh works when Android location is set to **Allow all the time**.

## What changed

- Bumped app version to `0.5.1` / versionCode `7`.
- Added `BackgroundLocationStatus.kt` to centralize foreground/background location permission checks.
- Updated Settings so the background widget update row explains the exact permission state:
  - location not granted,
  - background location not granted,
  - automatic widget weather enabled.
- Large widget now keeps and displays `lastWeatherEpoch`, for example `updated 8m ago`.
- README and CHANGELOG updated for v0.5.1.

## Test plan

1. Build and install v0.5.1.
2. Open Settings.
3. Confirm the background widget row tells you whether Android still needs **Allow all the time**.
4. Set Location permission to **Allow all the time**.
5. Place the large widget.
6. Confirm weather/city refreshes and the widget shows an updated timestamp.

## Commit

```bash
git add Android/AtomicClock
git commit -m "AtomicClock v0.5.1: improve widget weather permission guidance"
```
