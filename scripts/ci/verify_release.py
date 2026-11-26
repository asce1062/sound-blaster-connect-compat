#!/usr/bin/env python3
"""Check a signed release APK against its metadata and the accepted build.

    verify_release.py --apk <apk> --mode <test-release|release>
                      --cert <sha256> [--release-env <release.env>]
                      [--tag <tag>] [--expected tests/native/expected_abi.json]

Complements cmake/verify_signed_apk.cmake (signature, alignment, metadata,
payload). Each check is fatal:

  1. <apk>.sha256 names the APK and holds its SHA-256
  2. <apk>.json: file, sha256, size, signing mode and certificate match the
     APK and the expected certificate
  3. lib/arm64-v8a/ in the APK holds exactly the accepted libraries, with the
     accepted SHA-256s, and <apk>.json records the same hashes
  4. with --release-env: package, versions, tag and stock input SHA-256 in
     <apk>.json equal the build's release.env
  5. release mode: no pre-release label, and the tag equals --tag when given

Standard library only.
"""

import argparse
import hashlib
import json
import pathlib
import re
import sys
import zipfile

ABI = "arm64-v8a"


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def read_env(path):
    values = {}
    for line in pathlib.Path(path).read_text(encoding="utf-8").splitlines():
        m = re.match(r"^([A-Z0-9_]+)=(.*)$", line)
        if m:
            values[m.group(1)] = m.group(2)
    return values


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apk", required=True)
    ap.add_argument("--mode", required=True, choices=["test-release", "release"])
    ap.add_argument("--cert", required=True)
    ap.add_argument("--release-env")
    ap.add_argument("--tag")
    ap.add_argument(
        "--expected",
        default=str(pathlib.Path(__file__).resolve().parents[2] / "tests/native/expected_abi.json"))
    args = ap.parse_args()

    errors = []

    def check(ok, msg):
        if not ok:
            errors.append(msg)

    apk = pathlib.Path(args.apk)
    digest = sha256_file(apk)
    cert = re.sub(r"[: ]", "", args.cert.strip().lower())
    check(re.fullmatch(r"[0-9a-f]{64}", cert) is not None, "expected certificate is not a SHA-256")

    # 1. .sha256
    sums = pathlib.Path(str(apk) + ".sha256").read_text(encoding="utf-8")
    check(sums == f"{digest}  {apk.name}\n", f"{apk.name}.sha256 does not hold '{digest}  {apk.name}'")

    # 2. .json
    meta = json.loads(pathlib.Path(str(apk) + ".json").read_text(encoding="utf-8"))
    check(meta.get("file") == apk.name, f"json file {meta.get('file')!r} is not {apk.name!r}")
    check(meta.get("sha256") == digest, f"json sha256 {meta.get('sha256')} is not {digest}")
    check(meta.get("size") == apk.stat().st_size, "json size differs from the APK")
    check(meta.get("signing_mode") == args.mode, f"json signing_mode {meta.get('signing_mode')!r} is not {args.mode!r}")
    check(meta.get("certificate_sha256") == cert, f"json certificate {meta.get('certificate_sha256')} is not {cert}")
    check(meta.get("source_uncommitted_changes") is False or args.mode == "test-release",
          "release built from a tree with uncommitted changes")

    # 3. Native libraries.
    expected = json.loads(pathlib.Path(args.expected).read_text(encoding="utf-8"))
    accepted = expected["abis"][ABI]["accepted_sha256"]
    in_apk = {}
    with zipfile.ZipFile(apk) as z:
        for info in z.infolist():
            if info.filename.startswith(f"lib/{ABI}/") and not info.is_dir():
                in_apk[info.filename.rsplit("/", 1)[1]] = hashlib.sha256(z.read(info)).hexdigest()
    check(sorted(in_apk) == sorted(accepted),
          f"lib/{ABI}/ holds {sorted(in_apk)}, accepted {sorted(accepted)}")
    for name, want in accepted.items():
        check(in_apk.get(name) == want, f"lib/{ABI}/{name} is {in_apk.get(name)}, accepted {want}")
    check(meta.get("native_libraries_arm64_v8a_sha256") == accepted,
          "json native library hashes differ from the accepted hashes")

    # 4. release.env
    if args.release_env:
        env = read_env(args.release_env)
        for key, field in (("APP_ID", "package"), ("VERSION_NAME", "version_name"),
                           ("RELEASE_TAG", "release_tag"), ("STOCK_INPUT_SHA256", "stock_input_sha256")):
            check(env.get(key) == meta.get(field), f"release.env {key}={env.get(key)} but json {field}={meta.get(field)}")
        check(env.get("VERSION_CODE") == str(meta.get("version_code")),
              f"release.env VERSION_CODE={env.get('VERSION_CODE')} but json version_code={meta.get('version_code')}")

    # 5. Release mode.
    if args.mode == "release":
        tag = meta.get("release_tag", "")
        if args.tag is not None:
            check(tag == args.tag, f"json release_tag {tag!r} is not the tag {args.tag!r}")
        if args.release_env:
            label = read_env(args.release_env).get("PRERELEASE", "")
            check(not args.tag or label == "", f"pre-release label {label!r} on the release tag {args.tag}")

    for line in (f"apk           {apk.name}", f"sha256        {digest}", f"mode          {args.mode}",
                 f"certificate   {cert}", f"package       {meta.get('package')}",
                 f"version       {meta.get('version_name')} ({meta.get('version_code')})",
                 f"tag           {meta.get('release_tag')}", f"commit        {meta.get('source_commit')}"):
        print(line)
    for name in sorted(in_apk):
        print(f"lib/{ABI}/{name}  {in_apk[name]}")
    if errors:
        for e in errors:
            print(f"FAIL: {e}", file=sys.stderr)
        return 1
    print("verify_release: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
