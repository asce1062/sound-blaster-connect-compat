# Build times and equivalent builds

Validation record, 2026-11-26. Repository at `a5514d8`, local Windows
builds with the SDK's CMake 3.22.1 and Ninja, `apktool_jobs` 8. It records
where the APK build spends its time and whether a clean build reproduces
the accepted `compat` output.

## Stage times

From `.ninja_log` of the accepted build tree, where the four variants were
built at the same time, and from a separate clean build of `compat` alone:

| Stage | Time |
|---|---|
| configure | 15 s |
| decode (apktool d) | 57 s |
| Java shims (javac, d8, smali) | 16 s |
| `apktool b` per variant, four at once | 400 to 2100 s |
| `compat` alone, fresh tree to the unsigned APK | 1618 s |
| `resign` control (align, sign, payload proof) | 209 s |
| test-release sign and verify | 274 s |

`apktool b` spends most of its time compiling the resource table with
aapt2. It rebuilds the whole table each time; there is no incremental path
short of reusing built output.

## Clean build against the accepted build

A second build of `apk-compat-unsigned` in a separate build tree, with its
own decode directory and no state from the first tree:

| Item | Accepted build | Clean build |
|---|---|---|
| `sbc_compat.apk` size | 47243250 | 47243250 |
| `sbc_compat.apk` SHA-256 | `70385aa7...23d65a7` | `fab290cd...0c9e7b` |
| entries | 4309 | 4309 |
| entries with different uncompressed bytes | | 0 |
| entries with a different compression method | | 0 |
| entries differing only in timestamp | | 4309 |
| content digest | `246acc68...d6b836` | `246acc68...d6b836` |
| `libsbxapplogic_ctprotocol_jni.so` | `970d1744...0432d7836` | identical |
| `libserialport_jni.so` | `ca380c7c...8eff232` | identical |

The APK files differ only because apktool records the build time in every
ZIP entry. Their content is identical, and the native libraries are
byte-identical. Equivalence of two builds is therefore defined on content:
`scripts/ci/compare_apks.py`, which compares entry names, order, method and
uncompressed bytes, or its content digest.
