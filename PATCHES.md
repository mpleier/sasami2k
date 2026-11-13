# Compatibility fixes

The 2001 payload does not run unmodified on Windows 10/11: it fails twice during
startup, before the main window is shown. Both failures are environmental, not
application logic, and both are fixed here with the smallest possible change.

Everything is reproducible with `tools/extract_installer.py` and
`tools/compat_fixes.py`; `original/` keeps the untouched binaries.

| Artifact | Shipped state | Portable build |
|---|---|---|
| `app/sasami2k.exe` | UPX-packed, stock, named `sasami2000.exe` | unpacked, one 6-byte import-thunk patch, renamed |
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

Note on orientation: a BMP with positive `biHeight` stores its rows bottom-up,
while the RLE8 decoder here produces top-down rows. The writer therefore emits
rows in reverse. Skipping that step still yields a valid, pixel-identical file
when read back by an RLE-aware loader, but every image renders vertically
mirrored — the player's whole skin (including its logo) appeared upside down.
`tools/compat_fixes.py` round-trips all eight bitmaps pixel-for-pixel against the
originals.

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
upx -d original/sasami2000.packed.exe            # -> unpacked sasami2000.exe
python tools/compat_fixes.py exe <unpacked.exe> app/sasami2k.exe
```

Verified with UPX 4.2.4 against the packed 311,808-byte original
(`781,824` bytes unpacked).

---

## Fix 3 - executable name (`sasami2000.exe` -> `sasami2k.exe`)

**Symptom:** `Unexpected Error (Access violation at ... in module 'AcGenral.DLL'.
Write of address 00000010)`.

**Cause:** Windows ships an application-compatibility fix for this program. The
compatibility telemetry log names it explicitly:

```
Compatibility fix applied to ...\sasami2000.exe.
Fix information: Sasami 2000, {51c588bf-132d-4a98-b8e6-2de4dfa366f2}, 0x80010101
```

That fix injects `AcGenral.dll` - the generic shim engine - into the process. The
shim was written for much older Windows and faults on current builds. The
selector is the **file name**, not the file contents: the identical bytes under a
different name are not shimmed and `AcGenral` is never loaded.

**Fix:** ship the player as `sasami2k.exe`. Verified by module enumeration
(`AcGenral` absent) and by the absence of any new compatibility-fix event.

This does not change what the program does: filters register by CLSID, settings
live in `SASAMI2k.ini`, and the translator is launched by its own literal file
name. Only the launcher's `$PlayerExe` points at the new name.

---

## Launcher note — start the player with CreateProcess, not ShellExecute

No binary change, but the same class of first-run failure.

**Symptom:** on hosts that prompt for unsigned programs, every launch of the
portable tree raises *"Open File - Security Warning — the publisher could not be
verified"* naming `app\sasami2k.exe`, with *Run* / *Cancel* / *Always ask before
opening this file*.

**Cause:** the 2001 executable is unsigned, and starting it through the shell
(`Start-Process`, `ShellExecute`, a shortcut, an "Open with" entry) routes it
through the Attachment Manager, which refuses to run an unverified publisher
without confirmation. The file itself carries no `Zone.Identifier`, so this is
not a "downloaded file" mark — it is the unsigned-binary prompt.

**Fix:** `tools/portable.ps1 launch` starts the player with
`ProcessStartInfo { UseShellExecute = $false }`, i.e. plain `CreateProcess`,
which has no such policy attached. Verified by counting *Open File - Security
Warning* windows before and after a launch (0 new), with the player still
starting on the requested file. Elevation paths (`register -Machine`,
`unregister -Machine`) still use `Start-Process -Verb RunAs`, because UAC
consent genuinely requires the shell.

The same mistake in `tools/make-singlefile.ps1` was worse: its self-test ran the
freshly built (unsigned) bootstrapper with `Start-Process … -Wait`, so on such a
host the prompt appeared, nobody answered it and the build hung forever after
reporting a finished executable. It now uses `CreateProcess` + `WaitForExit`, and
a full run ends with `all 46 files extract byte-identically`.


---

## Fix 4 - the video-only UI block is guarded (`mov eax,[eax]` at `0x0047d540`)

**Symptom:** opening any audio-only file - a `.wav` at 44.1 or 48 kHz, or an
`.mp3` - raised *"Unexpected Error (Access violation at address 0047D540 in
module 'sasami2k.exe'. Read of address 00000000)"* and left the player sitting
behind that dialog. Files with a video stream played normally.

**Cause:** the player reconfigures its video controls in a block that starts at
`0x0047d4f1`. The block assumes the interface at `this+0x0A58` exists:

```
0x0047d4f1  push 0x480088
0x0047d4f6  mov  eax,[ebp-8]
0x0047d4f9  mov  eax,[eax+0xa58]     ; NULL when the graph has no video stream
0x0047d4ff  push eax
0x0047d500  mov  eax,[ebp-8]
0x0047d503  mov  eax,[eax+0xbb8]     ; the graph control - always present
...
0x0047d539  mov  eax,[eax+0xa58]
0x0047d53f  push eax
0x0047d540  mov  eax,[eax]           ; AV: read of address 0
0x0047d542  call dword ptr [eax+0x28]
```

Every other COM call in the routine guards its pointer - the helper at
`0x004724e4` opens with `cmp dword [ecx+0xb34],0 / je` - but this block does not.
With an audio-only graph the field stays NULL, so the dereference faults.
Confirmed with a purpose-built 32-bit Win32 debugger: first-chance `0xC0000005`,
main thread, `eax = 0`, `eip = 0x0047d540`, return chain `0x487d97 -> 0x48bdac ->
0x42d59b -> 0x42d297 -> 0x434174 -> 0x497ed3`.

**Fix:** gate the block on the field, leaving its own "no video" branch intact.
The five-byte `push 0x480088` at `0x0047d4f1` becomes a jump to a 32-byte stub in
the zero padding at the end of CODE (`0x497f00`):

```
push 0x480088            ; original first argument
mov  eax,[ebp-8]
mov  eax,[eax+0xa58]
test eax,eax
jz   .no_video
push eax                 ; original second argument
jmp  0x0047d500          ; into the block
.no_video:
add  esp,4               ; drop the argument already pushed
jmp  0x0047d4db          ; the block's own "gate was false" path
```

The CODE section's `VirtualSize` grows from `0x96efc` to `0x97000` so the loader
maps those padding bytes instead of zero-filling them (`SizeOfImage` already
covered the range, and the next section starts at `0x98000`).

**Verified** by measurement, not by inspection: audio-only `.wav` and `.mp3` open
with no dialog, and an MPEG-1/MP2 `.mpg` still builds its graph and renders
(322x242 window, changing frame fingerprint) exactly as before the patch.

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
