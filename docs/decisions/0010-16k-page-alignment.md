# 0010. Align 64-bit native libraries to 16 KiB with a linker flag

Status: Accepted

## Context

64-bit Android devices may use 16 KiB memory pages, and from Android 15 their
loader refuses a library whose `PT_LOAD` segments are aligned to less than
the page size. The pinned NDK r25b
([0004](0004-native-from-pinned-source.md)) aligns to 4 KiB by default. Newer
NDKs default to 16 KiB, but changing the NDK would change the compiler and
every generated instruction.

## Decision

Link the 64-bit ABIs with `-Wl,-z,max-page-size=16384`. Keep the NDK pin and
the source unchanged. 32-bit ABIs, including the x86 oracle build, keep the
default.

## Consequences

- Both arm64 libraries get new accepted hashes (`970d1744...`,
  `ca380c7c...`). Against the 4 KiB build, only segment addresses, the `adrp`
  page offsets that reach them, relocation and dynamic tables, and the build
  id differ.
- The x86 oracle build is byte-identical to the one the differential ran, so
  the oracle results still apply.
- A 16 KiB-aligned library is valid on 4 KiB and 16 KiB pages alike. These
  libraries run on 4 KiB-page phones (Pixel 8, Galaxy S24 Ultra, API 37);
  no 16 KiB-page arm64 phone has run them.
- A later NDK upgrade can drop the flag; it is then the default.

Detail: [NATIVE_LIBRARIES.md](../technical/NATIVE_LIBRARIES.md#16-kib-page-size).
