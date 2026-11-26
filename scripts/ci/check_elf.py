#!/usr/bin/env python3
"""Check built native libraries against tests/native/expected_abi.json.

For each library in a build output directory, checks:
  - ELF class and machine of the ABI;
  - every PT_LOAD segment's p_align against the ABI's minimum (16 KiB for
    64-bit ABIs, 4 KiB for 32-bit);
  - DT_NEEDED entries, exactly;
  - the exported dynamic symbols (JNI_OnLoad and the Java_* methods), exactly;
  - the SHA-256, when the expectation file records accepted hashes for the ABI.

Usage: check_elf.py <abi> <lib-dir> [--expected tests/native/expected_abi.json]
       check_elf.py --dump <file.so>   print the facts above as JSON
Exit status 0 when every check passes, 1 otherwise. Standard library only.
"""
import argparse
import hashlib
import json
import os
import struct
import sys

EM_NAMES = {3: "x86", 40: "arm", 62: "x86_64", 183: "aarch64"}
PT_LOAD = 1
PT_DYNAMIC = 2
DT_NULL = 0
DT_NEEDED = 1
DT_STRTAB = 5
SHT_DYNSYM = 11


class Elf:
    def __init__(self, path):
        with open(path, "rb") as f:
            self.data = f.read()
        d = self.data
        if d[:4] != b"\x7fELF":
            raise ValueError(f"{path}: not an ELF file")
        self.is64 = d[4] == 2
        if d[5] != 1:
            raise ValueError(f"{path}: not little-endian")
        self.machine = struct.unpack_from("<H", d, 18)[0]
        if self.is64:
            (self.phoff, self.shoff) = struct.unpack_from("<QQ", d, 32)
            (self.phentsize, self.phnum, self.shentsize, self.shnum) = struct.unpack_from("<HHHH", d, 54)
        else:
            (self.phoff, self.shoff) = struct.unpack_from("<II", d, 28)
            (self.phentsize, self.phnum, self.shentsize, self.shnum) = struct.unpack_from("<HHHH", d, 42)

    def phdrs(self):
        for i in range(self.phnum):
            o = self.phoff + i * self.phentsize
            if self.is64:
                p_type, _flags, p_offset, p_vaddr, _pa, p_filesz, _memsz, p_align = struct.unpack_from("<IIQQQQQQ", self.data, o)
            else:
                p_type, p_offset, p_vaddr, _pa, p_filesz, _memsz, _flags, p_align = struct.unpack_from("<IIIIIIII", self.data, o)
            yield p_type, p_offset, p_vaddr, p_filesz, p_align

    def shdrs(self):
        for i in range(self.shnum):
            o = self.shoff + i * self.shentsize
            if self.is64:
                (_name, sh_type, _flags, _addr, sh_offset, sh_size, sh_link, _info, _align, sh_entsize) = struct.unpack_from("<IIQQQQIIQQ", self.data, o)
            else:
                (_name, sh_type, _flags, _addr, sh_offset, sh_size, sh_link, _info, _align, sh_entsize) = struct.unpack_from("<IIIIIIIIII", self.data, o)
            yield sh_type, sh_offset, sh_size, sh_link, sh_entsize

    def cstr(self, off):
        end = self.data.index(b"\0", off)
        return self.data[off:end].decode("ascii")

    def vaddr_to_offset(self, vaddr):
        for p_type, p_offset, p_vaddr, p_filesz, _ in self.phdrs():
            if p_type == PT_LOAD and p_vaddr <= vaddr < p_vaddr + p_filesz:
                return vaddr - p_vaddr + p_offset
        raise ValueError(f"vaddr {vaddr:#x} not in a LOAD segment")

    def needed(self):
        dyn = [p for p in self.phdrs() if p[0] == PT_DYNAMIC]
        if not dyn:
            return []
        _, off, _, size, _ = dyn[0]
        fmt, step = ("<qQ", 16) if self.is64 else ("<iI", 8)
        entries = []
        strtab = None
        for i in range(size // step):
            tag, val = struct.unpack_from(fmt, self.data, off + i * step)
            if tag == DT_NULL:
                break
            if tag == DT_STRTAB:
                strtab = self.vaddr_to_offset(val)
            entries.append((tag, val))
        return [self.cstr(strtab + v) for t, v in entries if t == DT_NEEDED]

    def exported(self):
        shdrs = list(self.shdrs())
        names = []
        for sh_type, sh_offset, sh_size, sh_link, sh_entsize in shdrs:
            if sh_type != SHT_DYNSYM:
                continue
            str_off = shdrs[sh_link][1]
            for i in range(sh_size // sh_entsize):
                o = sh_offset + i * sh_entsize
                if self.is64:
                    st_name, st_info, _other, st_shndx = struct.unpack_from("<IBBH", self.data, o)
                else:
                    st_name, _value, _size, st_info, _other, st_shndx = struct.unpack_from("<IIIBBH", self.data, o)
                bind = st_info >> 4
                if st_shndx != 0 and bind in (1, 2) and st_name:
                    names.append(self.cstr(str_off + st_name))
        return sorted(names)


def facts(path):
    e = Elf(path)
    loads = [p for p in e.phdrs() if p[0] == PT_LOAD]
    with open(path, "rb") as f:
        sha = hashlib.sha256(f.read()).hexdigest()
    return {
        "class": 64 if e.is64 else 32,
        "machine": EM_NAMES.get(e.machine, str(e.machine)),
        "min_load_align": min(p[4] for p in loads),
        "needed": e.needed(),
        "exports": e.exported(),
        "sha256": sha,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("abi", nargs="?")
    ap.add_argument("libdir", nargs="?")
    ap.add_argument("--expected", default=os.path.join(os.path.dirname(__file__), "..", "..", "tests", "native", "expected_abi.json"))
    ap.add_argument("--dump")
    a = ap.parse_args()
    if a.dump:
        print(json.dumps(facts(a.dump), indent=2))
        return 0
    if not a.abi or not a.libdir:
        ap.error("abi and libdir are required")
    with open(a.expected, encoding="utf-8") as f:
        exp = json.load(f)
    abi = exp["abis"].get(a.abi)
    if abi is None:
        print(f"FAIL {a.abi}: no expectation for this ABI")
        return 1
    failures = 0
    for lib, lexp in exp["libraries"].items():
        path = os.path.join(a.libdir, lib)
        if not os.path.isfile(path):
            print(f"FAIL {lib}: missing in {a.libdir}")
            failures += 1
            continue
        got = facts(path)
        checks = [
            ("class", got["class"] == abi["class"], f"{got['class']} want {abi['class']}"),
            ("machine", got["machine"] == abi["machine"], f"{got['machine']} want {abi['machine']}"),
            ("load alignment", got["min_load_align"] >= abi["min_load_align"], f"{got['min_load_align']:#x} want >= {abi['min_load_align']:#x}"),
            ("needed", got["needed"] == lexp["needed"], f"{got['needed']} want {lexp['needed']}"),
            ("exports", got["exports"] == sorted(lexp["exports"]), f"{len(got['exports'])} symbols want {len(lexp['exports'])}"),
        ]
        accepted = abi.get("accepted_sha256", {}).get(lib)
        if accepted:
            checks.append(("accepted sha256", got["sha256"] == accepted, f"{got['sha256']} want {accepted}"))
        for name, ok, detail in checks:
            print(f"{'ok  ' if ok else 'FAIL'} {a.abi}/{lib} {name}: {detail}")
            failures += 0 if ok else 1
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
