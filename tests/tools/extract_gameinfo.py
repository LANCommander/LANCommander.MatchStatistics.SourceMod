"""Copies what the event research needs out of a dedicated server install.

    python -I extract_gameinfo.py <server-root> <output-dir>

Copies every *events*.res and gameinfo.txt found loose under the server root,
the same files out of every VPK (v1 and v2 directory files), and writes a
listing of the server's binaries (bin/, <mod>/bin/) with each one's ELF/PE
class, so 32/64-bit and Linux/Windows support can be read off.
"""

import os
import re
import struct
import sys

WANTED = re.compile(r"(^|/)(resource/[^/]*events[^/]*\.res|gameinfo\.txt|scripts/[^/]*events[^/]*\.res)$", re.I)


def read_cstring(f):
    data = bytearray()
    while True:
        c = f.read(1)
        if not c or c == b"\0":
            return data.decode("utf-8", "replace")
        data += c


def vpk_entries(dir_path):
    with open(dir_path, "rb") as f:
        signature, version, tree_size = struct.unpack("<III", f.read(12))
        if signature != 0x55AA1234:
            return
        header = 12 if version == 1 else 28
        if version == 2:
            f.read(16)
        while True:
            ext = read_cstring(f)
            if not ext:
                break
            while True:
                path = read_cstring(f)
                if not path:
                    break
                while True:
                    name = read_cstring(f)
                    if not name:
                        break
                    crc, preload, archive, offset, length, terminator = struct.unpack("<IHHIIH", f.read(18))
                    preload_data = f.read(preload)
                    full = (f"{path}/" if path.strip() else "") + f"{name}.{ext}"
                    yield full, preload_data, archive, offset, length, header + tree_size


def extract_vpk(dir_path, out_dir, rel_base):
    base = dir_path[: -len("_dir.vpk")]
    for full, preload, archive, offset, length, data_start in vpk_entries(dir_path):
        if not WANTED.search(full):
            continue
        data = preload
        if length:
            if archive == 0x7FFF:
                source, at = dir_path, data_start + offset
            else:
                source, at = f"{base}_{archive:03d}.vpk", offset
            with open(source, "rb") as f:
                f.seek(at)
                data += f.read(length)
        # By the VPK's path in the install: several mods each have a pak01.
        target = os.path.join(out_dir, "vpk", rel_base, full)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "wb") as out:
            out.write(data)


def binary_class(path):
    with open(path, "rb") as f:
        head = f.read(64)
    if head[:4] == b"\x7fELF":
        return "elf64" if head[4] == 2 else "elf32"
    if head[:2] == b"MZ":
        pe = struct.unpack("<I", head[60:64])[0]
        with open(path, "rb") as f:
            f.seek(pe + 4)
            machine = struct.unpack("<H", f.read(2))[0]
        return {0x14C: "pe32", 0x8664: "pe64"}.get(machine, hex(machine))
    return "?"


def main():
    root, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    binaries = []

    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = os.path.relpath(dirpath, root).replace("\\", "/")
        for name in filenames:
            rel = f"{rel_dir}/{name}" if rel_dir != "." else name
            full = os.path.join(dirpath, name)
            if WANTED.search(rel):
                target = os.path.join(out, "loose", rel)
                os.makedirs(os.path.dirname(target), exist_ok=True)
                with open(full, "rb") as src, open(target, "wb") as dst:
                    dst.write(src.read())
            elif name.endswith("_dir.vpk"):
                try:
                    extract_vpk(full, out, rel[: -len("_dir.vpk")])
                except Exception as error:  # a damaged or unusual VPK: note it, go on
                    binaries.append(f"VPK-ERROR {rel}: {error}")
            if re.search(r"(^|/)bin(/[^/]+)?/(server|engine|dedicated)[^/]*\.(so|dll)$", rel) or \
               re.fullmatch(r"srcds[^/]*", rel):
                binaries.append(f"{binary_class(full)} {rel}")

    with open(os.path.join(out, "binaries.txt"), "w") as listing:
        listing.write("\n".join(sorted(binaries)) + "\n")


if __name__ == "__main__":
    main()
