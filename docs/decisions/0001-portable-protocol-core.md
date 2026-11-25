# 0001. Keep all protocol behavior in a portable, JNI-free C core

Status: Accepted

## Context

The stock app talks to the speaker through `libsbxapplogic_ctprotocol_jni.so`,
a 32-bit native library that encodes command frames and decodes responses.
64-bit-only phones cannot load it, so the arm64 variant needs a replacement.
The replacement has to be checked against the stock library, which only runs
on a 32-bit Android runtime, and it also has to run on arm64 devices.

## Decision

All encoding and decoding logic lives in `patches/arm64/native/ctprotocol/core/`:
C11, standard headers only, no JNI, no allocation, no mutable global state,
no OS calls. A thin adapter in `ctprotocol/jni/` marshals Java arrays into core calls
and turns decoded events into cached Java callbacks.

## Consequences

- The same core source builds for x86 (oracle harness), arm64 (the app) and
  any desktop host (`tests/ctprotocol/`), so the protocol can be tested
  without Android.
- The JNI adapter is the only code that differs between the test driver and
  the shipped library; its marshalling is small and reproduced in the host
  driver.
- A future first-party app on another platform can reuse the core directly.

See [CTPROTOCOL.md](../technical/CTPROTOCOL.md) and
[JNI_INTERFACE.md](../technical/JNI_INTERFACE.md).
