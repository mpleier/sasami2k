#Requires -Version 5.1
<#
    lav-audio.ps1 - inspect and steer which 32-bit DirectShow filter decodes audio
    for SASAMI2k (and every other 32-bit DirectShow app on the machine).

    DirectShow picks a decoder by *merit*: the highest-merit filter that accepts
    the media type wins. The filter-mapper registrations for both the quartz
    "MPEG Audio Decoder" and LAV's "LAV Audio Decoder" live under

        HKLM\SOFTWARE\Classes\Wow6432Node\CLSID\{083863F1-70DE-11D0-BD40-00A0C911CE86}\Instance\<clsid>

    (the System Device Enumerator category key). A missing Merit value means the
    filter is registered with the system default, so two decoders can tie.

    Actions:
      status   (default) list the audio decoders a 32-bit graph can choose, with merit
      prefer   give LAV Audio Decoder an explicit MERIT_PREFERRED (needs elevation)
      default  drop that explicit merit again (needs elevation)

    Nothing here is installed or replaced: LAV must already be registered as a
    DirectShow filter (K-Lite's "register LAV Filters", or the LAV installer).
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'prefer', 'default')]
    [string]$Action = 'status',

    # Used by the self-elevation path: the elevated child records its output here
    # so the non-elevated parent can show it (the UAC process has its own console).
    [string]$LogPath = ''
)

$ErrorActionPreference = 'Stop'

$Template    = 'SOFTWARE\Classes\Wow6432Node\CLSID\{083863F1-70DE-11D0-BD40-00A0C911CE86}\Instance'
$LavAudioClsid  = '{E8E73B6B-4CB3-44A4-BE99-4F7BCB96E491}'   # LAV Audio Decoder
$LavAudioName   = 'LAV Audio Decoder'
$QuartzAudioName = 'MPEG Audio Decoder'                       # quartz's own MPEG audio decoder
$MeritPreferred = 0x00800000
$StateKey       = 'HKLM:\SOFTWARE\SASAMI2k\LavAudio'

function Write-Head([string]$Text) { Write-Host ""; Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Info([string]$Text) { Write-Host "   $Text" }
function Write-Ok([string]$Text)   { Write-Host "   $Text" -ForegroundColor Green }
function Write-Warn2([string]$Text){ Write-Host "   $Text" -ForegroundColor Yellow }
function Write-Err2([string]$Text) { Write-Host "   $Text" -ForegroundColor Red }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-InstanceKeys([string]$Hive) {
    $root = if ($Hive -eq 'HKLM') { "HKLM:\$Template" } else { "HKCU:\$Template" }
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    return @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)
}

# Every filter instance registered in the 32-bit view whose InprocServer32 or
# FriendlyName looks audio-ish, plus the CLSID's module path.
function Get-AudioDecoders {
    $rows = @()
    foreach ($inst in Get-InstanceKeys 'HKLM') {
        $p = Get-ItemProperty -Path $inst.PSPath -ErrorAction SilentlyContinue
        $name = $p.FriendlyName
        if (-not $name) { continue }
        if ($name -notmatch 'audio|ac3|dts|aac|mpeg') { continue }
        $clsid = $p.CLSID
        if (-not $clsid) { $clsid = Split-Path $inst.PSChildName -Leaf }
        $module = $null
        foreach ($hive in 'HKLM', 'HKCU') {
            $k = "${hive}:\SOFTWARE\Classes\Wow6432Node\CLSID\$clsid\InprocServer32"
            if (Test-Path -LiteralPath $k) {
                $module = (Get-ItemProperty -Path $k -Name '(default)' -ErrorAction SilentlyContinue).'(default)'
                break
            }
        }
        $merit = if ($null -ne $p.Merit) { [int]$p.Merit } else { $null }
        $rows += [pscustomobject]@{
            Name   = $name
            Clsid  = $clsid
            Merit  = $merit
            Module = $module
            Key    = $inst.PSPath
        }
    }
    return $rows
}

function Format-Merit($m) {
    if ($null -eq $m) { return 'default' }
    $label = switch ($m) {
        ([int]0x00800000) { 'MERIT_PREFERRED' }
        ([int]0x00600000) { 'MERIT_NORMAL' }
        ([int]0x00400000) { 'MERIT_UNLIKELY' }
        ([int]0x00200000) { 'MERIT_DO_NOT_USE' }
        default { '' }
    }
    ('0x{0:X8}{1}' -f $m, $(if ($label) { " ($label)" } else { '' }))
}

function Show-Status {
    Write-Head "SASAMI2k audio decoder selection (32-bit DirectShow)"
    $rows = @(Get-AudioDecoders)
    if (-not $rows.Count) {
        Write-Warn2 "No 32-bit audio decoders found in the filter mapper. Is a codec pack installed?"
        return 0
    }
    foreach ($r in ($rows | Sort-Object @{ Expression = { if ($null -eq $_.Merit) { -1 } else { $_.Merit } }; Descending = $true })) {
        $leaf = if ($r.Module) { Split-Path $r.Module -Leaf } else { '?' }
        $isLav = $r.Clsid -eq $LavAudioClsid
        $line = '{0,-36} {1,-30} {2}' -f $r.Name, (Format-Merit $r.Merit), $leaf
        if ($isLav) { Write-Ok $line } else { Write-Info $line }
    }

    $state = $null
    if (Test-Path -LiteralPath $StateKey) {
        $peek = Get-ItemProperty -Path $StateKey -ErrorAction SilentlyContinue
        if ($peek) { $state = $peek }
    }
    if ($state) {
        $prev = if ($state.Previous) { $state.Previous } else { 'none' }
        Write-Info ("explicit LAV merit set by this script: {0} (previous: {1})" -f (Format-Merit $state.Merit), $prev)
    }
    else {
        Write-Info "no explicit LAV merit set by this script"
    }
    Write-Head "Note"
    Write-Info "A 32-bit player only sees 32-bit filters, so a 64-bit-only codec install is invisible here."
    Write-Info "'prefer' sets LAV Audio Decoder to MERIT_PREFERRED (elevates once); 'default' removes it again."
    return 0
}

function Get-LavInstanceKey([string]$Hive) {
    $p = "$($Hive):\$Template\$LavAudioClsid"
    if (Test-Path -LiteralPath $p) { return $p }
    return $null
}

function Invoke-ElevatedSelf {
    $log = Join-Path $env:TEMP ("sasami2k-lav-{0}.log" -f $Action)
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    $argLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}" {1} -LogPath "{2}"' -f $PSCommandPath, $Action, $log
    Write-Info "Requesting administrator rights (the elevated window reports into this console)..."
    $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argLine -PassThru -Wait
    if (Test-Path -LiteralPath $log) {
        Get-Content -LiteralPath $log | Where-Object { $_ -notmatch '^\*{22}' -and $_ -notmatch '^(Windows PowerShell|Host Application|Process ID|PSVersion|PSEdition|PSCompatibleVersions|BuildVersion|CLRVersion|WSManStackVersion|SerializationVersion|PSRemotingProtocolVersion|Transcript started)' } |
            ForEach-Object { Write-Host $_ }
        Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    }
    return $p.ExitCode
}

function Set-LavMerit {
    param([Nullable[int]]$Merit)

    $key = Get-LavInstanceKey 'HKLM'
    if (-not $key) {
        Write-Err2 "LAV Audio Decoder is not registered in the 32-bit filter mapper."
        Write-Info "Register it first (K-Lite Codec Tweak Tool -> LAV Filters, or the LAV installer), then re-run."
        return 1
    }

    if ($null -eq $Merit) {
        if ((Get-ItemProperty -Path $key -Name 'Merit' -ErrorAction SilentlyContinue)) {
            Remove-ItemProperty -Path $key -Name 'Merit'
            Write-Ok "explicit merit removed; LAV Audio Decoder is back on the system default"
        }
        else {
            Write-Info "no explicit merit was set"
        }
        if (Test-Path -LiteralPath $StateKey) { Remove-Item -Path $StateKey -Recurse -Force }
        return 0
    }

    $previous = (Get-ItemProperty -Path $key -Name 'Merit' -ErrorAction SilentlyContinue).Merit
    New-Item -Path $StateKey -Force | Out-Null
    Set-ItemProperty -Path $StateKey -Name 'Previous' -Value ([string]$previous) -Type String
    Set-ItemProperty -Path $StateKey -Name 'Merit' -Value $Merit -Type DWord
    New-ItemProperty -Path $key -Name 'Merit' -Value $Merit -PropertyType DWord -Force | Out-Null
    Write-Ok ("LAV Audio Decoder merit set to {0}" -f (Format-Merit $Merit))
    Write-Info "applies to every 32-bit DirectShow graph; 'lav-audio.ps1 default' reverts it"
    return 0
}

try {
    if ($LogPath) { Start-Transcript -LiteralPath $LogPath -Force | Out-Null }
    switch ($Action) {
        'status' { $rc = Show-Status; if ($LogPath) { Stop-Transcript | Out-Null }; exit $rc }
        'prefer' {
            if (-not (Test-Admin)) { exit (Invoke-ElevatedSelf) }
            $rc = Set-LavMerit -Merit $MeritPreferred
            if ($LogPath) { Stop-Transcript | Out-Null }
            exit $rc
        }
        'default' {
            if (-not (Test-Admin)) { exit (Invoke-ElevatedSelf) }
            $rc = Set-LavMerit -Merit $null
            if ($LogPath) { Stop-Transcript | Out-Null }
            exit $rc
        }
    }
}
catch {
    Write-Err2 $_.Exception.Message
    if ($LogPath) { Stop-Transcript | Out-Null }
    exit 1
}
