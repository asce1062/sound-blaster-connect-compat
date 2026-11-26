#!/usr/bin/env python3
"""Check the relative links and anchors in the repository's Markdown files.

Every inline link [text](target) whose target is not an absolute URL must
name a file or directory tracked in git, and a #fragment must match a heading
of the target file (GitHub's anchor rules). External URLs are not fetched.
Code spans and fenced code blocks are ignored.

Usage: check_links.py [repo root]   (default: the current directory)
Exit status 0 when every link resolves, 1 otherwise. Standard library only.
"""
import os
import re
import subprocess
import sys
import urllib.parse

LINK = re.compile(r"(?<!!)\[(?:[^\[\]]|\[[^\]]*\])*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
IMAGE = re.compile(r"!\[[^\]]*\]\(([^)\s]+)\)")
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
SCHEME = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")


def strip_code(text, spans=True):
    out, fenced = [], False
    for line in text.splitlines():
        if line.lstrip().startswith(("```", "~~~")):
            fenced = not fenced
            out.append("")
            continue
        if fenced:
            out.append("")
        else:
            out.append(re.sub(r"`[^`]*`", "", line) if spans else line)
    return out


def slug(heading):
    h = re.sub(r"`", "", heading)
    h = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", h)
    h = h.strip().lower()
    h = re.sub(r"[^\w\- ]", "", h, flags=re.UNICODE)
    return h.replace(" ", "-")


def anchors(path, cache={}):
    if path not in cache:
        seen, result = {}, set()
        with open(path, encoding="utf-8") as f:
            for line in strip_code(f.read(), spans=False):
                m = HEADING.match(line)
                if not m:
                    continue
                s = slug(m.group(2))
                n = seen.get(s, 0)
                seen[s] = n + 1
                result.add(s if n == 0 else f"{s}-{n}")
        cache[path] = result
    return cache[path]


def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    files = subprocess.check_output(["git", "-C", root, "ls-files", "-z"]).decode().split("\0")
    tracked = {f for f in files if f}
    dirs = {os.path.dirname(f) for f in tracked}
    for d in list(dirs):
        while d:
            d = os.path.dirname(d)
            dirs.add(d)
    failures = 0
    checked = 0
    for md in sorted(f for f in tracked if f.endswith(".md")):
        with open(os.path.join(root, md), encoding="utf-8") as f:
            lines = strip_code(f.read())
        for n, line in enumerate(lines, 1):
            for m in list(LINK.finditer(line)) + list(IMAGE.finditer(line)):
                target = m.group(1)
                if SCHEME.match(target) or target.startswith("//"):
                    continue
                checked += 1
                path, _, frag = target.partition("#")
                path = urllib.parse.unquote(path)
                if path:
                    rel = os.path.normpath(os.path.join(os.path.dirname(md), path)).replace(os.sep, "/")
                else:
                    rel = md
                if rel.startswith("../"):
                    print(f"{md}:{n}: link leaves the repository: {target}")
                    failures += 1
                    continue
                is_file = rel in tracked
                is_dir = rel.rstrip("/") in dirs
                if not (is_file or is_dir):
                    print(f"{md}:{n}: no tracked file or directory: {target}")
                    failures += 1
                    continue
                if frag and is_file and rel.endswith(".md"):
                    if frag.lower() not in anchors(os.path.join(root, rel)):
                        print(f"{md}:{n}: no heading for #{frag} in {rel}")
                        failures += 1
    print(f"{checked} relative links checked, {failures} broken")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
