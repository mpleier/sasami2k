# SASAMI2k 757 — parity dossier

What a modern rebuild would have to reproduce, and what the shipped binary already
answers. Everything here is labelled:

* **observed** — read directly from the bytes, the running process or the registry;
* **derived** — computed from observations;
* **inferred** — judgement, not yet proven.

Method note: the craft-anything ledger was used for the brief and plan, but its
native analysis toolset could not be reached in this session (clean-room mode,
`core_target_open` not dispatchable after `enable_toolset`). The byte-level work
below was therefore done with `pefile` + `capstone` and a purpose-built 32-bit
Win32 debugger (`DbgProbe`), which produce the same class of evidence: addresses,
instruction bytes, register state, stack.

---

## 1. Audio-only crash (the open defect)

**Observed.** Playing a `.wav` (44.1 or 48 kHz) or `.mp3` raises a first-chance
`0xC0000005` in the main thread at VA `0x0047D540`, "read of address 0x00000000",
with `eax = 0x00000000`. Register and stack state at the fault:

```
eip=0x0047D540 esp=0x001AF6A4 ebp=0x001AFB18
eax=0 ebx=0 ecx=0x9CF edx=0 esi=0x20 edi=0x0046D00C
```

**Observed.** The instruction stream in the running image at the fault reads:

```
call 0x405C1C
push eax
mov  eax, [ebp-8]
mov  eax, [eax+0x0A58]      ; the interface pointer stored at this+0xA58
push eax
mov  eax, [eax]             ; 0x0047D540 — faults because that pointer is NULL
call dword ptr [eax+0x28]   ; vtable slot 10
```

**Derived.** This is an unguarded COM dispatch: the player dereferences an
interface pointer held at `this+0x0A58` without a null test, then calls its 11th
vtable entry. Every other site inspected in the same routine *is* guarded — the
helper at `0x004724E4` begins `cmp dword [ecx+0xB34], 0 / je …` before calling
`[eax+0x10]` — so this path is an oversight, not a convention.

**Observed.** The stack walk back from the fault:

```
#0 0x001AFB18 ret 0x00487D97
#1 0x001AFBB8 ret 0x0048BDAC
#2 0x001AFDD4 ret 0x0042D59B
#3 0x001AFDF8 ret 0x0042D297
#4 0x001AFF3C ret 0x00434174
#5 0x001AFF60 ret 0x00497ED3
```

**Inferred.** The chain starts in Delphi message/paint code (`0x497ED3`,
`0x434174`) and reaches the video-side setup through the form's own methods —
i.e. the player is updating a video control while the graph has no video stream,
which is exactly the condition that leaves `this+0xA58` NULL and explains why
audio-only files fault while video+audio files play.

**Open unknown (blocking a fix).** The bytes on disk at `0x0047D530` are *not* the
bytes in the running process:

```
file   : 6A 00 6A 01 6A 00 6A 00 33 D2 8B 45 F8 E8 A2 4F …
memory : E8 E7 86 F8 FF 50 8B 45 F8 8B 80 58 0A 00 00 50 8B 00 FF 50 28 …
```

The executable has no relocation directory (`IMAGE_DIRECTORY_ENTRY_BASERELOC`
RVA `0`) and `DllCharacteristics = 0`, so the loader cannot have rebased it and
the image base is the file's `0x400000`. Either the player patches its own code
at startup, or the running image is not the file we ship. Until that is settled,
a byte-level fix cannot be designed — patching the file at `0x47D540` would hit
different instructions than the ones that fault.

**Probe that would settle it:** start the process suspended, read the PE header
and a handful of landmark bytes in-process (`0x00401000`, `0x0047D4D4`,
`0x00405C1C`) and diff them against the file; a handful of differing sites means
a self-patch, a wholesale difference means an image mismatch.

---

## 2. Subtitle script engine (SMI → S2K)

**Observed.** The binary carries `.s2k`, `.sami`, `.smi`-family strings and the
shipped `Sasami2000_Translator.exe` converts scripts offline; the player's
preferences expose `Sasami.Script.Bold+`, `.Size+`, `.Soften`, `.Shadow`,
`.Transparent`, `.FadeIn` — i.e. per-script styling, not plain subtitles.

**Open unknown.** The accepted command set (the parser's verbs and their argument
grammar) has not been extracted. **Probe:** enumerate the string table around the
parser and the translator, group by prefix, and confirm each candidate verb by
hand with a minimal `.smi`.

---

## 3. Winamp DSP host

**Observed.** `app/Plugins/README_PLUGINS.TXT` documents the contract the author
shipped: drop `dsp_*.dll` in `Plugins\`, enable it in preferences, no
sub-folders, "pitch controls are not supported".

**Inferred.** This is the classic 32-bit Winamp DSP module ABI (`winampDSPModule`:
`Init/Quit/ModifySamples/GetModule`), which a 64-bit host cannot load in-process.
Whether a 64-bit rebuild could proxy it through a 32-bit helper is undecided.

**Open unknown.** The exact entry points and struct layout the host calls, and
whether it also supports `Config`. **Probe:** find the loader in the binary
(`LoadLibrary` + `GetProcAddress` sites near the `dsp_` string) and read the
struct offsets it fills.

---

## 4. DirectShow filter / merit model

**Observed.** The three private filters register per-user or machine-wide under
the WOW64 view only — `HKCU\Software\Classes\Wow6432Node\CLSID\{clsid}\InprocServer32`,
`ThreadingModel=Both`. A plain-view entry is invisible to the 32-bit player and
makes `CoCreateInstance` fail with `REGDB_E_CLASSNOTREG`.

| Module | CLSID | Role |
|---|---|---|
| `Sasami.ax` | `{6FFBDFFE-C9CE-11D3-BBAA-52544C191AD1}` | video driver/renderer |
| `Sasami4a.ax` | `{6FFBDFFE-C9CE-11DB-BBAA-52544C191AD1}` | audio renderer |
| `Sasamiv4a.ax` | `{FD501041-8EBE-11DE-8183-00AA00577DA1}` | video-for-audio |

**Observed.** Decoder selection is decided by the filter mapper, not by the
player: LAV's 32-bit registrations live under the System Device Enumerator
category key `HKLM\SOFTWARE\Classes\Wow6432Node\CLSID\{083863F1-70DE-11D0-BD40-00A0C911CE86}\Instance\<clsid>`,
and both LAV Audio Decoder (`{E8E73B6B-4CB3-44A4-BE99-4F7BCB96E491}`) and quartz's
"MPEG Audio Decoder" (`{4A2286E0-7BEF-11CE-9BD9-0000E202599C}`) were registered
with **no** explicit `Merit` — a tie, not a preference. `tools/lav-audio.ps1`
reports and can settle this.

**Derived.** A rebuild cannot reuse these `.ax` modules in a 64-bit process at
all; it has to own decoding and rendering itself (Media Foundation or libmpv),
which also makes the whole merit/registry machinery unnecessary.

---

## What this means for a rebuild

1. The look is cheap to keep: 8 indexed BMPs (~230 KB) plus 7 localisations of
   ~465 keys.
2. The subtitle engine and the DSP host are the expensive, undocumented parts;
   §2 and §3 are the two extractions worth doing before writing any code.
3. The audio-only crash is a genuine null-interface bug in the 2001 code, not an
   environment artefact — a rebuild deletes the defect rather than porting it.
4. Nothing here justifies a byte-level patch of the shipped binary yet: the
   on-disk/in-memory mismatch in §1 must be explained first.
