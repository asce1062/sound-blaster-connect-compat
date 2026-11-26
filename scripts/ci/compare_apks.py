#!/usr/bin/env python3
"""Compare two APKs entry by entry.

    compare_apks.py <a.apk> <b.apk> [--ignore-signatures] [--any-order] [--json out.json]
    compare_apks.py --digest <apk> [--ignore-signatures] [--any-order]

Two APKs are equivalent when they hold the same entry names, in the same
order, and every entry has the same uncompressed bytes (SHA-256) and the same
compression method. ZIP metadata that does not reach the installed app
(timestamps, extra fields, compressed bytes) is reported but does not count.
--ignore-signatures leaves out META-INF signature files, for comparing a
signed APK with its unsigned build. --any-order drops the order condition:
apktool writes entries in a different order on Windows and on Linux, so a
build on each is compared with it.

--digest prints the content digest of one APK: the SHA-256 of one line
"<name>\\t<method>\\t<sha256>\\n" per entry, in archive order, or sorted by
name with --any-order. Equivalent APKs have equal digests, so builds on
different machines or with and without caches can be compared by that one
value.

Exit 0 when equivalent, 1 otherwise. Standard library only.
"""

import argparse
import hashlib
import json
import re
import sys
import zipfile

SIGNATURE = re.compile(r"^META-INF/([^/]+\.(SF|RSA|DSA|EC)|MANIFEST\.MF)$")


def entries(path, ignore_signatures):
    out = []
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            if ignore_signatures and SIGNATURE.match(info.filename):
                continue
            data = z.read(info)
            out.append({
                "name": info.filename,
                "sha256": hashlib.sha256(data).hexdigest(),
                "size": len(data),
                "method": info.compress_type,
                "date_time": list(info.date_time),
                "compressed_size": info.compress_size,
            })
    return out


def digest(path, ignore_signatures, any_order=False):
    es = entries(path, ignore_signatures)
    if any_order:
        es.sort(key=lambda e: e["name"])
    h = hashlib.sha256()
    for e in es:
        h.update(f"{e['name']}\t{e['method']}\t{e['sha256']}\n".encode())
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b", nargs="?")
    ap.add_argument("--digest", action="store_true")
    ap.add_argument("--ignore-signatures", action="store_true")
    ap.add_argument("--any-order", action="store_true")
    ap.add_argument("--json")
    args = ap.parse_args()
    if args.digest:
        print(f"{digest(args.a, args.ignore_signatures, args.any_order)}  {args.a}")
        return 0
    if args.b is None:
        ap.error("two APKs are needed unless --digest is given")

    ea, eb = entries(args.a, args.ignore_signatures), entries(args.b, args.ignore_signatures)
    na, nb = [e["name"] for e in ea], [e["name"] for e in eb]
    report = {"entries": [len(ea), len(eb)], "only_a": sorted(set(na) - set(nb)),
              "only_b": sorted(set(nb) - set(na)), "order_differs": False,
              "content": [], "method": [], "metadata_only": 0}
    if not report["only_a"] and not report["only_b"]:
        report["order_differs"] = na != nb
        report["order_ignored"] = args.any_order
        by_b = {e["name"]: e for e in eb}
        for x in ea:
            y = by_b[x["name"]]
            if x["sha256"] != y["sha256"]:
                report["content"].append(x["name"])
            elif x["method"] != y["method"]:
                report["method"].append(x["name"])
            elif x["date_time"] != y["date_time"] or x["compressed_size"] != y["compressed_size"]:
                report["metadata_only"] += 1
    equivalent = not (report["only_a"] or report["only_b"]
                      or (report["order_differs"] and not args.any_order)
                      or report["content"] or report["method"])
    report["equivalent"] = equivalent

    print(f"entries        {len(ea)} / {len(eb)}")
    for key in ("only_a", "only_b", "content", "method"):
        for name in report[key]:
            print(f"{key:<14} {name}")
    if report["order_differs"]:
        print("order          differs" + (" (ignored)" if args.any_order else ""))
    print(f"metadata only  {report['metadata_only']} entries (timestamps or compressed bytes)")
    print("EQUIVALENT" if equivalent else "DIFFERENT")
    if args.json:
        with open(args.json, "w", encoding="utf-8", newline="\n") as f:
            json.dump(report, f, indent=2)
            f.write("\n")
    return 0 if equivalent else 1


if __name__ == "__main__":
    sys.exit(main())
