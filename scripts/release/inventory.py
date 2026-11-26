#!/usr/bin/env python3
"""Dependency and license inventory of a release.

    inventory.py [--metadata <apk>.json] [--json out.json] [-o out.md]

Lists what a release APK contains and what built it, each with its version
pin and license, read from the repository's own pins:

  contents   the stock app (supplied input, SHA-256 pin), this project's
             patches and shim classes, the native libraries built from
             patches/arm64/native (accepted SHA-256s)
  toolchain  apktool and uber-apk-signer (CMakeLists.txt pins), the Android
             SDK packages (scripts/ci/sdk-packages.txt), the JDK and the
             GitHub Actions (pinned commit SHAs in .github/)

A pin this script cannot find is an error, so the inventory never lists a
dependency without its version.
"""

import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]

LICENSES = {
    "apktool": "Apache-2.0",
    "uber-apk-signer": "Apache-2.0",
    "cmake": "BSD-3-Clause",
    "ndk": "Android Software Development Kit License",
    "build-tools": "Android Software Development Kit License",
    "platforms": "Android Software Development Kit License",
    "temurin": "GPL-2.0 with Classpath Exception",
    "actions": "MIT",
}


def cmake_pin(name):
    text = (ROOT / "CMakeLists.txt").read_text(encoding="utf-8")
    m = re.search(rf'set\({name}\s+"([^"]+)"', text)
    if not m:
        raise SystemExit(f"inventory: no pin {name} in CMakeLists.txt")
    return m.group(1)


def sdk_packages():
    out = []
    for line in (ROOT / "scripts/ci/sdk-packages.txt").read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            path, rev = line.split()
            out.append((path, rev))
    return out


def jdk_pin():
    text = (ROOT / ".github/actions/apk-toolchain/action.yml").read_text(encoding="utf-8")
    m = re.search(r'java-version:\s*"([^"]+)"', text)
    if not m:
        raise SystemExit("inventory: no java-version in the apk-toolchain action")
    return m.group(1)


def action_pins():
    pins = {}
    for f in sorted((ROOT / ".github").rglob("*.yml")):
        for m in re.finditer(r"uses:\s*([\w.-]+/[\w.-]+)@([0-9a-f]{40})\s*#\s*(\S+)", f.read_text(encoding="utf-8")):
            pins[m.group(1)] = (m.group(3), m.group(2))
    return pins


def build(metadata):
    expected = json.loads((ROOT / "tests/native/expected_abi.json").read_text(encoding="utf-8"))
    accepted = expected["abis"]["arm64-v8a"]["accepted_sha256"]
    contents = [
        {"component": "Sound Blaster Connect 1.04.02 (stock app)", "version": "1.04.02",
         "pin": cmake_pin("apk_input_sha256"), "license": "Proprietary, Creative Technology Ltd",
         "note": "supplied input; not in this repository"},
        {"component": "patches and shim classes (patches/)", "version": "this release",
         "pin": "source commit", "license": "MIT", "note": "this project"},
    ]
    for name in sorted(accepted):
        contents.append({"component": f"lib/arm64-v8a/{name}", "version": "this release",
                         "pin": accepted[name], "license": "MIT",
                         "note": "built from patches/arm64/native with the pinned NDK"})
    tools = [
        {"component": "apktool", "version": cmake_pin("apktool_version"),
         "pin": cmake_pin("apktool_sha256"), "license": LICENSES["apktool"], "note": "decode and rebuild"},
        {"component": "uber-apk-signer", "version": cmake_pin("uber_signer_version"),
         "pin": cmake_pin("uber_signer_sha256"), "license": LICENSES["uber-apk-signer"],
         "note": "debug signing of the controls; not used for release signing"},
        {"component": "Eclipse Temurin JDK", "version": jdk_pin(), "pin": "version",
         "license": LICENSES["temurin"], "note": "apktool, javac"},
    ]
    for path, rev in sdk_packages():
        kind = path.split("/", 1)[0]
        tools.append({"component": f"Android SDK {path}", "version": rev, "pin": "Pkg.Revision",
                      "license": LICENSES.get(kind, "see package"), "note": ""})
    for name, (tag, sha) in sorted(action_pins().items()):
        tools.append({"component": f"GitHub Action {name}", "version": tag, "pin": sha,
                      "license": LICENSES["actions"], "note": "CI only"})
    out = {"contents": contents, "toolchain": tools}
    if metadata:
        m = json.loads(pathlib.Path(metadata).read_text(encoding="utf-8"))
        out["release"] = {k: m[k] for k in ("file", "sha256", "version_name", "version_code",
                                            "source_commit", "certificate_sha256")}
        for row in contents:
            if row["pin"] == "source commit":
                row["pin"] = m["source_commit"]
    return out


def markdown(inv):
    lines = ["# Dependency and license inventory", ""]
    if "release" in inv:
        r = inv["release"]
        lines += [f"Release `{r['file']}`, {r['version_name']}, SHA-256 `{r['sha256']}`, "
                  f"source commit `{r['source_commit']}`.", ""]
    for title, key in (("Contents of the APK", "contents"), ("Build toolchain", "toolchain")):
        lines += [f"## {title}", "", "| Component | Version | Pin | License | Note |", "|---|---|---|---|---|"]
        for row in inv[key]:
            lines.append(f"| {row['component']} | {row['version']} | `{row['pin']}` | {row['license']} | {row['note']} |")
        lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--metadata")
    ap.add_argument("--json")
    ap.add_argument("-o", "--output")
    args = ap.parse_args()
    inv = build(args.metadata)
    if args.json:
        pathlib.Path(args.json).write_text(json.dumps(inv, indent=2) + "\n", encoding="utf-8", newline="\n")
    text = markdown(inv)
    if args.output:
        pathlib.Path(args.output).write_text(text, encoding="utf-8", newline="\n")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
