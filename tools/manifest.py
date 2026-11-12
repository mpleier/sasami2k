#!/usr/bin/env python3
"""Regenerate or check HASHES.txt.

HASHES.txt is the byte-level contract of this repository: every shipped file,
its size and its SHA-256. `tools/build.ps1` and `Status.cmd verify` both check
against it, so it has to be regenerated whenever a tracked file changes.

    python tools/manifest.py write     # rewrite HASHES.txt from the working tree
    python tools/manifest.py check     # verify the tree against HASHES.txt

Format (one record per line, ordinal-sorted by path):

    <sha256>  <size right aligned to 10>  <path with forward slashes>

Files that are never part of the manifest: this build/ directory, the per-user
runtime state the player rewrites (SASAMI2k.ini, SASAMI2k_Translator.ini,
sasami2k.m3u), the manifest itself and local scratch notes.
"""
import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "HASHES.txt")

IGNORED_PREFIXES = ("build/", ".git/")
IGNORED_NAMES = {
    "HASHES.txt",
    "SASAMI2k.ini",
    "SASAMI2k_Translator.ini",
    "sasami2k.m3u",
}


def iter_files():
    for dirpath, dirnames, filenames in os.walk(ROOT):
        rel_dir = os.path.relpath(dirpath, ROOT).replace("\\", "/")
        if rel_dir == ".":
            rel_dir = ""
        dirnames[:] = sorted(
            d for d in dirnames
            if not (rel_dir + "/" + d).lstrip("/").startswith(IGNORED_PREFIXES)
        )
        for name in sorted(filenames):
            rel = (rel_dir + "/" + name).lstrip("/")
            if rel.startswith(IGNORED_PREFIXES):
                continue
            if name in IGNORED_NAMES:
                continue
            yield rel


def digest(rel):
    path = os.path.join(ROOT, rel.replace("/", os.sep))
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest(), os.path.getsize(path)


def write_manifest():
    lines = [
        "# SHA-256 manifest - portable SASAMI2k Core #757",
        "# Covers every tracked file. See PATCHES.md for the documented fixes and",
        "# tools/ for the scripts that reproduce both the pristine payload and the fixes.",
        "# Regenerate with: python tools/manifest.py write",
        "",
    ]
    records = []
    for rel in iter_files():
        sha, size = digest(rel)
        records.append((rel, sha, size))
    records.sort(key=lambda r: r[0].lower())   # case-insensitive, like the original file
    for rel, sha, size in records:
        lines.append("%s %9d  %s" % (sha, size, rel))
    # CRLF: the repository stores bytes verbatim (.gitattributes sets "* -text"),
    # and the manifest has always been a CRLF file.
    with open(MANIFEST, "w", encoding="utf-8", newline="") as fh:
        fh.write("\r\n".join(lines) + "\r\n")
    print("wrote %s (%d entries)" % (os.path.relpath(MANIFEST, ROOT), len(records)))


def read_manifest():
    entries = {}
    with open(MANIFEST, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.lstrip().startswith("#"):
                continue
            parts = line.split(None, 2)
            if len(parts) != 3:
                print("unparseable manifest line: %r" % line)
                continue
            sha, size, rel = parts[0], int(parts[1]), parts[2].strip()
            entries[rel] = (sha, size)
    return entries


def check():
    if not os.path.exists(MANIFEST):
        print("FAIL: no HASHES.txt")
        return 1
    entries = read_manifest()
    problems = 0
    checked = 0
    for rel, (sha, size) in entries.items():
        path = os.path.join(ROOT, rel.replace("/", os.sep))
        if not os.path.exists(path):
            print("missing : %s" % rel)
            problems += 1
            continue
        got_sha, got_size = digest(rel)
        if got_size != size:
            print("size    : %s is %d, manifest says %d" % (rel, got_size, size))
            problems += 1
        elif got_sha != sha:
            print("sha256  : %s is %s, manifest says %s" % (rel, got_sha, sha))
            problems += 1
        checked += 1
    listed = set(entries)
    for rel in iter_files():
        if rel not in listed:
            print("unlisted: %s" % rel)
    if problems:
        print("FAIL: %d problem(s) across %d checked file(s)" % (problems, checked))
        return 1
    print("OK: %d files match HASHES.txt" % checked)
    return 0


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "check"
    if action == "write":
        write_manifest()
        sys.exit(0)
    if action == "check":
        sys.exit(check())
    print(__doc__)
    sys.exit(2)
