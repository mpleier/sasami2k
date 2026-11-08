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
HASHES.txt              SHA-256 of every shipped file

app/
  sasami2000.exe              The player (Core #757)
  Sasami2000_Translator.exe   Subtitle / SMI-S2K script translator
  Sasami2000_CBTHook.dll      WH_CBT helper used for global hotkeys
  Sasami.ax                   Video driver filter       ("Nuclei's Sasami")
  Sasami4a.ax                 Audio filter              ("Nuclei's Sasami for Audio")
  Sasamiv4a.ax                Video-for-audio filter    ("Nuclei's Video for Audio")
  regsvr32.exe                32-bit Microsoft registration tool (1999)
  SASAMI2k.ini                Player settings  (portable: lives next to the exe)
  SASAMI2k_Translator.ini     Translator settings
  Imgs/                       Player skin bitmaps
  Languages/                  UI localisations (Default, English, French, Korean,
                              Russian, Swedish, Ukraine)
  Plugins/                    Drop Winamp DSP `dsp_*.dll` files here
  README_ENGLISH.TXT          Original release notes
  README_KOREAN.TXT           Original release notes (Korean)

original/
  sasami2k_757.exe            The original installer, kept for provenance
```

Both executables were UPX‑packed inside the installer and remain in their
original shipped form, so their hashes match the archive exactly.

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
* **Files** — everything else stays inside this folder; `SASAMI2k.ini` and
  `SASAMI2k_Translator.ini` are read/written next to the executables, so
  preferences travel with the folder.

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

**"Failed to Register …" or video stays black** — the per‑user registration may
not be visible to the DirectShow filter mapper on your system. Run
`RegisterFilters.cmd` as administrator once.

**Moved the folder and playback broke** — run `SASAMI2k.cmd` again; it detects the
stale path and re‑registers. `Status.cmd` will show `-> points elsewhere: …`.

**No subtitles / wrong language** — subtitles are `.smi` / `.s2k`; the UI language
is `Sasami.Preference.LanguageFile` in `app\SASAMI2k.ini` (a file in
`app\Languages\`).

**Security software complains** — the original 2001 binaries are unsigned and
UPX‑packed, which trips generic heuristics. Hashes are in `HASHES.txt`; nothing
was modified.

---

## Provenance and verification

The portable tree is a direct extraction of the installer's InstallFactory
archive (`IFFH` records: name, unpacked size, packed size, CRC32, DOS timestamp,
raw deflate). All 31 records were inflated and **every CRC32 and size matched**.
The installed payload totals 1,011,640 bytes, exactly the `SpaceNeeded=1011640`
declared by the installer's own configuration.

* Original installer SHA-256: `4e2b22e4c280d19f804bbc3594f8b9c308179f8481f8b61f84e7bd1aeb88ee21`
* Installer payload: 25 files, 7 skin bitmaps, 7 localisations.

The only intentional change to the shipped data: `Sasami.LastDirectory` in
`app\SASAMI2k.ini` was reset (the original pointed at a folder on the author's
machine).

---

## Licence / attribution

SASAMI2k is © Ui‑jong Choi (nuclei@shinbiro.com) / Kiwidream. The player's own
About text states it is *"free for non‑commercial purposes"*; for commercial use
contact the author. No licence is granted or implied by this repository — it is a
preservation/portability repackaging of a freely distributed 2001 release, kept
for archival and interoperability purposes.
