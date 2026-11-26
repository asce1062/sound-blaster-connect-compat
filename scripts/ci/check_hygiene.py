#!/usr/bin/env python3
"""Repository privacy and artifact-hygiene checks over the tracked tree.

Fails when a tracked file:
  - is a build input or output the project never commits: an APK or other
    Android package, a native library, dex or jar, a signing key or keystore,
    a v4 signature (.idsig);
  - lives in a generated or local directory (build/, decompiled/, inputs/,
    tools/);
  - is stock smali outside a patch overlay (patches/<name>/overlay/);
  - is larger than the size limit;
  - contains a private key block, an unredacted Bluetooth or MAC address, an
    adb wireless-debugging service name, a private IPv4 address, a local
    user-profile path, or an e-mail address other than a GitHub noreply or
    documentation placeholder address.

With --history, also fails when a commit's author or committer e-mail is not
a GitHub noreply address. GitHub itself (noreply@github.com) is accepted as
committer only: it commits the merge a pull request run tests.

Usage: check_hygiene.py [--history] [repo root]
Exit status 0 when clean, 1 otherwise. Standard library only.
"""
import argparse
import os
import re
import subprocess
import sys

MAX_BYTES = 1024 * 1024

FORBIDDEN_EXT = (
    ".apk", ".aab", ".apks", ".xapk", ".so", ".dex", ".jar", ".class", ".idsig",
    ".jks", ".keystore", ".p12", ".pfx", ".pk8", ".pem", ".key",
)
FORBIDDEN_DIRS = ("build/", "decompiled/", "inputs/", "tools/")
OVERLAY_SMALI = re.compile(r"^patches/[^/]+/overlay/smali[^/]*/")

NOREPLY = re.compile(r"@users\.noreply\.github\.com$", re.I)
GITHUB_COMMITTER = "noreply@github.com"
PLACEHOLDER_DOMAINS = ("example.com", "example.org", "example.net")

CONTENT_RULES = [
    ("private key block", re.compile(r"-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----")),
    ("Bluetooth/MAC address", re.compile(r"(?<![0-9A-Fa-f:])(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}(?![0-9A-Fa-f:])")),
    ("adb wireless-debugging service name", re.compile(r"adb-[A-Za-z0-9]{6,}-[A-Za-z0-9]{6}\._adb-tls")),
    ("private IPv4 address", re.compile(r"(?<![\d.])(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}(?![\d.])")),
    ("local user-profile path", re.compile(r"(?i)(?:[a-z]:[\\/]+users[\\/]+|/home/|/Users/)(?!<|\$|%|\{|runner\b|you\b|user\b)[A-Za-z0-9._-]+")),
]
# Values that match a rule but identify nothing private, with the reason.
ALLOWED_VALUES = {
    "192.168.43.1": "the speaker's own setup access point, a constant of the stock app",
}
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")


def git(root, *args):
    return subprocess.check_output(["git", "-C", root, *args]).decode("utf-8", "replace")


def email_ok(addr):
    a = addr.lower()
    return bool(NOREPLY.search(a)) or a == GITHUB_COMMITTER or a.endswith(PLACEHOLDER_DOMAINS)


def check_tree(root):
    problems = []
    for path in sorted(p for p in git(root, "ls-files", "-z").split("\0") if p):
        low = path.lower()
        if low.endswith(FORBIDDEN_EXT):
            problems.append(f"{path}: file type is never committed")
        if low.startswith(FORBIDDEN_DIRS):
            problems.append(f"{path}: generated or local directory")
        if low.endswith(".smali") and not OVERLAY_SMALI.match(path):
            problems.append(f"{path}: smali outside a patch overlay")
        full = os.path.join(root, path)
        if not os.path.isfile(full):
            continue
        size = os.path.getsize(full)
        if size > MAX_BYTES:
            problems.append(f"{path}: {size} bytes, over the {MAX_BYTES} byte limit")
            continue
        with open(full, "rb") as f:
            raw = f.read()
        if b"\0" in raw[:8192]:
            continue
        text = raw.decode("utf-8", "replace")
        for n, line in enumerate(text.splitlines(), 1):
            for name, rule in CONTENT_RULES:
                for m in rule.finditer(line):
                    if m.group(0) not in ALLOWED_VALUES:
                        problems.append(f"{path}:{n}: {name}: {m.group(0)}")
            for m in EMAIL.finditer(line):
                if not email_ok(m.group(0)):
                    problems.append(f"{path}:{n}: e-mail address: {m.group(0)}")
    return problems


def check_history(root):
    problems = []
    for line in git(root, "log", "--all", "--format=%h%x09%ae%x09%ce").splitlines():
        h, author, committer = line.split("\t")
        for role, addr in (("author", author), ("committer", committer)):
            # GitHub commits the merge it tests for a pull request, and web
            # merges, as itself (GITHUB_COMMITTER).
            if role == "committer" and addr.lower() == GITHUB_COMMITTER:
                continue
            if not NOREPLY.search(addr):
                problems.append(f"commit {h}: {role} e-mail is not a GitHub noreply address")
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root", nargs="?", default=".")
    ap.add_argument("--history", action="store_true")
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    problems = check_tree(root)
    if a.history:
        problems += check_history(root)
    for p in problems:
        print(p)
    print(f"{len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
