<#
.SYNOPSIS
    Rebuilds the portable SASAMI2k tree from the pristine installer.

.DESCRIPTION
    Reproduces app\ byte-for-byte from original\sasami2k_757.exe:

      1. verify the installer's SHA-256
      2. extract the InstallFactory payload (CRC-checked, tools\extract_installer.py)
      3. UPX-unpack sasami2000.exe
      4. apply the import-thunk patch and rename to sasami2k.exe (tools\compat_fixes.py)
      5. re-encode the RLE8 skin bitmaps as BI_RGB (tools\compat_fixes.py)
      6. derive SASAMI2k.default.ini from the shipped ini
      7. copy the launcher and docs
      8. verify every produced file against HASHES.txt

    Nothing is written until step 2 writes into a temporary work directory; the
    output directory is created fresh.

.PARAMETER Installer
    Path to the original installer. Defaults to original\sasami2k_757.exe.

.PARAMETER OutDir
    Where the portable tree is produced. Defaults to build\portable.

.PARAMETER Upx
    Path to upx.exe. Auto-detected on PATH or under tools\upx-*\ when omitted.

.PARAMETER KeepWork
    Keep the temporary extraction/unpack directory for inspection.

.EXAMPLE
    .\tools\build.ps1
    .\tools\build.ps1 -OutDir D:\build\sasami2k -KeepWork
#>
[CmdletBinding()]
param(
    [string]$Installer,
    [string]$OutDir,
    [string]$Upx,
    [switch]$KeepWork
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
$Root      = Split-Path -Parent $ScriptDir

if (-not $Installer) { $Installer = Join-Path $Root 'original\sasami2k_757.exe' }
if (-not $OutDir)    { $OutDir    = Join-Path $Root 'build\portable' }

$ExpectedInstallerSha = '4e2b22e4c280d19f804bbc3594f8b9c308179f8481f8b61f84e7bd1aeb88ee21'

# The shipped SASAMI2k.ini is the author's session state, not a neutral default.
# These overrides make the first run portable and predictable.
$IniOverrides = [ordered]@{
    'Sasami.LastDirectory'                  = ''
    'Sasami.Window.Position.Top'            = '0'
    'Sasami.Window.Position.Left'           = '0'
    'Sasami.Volume.Value'                   = '21595'
    'Sasami.Preference.CustomSize.x'        = '320'
    'Sasami.Preference.CustomSize.y'        = '240'
    'Sasami.Preference.ActWhenActivated'    = '2'
}

# Launcher artefacts that live in the repository, not in the installer payload.
$LauncherFiles = @('SASAMI2k.cmd','RegisterFilters.cmd','UnregisterFilters.cmd','Status.cmd',
                   'Associate.cmd','Unassociate.cmd','IDEA.md','DOSSIER.md',
                   'README.md','PATCHES.md','HASHES.txt','.gitattributes','.gitignore')
$LauncherTools = @('portable.ps1','extract_installer.py','compat_fixes.py','build.ps1',
                   'make-singlefile.ps1','manifest.py','lav-audio.ps1')
# Sub-directories under tools\ that belong to the rebuild toolchain (copied whole).
$LauncherToolDirs = @('singlefile')

function Write-Step { param($Text) Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Ok   { param($Text) Write-Host "    $Text" -ForegroundColor Green }
function Write-Warn2{ param($Text) Write-Host "    $Text" -ForegroundColor Yellow }

function Resolve-Upx {
    param([string]$Explicit)
    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit)) { throw "upx.exe not found: $Explicit" }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }
    $vendored = Join-Path $ScriptDir 'upx\upx.exe'
    if (Test-Path -LiteralPath $vendored) { return (Resolve-Path -LiteralPath $vendored).Path }
    $cmd = Get-Command upx.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($base in @((Join-Path $Root 'tools'), (Split-Path -Parent $Root))) {
        if (-not (Test-Path -LiteralPath $base)) { continue }
        $hit = Get-ChildItem -LiteralPath $base -Directory -Filter 'upx*' -ErrorAction SilentlyContinue |
               ForEach-Object { Join-Path $_.FullName 'upx.exe' } |
               Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($hit) { return (Resolve-Path -LiteralPath $hit).Path }
    }
    throw "UPX not found. Put upx.exe on PATH, pass -Upx, or drop a upx-* folder under tools\."
}

function ConvertTo-DefaultIni {
    param([string]$Source, [string]$Destination, [System.Collections.Specialized.OrderedDictionary]$Overrides)
    $bytes = [System.IO.File]::ReadAllBytes($Source)
    $text  = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)   # latin-1: byte preserving
    $nl    = if ($text -match "`r`n") { "`r`n" } else { "`n" }
    $lines = $text -split "`r?`n"

    foreach ($key in $Overrides.Keys) {
        $value = $Overrides[$key]
        $found = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match ('^' + [regex]::Escape($key) + '=')) {
                $lines[$i] = "$key=$value"
                $found = $true
            }
        }
        if (-not $found) { Write-Warn2 "override not present in shipped ini: $key" }
    }
    $out = ($lines -join $nl)
    [System.IO.File]::WriteAllBytes($Destination, [System.Text.Encoding]::GetEncoding(28591).GetBytes($out))
}

# ---------------------------------------------------------------- preflight
Write-Step "Checking inputs"
if (-not (Test-Path -LiteralPath $Installer)) { throw "Installer not found: $Installer" }
$installerHash = (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash.ToLower()
if ($installerHash -ne $ExpectedInstallerSha) {
    throw "Installer SHA-256 mismatch: $installerHash (expected $ExpectedInstallerSha)"
}
Write-Ok "installer $([System.IO.Path]::GetFileName($Installer)) sha256 ok"

$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python) { $python = (Get-Command py -ErrorAction SilentlyContinue).Source }
if (-not $python) { throw "Python not found on PATH (needed by the extraction and patch tools)." }
Write-Ok "python $python"

$upxExe = Resolve-Upx -Explicit $Upx
Write-Ok "upx $upxExe"

# ---------------------------------------------------------------- workspace
$work = Join-Path $Root 'build\_work'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null

if (Test-Path -LiteralPath $OutDir) { Remove-Item -LiteralPath $OutDir -Recurse -Force }
$appOut = Join-Path $OutDir 'app'
New-Item -ItemType Directory -Force -Path $appOut | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $OutDir 'tools') | Out-Null

try {
    # ------------------------------------------------------------ 1. extract
    Write-Step "Extracting installer payload"
    $payload = Join-Path $work 'payload'
    & $python (Join-Path $ScriptDir 'extract_installer.py') $Installer $payload | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Payload extraction failed (exit $LASTEXITCODE)" }
    $packedExe = Join-Path $payload 'sasami2000.exe'
    if (-not (Test-Path -LiteralPath $packedExe)) { throw "Payload has no sasami2000.exe" }
    Write-Ok "payload extracted, $((Get-ChildItem $payload -Recurse -File | Measure-Object).Count) files"

    # ------------------------------------------------------------ 2. unpack
    Write-Step "UPX-unpacking the player"
    $unpacked = Join-Path $work 'sasami2000.unpacked.exe'
    $upxLog = & $upxExe -d $packedExe -o $unpacked 2>&1
    $upxLog | ForEach-Object { Write-Ok $_ }
    if (-not (Test-Path -LiteralPath $unpacked)) { throw "UPX did not produce $unpacked" }
    Write-Ok "unpacked: $((Get-Item -LiteralPath $unpacked).Length) bytes"

    # ------------------------------------------------------------ 3. patch
    Write-Step "Applying the import-thunk patch"
    & $python (Join-Path $ScriptDir 'compat_fixes.py') exe $unpacked (Join-Path $appOut 'sasami2k.exe') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "exe patch failed (exit $LASTEXITCODE)" }
    Write-Ok "sasami2k.exe $((Get-Item (Join-Path $appOut 'sasami2k.exe')).Length) bytes"

    # ------------------------------------------------------------ 4. bitmaps
    Write-Step "Re-encoding skin bitmaps (RLE8 -> BI_RGB)"
    & $python (Join-Path $ScriptDir 'compat_fixes.py') images (Join-Path $payload 'Imgs') (Join-Path $appOut 'Imgs') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "bitmap conversion failed (exit $LASTEXITCODE)" }
    Write-Ok "bitmaps converted"

    # ------------------------------------------------------------ 5. payload
    Write-Step "Copying payload files"
    $skip = @('sasami2000.exe','SASAMI2k.ini','SASAMI2k_Translator.ini','Imgs','_meta')
    Get-ChildItem -LiteralPath $payload -Force | Where-Object { $skip -notcontains $_.Name } | ForEach-Object {
        if ($_.PSIsContainer) {
            Copy-Item -LiteralPath $_.FullName -Destination $appOut -Recurse -Force
        } else {
            Copy-Item -LiteralPath $_.FullName -Destination $appOut -Force
        }
    }
    # _meta holds installer bookkeeping, not application files
    if (Test-Path (Join-Path $appOut '_meta')) { Remove-Item (Join-Path $appOut '_meta') -Recurse -Force }
    Write-Ok "copied"

    # ------------------------------------------------------------ 6. configs
    Write-Step "Deriving default settings"
    ConvertTo-DefaultIni -Source (Join-Path $payload 'SASAMI2k.ini') `
                         -Destination (Join-Path $appOut 'SASAMI2k.default.ini') `
                         -Overrides $IniOverrides
    Copy-Item -LiteralPath (Join-Path $payload 'SASAMI2k_Translator.ini') `
              -Destination (Join-Path $appOut 'SASAMI2k_Translator.default.ini') -Force
    Write-Ok "SASAMI2k.default.ini, SASAMI2k_Translator.default.ini"

    # ------------------------------------------------------------ 7. launcher
    Write-Step "Copying launcher and docs"
    foreach ($f in $LauncherFiles) {
        $src = Join-Path $Root $f
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $OutDir -Force }
    }
    foreach ($f in $LauncherTools) {
        $src = Join-Path $ScriptDir $f
        if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $OutDir 'tools') -Force }
    }
    foreach ($d in $LauncherToolDirs) {
        $src = Join-Path $ScriptDir $d
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $OutDir 'tools') -Recurse -Force
        }
    }
    Write-Ok "launcher scripts in place"

    # ------------------------------------------------------------ 8. verify
    Write-Step "Verifying against HASHES.txt"
    $manifest = Join-Path $Root 'HASHES.txt'
    $expected = @{}
    foreach ($line in Get-Content -LiteralPath $manifest) {
        if ($line -match '^#') { continue }
        if ($line -match '^([0-9a-f]{64})\s+(\d+)\s+(\S.*)$') {
            $expected[$Matches[3].Trim()] = @{ Hash = $Matches[1]; Size = [int]$Matches[2] }
        }
    }
    $checked = 0; $mismatch = @(); $missing = @()
    # HASHES.txt describes the repository. original\ (the pristine installer) and
    # tools\upx\ (the rebuild-only packer) are inputs to this script, not outputs.
    $inputPrefixes = @('original/','tools/upx/')
    foreach ($rel in $expected.Keys) {
        if ($inputPrefixes | Where-Object { $rel.StartsWith($_, 'OrdinalIgnoreCase') }) { continue }
        $path = Join-Path $OutDir ($rel -replace '/', '\')
        if (-not (Test-Path -LiteralPath $path)) { $missing += $rel; continue }
        $h = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
        if ($h -ne $expected[$rel].Hash) { $mismatch += "$rel  got $h  expected $($expected[$rel].Hash)" }
        $checked++
    }
    if ($missing.Count)  { Write-Warn2 "missing ($($missing.Count)):"; $missing  | ForEach-Object { Write-Warn2 "  $_" } }
    if ($mismatch.Count) { Write-Warn2 "mismatched ($($mismatch.Count)):"; $mismatch | ForEach-Object { Write-Warn2 "  $_" } }
    if (-not $missing.Count -and -not $mismatch.Count) {
        Write-Ok "all $checked manifest entries reproduce exactly"
    }

    Write-Step "Done"
    Write-Ok "output: $OutDir"
    $size = (Get-ChildItem -LiteralPath $OutDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
    Write-Ok ("$([math]::Round($size/1MB,1)) MB, $((Get-ChildItem -LiteralPath $OutDir -Recurse -File | Measure-Object).Count) files")
    if ($mismatch.Count -or $missing.Count) { exit 1 }
}
finally {
    if ($KeepWork) { Write-Host "    work dir kept: $work" -ForegroundColor Yellow }
    elseif (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
