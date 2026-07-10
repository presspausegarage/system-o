#Requires -Version 7.0
<#
.SYNOPSIS
  Move complete handoffs older than -Days into _archive/handoffs/<YYYY-QN>/.
.DESCRIPTION
  Reads each *.md in _meta/handoffs/, parses frontmatter, and moves any with
  status: complete OR status: obsolete AND completed_date <= today - Days
  into the quarterly archive. Handoffs without a terminal status (i.e.
  status: ready or anything else) are kept.

  Three downstream passes run after the sweep, each via $PSScriptRoot so
  they resolve alongside this script, each independently guarded and
  non-fatal (a missing or throwing pass logs a WARN and the sweep's own
  result stands regardless):
    1. bump-updated-field.ps1 -- frontmatter `updated:` sync (ported
       alongside this script).
    2. lint-handoff-frontmatter.ps1 -- schema check on what didn't sweep
       (ported alongside this script).
    3. check-session-log.ps1 -- session-log reconciliation. NOT part of
       this port; the guard degrades to a logged no-op. detect-wrap-tail.ps1
       (already in reference/scripts/, spec §Loop manifest) is the portable
       analog for this concern but wiring it into the sweep is a separate
       piece of work, not a mechanical port of this script.
.PARAMETER Root
  Vault root.
.PARAMETER Days
  Sweep window in days.
.PARAMETER Date
  Override "today" for backfills/tests (YYYY-MM-DD).
.PARAMETER DryRun
  Log what would move without touching the filesystem.
.EXAMPLE
  sweep-handoffs.ps1 -Root .
  sweep-handoffs.ps1 -Root . -DryRun
  sweep-handoffs.ps1 -Root . -Days 14 -Date 2026-05-15
#>
[CmdletBinding()]
param(
  [string]$Root = '.',
  [int]$Days = 7,
  [string]$Date = (Get-Date -Format 'yyyy-MM-dd'),
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$handoffsDir = Join-Path $Root '_meta/handoffs'
$archiveBase = Join-Path $Root '_archive/handoffs'
$logPath     = Join-Path $Root "_meta/logs/sweep-handoffs-$Date.log"

$logDir = Split-Path $logPath -Parent
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Write-Log {
  param([string]$Message)
  $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
  Add-Content -Path $logPath -Value $line -Encoding UTF8
  Write-Host $line
}

function Get-Quarter {
  param([datetime]$D)
  $q = [math]::Ceiling($D.Month / 3)
  return "{0}-Q{1}" -f $D.Year, $q
}

function Read-Frontmatter {
  # Naive single-line key:value parser. Multi-line YAML (lists, nested blocks)
  # is not extracted -- we only need scalar fields (status, completed_date).
  param([string]$Path)
  $lines = Get-Content -Path $Path -Encoding UTF8
  if ($lines.Count -lt 3 -or $lines[0] -ne '---') { return $null }
  $endIdx = -1
  for ($i = 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -eq '---') { $endIdx = $i; break }
  }
  if ($endIdx -lt 0) { return $null }

  $fm = @{}
  for ($i = 1; $i -lt $endIdx; $i++) {
    $line = $lines[$i]
    if ($line -match '^([a-zA-Z_][a-zA-Z0-9_]*):\s*(.*)$') {
      $key = $Matches[1]
      $val = $Matches[2].Trim().Trim('"').Trim("'")
      $fm[$key] = $val
    }
  }
  return $fm
}

Write-Log "sweep-handoffs: starting (root=$Root, days=$Days, today=$Date, dry-run=$($DryRun.IsPresent))"

if (-not (Test-Path $handoffsDir)) {
  Write-Log "ERROR: handoffs dir missing: $handoffsDir"
  exit 1
}

$today  = [datetime]::ParseExact($Date, 'yyyy-MM-dd', $null)
$cutoff = $today.AddDays(-$Days)

$candidates = @(Get-ChildItem -Path $handoffsDir -Filter '*.md' -File)
$swept = 0; $kept = 0; $skipped = 0

foreach ($f in $candidates) {
  $fm = Read-Frontmatter -Path $f.FullName
  if (-not $fm) {
    Write-Log "skipped (no frontmatter): $($f.Name)"
    $skipped++
    continue
  }

  $status = $fm['status']
  # obsolete = terminal abandoned/superseded, sweeps like complete, aged on
  # the same completed_date field (date declared dead).
  if ($status -notin @('complete','obsolete')) {
    Write-Log "kept (status=$status): $($f.Name)"
    $kept++
    continue
  }

  $cdate = $fm['completed_date']
  if (-not $cdate) {
    Write-Log "kept (status=$status but missing completed_date): $($f.Name)"
    $kept++
    continue
  }

  $cd = $null
  try {
    $cd = [datetime]::ParseExact($cdate, 'yyyy-MM-dd', $null)
  } catch {
    Write-Log "kept (unparsable completed_date '$cdate'): $($f.Name)"
    $kept++
    continue
  }

  if ($cd -gt $cutoff) {
    $age = ($today - $cd).Days
    Write-Log "kept (within window, age=${age}d): $($f.Name)"
    $kept++
    continue
  }

  # Sweep
  $quarter = Get-Quarter -D $cd
  $destDir = Join-Path $archiveBase $quarter
  $destPath = Join-Path $destDir $f.Name

  if ($DryRun) {
    Write-Log "[dry-run] would move: $($f.Name) -> _archive/handoffs/$quarter/"
    $swept++
    continue
  }

  if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

  if (Test-Path $destPath) {
    Write-Log "kept (destination already exists, manual review): $($f.Name)"
    $kept++
    continue
  }

  Move-Item -Path $f.FullName -Destination $destPath
  Write-Log "swept -> _archive/handoffs/$quarter/$($f.Name)"
  $swept++
}

Write-Log "sweep-handoffs: done. swept=$swept kept=$kept skipped=$skipped"

# --- Frontmatter `updated:` field bump ---
# Idempotent transform: aligns each note's frontmatter `updated:` line with
# the file's mtime date. Runs before lint so the validated state is the
# post-bump state. Non-fatal: failures log under WARN.
$bumper = Join-Path $PSScriptRoot 'bump-updated-field.ps1'
if (Test-Path $bumper) {
  try {
    Write-Log "bump: starting updated-field sync"
    $bumpOutput = & $bumper -Root $Root *>&1
    foreach ($line in $bumpOutput) {
      Write-Log ("bump | " + $line)
    }
    Write-Log "bump: done"
  } catch {
    $msg = $_.Exception.Message
    Write-Log "bump: WARN threw: $msg"
  }
} else {
  Write-Log "bump: WARN bumper script missing at $bumper - skipped"
}

# --- Frontmatter lint pass ---
# Surfaces schema drift on handoffs that did not sweep (the active set).
# Non-fatal: findings log under WARN. The sweep itself remains source of truth
# for what got moved. Lint output appends to this same log file.
$linter = Join-Path $PSScriptRoot 'lint-handoff-frontmatter.ps1'
if (Test-Path $linter) {
  try {
    Write-Log "lint: starting frontmatter check on remaining handoffs"
    # *>&1 captures all streams including Information (Write-Host) so findings
    # land in the log when run non-interactively under a scheduler.
    $lintOutput = & $linter -Root $Root *>&1
    $lintExit = $LASTEXITCODE
    foreach ($line in $lintOutput) {
      Write-Log ("lint | " + $line)
    }
    if ($lintExit -eq 0) {
      Write-Log "lint: clean (exit 0)"
    } else {
      Write-Log "lint: WARN findings present (exit $lintExit) - surface in next session"
    }
  } catch {
    $msg = $_.Exception.Message
    Write-Log "lint: WARN threw: $msg"
  }
} else {
  Write-Log "lint: WARN linter script missing at $linter - skipped"
}

# --- Session-log reconciliation ---
# Not part of this port (see .DESCRIPTION) -- guarded no-op if absent, same
# as the other two passes, so an adopter who later builds or ports their own
# check-session-log.ps1 alongside this one picks it up with no edit here.
$sessionCheck = Join-Path $PSScriptRoot 'check-session-log.ps1'
if (Test-Path $sessionCheck) {
  try {
    Write-Log "session-log: reconciling activity vs session-log.md"
    $scOutput = & $sessionCheck -Root $Root *>&1
    foreach ($line in $scOutput) { Write-Log ("session-log | " + $line) }
    Write-Log "session-log: done"
  } catch {
    $msg = $_.Exception.Message
    Write-Log "session-log: WARN threw: $msg"
  }
} else {
  Write-Log "session-log: WARN check script missing at $sessionCheck - skipped (not part of this reference; see .DESCRIPTION)"
}
