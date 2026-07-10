#Requires -Version 7.0
<#
.SYNOPSIS
  Aggregate the reference implementation's read-only checks into one
  machine-readable heartbeat artifact: _meta/logs/qa-status.json.
.DESCRIPTION
  Runs run-extensions.ps1 (spec §Extension surface) and inspects each
  registered loop's most recent ledger record (spec §Loop manifest) for a
  failure, then writes one JSON summary any surface can read without
  re-deriving chain state itself — e.g. the landing terminal's o-boy widget,
  wired to fetch this file when it's served from within a vault (post-v1.0,
  _meta/Kanban.md).

  Read-only against everything outside its own output file: same posture as
  an extension (spec §Extension surface), but this script itself is not one
  — it aggregates extensions plus the loop layer, which a single extension's
  own-directory-only write rule can't do. Always exits 0; a check that fails
  to run is recorded as its own flagged finding, not a script failure.
.PARAMETER Root
  Vault root.
.EXAMPLE
  build-qa-status.ps1 -Root .
#>
[CmdletBinding()]
param(
  [string]$Root = '.'
)

$ErrorActionPreference = 'Stop'

function New-Check {
  param([string]$Name, [string]$Status, [string]$Detail)
  [pscustomobject]@{ name = $Name; status = $Status; detail = $Detail }
}

$checks = [System.Collections.Generic.List[object]]::new()

# --- Extensions heartbeat (spec §Extension surface) ---
$runExtensions = Join-Path $Root '_meta/scripts/run-extensions.ps1'
if (Test-Path $runExtensions) {
  try {
    $out = & $runExtensions -Root $Root *>&1 | ForEach-Object { "$_" }
    $statusLine = $out | Where-Object { $_ -match '^STATUS extensions=(\d+) flagged=(\d+)(?:\s+\[([^\]]+)\])?' } | Select-Object -Last 1
    if ($statusLine) {
      $flaggedCount = [int]$Matches[2]
      $names = $Matches[3]
      if ($flaggedCount -eq 0) {
        $checks.Add((New-Check 'extensions' 'ok' "$($Matches[1]) registered, 0 flagged"))
      } else {
        $checks.Add((New-Check 'extensions' 'flagged' "$flaggedCount of $($Matches[1]) flagged: $names"))
      }
    } else {
      $checks.Add((New-Check 'extensions' 'flagged' 'ran but emitted no STATUS line (non-conformant runner output)'))
    }
  } catch {
    $checks.Add((New-Check 'extensions' 'flagged' "runner threw: $($_.Exception.Message)"))
  }
} else {
  $checks.Add((New-Check 'extensions' 'skipped' 'run-extensions.ps1 not present'))
}

# --- Loop layer: last ledger record per registered (non-.example) manifest ---
$loopsDir = Join-Path $Root '_meta/loops'
$manifests = @()
if (Test-Path $loopsDir) {
  $manifests = @(Get-ChildItem -Path $loopsDir -Filter '*.yaml' -File -ErrorAction SilentlyContinue)
}
if ($manifests.Count -eq 0) {
  $checks.Add((New-Check 'loops' 'skipped' 'no active loop manifests (*.yaml) — only .yaml.example present, or none configured'))
} else {
  foreach ($m in $manifests) {
    $loopName = $m.BaseName
    $ledgerFile = Join-Path $loopsDir "$loopName.ledger.jsonl"
    if (-not (Test-Path $ledgerFile)) {
      $checks.Add((New-Check "loop:$loopName" 'skipped' 'no ledger yet — has not run'))
      continue
    }
    $lastLine = Get-Content -Path $ledgerFile -Tail 1 -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $lastLine) {
      $checks.Add((New-Check "loop:$loopName" 'skipped' 'ledger present but empty'))
      continue
    }
    try {
      $rec = $lastLine | ConvertFrom-Json
      $event = "$($rec.event)"
      if ($event -match 'fail') {
        $checks.Add((New-Check "loop:$loopName" 'flagged' "last ledger event: $event"))
      } else {
        $checks.Add((New-Check "loop:$loopName" 'ok' "last ledger event: $event"))
      }
    } catch {
      $checks.Add((New-Check "loop:$loopName" 'flagged' 'last ledger line failed to parse as JSON'))
    }
  }
}

# --- Assemble + write ---
$flagged = @($checks | Where-Object { $_.status -eq 'flagged' })
$summary = [pscustomobject]@{
  generated = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  ok        = ($flagged.Count -eq 0)
  checks    = $checks
}

$logsDir = Join-Path $Root '_meta/logs'
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
$outFile = Join-Path $logsDir 'qa-status.json'
$summary | ConvertTo-Json -Depth 5 | Set-Content -Path $outFile -Encoding UTF8

Write-Host ("STATUS checks={0} flagged={1} -> {2}" -f $checks.Count, $flagged.Count, $outFile)
exit 0
