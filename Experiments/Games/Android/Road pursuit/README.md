# Road Pursuit — Native Android (Kotlin / Canvas / SurfaceView)

An original top-down vehicular-combat game in the Spy Hunter tradition. Pure
Kotlin, no game engine, no third-party libraries — everything renders on a
`Canvas` driven by a `SurfaceView` render thread, and every sound effect is
synthesized at runtime through `AudioTrack` (no bundled audio).

## Open & run

1. Android Studio → **Open** → select the `RoadPursuit` folder.
2. Let it sync. If it prompts about the Gradle wrapper (this archive omits the
   binary `gradle-wrapper.jar`), just accept Android Studio's offer to use/regenerate
   the wrapper, or from a terminal in the project root run:
   `gradle wrapper --gradle-version 8.7`
3. Run on a device or emulator (portrait, API 24+).

## Setup notes (the things that usually bite)

- **Gradle JDK = 17.** Settings → Build, Execution, Deployment → Build Tools →
  Gradle → *Gradle JDK* should be **17** (the bundled JetBrains Runtime 17 is
  fine). The build pins `sourceCompatibility`/`targetCompatibility`/`jvmTarget`
  to 17 in `app/build.gradle.kts`, so anything else will fail the sync.
- **No drawable/mipmap XML to break.** The launcher icon uses the framework
  resource `@android:drawable/sym_def_app_icon`, so there are no custom vector
  drawables or adaptive-icon XML to misconfigure. Swap in your own later via the
  Image Asset wizard if you want.
- **No AppCompat/Material dependency.** The theme is the framework
  `Theme.Material.NoActionBar` and `MainActivity` extends `android.app.Activity`.
  Fewer moving parts, fewer version-mismatch surprises.
- **Versions:** AGP 8.5.2, Kotlin 1.9.24, Gradle 8.7, compileSdk/targetSdk 34,
  minSdk 24.

## Controls (on-screen, drawn into the canvas)

- `<` / `>` — steer
- `GAS` / `BRK` — throttle up / slow down
- `FIRE` — twin machine guns
- `OIL` — drop an oil slick (spins out pursuers)
- `SMK` — smoke screen
- top-right `II` pause, `<)` / `x` mute toggle
- Tap anywhere on the title / game-over screen to start.

## Gameplay

- Wreck red **bandit** cars (shoot them, or `GAS` into them to ram). Orange
  **boss** cars take several hits and chase harder.
- Don't shoot or ram the grey **civilians** — both cost points.
- Drive into the rear of the green **AMMO van** to resupply oil + smoke and grab
  a brief shield (+100, once per van).
- Difficulty escalates in **stages** every ~1800m: faster spawns, more bosses,
  tougher bosses.
- The highway periodically becomes a **river** — all vehicles become boats,
  oil slicks become whirlpools, barriers become buoys. Hitting the bank wrecks
  you the same as going off-road.
- Best score is saved in `SharedPreferences`.

## Project layout

```
app/src/main/java/com/typezero/roadpursuit/
  MainActivity.kt   – immersive fullscreen host
  GameView.kt       – SurfaceView + render thread + touch -> logical mapping
  Game.kt           – simulation + all Canvas rendering (logical 420x640 space)
  Entities.kt       – plain data classes for game objects
  SoundManager.kt   – runtime PCM synthesis via AudioTrack
```

The simulation runs in a fixed 420×640 logical coordinate space; `GameView`
letterbox-scales it to any screen and converts touch points back to logical
coordinates, so the layout is identical across devices.
