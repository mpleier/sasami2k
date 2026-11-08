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
tools/portable.ps1      The logic behind those four scripts
tools/extract_installer.py  Re-extracts the payload from the original installer
tools/compat_fixes.py   Reproduces the two compatibility fixes (see PATCHES.md)
HASHES.txt              SHA-256 of every shipped file

app/
  sasami2k.exe                The player (Core #757): unpacked, one import patch, renamed
  Sasami2000_Translator.exe   Subtitle / SMI-S2K script translator
  Sasami2000_CBTHook.dll      WH_CBT helper used for global hotkeys
  Sasami.ax                   Video driver filter       ("Nuclei's Sasami")
  Sasami4a.ax                 Audio filter              ("Nuclei's Sasami for Audio")
  Sasamiv4a.ax                Video-for-audio filter    ("Nuclei's Video for Audio")
  regsvr32.exe                32-bit Microsoft registration tool (1999)
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

## Why a launcher is needed

SASAMI2k builds its filter graph through COM, so the three `.ax` modules must be
registered before the player can create them. The original installer did this
silently with `Sasami2000.exe /register`, which in turn runs
`regsvr32.exe /s <path>\<name>.ax`.

Being a DirectShow app, it cannot be *completely* registry‑free — but the
registration is small, points at this folder, and is easy to undo:

| Module | CLSID | Registered as |
|---|---|---|
| `Sasami.ax` | `{6FFBDFFE-C9CE-11D3-BBAA-52544C191AD1}` | `HKCR\CLSID\…\InprocServer32`, `ThreadingModel=Both` |
| `Sasami4a.ax` | `{6FFBDFFE-C9CE-11DB-BBAA-52544C191AD1}` | same |
| `Sasamiv4a.ax` | `{FD501041-8EBE-11DE-8183-00AA00577DA1}` | same |

`RegisterFilters.cmd` uses the **bundled 32‑bit** `regsvr32.exe` on purpose: on
64‑bit Windows the `regsvr32` in `System32` is the 64‑bit build and cannot
register a 32‑bit DirectShow filter.

For the same reason the per‑user fallback writes to the **WOW64 view**,
`HKCU\Software\Classes\Wow6432Node\CLSID\…`. An entry in the plain
`HKCU\Software\Classes\CLSID` is visible only to 64‑bit clients: the 32‑bit
player then fails `CoCreateInstance` with `REGDB_E_CLASSNOTREG`, builds no filter
graph and quietly never plays anything.

---

## What this touches on your system

* **Registry (filters)** — the three `CLSID` keys above, either machine‑wide
  (`HKLM\SOFTWARE\Classes\CLSID\…`) or per‑user (`HKCU\Software\Classes\CLSID\…`).
  `UnregisterFilters.cmd` removes them.
* **Registry (file types)** — on startup the player ensures/repairs its own
  associations: `HKCR\.mms`, `.asx`, `.smi`, `.s2k` plus `Sasami2k.<ext>` with the
  verbs `Open` (translator), `Read` (`notepad.exe "%1"`), `Play` and
  `Enqueue` (`… "%1" /Add`). Its documented `/unregister` option removes the
  filters *"and repair[s] associated files"*.
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

---

## Known limitations

* **44.1 kHz MPEG audio crackles.** Clips whose audio is MPEG-1 Layer II at
  44.1 kHz - typical of the old `.mpg` AMV rips - play with crackling/buzzing.
  The same video with 48 kHz MPEG audio, or with uncompressed PCM audio, plays
  cleanly, so the fault is in the decoder DirectShow picks: the built-in
  `quartz.dll` "MPEG Audio Codec" (`{4A2286E0-7BEF-11CE-9BD9-0000E202599C}`), the
  only MPEG audio decoder the filter graph builder will select on this system.
  * Swapping it is not possible with registry values alone: LAV Filters (installed
    via K-Lite) is registered only as a COM server, with no DirectShow
    filter-mapper entry, so the graph builder never considers it; and Microsoft's
    decoder key is owned by `TrustedInstaller` with Administrators read-only, so
    its merit cannot be lowered either.
  * Workarounds: let K-Lite's Codec Tweak Tool register LAV properly, or remux
    the audio to 48 kHz.

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
