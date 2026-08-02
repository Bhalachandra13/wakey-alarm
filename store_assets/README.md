# `store_assets/`

Pre-rendered assets for the Google Play Store listing and the
in-app launcher icon set.

## Files in this directory (already generated)

| File | Size | Purpose |
|---|---|---|
| `icon-512.png` | 512×512 | Play Store listing icon. The Play Console **requires** exactly 512×512, alpha-enabled PNG, ≤ 1024 KB. |
| `feature-graphic-1024x500.png` | 1024×500 | Play Store feature graphic. Shown at the top of the app's Play Store listing. |

## Subdirectory (created by you before publishing)

```
store_assets/
  screenshots/
    phone/          ← 2–8 screenshots, 16:9 or 9:16, 320–3840 px
    7-inch/         ← optional but recommended
    10-inch/        ← optional
```

Capture the screenshots on a physical device (per
`docs/play-store-publish.md` §2). Recommended scenes:
1. Alarms tab — empty state.
2. Alarms tab — list with one time + one geofence alarm.
3. Map picker with favourite chips + radius circle.
4. Ringing activity on the lock screen.
5. Permission setup wizard.
6. Timer / stopwatch tab with live progress ring.

## Regenerating the icon and feature graphic

The script `tools/generate_launcher_icon.py` (pure Python, no
PIL/ImageMagick required) regenerates every asset in this
directory plus the Android mipmaps and adaptive-icon
drawable. It is idempotent — running it twice produces the
same result.

```bash
python3 tools/generate_launcher_icon.py
```

To change the brand colour, edit the `BRAND_BLUE` and
`BRAND_AMBER` constants at the top of the script. To
substitute a different artwork (e.g. a designer hands you a
vector logo), the cleanest approach is to replace
`store_assets/icon-512.png` and
`android/app/src/main/res/mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png`
*after* re-running the script — the script's outputs are the
canonical sources of truth, and the script's box-filter
downscale gives cleaner small icons than most manual
exports.

## What is intentionally not in this directory

- **App icon for the iOS App Store.** Phase 1 is Android only
  per `docs/requirements.md` §1.
- **Promo graphic (1024×680).** Optional; only needed for
  featuring.
- **TV banner (1280×720).** Skipped — not a TV app.
- **Wear OS screenshot.** Skipped — not a Wear app.
