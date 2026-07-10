#Requires -Version 7.0
<#
.SYNOPSIS
  Extension: flag documents that restate a fact out of sync with its canonical source.
.DESCRIPTION
  Worked example of the extension contract (spec §Extension surface) — and the
  reference implementation's answer to doc rot as a first-class, not narrative-
  only, concern. Policy lives in a manifest (same principle as §Transform
  manifest and §Loop manifest), never in this script: `checks.yaml` declares
  pairs of {canonical source + extraction pattern} -> {one or more derived
  documents + their own extraction pattern for the same fact}. A mismatch
  between the extracted values is doc rot, caught mechanically instead of by
  someone happening to notice.

  Generalizes the registry-vs-prose drift pattern (a project registry is
  canonical; hand-authored docs that restate counts/names from it silently
  diverge) into something any adopter configures for their own "N docs assert
  one fact" problem — no fixed file names, no fixed regex, no code change per
  check added.
.PARAMETER Root
  Vault root.
.PARAMETER Manifest
  Path to the checks manifest, relative to Root. Default: this extension's own
  checks.yaml alongside check.ps1.
.PARAMETER DryRun
  Required by the extension contract; this check never writes regardless.
#>
[CmdletBinding()]
param(
  [string]$Root = '.',
  [string]$Manifest = '_meta/extensions/source-drift/checks.yaml',
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# --- tiny manifest parser: a flat list of {name, source:{file,pattern}, derived:[{file,pattern}]} ---
function Read-ChecksManifest {
  param([string]$Path)
  $checks = [System.Collections.ArrayList]::new()
  $cur = $null; $section = ''; $derivedItem = $null
  foreach ($line in (Get-Content -Path $Path -Encoding UTF8)) {
    if ($line -match '^\s*(#.*)?$') { continue }
    if ($line -match '^\s*-\s+name:\s*(.+)$') {
      if ($cur) { [void]$checks.Add($cur) }
      $cur = @{ name = $Matches[1].Trim().Trim('"').Trim("'"); source = @{}; derived = [System.Collections.ArrayList]::new() }
      $section = ''; $derivedItem = $null
      continue
    }
    if (-not $cur) { continue }
    if ($line -match '^\s+source:\s*$') { $section = 'source'; continue }
    if ($line -match '^\s+derived:\s*$') { $section = 'derived'; continue }
    if ($section -eq 'source' -and $line -match '^\s+(file|pattern):\s*(.+)$') {
      $cur.source[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'"); continue
    }
    if ($section -eq 'derived' -and $line -match '^\s+-\s+(file|pattern):\s*(.+)$') {
      if ($Matches[1] -eq 'file') { $derivedItem = @{ file = $Matches[2].Trim().Trim('"').Trim("'") }; [void]$cur.derived.Add($derivedItem) }
      continue
    }
    if ($section -eq 'derived' -and $derivedItem -and $line -match '^\s+(pattern):\s*(.+)$') {
      $derivedItem[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'"); continue
    }
  }
  if ($cur) { [void]$checks.Add($cur) }
  return $checks
}

function Get-ExtractedValue {
  param([string]$Root, [string]$RelPath, [string]$Pattern)
  $full = Join-Path $Root $RelPath
  if (-not (Test-Path $full)) { return $null }
  $text = Get-Content -Path $full -Raw -Encoding UTF8
  $m = [regex]::Match($text, $Pattern)
  if (-not $m.Success) { return $null }
  if ($m.Groups.Count -gt 1) { return $m.Groups[1].Value.Trim() } else { return $m.Value.Trim() }
}

$manifestPath = Join-Path $Root $Manifest
$mismatches = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path $manifestPath)) {
  Write-Host "no checks.yaml configured — nothing to verify (add $Manifest to enable)"
  Write-Host "EXTENSION-STATUS name=source-drift flagged=false"
  exit 0
}

$checks = Read-ChecksManifest $manifestPath
foreach ($c in $checks) {
  $srcVal = Get-ExtractedValue -Root $Root -RelPath $c.source['file'] -Pattern $c.source['pattern']
  if ($null -eq $srcVal) {
    $mismatches.Add("$($c.name): source $($c.source['file']) — pattern did not match (source unreadable or format changed)")
    continue
  }
  foreach ($d in $c.derived) {
    $derVal = Get-ExtractedValue -Root $Root -RelPath $d.file -Pattern $d.pattern
    if ($null -eq $derVal) {
      $mismatches.Add("$($c.name): $($d.file) — pattern did not match (doc may have been restructured)")
    } elseif ($derVal -ne $srcVal) {
      $mismatches.Add("$($c.name): $($d.file) says '$derVal'; source $($c.source['file']) says '$srcVal'")
    }
  }
}

$flagged = $mismatches.Count -gt 0
if ($flagged) {
  foreach ($m in $mismatches) { Write-Host $m }
} else {
  Write-Host ("{0} check(s) verified, all consistent with their source" -f $checks.Count)
}
Write-Host ("EXTENSION-STATUS name=source-drift flagged={0}" -f $flagged.ToString().ToLower())
