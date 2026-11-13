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

**Observed.** The instruction stream at the fault, read from the running process:

```
0x0047D535  push eax                  ; argument: object returned by 0x405C1C
0x0047D536  mov  eax, [ebp-8]         ; this
0x0047D539  mov  eax, [eax+0x0A58]    ; interface field
0x0047D53F  push eax                  ; argument: that interface
0x0047D540  mov  eax, [eax]           ; FAULT — vtable of a NULL pointer
0x0047D542  call dword ptr [eax+0x28] ; slot 10
0x0047D545  lea  eax, [ebp-0x10]      ; execution resumes here when the call returns
```

**Derived.** This is the plain Delphi interface-call idiom `push obj; mov eax,[obj];
call [eax+slot]` applied to the pointer held at `this+0x0A58`, with no null test.
The same idiom appears twice *earlier in the same basic block* against
`this+0x0BB8` (`0x0047D500` and `0x0047D51E`, slot `+0x0C`) and never faults,
because that interface always exists. `this+0x0A58` is the one that only exists
when the graph carries a video stream — which is exactly the observed condition:
audio-only faults, video+audio plays.

**Correction to an earlier reading.** A first pass claimed the on-disk bytes at
`0x0047D530` differed from the running image and treated that as an unresolved
blocker. It was a tooling bug: `pefile.get_data()` takes an **RVA**, and the
script passed it a file offset, so the comparison read the wrong bytes (and the
disassembly in that pass was shifted, which produced plausible-looking but wrong
code). Re-read by RVA, the file and the image agree byte for byte, the exe needs
no runtime self-patching to explain anything, and the faulting instruction is
exactly the file's `8B 00` at `0x0047D540`. Verified by locating the in-memory
byte patterns in the file at their RVA-derived offsets (delta 0x0 for
`0x00404000`, `0x0047D4D4` and `0x0047D530`).

**Fix candidate (designed, not applied).** The call site needs 16 bytes —
`mov eax,[eax+0xA58]` (6), `test eax,eax` (2), `jz +6` (2), `push eax` (1),
`mov eax,[eax]` (2), `call [eax+0x28]` (3) — but only 12 are available before
`0x0047D545`, and skipping the call must not disturb the stack, since the callee
consumes the pushed interface. The clean shape is therefore a five-byte
`jmp` placed at `0x0047D539` into the CODE section's slack
(`0x97EFC`–`0x98000`, ~0x104 mapped-but-unused bytes), the guarded sequence
there, and a `jmp 0x0047D545` back. It must be verified twice: audio-only opens
with no dialog, and video+audio still renders frames.

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
4. The audio-only crash is patchable without touching anything else: one guard,
   one code cave, two tests. It is worth doing before any rebuild, because it
   proves the 2001 binary can still be corrected rather than merely wrapped.
