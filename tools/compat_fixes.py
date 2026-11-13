#!/usr/bin/env python3
"""Reproduce the compatibility fixes applied to the portable build.

Neither fix changes what the program *means*; each works around behaviour that did
not exist (or was never exercised) in 2001.

1. images  - re-encode the RLE8 skin bitmaps as uncompressed BI_RGB.
             The player loads its skin with LoadImage(LR_LOADFROMFILE), which
             fails on RLE-compressed bitmaps on current Windows, producing
             "Failed to open control image". Pixels and palette are preserved.

2. exe     - two independent patches on the unpacked player:
             a) the import thunk for auxGetNumDevs returns 0. On current Windows
                the legacy MME "aux" path inside winmmbase crashes (GlobalLock on
                a stale 16-bit handle -> AV at winmmbase+0x5ab3), so reporting
                "no aux devices" is both correct and safer; the player falls back
                to its waveOut volume path.
             b) the video-only UI block at 0x0047d4f1 is gated on the video
                interface stored at this+0x0A58. With no video stream that field
                is NULL, and the block dereferences it unguarded
                (mov eax,[eax] at 0x0047d540, then call [eax+0x28]), which is the
                "Unexpected Error (Access violation at address 0047D540 ... Read
                of address 00000000)" seen for every audio-only file. The gate
                skips the block when the interface is absent.

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

# --- gate for the video-only UI block ---------------------------------------
# The block starts at 0x47d4f1 with "push 0x480088; mov eax,[ebp-8];
# mov eax,[eax+0xa58]; push eax; ...". Replacing the push with a jump into a stub
# lets the stub test the interface first, keep the original push order, and fall
# into the block's own "no video" path when the field is NULL.
GATE_VA = 0x47D4F1
GATE_EXPECTED = bytes.fromhex('68 88 00 48 00')     # push 0x480088
GATE_CONTINUE_VA = 0x47D500                          # block body (after the two pushes)
GATE_NOVIDEO_VA = 0x47D4DB                           # the branch taken when the block is skipped
CAVE_RVA = 0x97F00                                   # zero padding at the end of CODE
CAVE_SIZE = 32



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
    """Write an 8bpp BI_RGB BMP.

    ``pixels`` is top-down (row 0 = top). A BMP with a positive height stores
    rows bottom-up, so the rows are emitted in reverse; getting this wrong
    renders the whole image upside down.
    """
    rows = abs(height)
    stride = (width + 3) & ~3
    body = bytearray()
    for r in range(rows - 1, -1, -1):
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
def _rel32(after_va, target_va):
    return struct.pack('<i', target_va - after_va)


def apply_video_gate(pe, data):
    """Make the video-only UI block skip itself when there is no video stream.

    The block assumes the interface at this+0x0A58 exists. For an audio-only graph
    it is NULL and the block dereferences it, which is the 0x47D540 crash. The
    gate keeps the block's own "no video" path intact: the stub tests the field
    before pushing the second argument and jumps to GATE_NOVIDEO_VA when it is
    absent, dropping the argument it had already pushed so the stack stays
    balanced.
    """
    sections = {s.Name.rstrip(b'\x00'): s for s in pe.sections}
    code, data_section = sections.get(b'CODE'), sections.get(b'DATA')
    if code is None or data_section is None:
        raise SystemExit('unexpected sections: %s' % [s.Name for s in pe.sections])

    cave_va = IMAGE_BASE + CAVE_RVA
    gate_off = pe.get_offset_from_rva(GATE_VA - IMAGE_BASE)
    cave_off = pe.get_offset_from_rva(CAVE_RVA)

    actual = bytes(data[gate_off:gate_off + len(GATE_EXPECTED)])
    if actual != GATE_EXPECTED:
        raise SystemExit('unexpected bytes at VA 0x%x: %s (input already patched?)'
                         % (GATE_VA, actual.hex(' ')))
    if set(data[cave_off:cave_off + CAVE_SIZE]) != {0}:
        raise SystemExit('code cave at VA 0x%x is not empty' % cave_va)

    stub = bytearray()
    stub += GATE_EXPECTED                                     # push 0x480088 (arg 1)
    stub += bytes.fromhex('8b 45 f8')                         # mov eax,[ebp-8]
    stub += bytes.fromhex('8b 80 58 0a 00 00')                # mov eax,[eax+0xa58]
    stub += bytes.fromhex('85 c0')                            # test eax,eax
    stub += bytes.fromhex('74 06')                            # jz  .no_video
    stub += bytes.fromhex('50')                               # push eax (arg 2)
    stub += b'\xe9' + _rel32(cave_va + 24, GATE_CONTINUE_VA)  # jmp block body
    stub += bytes.fromhex('83 c4 04')                         # .no_video: add esp,4
    stub += b'\xe9' + _rel32(cave_va + 32, GATE_NOVIDEO_VA)   # jmp skip path
    if len(stub) != CAVE_SIZE:
        raise SystemExit('stub size %d != %d' % (len(stub), CAVE_SIZE))
    if stub[16 + 2 + 6] != 0x83:      # the jz must land on "add esp,4"
        raise SystemExit('gate stub is misaligned')

    data[cave_off:cave_off + CAVE_SIZE] = stub
    data[gate_off:gate_off + 5] = b'\xe9' + _rel32(GATE_VA + 5, cave_va)

    # The cave sits in the CODE section's zero padding, past its VirtualSize, and
    # the loader zero-fills what the section does not claim. Grow VirtualSize up
    # to the next section so those bytes are mapped (and executable).
    header = pe.DOS_HEADER.e_lfanew + 0x18 + pe.FILE_HEADER.SizeOfOptionalHeader
    index = list(pe.sections).index(code)
    new_vsize = data_section.VirtualAddress - code.VirtualAddress
    struct.pack_into('<I', data, header + index * 40 + 8, new_vsize)
    return cave_va, new_vsize


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
    cave_va, new_vsize = apply_video_gate(pe, data)
    with open(dst, 'wb') as fh:
        fh.write(bytes(data))

    print('patched auxGetNumDevs thunk')
    print('  VA  0x%08x (file offset 0x%x)' % (THUNK_VA, off))
    print('  was %s  (jmp dword ptr [0x49b908])' % THUNK_EXPECTED.hex(' '))
    print('  now %s  (xor eax,eax; ret; nop; nop; nop)' % THUNK_REPLACEMENT.hex(' '))
    print('gated the video-only UI block')
    print('  gate VA 0x%08x -> stub VA 0x%08x (CODE VirtualSize now 0x%x)'
          % (GATE_VA, cave_va, new_vsize))
    print('  skips to VA 0x%08x when this+0x0A58 is NULL' % GATE_NOVIDEO_VA)
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
