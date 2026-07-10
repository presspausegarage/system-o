#Requires -Version 7.0
<#
.SYNOPSIS
  Discover and run every _meta/extensions/*/check.ps1 (spec §Extension surface).
.DESCRIPTION
  Generic aggregator — adding an extension requires no change to this script or
  to any other extension. Each extension is invoked with -Root -DryRun and must
  emit one `EXTENSION-STATUS name=<name> flagged=<true|false>` line; everything
  above that line is passed through as human-readable detail. Extensions never
  abort the chain: a missing check.ps1, a nonzero exit, or a malformed status
  line is reported as its own flagged finding, not a script failure.

  Intended as a heartbeat step in the nightly automation chain, alongside (not
  instead of) any loop-cell runs — extensions are layer-2 automation-chain
  checks, not layer-3 loop cells (spec §System architecture): read-only,
  flag-only, never gating, no LLM.
.PARAMETER Root
  Vault root.
.EXAMPLE
  run-extensions.ps1 -Root .
#>
[CmdletBinding()]
param(
  [string]$Root = '.'
)

$ErrorActionPreference = 'Stop'

$extDir = Join-Path $Root '_meta/extensions'
if (-not (Test-Path $extDir)) {
  Write-Host "STATUS extensions=0 flagged=0 (no _meta/extensions/ present)"
  exit 0
}

$dirs = @(Get-ChildItem -Path $extDir -Directory | Sort-Object Name)
if ($dirs.Count -eq 0) {
  Write-Host "STATUS extensions=0 flagged=0 (no extensions registered)"
  exit 0
}

$flaggedNames = New-Object System.Collections.Generic.List[string]
foreach ($d in $dirs) {
  $check = Join-Path $d.FullName 'check.ps1'
  Write-Host "extension> $($d.Name)"
  if (-not (Test-Path $check)) {
    Write-Host "extension> $($d.Name): MISSING check.ps1 — treated as flagged"
    $flaggedNames.Add($d.Name); continue
  }
  try {
    $out = & $check -Root $Root -DryRun *>&1 | ForEach-Object { "$_" }
  } catch {
    Write-Host "extension> $($d.Name): threw — $($_.Exception.Message) — treated as flagged"
    $flaggedNames.Add($d.Name); continue
  }
  foreach ($l in $out) { Write-Host ("extension> " + $l) }
  $statusLine = $out | Where-Object { $_ -match '^EXTENSION-STATUS\s+name=(\S+)\s+flagged=(true|false)' } | Select-Object -Last 1
  if (-not $statusLine) {
    Write-Host "extension> $($d.Name): no EXTENSION-STATUS line emitted — treated as flagged (non-conformant)"
    $flaggedNames.Add($d.Name); continue
  }
  if ($Matches[2] -eq 'true') { $flaggedNames.Add($Matches[1]) }
}

$statusLine = "STATUS extensions={0} flagged={1}" -f $dirs.Count, $flaggedNames.Count
if ($flaggedNames.Count -gt 0) { $statusLine += " [" + ($flaggedNames -join ',') + "]" }
Write-Host $statusLine
