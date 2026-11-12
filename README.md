# SASAMI2k 757 — portable build

A no-installer, self-contained copy of **SASAMI2k Core build #757** (2001‑08‑24),
the DirectShow/ActiveMovie2 media player by Ui‑jong Choi (`nuclei@shinbiro.com`,
"Project SASAMI2k", supported by Kiwidream). Files were extracted from the
original Windows installer `sasami2k_757.exe` and are byte‑identical to what it
would have installed.

> SASAMI = *Specially Advanced Synchronized Accessible Media Interchange*
> Release note from the author: *"Release ; 2001/08/24 Core #757, SMI Converter #309, Main filter 1921"*

---

## Quick start

1. Double‑click **`SASAMI2k.cmd`**.
2. On first run it registers the three DirectShow filters for the current user
   (no admin prompt), then starts the player.
3. Open a file, or drop one on the launcher: `SASAMI2k.cmd "D:\movie.avi"`.

If video does not play, register the filters machine‑wide once — right‑click
**`RegisterFilters.cmd`** → *Run as administrator*. Check the current state at any
time with **`Status.cmd`**.

Moving or renaming the folder is fine: the launcher notices the filters point at
the old path and re‑registers them.

---

## What's in here

```
SASAMI2k.cmd            Launcher: ensures filter registration, starts the player
RegisterFilters.cmd     Machine-wide registration (elevates via UAC)
UnregisterFilters.cmd   Removes registration again
Status.cmd              Shows whether the filters point at this folder
                        (`Status.cmd verify` checks every shipped file instead)
Associate.cmd           Opt-in per-user file associations (see below)
Unassociate.cmd         Removes them again, restoring shadowed handlers
tools/portable.ps1      The logic behind those six scripts
tools/extract_installer.py  Re-extracts the payload from the original installer
tools/compat_fixes.py   Reproduces the two compatibility fixes (see PATCHES.md)
tools/build.ps1         Rebuilds the whole app\ tree from original\sasami2k_757.exe
tools/manifest.py       Regenerates / checks HASHES.txt
tools/lav-audio.ps1     Shows (and optionally sets) the 32-bit audio decoder merit
tools/upx/              Vendored UPX 4.2.4, used by the build to unpack the player
tools/make-singlefile.ps1  Packs the built tree into one self-extracting .exe
tools/singlefile/       Bootstrapper source for that executable
HASHES.txt              SHA-256 of every shipped file

app/
  sasami2k.exe                The player (Core #757): unpacked, one import patch, renamed
  Sasami2000_Translator.exe   Subtitle / SMI-S2K script translator
  Sasami2000_CBTHook.dll      WH_CBT helper used for global hotkeys
  Sasami.ax                   Video driver filter       ("Nuclei's Sasami")
  Sasami4a.ax                 Audio filter              ("Nuclei's Sasami for Audio")
  Sasamiv4a.ax                Video-for-audio filter    ("Nuclei's Video for Audio")
  regsvr32.exe                32-bit registration tool (1999); fallback only
  SASAMI2k.default.ini        Shipped player defaults (copied to SASAMI2k.ini on first run)
  SASAMI2k_Translator.default.ini  Shipped translator defaults
  Imgs/                       Player skin bitmaps (re-encoded to BI_RGB)
  Languages/                  UI localisations (Default, English, French, Korean,
                              Russian, Swedish, Ukraine)
  Plugins/                    Drop Winamp DSP `dsp_*.dll` files here
  README_ENGLISH.TXT          Original release notes
  README_KOREAN.TXT           Original release notes (Korean)

original/
  sasami2k_757.exe            The original installer, kept for provenance
  sasami2000.packed.exe       The player exactly as shipped (UPX-packed, unpatched)
```

Two small compatibility fixes were necessary to make a 2001 DirectShow app start
on Windows 10/11: the skin bitmaps had to be re-encoded from RLE8, and one
`auxGetNumDevs` import thunk is neutralised. Both are documented byte-for-byte,
with symptoms, evidence and reproduction steps, in **[PATCHES.md](PATCHES.md)**;
`original/` keeps the untouched binaries.

Everything else is still byte-identical to the installer payload
(`Sasami2000_Translator.exe` and the three `.ax` filters are unmodified).

---

## Rebuilding from the installer

Everything under `app\` is derived and can be regenerated from the pristine
installer in one step:

```
powershell -ExecutionPolicy Bypass -File tools\build.ps1
```

The script verifies the installer's SHA-256, extracts the CRC-checked payload,
UPX-unpacks the player, applies the import-thunk patch, re-encodes the seven skin
bitmaps, derives the `*.default.ini` files, copies the launcher, and then checks
every produced file against `HASHES.txt`. A clean run ends with:

```
==> Verifying against HASHES.txt
    all 46 manifest entries reproduce exactly
```

(The manifest has 53 entries; the 7 under `original\` and `tools\upx\` are
inputs to the build rather than outputs, so they are not re-checked here.
`Status.cmd verify` checks all 53 in place.)

Requirements: Windows PowerShell 5.1 and Python 3 on `PATH`. UPX is vendored in
`tools\upx\` (GPL, see `tools\upx\README-SASAMI2k.txt`); pass `-Upx <path>` to
use a different build. Output defaults to `build\portable` (`-OutDir`), and
`-KeepWork` keeps the temporary extraction for inspection.

`original\` (the pristine installer) and `tools\upx\` (rebuild-only tooling) are
inputs, so they are deliberately not copied into the output and are excluded from
the output verification. The built tree is self-contained: running its
`SASAMI2k.cmd` re-points the filter registration at itself.

---

## Single-file build

`tools\make-singlefile.ps1` packs the whole portable tree into one executable:

```
powershell -ExecutionPolicy Bypass -File tools\make-singlefile.ps1
-> build\SASAMI2k-portable.exe   (~780 KiB incl. a ~770 KiB payload)
```

The executable is a small .NET bootstrapper with a ZIP payload appended behind a
24-byte footer (`S2KSFX01`, offset, length). On first run it unpacks the tree next
to itself into `SASAMI2k.data\` - or into `%LOCALAPPDATA%\SASAMI2k.data\` when
that folder is not writable - records a stamp so later runs skip extraction, and
then invokes the normal `tools\portable.ps1 launch` with whatever arguments it was
given. Settings persist in `SASAMI2k.data\app\SASAMI2k.ini`, and a short
`SASAMI2k.data\launch.log` records each launcher invocation.

```
SASAMI2k-portable.exe "D:\movie.avi"
SASAMI2k-portable.exe /fullscreen "D:\movie.avi"
```

The build self-tests: it extracts the payload to a temporary folder and compares
every file against the source tree before reporting success (47/47 byte-identical).

Requirements: `csc.exe` from .NET Framework 4.x (present on Windows 10/11) and
PowerShell 5.1. The payload ZIP is written with fixed entry timestamps, so the
packed tree is byte-identical build to build; the .exe itself is not, because the
.NET stub carries a compiler-generated PE timestamp and module id (measured: 18
bytes differ between two runs of the same tree). Compare the self-test result and
the payload, not the whole-file hash, when checking reproducibility.

---

## Why a launcher is needed

SASAMI2k builds its filter graph through COM, so the three `.ax` modules must be
registered before the player can create them. The original installer did this
silently with `Sasami2000.exe /register`, which in turn runs
`regsvr32.exe /s <path>\<name>.ax`, using the 32-bit build from
`%SystemRoot%\SysWOW64`.

Being a DirectShow app, it cannot be *completely* registry‑free — but the
registration is small, points at this folder, and is easy to undo:

| Module | CLSID | Registered as |
|---|---|---|
| `Sasami.ax` | `{6FFBDFFE-C9CE-11D3-BBAA-52544C191AD1}` | `HKCR\CLSID\…\InprocServer32`, `ThreadingModel=Both` |
| `Sasami4a.ax` | `{6FFBDFFE-C9CE-11DB-BBAA-52544C191AD1}` | same |
| `Sasamiv4a.ax` | `{FD501041-8EBE-11DE-8183-00AA00577DA1}` | same |

`RegisterFilters.cmd` runs the system's **32‑bit** `regsvr32.exe` from
`%SystemRoot%\SysWOW64`: on 64‑bit Windows the `regsvr32` in `System32` is the
64‑bit build and cannot register a 32‑bit DirectShow filter. The 1999 copy the
installer shipped is kept only as a fallback for hosts without `SysWOW64`.

For the same reason the per‑user fallback writes to the **WOW64 view**,
`HKCU\Software\Classes\Wow6432Node\CLSID\…`. An entry in the plain
`HKCU\Software\Classes\CLSID` is visible only to 64‑bit clients: the 32‑bit
player then fails `CoCreateInstance` with `REGDB_E_CLASSNOTREG`, builds no filter
graph and quietly never plays anything.

---

## What this touches on your system

* **Registry (filters)** — the three `CLSID` keys above, either machine‑wide
  (`HKLM\SOFTWARE\Classes\WOW6432Node\CLSID\…`) or per‑user
  (`HKCU\Software\Classes\Wow6432Node\CLSID\…`). The **WOW64 view is
  required**: these are 32‑bit filters, and an entry in the plain
  `CLSID` key is invisible to the 32‑bit player. `UnregisterFilters.cmd` removes them.
* **Registry (file types)** — nothing is changed by a normal launch. The binary
  does contain association‑repair code and strings (`.mms`, `.asx`, `.smi`, `.s2k`
  ProgIDs with `Open`/`Read`/`Play`/`Enqueue` verbs), and the built‑in help
  documents `/unregister` as *"unregister sasami filters, and repair associated
  files"*. On this build, however, neither a normal start nor `sasami2k.exe
  /register` created or modified any file association — checked by comparing
  `HKCU`/`HKLM` classes entries before and after. `Associate.cmd` is the
  opt‑in alternative: it adds `HKCU\Software\Classes\SASAMI2k.Media` plus one
  entry per extension, and `Unassociate.cmd` removes exactly that again.
* **Files** — everything else stays inside this folder. The player writes its
  preferences to `app\SASAMI2k.ini` (and the translator to
  `app\SASAMI2k_Translator.ini`); those live files are created from the shipped
  `*.default.ini` on first run and are deliberately not tracked, so your settings
  travel with the folder without dirtying the repository. Delete them to reset.

No installer, no service, no background updater, no network access of its own
(the original installer contains no networking code at all; the only URLs in the
player are the author's homepage and e‑mail address).

---

## Player command line

From the built‑in help:

```
[ SASAMI2k, command line options ]
/first       : show greeting message.
/register    : register sasami filters.
/unregister  : unregister sasami filters, and repair associated files.
[file] /add  : enqueue [file] in playlist.
/help        : show this message.
/fullscreen  : start with fullscreen mode.
/maxscreen   : start with maxscreen mode.
```

Pass them through the launcher, e.g. `SASAMI2k.cmd /maxscreen "D:\movie.avi"`.

---

## File associations (opt-in)

A normal launch deliberately changes no file types. If you want double-click
handling, opt in per user — no administrator rights, nothing machine-wide:

```
Associate.cmd                 # .mms .asx .smi .s2k -> SASAMI2k
Associate.cmd .mpg .avi       # any extra extensions you want to hand over
Unassociate.cmd               # undo, restoring whatever was there before
```

It writes one ProgID (`SASAMI2k.Media`, verbs *Play* and *Enqueue*) plus the
extension keys under `HKCU\Software\Classes`, and records what it shadowed under
`HKCU\Software\SASAMI2k` so `Unassociate.cmd` can put it back. `Status.cmd`
lists the current state.

Windows 11 may still keep an existing default for a well-known type: on a host
that has `.asx` owned by Windows Media Player, double-clicking an `.asx` opens
the system picker instead of SASAMI2k, while `.mms`, `.smi` and `.s2k` go
straight to the player. Either use *Open with → Choose another app* once for
such a type, or pass the file to the launcher directly.

---

## Checking the shipped files

`HASHES.txt` is the byte-level contract of the tree, and the copy you have can
be checked at any time without Python:

```
Status.cmd verify
-> == Integrity check
   manifest : 53 entries
   all 53 shipped files match HASHES.txt
```

Every entry is compared by size and SHA-256; missing or modified files are
listed and the script exits non-zero. Files that are not part of the shipped
payload (build output, the live `SASAMI2k.ini`, local notes) are reported
separately and do not fail the check. After changing any tracked file,
regenerate the manifest with `python tools/manifest.py write`.

---

## Troubleshooting

**Nothing happens / launcher exits with code 1** — run `Status.cmd`; it prints the
folder, whether the player is present, and the registration state.

**A file is accepted but nothing plays** — the filter registration is not visible
to the 32‑bit player. `Status.cmd` shows this as *"only in the 64‑bit view; the
32‑bit player cannot see it"*; run `SASAMI2k.cmd` again (it repairs this) or
`RegisterFilters.cmd` as administrator.

**"Failed to Register …" or video stays black** — the per‑user registration may
not be visible to the DirectShow filter mapper on your system. Run
`RegisterFilters.cmd` as administrator once.

**Moved the folder and playback broke** — run `SASAMI2k.cmd` again; it detects the
stale path and re‑registers. `Status.cmd` will show `-> points elsewhere: …`.

**No subtitles / wrong language** — subtitles are `.smi` / `.s2k`; the UI language
is `Sasami.Preference.LanguageFile` in `app\SASAMI2k.ini` (a file in
`app\Languages\`).

**"Select files to play" appears at startup** — that is the player's normal
open dialog when it is started without a file. Pass a file to skip it.

**Security software complains** — the 2001 binaries are unsigned and the
translator is still UPX-packed, which trips generic heuristics. The player itself
is shipped unpacked (see [PATCHES.md](PATCHES.md)); every file's SHA-256 is in
`HASHES.txt`.

**"The publisher could not be verified" on every launch** — the launcher starts
the player with `CreateProcess`, so it never raises that prompt itself. If you
see it, the player is being started through the shell by something else: a
shortcut on the executable, an "Open with" handler pointing straight at
`sasami2k.exe`, or a tool that calls `ShellExecute`. Point that shortcut at
`SASAMI2k.cmd` (or add a `Run` verb) instead.

---

## Known limitations

* **44.1 kHz MPEG audio — measure before blaming the decoder.** Clips whose audio
  is MPEG-1 Layer II at 44.1 kHz (typical of the old `.mpg` AMV rips) were
  reported to crackle/buzz, while the same video at 48 kHz or with PCM audio
  played cleanly. Re-tested on Windows 11 (26200) by capturing the player's own
  output through a WASAPI loopback of the default render endpoint: a 44.1 kHz MP2
  probe and a 48 kHz MP2 probe come out **indistinguishable** — median RMS
  0.0326 in both, no dropouts, no sample-jump spikes, high-frequency (above
  2 kHz) energy −56.2 dB vs −56.1 dB.
  * The earlier explanation (*"LAV is registered only as a COM server, so the
    graph builder can only pick quartz"*) does not hold on this machine: the
    32-bit filter mapper does register LAV Audio Decoder
    (`{E8E73B6B-4CB3-44A4-BE99-4F7BCB96E491}`) — its instance keys live under
    `HKLM\SOFTWARE\Classes\Wow6432Node\CLSID\{083863F1-70DE-11D0-BD40-00A0C911CE86}\Instance`,
    not in the `CLSID\…\Instance` shape a quick look suggests — and LAV's
    `LAVAudio.ax`, `avcodec`, `swresample` are loaded by the player while that
    file plays. Both LAV Audio Decoder and quartz's "MPEG Audio Decoder" were
    registered *without* an explicit merit, so the selection was a tie-break
    rather than a preference.
  * `tools\lav-audio.ps1 status` lists the audio decoders a 32-bit graph can
    choose, with merit and module; `tools\lav-audio.ps1 prefer` gives LAV Audio
    Decoder an explicit `MERIT_PREFERRED` (one UAC prompt; `tools\lav-audio.ps1
    default` removes that value again). Setting it changed the measured output by
    nothing — LAV was already the decoder in use.
  * If a specific file still crackles, remux its audio to 48 kHz; that path is
    the one that measures clean here.

* **Audio-only files crash on open.** Playing a bare audio file — a 44.1 kHz or
  48 kHz PCM `.wav`, or an `.mp3` — raises
  *"Unexpected Error (Access violation at address 0047D540 in module
  'sasami2k.exe'. Read of address 00000000)"* and the player sits there with the
  dialog. The fault is in the 2001 player itself, not in the compatibility
  patches: the same address faults when the `auxGetNumDevs` thunk is restored to
  the shipped code. The crash is not triggered by the media, it is triggered by
  the *absence of a video stream* — an audio-only graph has no video window for
  the render path it takes.
  * Workaround: give the file a video track. Remuxing the audio next to a static
    black video already works (verified with a 1 fps MPEG-4 video track):
    `ffmpeg -f lavfi -i color=black:s=320x240:r=1 -i in.wav -shortest -c:v mpeg4 -c:a pcm_s16le out.avi`

* **Modern codecs play fine where DirectShow can decode them.** This build was
  written for DivX-era MPEG-1/MPEG-4, but the graph is built by the system, so
  the decoders Windows 10/11 ships (and any third-party DirectShow decoder
  registered as a real filter) are used: H.264 in `.mp4`/`.mkv` and HEVC in
  `.mp4` play, with AAC audio, at the right size. Nothing here needs patching to
  get that — it is a property of the DirectShow graph, not of the player.

* **A 32-bit player sees only 32-bit DirectShow filters.** A codec pack that
  registers only 64-bit modules is invisible to SASAMI2k, so check the 32-bit
  view (`HKLM\SOFTWARE\Classes\Wow6432Node\…`) before concluding a decoder is
  installed. K-Lite's LAV is registered in both views here — including the
  32-bit filter-mapper entries — which is why LAV is in the player's graph; what
  it lacked was an explicit merit. `tools\lav-audio.ps1 status` shows the
  decoders that a 32-bit graph can actually choose.

## Provenance and verification

The portable tree is a direct extraction of the installer's InstallFactory
archive (`IFFH` records: name, unpacked size, packed size, CRC32, DOS timestamp,
raw deflate). All 31 records were inflated and **every CRC32 and size matched**.
The installed payload totals 1,011,640 bytes, exactly the `SpaceNeeded=1011640`
declared by the installer's own configuration.

* Original installer SHA-256: `4e2b22e4c280d19f804bbc3594f8b9c308179f8481f8b61f84e7bd1aeb88ee21`
* Installer payload: 25 files, 7 skin bitmaps, 7 localisations.

Intentional changes to the shipped data, all documented:

* `app\SASAMI2k.default.ini` — `Sasami.LastDirectory` reset (the original pointed
  at a folder on the author's machine); the live `.ini` is generated from this file.
* `app\sasami2k.exe` — unpacked, one import thunk patched, and renamed from
  `sasami2000.exe` to escape a broken Windows compatibility shim (PATCHES.md, fixes 2 and 3).
* `app\Imgs\*.bmp` — seven RLE8 bitmaps re-encoded as BI_RGB (PATCHES.md, fix 1).

`tools/extract_installer.py` and `tools/compat_fixes.py` reproduce both the
pristine payload and the fixed binaries; the shipped artefacts were verified to be
reproduced byte-for-byte.

---

## Licence / attribution

SASAMI2k is © Ui‑jong Choi (nuclei@shinbiro.com) / Kiwidream. The player's own
About text states it is *"free for non‑commercial purposes"*; for commercial use
contact the author. No licence is granted or implied by this repository — it is a
preservation/portability repackaging of a freely distributed 2001 release, kept
for archival and interoperability purposes.
