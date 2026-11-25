# History rewrite

Status: **EXECUTED 2026-11-25**, before the first push. This file records what
the one-time pre-publication rewrite did and what it checked.

Every commit in this repository was rewritten once so that no published commit
carries third-party binaries, build products or private metadata. The tree at
the rewritten tip is byte-identical to the tree at the pre-rewrite tip; only
history changed. Commit hashes in this repository therefore differ from those
in earlier private records; an old-to-new commit map is kept privately with the
offline baseline, not in the repository.

The rewrite adds no runtime evidence. Hardware validation results cited in
`docs/` were obtained on the pre-rewrite commits they name (those citations now
use the rewritten hashes of the same commits) and the APK and library hashes
they record are unchanged. Raw runtime logs from the October 2026 sessions were
not preserved; `docs/` keeps the recorded excerpts and summaries only.

## Baseline and rollback

- Pre-rewrite state is preserved offline: full-history bundle, LFS payloads,
  stock APK, accepted native libraries, validated APKs and hardware records,
  all listed with SHA-256. The bundle restores every original commit and ref.
- The rewrite ran in a new clone in a new directory. The pre-rewrite repository
  was not modified and stays offline as the research and evidence archive. Its
  history is never merged or pushed into this repository.

## Scope

The rewrite took one branch, `publish/prep` (26 commits: 23 baseline commits
plus 3 preparation commits), and published it as `main`. All other branches of
the pre-rewrite repository (`main` and `native/ctprotocol-core`, both ancestors
of `publish/prep`, and an agent working branch) were left out. There were no
tags. One author identity.

## Operations (one pass)

1. **Removed from every commit**:
   - `SBConnect_v1.04.02.apk` (stock APK, third-party; an LFS pointer in Git)
   - `patches/arm64/overlay/lib/arm64-v8a/libserialport_jni.so`
   - `patches/arm64/overlay/lib/arm64-v8a/libsbxapplogic_ctprotocol_jni.so`

   Each introducing commit also carried other changes, so no commit became
   empty. The Git LFS tracking rules and their comments were removed from every
   historical `.gitattributes`; the repository has no Git LFS dependency.

2. **Redacted in every historical blob**, from a private replacement list kept
   outside the repository:
   - the test speaker's Bluetooth address (full and partially masked forms),
     replaced with `xx:xx:xx:xx:xx:xx`
   - per-install Android package path tokens, replaced with `<redacted>`
   - a test device serial number, replaced with `<redacted>`
   - user-profile filesystem paths (Android SDK location, a private tools
     folder), replaced with `$ANDROID_SDK_ROOT`, `%LOCALAPPDATA%\Android\Sdk`
     and `<tools>`
   - names of unrelated private sibling projects, replaced with generic
     wording

3. **Author and committer email** on every commit rewritten to the
   maintainer's GitHub noreply address. Names and dates are unchanged.

4. **Commit messages**: abbreviated hashes that reference rewritten commits
   were remapped to the new hashes. A merge message that named an agent working
   branch now reads "the modernize-32bit lane branch"; sibling project names in
   messages were replaced as in step 2.

## Tool

`git filter-repo` 2.47.0 (PyPI `git-filter-repo`, wheel SHA-256
`2cd04929b9024e83e65db571cbe36aec65ead0cb5f9ec5abe42158654af5ad83`) with
`--invert-paths`, `--replace-text`, `--replace-message`, `--mailmap` and
`--replace-refs delete-no-add`, followed by reflog expiry and
`git gc --prune=now --aggressive`.

## Acceptance checks

All passed on the rewritten repository:

1. Only `refs/heads/main`; no tags, stash, `refs/original`, `refs/replace` or
   filter-repo state.
2. The tip tree hash equals the pre-rewrite tip tree hash
   (`a76837f700f7834a7c713179ac70f0c64f8737ef`).
3. No path matching `*.apk`, `*.aab`, `*.so`, `*.jks`, `*.keystore`, `*.p12`
   or `*.pk8` in any commit.
4. Zero matches for every private, LFS or agent-branch pattern across all
   objects in the object database (blobs, trees, commit metadata and messages).
5. One author and committer identity, the noreply address.
6. No unreachable objects; `git fsck --full --strict` clean.
7. No hooks and no `.git/lfs` store.
8. Commit count, author names, dates, subjects and graph shape (parent counts)
   identical to the pre-rewrite branch.
9. A fresh clone with the stock APK supplied as a local input configures and
   builds every variant. The arm64 native libraries hash to the accepted
   from-source values, and the arm64 APK's 4,312 entries are byte-identical to
   the pre-rewrite build. Missing and wrong APK inputs fail at configure with
   the documented messages.
10. Encoder and decoder regressions against the frozen vectors in
    `oracle/vectors/` pass, on the 32-bit x86 emulator (stock and
    reimplementation libraries, byte-identical output) and on the host.
