#!/usr/bin/env python3
"""Dependency integrity checks.

  - Every `uses:` in .github/workflows/ and .github/actions/ names a local
    action (./...) or an external action pinned to a full 40-hex commit SHA.
  - The tool pins in CMakeLists.txt (apktool, uber-apk-signer, the stock APK
    hash) are well formed: a version and a 64-hex SHA-256 each.
  - With --download <dir>: both jars are downloaded from their pinned release
    URLs (or reused from <dir>) and must match their pinned SHA-256.
  - With --sdk <root>: every package of scripts/ci/sdk-packages.txt is
    installed with exactly its revision.

Usage: check_pins.py [--download DIR] [--sdk ROOT] [repo root]
Exit status 0 when every check passes, 1 otherwise. Standard library only.
"""
import argparse
import glob
import hashlib
import os
import re
import sys
import urllib.request

USES = re.compile(r"^\s*(?:-\s*)?uses:\s*['\"]?([^'\"\s#]+)")
PINNED = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}$")
SET = re.compile(r"set\(\s*(\w+)\s*\"([^\"]*)\"", re.S)
HEX64 = re.compile(r"^[0-9a-f]{64}$")

JARS = {
    "apktool": ("https://github.com/iBotPeaches/Apktool/releases/download/v{v}/apktool_{v}.jar", "apktool_version", "apktool_sha256"),
    "uber-apk-signer": ("https://github.com/patrickfav/uber-apk-signer/releases/download/v{v}/uber-apk-signer-{v}.jar", "uber_signer_version", "uber_signer_sha256"),
}


def cmake_pins(root):
    with open(os.path.join(root, "CMakeLists.txt"), encoding="utf-8") as f:
        return dict(SET.findall(f.read()))


def check_uses(root):
    problems, count = [], 0
    files = glob.glob(os.path.join(root, ".github", "workflows", "*.y*ml"))
    files += glob.glob(os.path.join(root, ".github", "actions", "**", "action.y*ml"), recursive=True)
    for path in sorted(files):
        with open(path, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                m = USES.match(line)
                if not m:
                    continue
                count += 1
                ref = m.group(1)
                if ref.startswith("./"):
                    continue
                if not PINNED.match(ref):
                    problems.append(f"{os.path.relpath(path, root)}:{n}: not pinned to a commit SHA: {ref}")
    print(f"{count} action references checked")
    return problems


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def check_jars(pins, outdir):
    problems = []
    os.makedirs(outdir, exist_ok=True)
    for name, (url_t, vkey, hkey) in JARS.items():
        url = url_t.format(v=pins[vkey])
        dest = os.path.join(outdir, os.path.basename(url))
        if not os.path.isfile(dest):
            urllib.request.urlretrieve(url, dest)
        got = sha256(dest)
        ok = got == pins[hkey]
        print(f"{'ok  ' if ok else 'FAIL'} {name} {pins[vkey]}: {got}")
        if not ok:
            problems.append(f"{name}: SHA-256 {got}, pinned {pins[hkey]}")
    return problems


def check_sdk(root, sdk):
    problems = []
    with open(os.path.join(root, "scripts", "ci", "sdk-packages.txt"), encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            path, rev = line.split()
            props = os.path.join(sdk, path, "source.properties")
            got = ""
            if os.path.isfile(props):
                with open(props, encoding="utf-8") as p:
                    for pl in p:
                        if pl.startswith("Pkg.Revision"):
                            got = pl.split("=", 1)[1].strip()
            ok = got == rev
            print(f"{'ok  ' if ok else 'FAIL'} {path}: {got or 'missing'}")
            if not ok:
                problems.append(f"{path}: revision '{got}', want '{rev}'")
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root", nargs="?", default=".")
    ap.add_argument("--download")
    ap.add_argument("--sdk")
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    pins = cmake_pins(root)
    problems = check_uses(root)
    for key in ("apktool_sha256", "uber_signer_sha256", "apk_input_sha256"):
        if not HEX64.match(pins.get(key, "")):
            problems.append(f"CMakeLists.txt: {key} is not a 64-hex SHA-256")
    for key in ("apktool_version", "uber_signer_version"):
        if not re.match(r"^\d+\.\d+\.\d+$", pins.get(key, "")):
            problems.append(f"CMakeLists.txt: {key} is not a release version")
    if a.download and not problems:
        problems += check_jars(pins, a.download)
    if a.sdk:
        problems += check_sdk(root, a.sdk)
    for p in problems:
        print(p)
    print(f"{len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
