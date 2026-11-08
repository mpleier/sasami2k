#!/usr/bin/env python3
"""Reproduce the two compatibility fixes applied to the portable build.

Neither fix changes what the program does; both work around Windows behaviour
that did not exist in 2001.

1. images  - re-encode the RLE8 skin bitmaps as uncompressed BI_RGB.
             The player loads its skin with LoadImage(LR_LOADFROMFILE), which
             fails on RLE-compressed bitmaps on current Windows, producing
             "Failed to open control image". Pixels and palette are preserved.

2. exe     - patch the import thunk for auxGetNumDevs so it returns 0.
             On current Windows the legacy MME "aux" path inside winmmbase
             crashes (GlobalLock on a stale 16-bit handle -> AV at
             winmmbase+0x5ab3) whenever an application calls auxGetNumDevs.
             Reporting "no aux devices" is the correct answer on modern
             Windows and lets the player fall back to its waveOut volume path.

Usage:
    python tools/compat_fixes.py images <src-dir> <dst-dir>
    python tools/compat_fixes.py exe    <in.exe>  <out.exe>
"""

import os
import struct
import sys

# --- auxGetNumDevs import thunk in the unpacked player -----------------------
# VA 0x44d294 holds "jmp dword ptr [0x49b908]"; replace with xor eax,eax; ret.
THUNK_VA = 0x44D294
THUNK_EXPECTED = bytes.fromhex('ff 25 08 b9 49 00')
THUNK_REPLACEMENT = bytes.fromhex('33 c0 c3 90 90 90')
IMAGE_BASE = 0x400000


# --------------------------------------------------------------------------
# BMP helpers (8bpp only; enough for these skin files)
# --------------------------------------------------------------------------
def read_bmp(path):
    data = open(path, 'rb').read()
    if data[:2] != b'BM':
        raise ValueError('%s is not a BMP' % path)
    dataoff = struct.unpack_from('<I', data, 10)[0]
    hdrsize = struct.unpack_from('<I', data, 14)[0]
    width, height = struct.unpack_from('<ii', data, 18)
    bpp = struct.unpack_from('<H', data, 28)[0]
    compression = struct.unpack_from('<I', data, 30)[0]
    colors = struct.unpack_from('<I', data, 46)[0] if hdrsize >= 40 else 0
    ncolors = colors or ((1 << bpp) if bpp <= 8 else 0)
    palette = data[14 + hdrsize:14 + hdrsize + 4 * ncolors]
    return data, width, height, bpp, compression, dataoff, palette


def decode_rle8(data, width, height, dataoff):
    rows = abs(height)
    bottom_up = height > 0
    pixels = bytearray(width * rows)
    x = y = 0
    i = dataoff
    while i + 1 < len(data):
        count, value = data[i], data[i + 1]
        i += 2
        if count > 0:
            for _ in range(count):
                if 0 <= x < width and 0 <= y < rows:
                    pixels[y * width + x] = value
                x += 1
        elif value == 0:                       # end of line
            x = 0
            y += 1
        elif value == 1:                       # end of bitmap
            break
        elif value == 2:                       # delta
            dx, dy = data[i], data[i + 1]
            i += 2
            x += dx
            y += dy
        else:                                  # absolute mode
            n = value
            for k in range(n):
                if i + k < len(data):
                    if 0 <= x < width and 0 <= y < rows:
                        pixels[y * width + x] = data[i + k]
                    x += 1
            i += n
            if n & 1:
                i += 1
    ordered = bytearray(width * rows)
    for r in range(rows):
        src = (rows - 1 - r) if bottom_up else r
        ordered[r * width:(r + 1) * width] = pixels[src * width:(src + 1) * width]
    return bytes(ordered)


def write_bmp(path, width, height, palette, pixels):
    rows = abs(height)
    stride = (width + 3) & ~3
    body = bytearray()
    for r in range(rows):
        body += pixels[r * width:(r + 1) * width]
        body += b'\x00' * (stride - width)
    palette = palette.ljust(1024, b'\x00')[:1024]
    offbits = 14 + 40 + len(palette)
    file_hdr = b'BM' + struct.pack('<IHHI', offbits + len(body), 0, 0, offbits)
    info_hdr = struct.pack('<IiiHHIIiiII', 40, width, rows, 1, 8, 0,
                           len(body), 2835, 2835, len(palette) // 4, 0)
    with open(path, 'wb') as fh:
        fh.write(file_hdr + info_hdr + palette + bytes(body))


def fix_images(src_dir, dst_dir):
    os.makedirs(dst_dir, exist_ok=True)
    changed = 0
    for name in sorted(os.listdir(src_dir)):
        if not name.lower().endswith('.bmp'):
            continue
        src = os.path.join(src_dir, name)
        dst = os.path.join(dst_dir, name)
        data, width, height, bpp, compression, dataoff, palette = read_bmp(src)
        if compression == 1 and bpp == 8:
            pixels = decode_rle8(data, width, height, dataoff)
            write_bmp(dst, width, height, palette, pixels)
            print('re-encoded %-28s %dx%d  BI_RLE8 -> BI_RGB  %d -> %d bytes'
                  % (name, width, height, len(data), os.path.getsize(dst)))
            changed += 1
        else:
            with open(dst, 'wb') as fh:
                fh.write(data)
            print('kept       %-28s compression=%d' % (name, compression))
    print('\n%d bitmap(s) re-encoded' % changed)


# --------------------------------------------------------------------------
def fix_exe(src, dst):
    import pefile                                   # noqa: PLC0415

    pe = pefile.PE(src)
    rva = THUNK_VA - IMAGE_BASE
    off = pe.get_offset_from_rva(rva)
    data = bytearray(open(src, 'rb').read())

    actual = bytes(data[off:off + len(THUNK_EXPECTED)])
    if actual != THUNK_EXPECTED:
        raise SystemExit('unexpected bytes at VA 0x%x: %s (input already patched?)'
                         % (THUNK_VA, actual.hex(' ')))

    data[off:off + len(THUNK_REPLACEMENT)] = THUNK_REPLACEMENT
    with open(dst, 'wb') as fh:
        fh.write(bytes(data))

    print('patched auxGetNumDevs thunk')
    print('  VA  0x%08x (file offset 0x%x)' % (THUNK_VA, off))
    print('  was %s  (jmp dword ptr [0x49b908])' % THUNK_EXPECTED.hex(' '))
    print('  now %s  (xor eax,eax; ret; nop; nop; nop)' % THUNK_REPLACEMENT.hex(' '))
    print('  written: %s' % dst)


def main(argv):
    if len(argv) >= 4 and argv[1] == 'images':
        fix_images(argv[2], argv[3])
        return 0
    if len(argv) >= 4 and argv[1] == 'exe':
        fix_exe(argv[2], argv[3])
        return 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
