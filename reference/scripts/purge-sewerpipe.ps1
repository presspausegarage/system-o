#Requires -Version 7.0
<#
.SYNOPSIS
  Hard-delete _sewerpipe/ items older than the retention window.
.DESCRIPTION
  Run daily, after triage-inbox.ps1 -- ordering matters: anything triage
  just routed to _sewerpipe/ this run gets a fresh mtime and must not be
  evaluated for deletion in the same pass. Skips README.md so the folder's
  own documentation survives the sweep.
.PARAMETER Root
  Vault root.
.PARAMETER RetentionDays
  Age (by mtime) after which a _sewerpipe/ item is hard-deleted.
.PARAMETER DryRun
  Report what would be deleted without deleting anything.
.EXAMPLE
  purge-sewerpipe.ps1 -Root .
  purge-sewerpipe.ps1 -Root . -DryRun
#>
[CmdletBinding()]
param(
    [string]$Root          = '.',
    [int]$RetentionDays    = 30,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$sewerpipePath = Join-Path $Root '_sewerpipe'
$logDir        = Join-Path $Root '_meta/logs'
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDir ("purge-sewerpipe-{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))

function Write-Log {
    param([string]$msg)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Write-Output $line
    Add-Content -Path $logFile -Value $line -Encoding utf8
}

if (-not (Test-Path $sewerpipePath)) {
    Write-Log "purge-sewerpipe: $sewerpipePath does not exist; nothing to do."
    exit 0
}

$cutoff = (Get-Date).AddDays(-$RetentionDays)
Write-Log "purge-sewerpipe: starting (cutoff=$($cutoff.ToString('yyyy-MM-dd')), dry-run=$DryRun)"

# Skip the README. Everything else is fair game.
$candidates = Get-ChildItem -Path $sewerpipePath -Force |
    Where-Object { $_.Name -ne 'README.md' -and $_.Name -ne 'desktop.ini' -and $_.LastWriteTime -lt $cutoff }

$deleted = 0
$totalBytes = 0
foreach ($item in $candidates) {
    $age = [int]((Get-Date) - $item.LastWriteTime).TotalDays
    if ($item.PSIsContainer) {
        $size = (Get-ChildItem $item.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum).Sum
    } else {
        $size = $item.Length
    }
    $totalBytes += $size

    if (-not $DryRun) {
        Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Log "deleted (${age}d, $([math]::Round($size/1KB,1)) KB): $($item.Name)"
    $deleted++
}

Write-Log "purge-sewerpipe: done. deleted=$deleted total=$([math]::Round($totalBytes/1MB,2))MB dry-run=$DryRun"
exit 0
