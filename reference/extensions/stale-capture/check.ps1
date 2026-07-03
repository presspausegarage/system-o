#Requires -Version 7.0
<#
.SYNOPSIS
  Extension: flag capture-folder items stuck past a staleness threshold.
.DESCRIPTION
  Worked example of the extension contract (spec §Extension surface). Generic
  by construction: no vault-specific folder names, no domain assumptions.
  Every capture pad accumulates items that fall through whatever routing rule
  moves them elsewhere; this catches the routing gap, not any specific rule.
.PARAMETER Root
  Vault root.
.PARAMETER CaptureDir
  The capture folder to scan, relative to Root. Default: _inbox.
.PARAMETER StaleDays
  Age threshold in days. Default: 7.
.PARAMETER DryRun
  Required by the extension contract; this check never writes regardless.
#>
[CmdletBinding()]
param(
  [string]$Root = '.',
  [string]$CaptureDir = '_inbox',
  [int]$StaleDays = 7,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$dir = Join-Path $Root $CaptureDir
$flagged = $false

if (Test-Path $dir) {
  $cut = (Get-Date).AddDays(-$StaleDays)
  $stale = @(Get-ChildItem -Path $dir | Where-Object { $_.Name -ne 'README.md' -and $_.LastWriteTime -lt $cut })
  if ($stale.Count -gt 0) {
    $oldest = $stale | Sort-Object LastWriteTime | Select-Object -First 1
    Write-Host ("{0} item(s) in {1} older than {2}d; oldest: {3} ({4})" -f $stale.Count, $CaptureDir, $StaleDays, $oldest.Name, $oldest.LastWriteTime.ToString('yyyy-MM-dd'))
    $flagged = $true
  }
} else {
  Write-Host "$CaptureDir not present — nothing to check"
}

Write-Host ("EXTENSION-STATUS name=stale-capture flagged={0}" -f $flagged.ToString().ToLower())
