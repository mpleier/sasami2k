<#
.SYNOPSIS
    Packs the portable tree into a single self-extracting executable.

.DESCRIPTION
    Compiles tools\singlefile\Bootstrapper.cs, appends a ZIP of the portable
    build and a 24-byte footer, and writes build\SASAMI2k-portable.exe.

    On first run the executable unpacks its payload next to itself into
    SASAMI2k.data (or %LOCALAPPDATA%\SASAMI2k.data when that is not writable)
    and then calls tools\portable.ps1 launch with the caller's arguments.
    Settings therefore persist in SASAMI2k.data between runs.

    The ZIP is written with a fixed timestamp for every entry so repeated builds
    of the same tree are byte-identical.

.PARAMETER OutFile
    Output executable. Defaults to build\SASAMI2k-portable.exe.

.PARAMETER Source
    Portable tree to embed. Defaults to build\portable (built when missing).

.PARAMETER SkipVerify
    Skip the extraction self-test.

.EXAMPLE
    .\tools\make-singlefile.ps1
    .\tools\make-singlefile.ps1 -OutFile D:\SASAMI2k-portable.exe -SkipVerify
#>
[CmdletBinding()]
param(
    [string]$OutFile,
    [string]$Source,
    [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
$Root      = Split-Path -Parent $ScriptDir

if (-not $OutFile) { $OutFile = Join-Path $Root 'build\SASAMI2k-portable.exe' }
if (-not $Source)  { $Source  = Join-Path $Root 'build\portable' }

$csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$refDir = Split-Path -Parent $csc
$stubSource = Join-Path $ScriptDir 'singlefile\Bootstrapper.cs'

function Write-Step { param($t) Write-Host "==> $t" -ForegroundColor Cyan }
function Write-Ok   { param($t) Write-Host "    $t" -ForegroundColor Green }

# ---------------------------------------------------------------- preflight
Write-Step "Checking inputs"
if (-not (Test-Path -LiteralPath $csc)) { throw "csc.exe not found: $csc" }
if (-not (Test-Path -LiteralPath $stubSource)) { throw "Bootstrapper source missing: $stubSource" }
Write-Ok "csc $csc"

if (-not (Test-Path -LiteralPath $Source)) {
    Write-Step "No portable tree at $Source - running tools\build.ps1"
    & (Join-Path $ScriptDir 'build.ps1') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "tools\build.ps1 failed" }
}
$sourceFiles = Get-ChildItem -LiteralPath $Source -Recurse -File
Write-Ok "source tree: $($sourceFiles.Count) files, $([math]::Round(($sourceFiles | Measure-Object -Property Length -Sum).Sum/1MB,2)) MB"

$work = Join-Path $Root 'build\_sfx'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null

try {
    # ------------------------------------------------------------ payload zip
    Write-Step "Building payload archive"
    $zipPath = Join-Path $work 'payload.zip'
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem | Out-Null

    $sourceFull = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\') + '\'
    $files = $sourceFiles | Sort-Object FullName
    $fixedTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)

    $zipStream = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    try {
        $zip = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            foreach ($f in $files) {
                $rel = $f.FullName.Substring($sourceFull.Length).Replace('\', '/')
                $entry = $zip.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = $fixedTime
                $out = $entry.Open()
                try {
                    $in = [System.IO.File]::OpenRead($f.FullName)
                    try { $in.CopyTo($out) } finally { $in.Dispose() }
                }
                finally { $out.Dispose() }
            }
        }
        finally { $zip.Dispose() }
    }
    finally { $zipStream.Dispose() }

    $zipInfo = Get-Item -LiteralPath $zipPath
    Write-Ok ("{0:N0} bytes, ratio {1:P0}" -f $zipInfo.Length, ($zipInfo.Length / ($sourceFiles | Measure-Object -Property Length -Sum).Sum))

    # ------------------------------------------------------------ compile stub
    Write-Step "Compiling bootstrapper"
    $stub = Join-Path $work 'stub.exe'
    $cscArgs = @(
        '/nologo', '/target:winexe', '/optimize+', '/platform:anycpu',
        ('/out:' + $stub),
        '/r:System.dll',
        ('/r:' + (Join-Path $refDir 'System.IO.Compression.dll')),
        ('/r:' + (Join-Path $refDir 'System.IO.Compression.FileSystem.dll')),
        $stubSource
    )
    $cscOutput = & $csc @cscArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        $cscOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        throw "csc failed with exit code $LASTEXITCODE"
    }
    Write-Ok "stub: $((Get-Item -LiteralPath $stub).Length) bytes"

    # ------------------------------------------------------------ assemble
    Write-Step "Assembling single file"
    $outDir = Split-Path -Parent $OutFile
    if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
    if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile -Force }

    $stubLen = (Get-Item -LiteralPath $stub).Length
    $zipLen  = (Get-Item -LiteralPath $zipPath).Length
    $fs = [System.IO.File]::Create($OutFile)
    try {
        $stubBytes = [System.IO.File]::ReadAllBytes($stub)
        $fs.Write($stubBytes, 0, $stubBytes.Length)
        $zipBytes = [System.IO.File]::ReadAllBytes($zipPath)
        $fs.Write($zipBytes, 0, $zipBytes.Length)

        $footer = New-Object byte[] 24
        [System.Text.Encoding]::ASCII.GetBytes('S2KSFX01').CopyTo($footer, 0)
        [BitConverter]::GetBytes([int64]$stubLen).CopyTo($footer, 8)
        [BitConverter]::GetBytes([int64]$zipLen).CopyTo($footer, 16)
        $fs.Write($footer, 0, 24)
    }
    finally { $fs.Dispose() }

    $outInfo = Get-Item -LiteralPath $OutFile
    $hash = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLower()
    Write-Ok ("{0}  {1:N0} bytes" -f $outInfo.Name, $outInfo.Length)
    Write-Ok "sha256 $hash"

    # ------------------------------------------------------------ self-test
    if (-not $SkipVerify) {
        Write-Step "Self-test: extract and compare with the source tree"
        $tmp = Join-Path $work 'extract-test'
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
        # CreateProcess, not Start-Process: the freshly built bootstrapper is
        # unsigned, and going through the shell raises "The publisher could not
        # be verified" on hosts that prompt for unsigned programs - which blocks
        # this self-test forever instead of failing.
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $OutFile
        $psi.Arguments = '--s2k-extract-only --s2k-target "' + $tmp + '"'
        $psi.UseShellExecute = $false
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.WaitForExit()
        if ($p.ExitCode -ne 0) { throw "self-extraction failed with exit code $($p.ExitCode)" }

        $produced = Get-ChildItem -LiteralPath $tmp -Recurse -File |
                    Where-Object { $_.Name -ne '.payload-stamp' } |
                    ForEach-Object { $_.FullName.Substring($tmp.Length + 1) }
        $missing = @(); $differ = @()
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($sourceFull.Length)
            $candidate = Join-Path $tmp $rel
            if (-not (Test-Path -LiteralPath $candidate)) { $missing += $rel; continue }
            if ((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash -ne
                (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash) { $differ += $rel }
        }
        if ($missing.Count -or $differ.Count) {
            $missing | ForEach-Object { Write-Host "    missing: $_" -ForegroundColor Yellow }
            $differ  | ForEach-Object { Write-Host "    differs: $_" -ForegroundColor Yellow }
            throw "Self-test mismatch"
        }
        Write-Ok "all $($files.Count) files extract byte-identically"

        Remove-Item -LiteralPath $tmp -Recurse -Force
    }

    Write-Step "Done"
    Write-Ok "single file: $OutFile"
}
finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
