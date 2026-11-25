# Contributing

## Ground rules

- **Protocol behavior is frozen.** The CtProtocol encoder and decoder in
  `patches/arm64/native/ctprotocol/` reproduce the stock library. The vector
  files in `oracle/vectors/` are the contract and are never edited. A change
  to the core must keep every vector set passing on the host
  ([TESTING.md](docs/development/TESTING.md)); a change that alters an output
  line is a behavior change, not a fix, and needs a new research record and
  oracle capture first.
- **Stock quirks are kept.** Behavior that looks wrong but matches the stock
  library (over-reads of a zeroed buffer, unreachable checks, lossy
  truncations) stays, with a comment saying it is preserved on purpose.
- **Patches anchor on 1.04.02.** Every edit in a `patch.cmake` asserts how
  many times its anchor occurs. Keep that assertion when adding an edit.
- **No stock binaries.** Never commit the stock APK, its libraries, extracted
  resources, or built APKs. `.gitignore` covers the usual paths.
- **The native toolchain is pinned.** Change the NDK revision only together
  with a recorded comparison of the resulting libraries.

## Where things are written

Each kind of writing has one home:

- **Git history** records how the software evolved.
- **Research records** (`docs/research/`) explain how behavior was
  established.
- **Source comments** explain why the current implementation works as it
  does.
- **Technical documentation** (`docs/technical/`) describes the contracts that
  future implementations must preserve.

Decisions with lasting consequences go in `docs/decisions/` as an ADR. User
instructions go in `docs/user/`, build and test instructions in
`docs/development/`.

Research records are historical. Do not rewrite them to match later changes;
add an entry to the errata table in
[docs/research/README.md](docs/research/README.md) instead.

## Writing standards

- **State the fact, not the discovery.** Write "The decoder reads three bytes
  past a short frame", not "We found that the decoder reads...". Describe what
  is true, not how it was found or which work item found it.
- **Mark the basis of every claim** in technical documentation: reproduced by
  a vector, read from code, observed on a device, or expected from platform
  documentation. Do not present an expectation as an observation.
- **No guarantees the evidence does not support.** "Matches the stock library
  on the vectors in `dec_valid.txt`" is a fact; "always matches the stock
  library" is not.
- **Comments describe contracts.** Public C functions and types get Doxygen
  blocks (`/** @brief ... */`) with parameters, return values including the
  error value, and preconditions such as buffer sizes. Reverse-engineering
  addresses (`FUN_...`, raw offsets) may appear only as a labelled provenance
  note after a behavioral description.
- **Plain punctuation.** No em or en dashes. No `--` inside XML comments.
- **Paths are clickable.** Reference files with relative Markdown links that
  resolve from the document's own directory.

## Commits

Commits follow [Conventional Commits](https://www.conventionalcommits.org/):
`type(scope): summary`, with types such as `feat`, `fix`, `docs`, `test`,
`build`, `chore` and `refactor`. A change that affects behavior or spans
several files gets a body explaining what changed and why.

## Before opening a pull request

- Host regression tests pass:
  `cmake -S tests/ctprotocol -B build/host-tests && cmake --build build/host-tests && ctest --test-dir build/host-tests`.
- If you touched the native source, the emulator differential still passes,
  or say in the pull request that you could not run it.
- If you touched the pipeline or a patch, `cmake --build --preset apks`
  succeeds with the pinned input.
- Documentation you changed has working relative links.
