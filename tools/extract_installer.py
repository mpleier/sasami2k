#!/usr/bin/env python3
"""Extract the InstallFactory archive embedded in original/sasami2k_757.exe.

The installer is a self-extracting InstallFactory v2.60 archive. Each member is
an "IFFH" record:

    "IFFH" | u32 unpacked size | u32 packed size | u32 CRC32 | u32 DOS time
           | 8 bytes flags | u8 name length | name | raw-deflate payload

Every record is inflated and verified against its declared size and CRC32.

Usage:
    python tools/extract_installer.py [installer.exe] [output-dir]
"""

import os
import struct
import sys
import zlib


def iter_records(data):
    i = 0
    while True:
        j = data.find(b'IFFH', i)
        if j < 0:
            return
        i = j + 1
        if j + 29 > len(data):
            return
        unpacked, packed, crc, dostime = struct.unpack_from('<IIII', data, j + 4)
        namelen = data[j + 28]
        if not 1 <= namelen <= 120:
            continue
        raw = data[j + 29:j + 29 + namelen]
        dataoff = j + 29 + namelen
        if not raw or any(c < 0x20 or c > 0x7e for c in raw):
            continue
        if packed == 0 or dataoff + packed > len(data):
            continue
        yield raw.decode('ascii'), unpacked, packed, crc, dostime, dataoff


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join('original', 'sasami2k_757.exe')
    dst = sys.argv[2] if len(sys.argv) > 2 else 'build'
    data = open(src, 'rb').read()

    count = 0
    failures = 0
    for name, unpacked, packed, crc, dostime, off in iter_records(data):
        blob = data[off:off + packed]
        try:
            out = zlib.decompressobj(-15).decompress(blob, unpacked + 65536)
        except Exception as exc:                      # noqa: BLE001
            print('FAIL %-38s %s' % (name, exc))
            failures += 1
            continue

        ok = len(out) == unpacked and (zlib.crc32(out) & 0xffffffff) == crc
        rel = name.replace('\\', '/')
        if rel.startswith('Src/'):
            rel = rel[4:]
        else:
            rel = '_meta/' + rel

        path = os.path.join(dst, rel)
        parent = os.path.dirname(path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(path, 'wb') as fh:
            fh.write(out)

        count += 1
        if not ok:
            failures += 1
        print('%s %-38s %8d bytes  crc=%08x' % ('OK  ' if ok else 'BAD ', name, len(out), crc))

    print('\n%d records extracted, %d failures' % (count, failures))
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
