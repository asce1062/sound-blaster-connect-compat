# SBConnect bring-up

Reproducible pipeline that decodes the stock **Sound Blaster Connect** APK,
applies a selected patch set, and rebuilds a signed, sideloadable APK — a
bring-up so the abandoned app installs on current Android instead of showing
*not compatible with your device*.

Not a mod. The goal is to get the stock app running on recent Android and, on
the native track, to recover the device protocol for a future first-party app.

## Why the stock app fails on new devices

Two separate problems (full analysis in [docs/FINDINGS.md](docs/FINDINGS.md)):

1. **Play Store listing filter** — low targetSdk (26) + missing ABIs. A
   re-signed sideload bypasses it.
2. **64-bit-only devices** (Pixel 7/8) — the APK ships only 32-bit native
   libs, so Tensor-class phones cannot load them at all. Needs `arm64-v8a`
   builds of the two libraries, which means reverse engineering them.

## Variants

One build produces three mutually-exclusive APKs under `build/`:

| Variant | What it changes | Runs on |
|---|---|---|
| `resign` | nothing — stock app rebuilt + debug-signed | modern phones that still have 32-bit support (sideload) |
| `modernize` | `resign` + targetSdk raised (and the behavior fixes it needs) | same, more modern |
| `arm64` | `modernize` + `arm64-v8a` native libs | 64-bit-only devices — once the libs exist |

## Build

Needs Java 17+, CMake 3.22+, Ninja, and internet on the first configure
(fetches apktool 3.0.3 + uber-apk-signer 1.3.0, SHA-256 verified). The stock
APK is tracked with Git LFS — run `git lfs pull` after cloning.

```bash
cmake --preset default              # verify APK, fetch tools, decode -> decompiled/
cmake --build --preset resign       # -> build/sbc_resign-aligned-debugSigned.apk
cmake --build --preset modernize    # -> build/sbc_modernize-aligned-debugSigned.apk
cmake --build --preset apks         # all variants
```

On this machine CMake/Ninja are not on PATH; use the Android SDK copies (see
[docs/TOOLING.md](docs/TOOLING.md)).

Install and watch it run on a connected device:

```bash
cmake --build build --target deploy      # adb install + launch + logcat (resign)
```

Pick the variant with `-Ddeploy_variant=modernize` at configure time.

## Layout

```
CMakeLists.txt          pipeline (decode -> stage -> patch -> apktool b -> sign)
CMakePresets.json       configure + per-variant build presets
cmake/
  sbc_patches.cmake     variant framework
  apply_patch.cmake     patch applier (overlay + patch.cmake per patch)
  deploy_apk.cmake      adb install + launch + logcat
patches/
  modernize/            targetSdk bump + Android 12/13/14 behavior fixes
  arm64/                arm64-v8a native libs (native RE track)
docs/
  FINDINGS.md           compatibility analysis, component + ABI inventory
  TOOLING.md            where the tools are on this machine
SBConnect_v1.04.02.apk  stock input (Git LFS)
```

Each patch is `patches/<name>/` with an `overlay/` tree (copied onto the
decoded app) and/or a `patch.cmake` (in-place edits, run with `${TREE}` set).

## Status

- `resign` — pipeline complete, builds a signed APK.
- `modernize` — starter bumps targetSdk to 30; the 31+ work is open.
- `arm64` — native RE track, open.
