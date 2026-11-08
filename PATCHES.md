# Compatibility fixes

The 2001 payload does not run unmodified on Windows 10/11: it fails twice during
startup, before the main window is shown. Both failures are environmental, not
application logic, and both are fixed here with the smallest possible change.

Everything is reproducible with `tools/extract_installer.py` and
`tools/compat_fixes.py`; `original/` keeps the untouched binaries.

| Artifact | Shipped state | Portable build |
|---|---|---|
| `app/sasami2000.exe` | UPX-packed, stock | unpacked + one 6-byte import-thunk patch |
| `app/Imgs/*.bmp` | 7 of 8 are BI_RLE8 | re-encoded to BI_RGB, same palette/pixels |
| everything else | unchanged | unchanged |

---

## Fix 1 — skin bitmaps (`BI_RLE8` → `BI_RGB`)

**Symptom:** at startup, a dialog titled *Error Occured* saying
*"Failed to open control image, re-install recommended."*, main window never
appears.

**Cause:** the player loads its skin with `LoadImage(..., LR_LOADFROMFILE)`
(Delphi VCL `TBitmap.LoadFromFile`). Current Windows rejects RLE-compressed BMPs
in that path. All four "control images" (`background_caption.bmp`,
`background_controls.bmp`, `trackbar.bmp`, `trackbar_tip.bmp`) are BI_RLE8 —
which is exactly the set the message complains about.

**Fix:** decode the RLE8 streams and re-write the files as uncompressed 8bpp
`BI_RGB`, keeping the identical palette and pixel data. `MenuBar_MainMenu.bmp`
was already `BI_RGB` and is copied through untouched.

```
Background.bmp            320x240   6188 -> 77878 bytes
Background_Caption.bmp     60x16    1362 ->  2038 bytes
Background_Controls.bmp   130x480  43418 -> 64438 bytes
MenuBar_PopupMenu.bmp      24x400  10234 -> 10678 bytes
TrackBar.bmp              190x6     1120 ->  2230 bytes
TrackBar_Tip.bmp           25x21    1330 ->  1666 bytes
Volume_Tip.bmp             60x6     1144 ->  1438 bytes
```

Reproduce: `python tools/compat_fixes.py images <extracted>/Imgs out/Imgs`

---

## Fix 2 — `auxGetNumDevs` (import thunk patch)

**Symptom:** after fix 1, startup instead shows
*"Unexpected Error (Access violation at address 710B5AB3 in module
'winmmbase.dll'. Read of address 00000008)"*. Dismissing it lets the player run,
so the dialog appeared on every start.

**Cause:** the player enumerates legacy MME auxiliary devices at startup. On
current Windows `winmmbase.dll` answers that call through its 16-bit-compatible
driver path, which no longer exists:

```
winmmbase!auxGetNumDevs              (winmmbase+0x71b0)
  -> winmmbase+0x10a34 .. 0x58f7
     -> winmmbase+0x59e4            (internal driver-list helper)
        GlobalLock(handle 0x00b94a5e)  -> NULL   (stale 16-bit handle)
        cmp dword ptr [edx+8], edi     -> AV     (winmmbase+0x5ab3)
```

Because the fault is inside a system DLL, the only practical fix at application
level is to stop asking the question: `auxGetNumDevs` returns 0 ("no auxiliary
devices"), which is also the truthful answer on systems without MMC aux hardware.
The player then uses its normal `waveOut` volume path.

**Patch** — the import thunk of `auxGetNumDevs`:

```
VA   0x0044d294   (file offset 0x4c694)
was  ff 25 08 b9 49 00    jmp dword ptr [__imp_auxGetNumDevs]
now  33 c0 c3 90 90 90    xor eax, eax ; ret ; nop ; nop ; nop
```

Nothing else in the executable is modified.

Note the executable must be unpacked first — the shipped copy is UPX 1.02 packed,
so the thunk does not exist as such on disk:

```
upx -d app/sasami2000.exe            # or original/sasami2000.packed.exe
python tools/compat_fixes.py exe <unpacked.exe> app/sasami2000.exe
```

Verified with UPX 4.2.4 against the packed 311,808-byte original
(`781,824` bytes unpacked).

---

## What was *not* changed

* No other code, import, string, resource, or section was touched.
* `Sasami2000_Translator.exe`, `Sasami.ax`, `Sasami4a.ax`, `Sasamiv4a.ax`,
  `Sasami2000_CBTHook.dll` and `regsvr32.exe` are byte-identical to the installer
  payload.
* The two executables are still unsigned and still link against the same Delphi
  RTL and DirectShow interfaces.

## Reverting

Everything here is optional. To get the untouched 2001 binaries:

```
python tools/extract_installer.py original/sasami2k_757.exe build
```

`build/sasami2000.exe` is the original packed player (also kept as
`original/sasami2000.packed.exe`), and `build/Imgs` holds the original RLE8
bitmaps. Running those reproduces both dialogs described above.
