# Atomic Clock v0.5.1 patch

This source pack builds on v0.5.0. v0.4.2 confirmed the widget refresh works when Android location is set to **Allow all the time**; v0.5.0 added guidance and weather freshness.

## What changed

- Bumped app version to `0.5.1` / versionCode `8`.
- Polished the large widget layout so `Updated ...` is on its own muted line below weather.
- Weather row stays focused on current conditions: temperature, condition, humidity, and city.
- Weather freshness turns amber after 1 hour and red after 6 hours.
- README and CHANGELOG updated for v0.5.1.

## Expected large widget layout

```text
19:17
Tue 30 Jun

☀️ 84°F · Clear    💧 76% · Baytown
Updated just now
Drift +1.02 s · Google S1 · just now
```

## Test checklist

1. Build and install v0.5.1.
2. Confirm About shows `Version 0.5.1`.
3. Add the large widget.
4. Confirm weather update time is not crammed into the weather row.
5. Confirm the weather row no longer clips after the city unless the widget is very narrow.

## Commit

```bash
git commit -m "AtomicClock v0.5.1: polish widget weather layout"
```
