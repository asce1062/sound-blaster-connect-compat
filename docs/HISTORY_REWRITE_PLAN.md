# History rewrite plan

Status: **PROPOSED, awaiting operator approval.** Nothing below has run.

The repository has never been pushed. Before the first push, its history is
rewritten once so that no published commit carries third-party binaries,
build products, or private metadata. The current HEAD is already clean; the
rewrite carries that state back through every earlier commit.

## Baseline and rollback

- Pre-rewrite state is preserved offline (full-history bundle, LFS payloads,
  stock APK, accepted native libraries, validated APKs, hardware records, all
  SHA-256 listed). The bundle restores every original commit and ref.
- The rewrite runs in a **new clone** in a new directory. The existing working
  repository is not modified, so rollback is "delete the new clone".

## Scope

| Ref | At | Published |
|---|---|---|
| `main` | `4d24356` | yes, after `publish/prep` merges into it |
| `publish/prep` | `f4ad23f` | merged into `main`, then not pushed separately |
| `native/ctprotocol-core` | `4d24356` | no (ancestor of `main`; dropped) |
| an agent working branch (lane C) | `4d24356` | no (dropped) |
| tags | none | n/a |

24 commits, one author identity, no tags.

## Operations (one pass)

1. **Remove paths from every commit**
   - `SBConnect_v1.04.02.apk` (stock APK, third-party; an LFS pointer in Git,
     payload in local LFS storage only)
   - `patches/arm64/overlay/lib/arm64-v8a/libserialport_jni.so`
   - `patches/arm64/overlay/lib/arm64-v8a/libsbxapplogic_ctprotocol_jni.so`

   Introduced by the first commit, the serialport arm64 commit and the
   ctprotocol arm64 packaging commit. Each also carries other changes, so no
   commit becomes empty. Historical `.gitattributes` keeps its LFS lines; they
   no longer match any tracked file.

2. **Redact private values in every historical blob.** The literal patterns
   live in a private replacement list outside the repository. Categories:
   - the test speaker's Bluetooth address (full and partially masked forms),
     replaced with `xx:xx:xx:xx:xx:xx`
   - per-install Android package path tokens, replaced with `<redacted>`
   - a test device serial number, replaced with `<redacted>`
   - user-profile filesystem paths (Android SDK location, a private tools
     folder), replaced with `$ANDROID_SDK_ROOT`, `%LOCALAPPDATA%\Android\Sdk`
     and `<tools>`

   Affected files: `docs/TOOLING.md`, `docs/arm64/ARM64_RUNTIME.md`,
   `docs/arm64/runtime/launch_log_excerpt.txt`, `oracle/run.sh`.

3. **Rewrite author and committer email** on every commit to the operator's
   GitHub noreply address (`<id>+<login>@users.noreply.github.com`). The name
   stays the GitHub login. Dates are kept.

4. **Commit messages**: abbreviated hashes that reference rewritten commits are
   remapped to the new hashes. One merge message names an agent working branch;
   it is reworded to "the modernize-32bit lane branch" (optional, see D4).

## Tool

`git filter-repo` (PyPI `git-filter-repo`, single Python file, MIT) does all
four operations in one pass and writes the old-to-new commit map. It is not
installed on the build machine. The fallback is the built-in
`git filter-branch` (`--index-filter` for removal, `--tree-filter` for
redaction, `--env-filter` for identity, `--msg-filter` for messages), with the
commit map derived from the rewritten refs. Both give the same result on 24
commits.

## Acceptance checks (all must pass before any push)

1. No path matching `*.apk`, `*.so`, `*.jks`, `*.keystore` in any commit.
2. Full-history search for every private pattern returns zero matches.
3. `git log --format='%ae %ce'` lists only the noreply address.
4. The rewritten HEAD tree hash equals the pre-rewrite HEAD tree hash (HEAD is
   already clean, so the rewrite must not change it).
5. Clean configure + `apk-arm64` from the rewritten clone, with the stock APK
   supplied as a local input, reproduces the same native library hashes.
6. No Git LFS hooks or LFS objects in the new clone.
7. Old-to-new commit map stored privately next to the baseline, not in the
   repository.

## After the rewrite

- Documents that cite short commit hashes (for example
  `docs/arm64/ARM64_BUILD.md`, `docs/arm64/CHECKPOINT.md`) still name the old
  hashes; a follow-up commit updates them from the commit map.
- The first push goes to the private upstream only, `main` only, on explicit
  operator instruction. Public visibility is a separate operator action.
- The pre-rewrite working repository is retired once the new clone is
  accepted. Its history must never be pushed.

## Operator decisions

- **D1** Approve this plan.
- **D2** Noreply address: GitHub, Settings, Emails, the
  `<id>+<login>@users.noreply.github.com` form.
- **D3** Tool: install `git-filter-repo` (recommended) or use `git filter-branch`.
- **D4** Reword the merge message that names the agent working branch: yes/no.
- **D5** The historical `docs/TOOLING.md` also names two unrelated private
  sibling projects; replace those names with "a sibling project": yes/no.
