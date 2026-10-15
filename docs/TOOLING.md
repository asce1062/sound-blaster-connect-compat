# Tooling — SBConnect bring-up

Where the tools are on this machine, so the next session does not re-search.
Machine-wide tool locations live in `~/.claude/CLAUDE.md`; this file records
the Android-specific ones and what the pipeline fetches.

## The pipeline fetches (SHA-256 verified)

The CMake configure downloads these to `build/tools/` and verifies the hash:

| Tool | Version | Pin source |
|---|---|---|
| apktool | 3.0.3 | same jar + hash as a sibling project (CI-verified there) |
| uber-apk-signer | 1.3.0 | same |

Requires: Java 17+ (apktool 3.x), CMake 3.22+, Ninja, internet on first
configure.

## On this machine already

- **Android SDK** `%LOCALAPPDATA%\Android\Sdk`
  - `build-tools\33.0.1\` — `aapt2.exe`, `apksigner.bat/.jar`, `zipalign.exe`,
    `d8.bat`, and a bundled `apktool.jar` (**2.9.3**, older than the pipeline's
    3.0.3; fine for ad-hoc `d`/`b` inspection).
  - `cmake\3.22.1\bin\cmake.exe` and `cmake\3.10.2.4988404\bin\{cmake,ninja}.exe`
    — no system CMake/Ninja on PATH; use these or add them to PATH.
  - `platform-tools` has `adb`; `adb` is also at `C:\platform-tools\adb`.
  - `platforms\` android-16..android-33; `ndk\` 21.3, 21.4, 25.1.
- **Java** 23 on PATH (`java`); JDKs under `C:\Program Files\Java\`.
- **git-lfs** 3.7.1 on PATH (the stock APK is LFS-tracked).

## Sibling projects (reference, not dependencies)

- `..\sibling-project` — the CMake APK pipeline this one mirrors
  (decode → patch overlay → rebuild → sign; it adds AES asset crypto this app
  does not need). Patch-framework idiom, fetch/verify helper, deploy script.
- `..\sibling-project-2` — native RE harness and toolchain:
  - `tools\` (gitignored): `jadx-1.5.6`, `Il2CppDumper`, `frida` +
    `frida-il2cpp-bridge`, `frida-server-17.18.0-android-arm64`, `quickbms`.
  - `vendor\` submodules: `Apktool`, `APKEditor`, `uber-apk-signer`,
    `Android-Mod-Menu`. `tools\bin\APKEditor.jar` (1.4.9) is prebuilt.
  - `common\`: `And64InlineHook`, `elf_img.h`, `zygisk.hpp` — aarch64 inline
    hooking + Zygisk harness, relevant to the arm64 native track.

## Reverse engineering (arm64 track)

- **REA** MCP server (`rea`) — registered but **timed out connecting** this
  session (30 s). Retry; it drives Ghidra (default provider).
- **Ghidra** 12.1.4 and 12.1.2 in `<tools>\`.
- **IDA** Professional 9.1 and 7.2. Headless IDA is parked (see
  `~/.claude/CLAUDE.md`); use Ghidra/REA.
- **jadx** (in the sibling project's `tools\`) for the Java/smali side.
