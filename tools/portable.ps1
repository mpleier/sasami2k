#Requires -Version 5.1
<#
    portable.ps1 - launcher / filter registration helper for the portable SASAMI2k tree.

    SASAMI2k is a DirectShow application: the player creates its video/audio filters
    through COM, so the three .ax modules must be registered (the original installer
    did this silently via "Sasami2000.exe /register" -> 32-bit regsvr32).

    Because COM/DirectShow registration is machine- or user-scoped by design, a
    DirectShow app can never be 100% "no registry". This script keeps the footprint
    minimal, local and reversible:
      * machine registration via the bundled 32-bit regsvr32 (needs admin), or
      * per-user registration in HKCU\Software\Classes (no admin needed).

    Actions: launch (default), register, unregister, status.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('launch', 'register', 'unregister', 'status')]
    [string]$Action = 'launch',

    # Force per-user registration (no elevation).
    [switch]$PerUser,

    # Force machine-wide registration (elevates if needed).
    [switch]$Machine,

    # Anything after the action is passed through to the player, e.g.:
    #   SASAMI2k.cmd "D:\movie.avi"
    #   SASAMI2k.cmd /fullscreen "D:\movie.avi"
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PlayerArgs
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
$Root      = Split-Path -Parent $ScriptDir
$AppDir    = Join-Path $Root 'app'
$PlayerExe = Join-Path $AppDir 'sasami2k.exe'
# Machine-wide (un)registration runs regsvr32 on the filter modules. Prefer the
# system's 32-bit regsvr32: System32\regsvr32.exe is the 64-bit build and cannot
# register a 32-bit DirectShow filter, but SysWOW64\regsvr32.exe is the matching
# 32-bit one. The bundled copy (a 1999-era build shipped with the installer) is
# only a fallback for hosts without SysWOW64.
$SystemRegsvr  = Join-Path $env:SystemRoot 'SysWOW64\regsvr32.exe'
$BundledRegsvr = Join-Path $AppDir 'regsvr32.exe'
$RegsvrExe     = if (Test-Path -LiteralPath $SystemRegsvr) { $SystemRegsvr } else { $BundledRegsvr }

# CLSIDs and display names as registered by each module's DllRegisterServer
# (recovered from the AMOVIESETUP_FILTER records in the binaries).
$Filters = @(
    [pscustomobject]@{ File = 'Sasami.ax';    Clsid = '{6FFBDFFE-C9CE-11D3-BBAA-52544C191AD1}'; Name = "Nuclei's Sasami" }
    [pscustomobject]@{ File = 'Sasami4a.ax';  Clsid = '{6FFBDFFE-C9CE-11DB-BBAA-52544C191AD1}'; Name = "Nuclei's Sasami for Audio" }
    [pscustomobject]@{ File = 'Sasamiv4a.ax'; Clsid = '{FD501041-8EBE-11DE-8183-00AA00577DA1}'; Name = "Nuclei's Video for Audio" }
)

# The player rewrites its settings on exit. Live copies are created from the
# shipped defaults on first run, so the repository stays clean while preferences
# still live (and travel) with the folder.
$ConfigDefaults = @(
    [pscustomobject]@{ Live = 'SASAMI2k.ini';            Default = 'SASAMI2k.default.ini' }
    [pscustomobject]@{ Live = 'SASAMI2k_Translator.ini'; Default = 'SASAMI2k_Translator.default.ini' }
)

function Write-Head([string]$Text)  { Write-Host ""; Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Info([string]$Text)  { Write-Host "   $Text" }
function Write-Ok([string]$Text)    { Write-Host "   $Text" -ForegroundColor Green }
function Write-Warn2([string]$Text) { Write-Host "   $Text" -ForegroundColor Yellow }
function Write-Err2([string]$Text)  { Write-Host "   $Text" -ForegroundColor Red }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Normalize-Path([string]$Path) {
    if (-not $Path) { return '' }
    $p = $Path.Trim().Trim('"')
    if ($p.StartsWith('\??\')) { $p = $p.Substring(4) }
    try { $p = [IO.Path]::GetFullPath($p) } catch { }
    return $p.TrimEnd('\').ToLowerInvariant()
}

# Runs reg.exe without letting its "ERROR: ..." stderr terminate the script.
function Invoke-RegQuery([string]$Key, [string]$View) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $out = & reg.exe query $Key /ve $View 2>&1
        if ($LASTEXITCODE -eq 0 -and $out) {
            foreach ($line in $out) {
                if (([string]$line) -match 'REG_SZ\s+(.+?)\s*$') { return $Matches[1] }
            }
        }
    }
    finally {
        $ErrorActionPreference = $prev
    }
    return $null
}

function Get-ExpectedPath([object]$Filter) { return (Join-Path $AppDir $Filter.File) }

# Materialises the live settings files from the shipped defaults when absent.
function Initialize-ConfigFiles {
    foreach ($c in $ConfigDefaults) {
        $live = Join-Path $AppDir $c.Live
        $dflt = Join-Path $AppDir $c.Default
        if (-not (Test-Path -LiteralPath $live) -and (Test-Path -LiteralPath $dflt)) {
            Copy-Item -LiteralPath $dflt -Destination $live -Force
            Write-Info "Created $($c.Live) from $($c.Default)."
        }
    }
}

# Per-user COM entries for a 32-bit in-process server must live in the WOW64
# ("Wow6432Node") view of HKCU\Software\Classes. Writing the plain key puts them
# where only 64-bit clients look: a 32-bit player then fails CoCreateInstance
# with REGDB_E_CLASSNOTREG and silently refuses to build its filter graph.
$UserClsidRoot32 = 'HKCU:\Software\Classes\Wow6432Node\CLSID'
$UserClsidRoot64 = 'HKCU:\Software\Classes\CLSID'

function Get-UserPathFor([string]$Root, [string]$Clsid) {
    $key = Join-Path $Root "$Clsid\InprocServer32"
    if (-not (Test-Path -LiteralPath $key)) { return $null }
    $v = (Get-ItemProperty -Path $key -Name '(default)' -ErrorAction SilentlyContinue).'(default)'
    if ($v) { return $v }
    return $null
}

# Returns effective per-user and machine-wide InprocServer32 values for a CLSID.
function Get-RegistrationInfo([object]$Filter) {
    $clsid = $Filter.Clsid
    $expected = Normalize-Path (Get-ExpectedPath $Filter)

    # Only the WOW64 view is visible to the 32-bit player, so only that view
    # counts as registered. A leftover entry in the plain view is reported but
    # never treated as sufficient.
    $userPath  = Get-UserPathFor $UserClsidRoot32 $clsid
    $legacy64  = Get-UserPathFor $UserClsidRoot64 $clsid

    $machinePath = $null
    foreach ($view in @('/reg:32', '/reg:64')) {
        $v = Invoke-RegQuery "HKLM\SOFTWARE\Classes\CLSID\$clsid\InprocServer32" $view
        if ($v) { $machinePath = $v; break }
    }

    return [pscustomobject]@{
        UserPath     = $userPath
        Legacy64Path = $legacy64
        MachinePath  = $machinePath
        Path         = $(if ($userPath) { $userPath } elseif ($legacy64) { $legacy64 } else { $machinePath })
        UserOwned    = [bool]($userPath -and (Normalize-Path $userPath) -eq $expected)
        MachineOwned = [bool]($machinePath -and (Normalize-Path $machinePath) -eq $expected)
    }
}

# Filters that are not registered to this folder (absent or pointing elsewhere).
function Get-PendingFilters {
    $pending = @()
    foreach ($f in $Filters) {
        $info = Get-RegistrationInfo $f
        if (-not ($info.UserOwned -or $info.MachineOwned)) { $pending += $f }
    }
    return $pending
}

function Invoke-MachineRegister([object[]]$List) {
    if (-not (Test-Path -LiteralPath $RegsvrExe)) { throw "No 32-bit regsvr32.exe available (looked for $SystemRegsvr and $BundledRegsvr)" }
    Write-Info ("Registering with the 32-bit regsvr32 ({0}) (machine-wide)..." -f (Split-Path -Leaf (Split-Path -Parent $RegsvrExe)))
    foreach ($f in $List) {
        $path = Get-ExpectedPath $f
        if (-not (Test-Path -LiteralPath $path)) { throw "Missing filter module: $path" }
        & $RegsvrExe /s $path | Out-Null
        Write-Info ("regsvr32 /s `"{0}`"" -f $path)
    }
}

function Invoke-PerUserRegister([object[]]$List) {
    Write-Info "Registering per-user in HKCU\Software\Classes\Wow6432Node (32-bit view)..."
    foreach ($f in $List) {
        $path = Get-ExpectedPath $f
        if (-not (Test-Path -LiteralPath $path)) { throw "Missing filter module: $path" }

        $base = Join-Path $UserClsidRoot32 $f.Clsid
        New-Item -Path $base -Force | Out-Null
        Set-ItemProperty -Path $base -Name '(default)' -Value $f.Name
        $inproc = Join-Path $base 'InprocServer32'
        New-Item -Path $inproc -Force | Out-Null
        Set-ItemProperty -Path $inproc -Name '(default)' -Value $path
        New-ItemProperty -Path $inproc -Name 'ThreadingModel' -Value 'Both' `
            -PropertyType String -Force | Out-Null

        # drop a stale 64-bit-view copy left by an earlier build of this script
        $legacy = Join-Path $UserClsidRoot64 $f.Clsid
        if (Test-Path -LiteralPath $legacy) {
            $lv = Join-Path $legacy 'InprocServer32'
            $lvp = (Get-ItemProperty -Path $lv -Name '(default)' -ErrorAction SilentlyContinue).'(default)'
            if ($lvp -and (Normalize-Path $lvp) -eq (Normalize-Path $path)) {
                Remove-Item -Path $legacy -Recurse -Force
            }
        }
        Write-Info "$($f.Clsid) -> $path"
    }
}

function Invoke-MachineUnregister([object[]]$List) {
    if (-not (Test-Path -LiteralPath $RegsvrExe)) { throw "No 32-bit regsvr32.exe available (looked for $SystemRegsvr and $BundledRegsvr)" }
    Write-Info ("Unregistering machine-wide entries with {0}..." -f (Split-Path -Leaf $RegsvrExe))
    foreach ($f in $List) {
        $path = Get-ExpectedPath $f
        if (Test-Path -LiteralPath $path) {
            & $RegsvrExe /u /s $path | Out-Null
            Write-Info ("regsvr32 /u /s `"{0}`"" -f $path)
        }
    }
}

function Invoke-PerUserUnregister([object[]]$List) {
    Write-Info "Removing per-user registrations owned by this folder..."
    foreach ($f in $List) {
        $expected = Normalize-Path (Get-ExpectedPath $f)
        foreach ($root in @($UserClsidRoot32, $UserClsidRoot64)) {
            $base = Join-Path $root $f.Clsid
            if (-not (Test-Path -LiteralPath $base)) { continue }
            $inproc = Join-Path $base 'InprocServer32'
            $cur = (Get-ItemProperty -Path $inproc -Name '(default)' -ErrorAction SilentlyContinue).'(default)'
            if ($cur -and (Normalize-Path $cur) -eq $expected) {
                Remove-Item -Path $base -Recurse -Force
                Write-Info "$($f.Clsid) removed"
            }
        }
    }
}

function Show-Status {
    Write-Head "SASAMI2k portable"
    Write-Info ("Folder   : {0}" -f $Root)
    Write-Info ("Player   : {0}" -f $(if (Test-Path -LiteralPath $PlayerExe) { 'present' } else { 'MISSING' }))
    Write-Info ("Elevated : {0}" -f $(if (Test-Admin) { 'yes' } else { 'no' }))
    Write-Head "DirectShow filters"
    foreach ($f in $Filters) {
        $info = Get-RegistrationInfo $f
        $scope = @()
        if ($info.MachineOwned) { $scope += 'machine' }
        if ($info.UserOwned)    { $scope += 'user' }
        if ($scope.Count) {
            Write-Ok ("{0,-13} {1}  -> OK [{2}]" -f $f.File, $f.Clsid, ($scope -join '+'))
        }
        elseif ($info.Legacy64Path) {
            Write-Warn2 ("{0,-13} {1}  -> only in the 64-bit view; the 32-bit player cannot see it" -f $f.File, $f.Clsid)
        }
        elseif ($info.Path) {
            Write-Warn2 ("{0,-13} {1}  -> points elsewhere: {2}" -f $f.File, $f.Clsid, $info.Path)
        }
        else {
            Write-Warn2 ("{0,-13} {1}  -> not registered" -f $f.File, $f.Clsid)
        }
    }
}

function Resolve-RegisterMode {
    if ($PerUser)   { return 'peruser' }
    if ($Machine)   { return 'machine' }
    if (Test-Admin) { return 'machine' }
    return 'peruser'
}

function Invoke-Register {
    $mode = Resolve-RegisterMode
    if ($mode -eq 'machine' -and -not (Test-Admin)) {
        Write-Info "Requesting administrator rights..."
        $args = '-NoProfile -ExecutionPolicy Bypass -File "{0}" register -Machine' -f $PSCommandPath
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $args | Out-Null
        return 0
    }
    $pending = @(Get-PendingFilters)
    if (-not $pending.Count) { Write-Ok "All filters already registered to this folder."; return 0 }
    if ($mode -eq 'machine') { Invoke-MachineRegister $pending }
    else                     { Invoke-PerUserRegister $pending }
    $left = @(Get-PendingFilters)
    if ($left.Count) {
        Write-Err2 "Registration did not take effect for: $($left.File -join ', ')"
        return 1
    }
    Write-Ok "Filters registered to this folder."
    return 0
}

function Invoke-Unregister {
    $machineList = @(); $userList = @()
    foreach ($f in $Filters) {
        $info = Get-RegistrationInfo $f
        if ($info.MachineOwned) { $machineList += $f }
        if ($info.UserOwned)    { $userList    += $f }
    }
    $machineList = @($machineList); $userList = @($userList)
    if (-not $machineList.Count -and -not $userList.Count) {
        Write-Ok "Nothing registered to this folder; nothing to remove."
        return 0
    }
    if ($machineList.Count) {
        if (Test-Admin) {
            Invoke-MachineUnregister $machineList
        }
        else {
            Write-Info "Requesting administrator rights to remove machine-wide registration..."
            $args = '-NoProfile -ExecutionPolicy Bypass -File "{0}" unregister -Machine' -f $PSCommandPath
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $args | Out-Null
            return 0
        }
    }
    if ($userList.Count) { Invoke-PerUserUnregister $userList }
    Write-Ok "Done."
    return 0
}

try {
    if (-not (Test-Path -LiteralPath $AppDir)) { throw "app folder not found: $AppDir" }
    Initialize-ConfigFiles

    switch ($Action) {
        'status' { Show-Status; exit 0 }

        'register' { exit (Invoke-Register) }

        'unregister' { exit (Invoke-Unregister) }

        'launch' {
            $pending = @(Get-PendingFilters)
            if ($pending.Count) {
                Write-Head "First run / folder moved - registering filters"
                $rc = Invoke-Register
                if ($rc -ne 0) { Write-Warn2 "Continuing anyway; playback may fail." }
            }
            if (-not (Test-Path -LiteralPath $PlayerExe)) { throw "player not found: $PlayerExe" }
            Write-Head "Starting SASAMI2k"

            $argList = @()
            if ($PlayerArgs) {
                $argList = @($PlayerArgs | Where-Object { $_ -ne $null -and $_ -ne '' })
            }
            if ($argList.Count) { Write-Info ("args: " + ($argList -join ' ')) }

            # NB: Start-Process rejects an empty -ArgumentList on Windows PowerShell 5.1,
            # so only pass the parameter when there is something to pass.
            $startParams = @{ FilePath = $PlayerExe; WorkingDirectory = $AppDir }
            if ($argList.Count) { $startParams['ArgumentList'] = [string[]]$argList }
            Start-Process @startParams | Out-Null
            exit 0
        }
    }
}
catch {
    Write-Err2 $_.Exception.Message
    exit 1
}
