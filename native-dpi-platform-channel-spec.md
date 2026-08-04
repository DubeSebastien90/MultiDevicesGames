# Native DPI Platform Channel — Spec

## Purpose

Improve physical-size (millimetre) accuracy in the multiscreen game's **calibration phase** by reading native panel DPI instead of Flutter's density bucket.

Flutter only exposes `devicePixelRatio` — a rounded density bucket (2.0, 2.625, 3.0…), not the panel's real DPI. Deriving physical size from it can be several percent off, which is several millimetres of seam misalignment. Native platforms expose better data. This module reaches that data through a platform channel while keeping the app in Flutter.

## What this changes (and what it doesn't)

- **Does:** give calibration a closer-to-true starting estimate of each phone's active screen size in mm, so the placement guide lines start nearer to aligned.
- **Does NOT:** remove the need for the visual calibration check (the straddling circle / unbroken guide lines) or the manual tap-to-Measure ruler override. No API on any platform verifies *where* the phones physically are — Confirm remains a human promise. Better DPI just narrows the gap the user nudges away. Keep both fallbacks.

## Accuracy expectations per platform

| Platform | Source of physical DPI | Quality | Caveat |
|---|---|---|---|
| Android | `DisplayMetrics.xdpi` / `ydpi` (manufacturer-reported physical DPI, per axis) | Usually accurate to 1–2 mm | Only as good as OEM device profile; some OEMs echo the density bucket or report wrong values. |
| iOS | Device-model → known panel PPI **lookup table** (Apple exposes no physical-DPI API) | Accurate for known models | Must maintain the table; unknown/new models fall back to the density bucket. |
| Fallback (either) | Flutter `devicePixelRatio` density bucket | Several % off | Always available; last resort. |

Ground truth on ALL devices (including OEMs with bad data) remains the **manual ruler measurement** the user can enter. This module improves the default; the ruler overrides it.

## Contract (Dart side)

Define a single method channel, e.g. `com.yourgame/display_metrics`, with one method `getPhysicalScreenInfo` returning:

```dart
class PhysicalScreenInfo {
  final int widthPx;        // active screen width in physical pixels
  final int heightPx;       // active screen height in physical pixels
  final double xdpi;        // horizontal DPI (native-reported or looked-up)
  final double ydpi;        // vertical DPI
  final String source;      // 'android_metrics' | 'ios_lookup' | 'density_bucket'
  final bool trusted;       // false when we fell back to the density bucket
}
```

- Compute mm downstream in Dart: `widthMm = widthPx / xdpi * 25.4`, `heightMm = heightPx / ydpi * 25.4`.
- `source` and `trusted` let the calibration UI decide whether to nudge the user toward the ruler ("we couldn't read your exact screen size — measure it for a cleaner seam").
- Always wrap the call in try/catch; on any failure, fall back to Flutter's `MediaQuery` density-bucket derivation and set `trusted = false`.

## Android implementation (Kotlin)

- Read `DisplayMetrics` via `WindowManager` / `Display`. Use `xdpi` and `ydpi` (physical) — NOT `densityDpi` (that's the bucket).
- Return active resolution from the real display metrics (account for the app not being full-bleed if relevant; for a game it usually is).
- **Sanity-check the OEM value:** if `xdpi`/`ydpi` is suspiciously equal to `densityDpi` or wildly out of a plausible phone range (say <200 or >800), mark `trusted = false` and let Dart prefer the ruler.
- Set `source = 'android_metrics'` on success.

Pseudostructure:
```kotlin
val metrics = DisplayMetrics()
// obtain from context.display (API 30+) or windowManager.defaultDisplay (legacy)
display.getRealMetrics(metrics)
val xdpi = metrics.xdpi
val ydpi = metrics.ydpi
val widthPx = metrics.widthPixels
val heightPx = metrics.heightPixels
val plausible = xdpi in 200.0..800.0 && ydpi in 200.0..800.0
// return map { widthPx, heightPx, xdpi, ydpi, source="android_metrics", trusted=plausible }
```

## iOS implementation (Swift)

- iOS has **no physical-DPI API.** Build a lookup keyed on device model identifier (`utsname.machine`, e.g. `"iPhone15,2"`) → known screen PPI (public spec per model).
- Get resolution from `UIScreen.main.nativeBounds` (native pixels) × `nativeScale` as needed.
- Look up PPI by model id; if the model isn't in the table, return `trusted = false` and let Dart fall back to the density bucket.
- Set `source = 'ios_lookup'` on a table hit.

Pseudostructure:
```swift
// 1. get model id from utsname.machine
// 2. ppiTable: [String: Double] = ["iPhone15,2": 460, ...]
// 3. if let ppi = ppiTable[modelId] {
//      widthPx = Int(UIScreen.main.nativeBounds.width)
//      heightPx = Int(UIScreen.main.nativeBounds.height)
//      return [widthPx, heightPx, xdpi: ppi, ydpi: ppi, source: "ios_lookup", trusted: true]
//    } else { trusted = false }
```

Keep the PPI table in a separate file so it's easy to extend as new models ship. Unknown model = graceful density-bucket fallback, never a crash.

## Integration into calibration

1. On entering calibration, each phone calls `getPhysicalScreenInfo`.
2. Convert to mm in Dart; feed `screenMm` + `bezelMm` into the existing calibration handshake message.
3. If `trusted == false`, surface a gentle prompt steering the user to the tap-to-Measure ruler.
4. The ruler override always wins over the native value when the user enters one.
5. Everything downstream (coverage map, world offsets, seam) is unchanged — this module only improves the mm numbers that flow in.

## Scope guardrails

- This is a **thin native shim**, not a rewrite. Keep the whole app in Flutter; only the DPI read is native.
- Don't attempt to detect physical placement/rotation — no platform supports it. The visual calibration check stays the source of truth for placement.
- Don't over-trust either native path: both Android OEM data and the iOS table can be wrong, so the `trusted` flag + ruler override are mandatory, not optional.
- Add this only if testers report the starting seam misalignment is annoyingly large; the density bucket may be good enough for a first prototype.
