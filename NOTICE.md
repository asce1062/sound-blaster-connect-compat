# Notice

## No affiliation

SB Connect Compat is an independent compatibility project. It is not
affiliated with, endorsed by, or supported by Creative Technology Ltd. Sound
Blaster, Sound BlasterX, Sound Blaster Connect and Katana are names of
Creative Technology Ltd and are used here only to identify the software and
hardware this project works with.

## The stock app is not distributed

The pipeline operates on a copy of the stock Sound Blaster Connect 1.04.02
APK that you supply. That APK, its code, resources and native libraries are
Creative's software. This repository does not contain them and the project
does not distribute them. An APK you build contains the stock app's code and
resources together with this project's changes; you are responsible for how
you use it.

The repository contains:

- build scripts and patches that describe changes to the stock app;
- small shim classes (smali) added to the app by the `modernize` patch;
- C source for 64-bit replacements of the stock app's two native libraries,
  written to reproduce their observable behavior;
- a test harness and the behavioral test vectors captured from the stock
  library's outputs;
- documentation, including research records of how the stock behavior was
  established.

Method, field and class names in patches and harness code are the identifiers
the stock app uses; they are needed to bind to it.

## Third-party tools

The build downloads these tools at configure time, verifies their SHA-256 and
runs them. They are not part of this repository and remain under their own
licenses:

| Tool | Version | Source |
|---|---|---|
| apktool | 3.0.3 | https://github.com/iBotPeaches/Apktool |
| uber-apk-signer | 1.3.0 | https://github.com/patrickfav/uber-apk-signer |

The Android SDK, build-tools and NDK are installed by the user under Google's
terms.
