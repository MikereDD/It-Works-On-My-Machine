<div align="center">

# 🕰️ Atomic Clock

### Precise time over NTP · live local weather · a home-screen widget

![Version](https://img.shields.io/badge/version-0.3.0-39E0D0?style=flat-square)
![Platform](https://img.shields.io/badge/platform-Android-3DDC84?style=flat-square&logo=android&logoColor=white)
![minSdk](https://img.shields.io/badge/minSdk-26-1E88E5?style=flat-square)
![Kotlin](https://img.shields.io/badge/Kotlin-2.1-7F52FF?style=flat-square&logo=kotlin&logoColor=white)
![Compose](https://img.shields.io/badge/Jetpack%20Compose-Material%203-4285F4?style=flat-square&logo=jetpackcompose&logoColor=white)

[**⬇️ Download APK**](https://github.com/MikereDD/It-Works-On-My-Machine/raw/refs/heads/main/Android/AtomicClock/releases/atomic-clock-v0.3.0.apk) &nbsp;·&nbsp; [**📜 Changelog**](https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/AtomicClock/CHANGELOG.md)

</div>

---

A polished Android clock that syncs to internet time servers over **SNTP/NTP** and shows true atomic time — not your device's (possibly drifting) wall clock — with live local weather and a home-screen widget.

## ⏱️ What makes it accurate

- 🛰️ **SNTP client (RFC 4330)** — computes clock offset and round-trip delay from the four NTP timestamps, modelled on AOSP's `SntpClient`.
- ⚓ **Monotonic anchoring** — the resolved time is pinned to `SystemClock.elapsedRealtime()`, so it stays correct even if the device clock is wrong or gets changed.
- 🎯 **Best-of-N sampling** — each sync queries the chosen server several times and keeps the lowest-latency response, falling back across other public servers if needed.

## 🌦️ Weather

- 🌡️ Current **temperature, conditions, feels-like, humidity, wind** (speed + direction), **dew point**, and **city**.
- 🔑 Powered by [Open-Meteo](https://open-meteo.com) — free, no API key.
- 📍 Coarse location via the platform `LocationManager` (no Play Services). Fully optional — the clock works without it.

## 🧩 Home-screen widget

- 📐 Two **separately pickable** sizes — **2×1** and **4×2** tiles (both resizable).
- ⏰ Time self-updates to the minute via Android's `TextClock` (no service, no battery cost).
- 📊 Shows drift, sync source, and a weather line; **tap to open the app**.
- 🎨 Adjustable background — **Solid · Translucent · Clear** — to sit lighter over your wallpaper.

## ⚙️ Settings

- 🌡️ Independent **°C / °F** and **km/h / mph** toggles — defaulting by locale; **tap the temperature** to flip units.
- 🕓 24-hour / 12-hour and milliseconds on/off.
- 🌐 Time source: **Google · Cloudflare · NTP Pool · Apple · NIST**.
- ℹ️ About dialog with version, credits, and a GitHub link.

## 📲 Install

[**Download the APK**](https://github.com/MikereDD/It-Works-On-My-Machine/raw/refs/heads/main/Android/AtomicClock/releases/atomic-clock-v0.3.0.apk) and open it on your device (allow install from unknown sources), or build from source below.

> **Permissions:** `INTERNET`; `ACCESS_COARSE_LOCATION` (optional — weather only).

## 🛠️ Build

Open the project in Android Studio and Run, or from the command line:

```sh
./gradlew :app:assembleRelease
```

`minSdk` 26 · `targetSdk` / `compileSdk` 35 · Kotlin 2.1 · Jetpack Compose (Material 3)

## 📂 Project layout

```
app/src/main/java/com/typezero/atomicclock/
├── MainActivity.kt
├── ClockViewModel.kt
├── ntp/        SntpClient, SntpResult, NtpServer
├── data/       TimeSyncRepository, SettingsRepository
├── weather/    OpenMeteoClient, LocationProvider, WeatherRepository
├── ui/         AtomicClockScreen, formatting, theme/, components/
└── widget/     AtomicClockWidget (AppWidgetProvider), WidgetStore
```

## 📜 Changelog

See the [**full changelog**](https://github.com/MikereDD/It-Works-On-My-Machine/blob/main/AtomicClock/CHANGELOG.md) for version history.

<div align="center"><sub>Built by <b>typezero</b> · It-Works-On-My-Machine</sub></div>
