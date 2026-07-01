# AtomicClock widget refresh fix

Copy these files over the existing project at:

`Android/AtomicClock/`

## What this changes

- Adds `LocationCache.kt` so the last good coordinates/city are saved when the app gets location.
- Updates `WeatherRepository.kt` so the app caches location and the widget worker can refresh weather from cached coordinates.
- Updates `WidgetUpdater.kt` so background widget refresh does not depend only on live background location.
- Updates `WidgetRefreshWorker.kt` to use `ExistingPeriodicWorkPolicy.UPDATE` and add an immediate one-shot refresh helper.
- Updates `AtomicClockWidget.kt` so widget update/placement re-arms the worker and queues an immediate refresh.
- Adds `WidgetBootReceiver.kt` so refresh is re-armed after reboot/app update.
- Updates `AndroidManifest.xml` with `RECEIVE_BOOT_COMPLETED` and the boot/package receiver.

## Test

```bash
cd Android/AtomicClock
./gradlew :app:assembleDebug
```

Then install, open the app once, allow location, place the widget, and watch the large widget's `... ago` line update after the worker runs.

## Commit message

```bash
git commit -m "AtomicClock: make widget weather refresh reliable"
```


## Verification note
This repack bumps the app to versionName 0.4.2 / versionCode 6 and fixes the boot/update receiver intent filters so periodic widget refresh is re-armed after reboot or app update.
