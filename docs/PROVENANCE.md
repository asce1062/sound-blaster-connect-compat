# Provenance

Where the contents of this repository come from, what they are derived from,
and what the published history does and does not contain.

## Contents by origin

| Contents | Origin |
|---|---|
| Build scripts (`CMakeLists.txt`, `cmake/`), patch scripts, shim classes in `patches/modernize/overlay/`, tests, documentation | Written for this project. |
| Native reimplementation (`patches/arm64/native/`) | Written for this project to reproduce the observable behavior of the stock 32-bit libraries, established by analysis of those libraries and differential testing against them ([research index](research/README.md)). |
| Test vectors (`oracle/vectors/`) | Inputs written for this project; the expected outputs are the stock library's outputs for those inputs. |
| Identifiers in patches and the harness (class, method, field and native-method names, smali match strings) | The stock app's identifiers, used to bind to it. |
| Stock APK, its code, resources and native libraries | Creative's software. Not in this repository; supplied by the user at build time. |

The MIT license in [LICENSE](../LICENSE) covers this project's original
contributions. It grants no rights in the stock app, its identifiers or
Creative's trademarks. The scope of each category above is subject to an open
provenance review; until it concludes, the categories derived from the stock
app are not represented as the project's own work.

## Published history

The history was rewritten once, before the first publication, so that no
published commit contains:

- the stock APK or any other third-party binary;
- prebuilt native libraries or other build products;
- private metadata (device serials and addresses, user-profile paths, personal
  email addresses).

The rewrite did not change the tree at its tip, commit `87d980a`. Commit
hashes cited in [research records](research/README.md) are rewritten hashes
of the same commits. A fresh clone builds every variant; the arm64 native
libraries and all 4,312 entries of the arm64 APK are byte-identical to the
build from before the rewrite. The detailed rewrite records and an
old-to-new commit map are kept privately with an offline baseline of the
pre-rewrite repository.

## Evidence limits

Hardware results cited in `docs/` were obtained on the commits they name. Raw
runtime logs from the October 2026 hardware sessions were not preserved; the
records keep the excerpts and summaries made at the time. No later log stands
in for them.
