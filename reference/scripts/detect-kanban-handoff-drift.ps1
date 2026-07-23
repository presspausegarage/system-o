#Requires -Version 7.0
<#
.SYNOPSIS
  Detector for the kanban-handoff-reconciler loop: finds status drift between
  handoffs and the Kanban cards that cite them.
.DESCRIPTION
  Two deterministic finding types (system-o v0.3.0 slice, grill decisions 1-3):

  D1 ready-but-done — a `status: ready` handoff whose citing Kanban cards
     (cards containing the handoff basename — the basename IS the stable ID)
     are ALL checked `[x]`, with at least one such card. The handoff should
     flip complete. A ready handoff with zero Kanban mentions is NOT a finding
     (out of the loop's reach by design — the human's to flip).

  D2 cited-but-open — a `status: complete` handoff whose verification block
     carries a `task: "<kanban> -- <text> -- checked <date>"` citation whose
     cited task line is still `[ ]`. The box should be checked. (This is the
     lint's citation cross-check promoted from flag to repair; obsolete
     handoffs are exempt, matching the lint.)

  Output contract (parsed by kanban-handoff-reconciler.cell.ps1) — one line
  per item, ' :: ' separated, prefixed '[dry-run] ' under -DryRun:
    D1 ready-but-done: <basename>
    D1-card: <basename> :: <kanban-rel-path> :: <task line text>
    D2 cited-but-open: <basename> :: <kanban-rel-path> :: <cited fragment>
    kanban-handoff drift: <n> ready-but-done, <m> cited-but-open   (always)

  This script is READ-ONLY regardless of -DryRun; the switch is accepted for
  the loop runner's detect-step conformance (the runner forces it on) and
  controls only the output prefix.
.PARAMETER Root
  Vault root. Default '.'.
.EXAMPLE
  detect-kanban-handoff-drift.ps1 -Root . -DryRun
#>
[CmdletBinding()]
param(
  [string]$Root = '.',
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$prefix = if ($DryRun) { '[dry-run] ' } else { '' }
function Emit { param([string]$m) Write-Output ($prefix + $m) }

$handoffDir = Join-Path $Root '_meta/handoffs'
if (-not (Test-Path $handoffDir)) { Emit 'kanban-handoff drift: 0 ready-but-done, 0 cited-but-open'; exit 0 }

# All Kanban boards outside archival/purge/vcs trees, read once. Separators are
# normalized before the exclusion match — a literal backslash pattern silently
# never fires on a POSIX host (the bump-updated-field port bug, 2026-07-09).
$kanbans = @(Get-ChildItem -Path $Root -Filter 'Kanban.md' -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { ($_.FullName -replace '\\','/') -notmatch '/(_archive|_sewerpipe|node_modules|\.git)/' })
$kanbanLines = @{}
foreach ($k in $kanbans) {
  $rel = ([System.IO.Path]::GetRelativePath($Root, $k.FullName)) -replace '\\','/'
  $kanbanLines[$rel] = @(Get-Content -Path $k.FullName -Encoding UTF8)
}

$handoffs = @()
foreach ($f in (Get-ChildItem -Path $handoffDir -Filter '*.md' -File)) {
  $head = Get-Content -Path $f.FullName -TotalCount 40 -Encoding UTF8 | Out-String
  $status = if ($head -match '(?m)^status:\s*(\S+)') { $Matches[1] } else { '' }
  $handoffs += [pscustomobject]@{ Base = $f.BaseName; Status = $status; Path = $f.FullName }
}

# --- D1: ready handoffs whose citing cards are all checked -------------------
$d1 = 0
foreach ($h in ($handoffs | Where-Object Status -eq 'ready')) {
  $cards = [System.Collections.ArrayList]::new()
  foreach ($rel in $kanbanLines.Keys) {
    $lines = $kanbanLines[$rel]
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -notmatch [regex]::Escape($h.Base)) { continue }
      # walk back to the owning task line (mentions can sit in a card's wrapped body)
      $j = $i
      while ($j -ge 0 -and $lines[$j] -notmatch '^\s*-\s*\[[ x]\]') { $j-- }
      if ($j -lt 0) { continue }
      $state = if ($lines[$j] -match '^\s*-\s*\[x\]') { 'x' } else { ' ' }
      $text = ($lines[$j] -replace '^\s*-\s*\[[ x]\]\s*', '').Trim()
      [void]$cards.Add([pscustomobject]@{ Kanban = $rel; State = $state; Text = $text })
    }
  }
  $uniq = @($cards | Sort-Object Kanban, Text -Unique)
  if ($uniq.Count -eq 0) { continue }                       # out of reach — not a finding
  if (@($uniq | Where-Object State -eq ' ').Count -gt 0) { continue }   # work genuinely open
  $d1++
  Emit ("D1 ready-but-done: {0}" -f $h.Base)
  foreach ($c in $uniq) { Emit ("D1-card: {0} :: {1} :: {2}" -f $h.Base, $c.Kanban, $c.Text) }
}

# --- D2: complete handoffs citing still-open tasks ---------------------------
$d2 = 0
foreach ($h in ($handoffs | Where-Object Status -eq 'complete')) {
  $raw = Get-Content -Path $h.Path -Raw -Encoding UTF8
  foreach ($m in [regex]::Matches($raw, '(?m)^\s*-\s*task\s*:\s*"?(.+?)"?\s*$')) {
    $parts = $m.Groups[1].Value -split '\s*--\s*'
    if ($parts.Count -lt 2) { continue }                    # malformed — the lint's finding, not ours
    $kRel = ($parts[0].Trim()) -replace '\\','/'
    if (-not $kanbanLines.ContainsKey($kRel)) { continue }  # missing kanban — the lint's finding
    $frag = $parts[1].Trim()
    $esc = [regex]::Escape($frag)
    $openHit = $false
    foreach ($line in $kanbanLines[$kRel]) {
      if ($line -match ('^\s*-\s*\[ \]\s*.*' + $esc)) { $openHit = $true; break }
    }
    if ($openHit) {
      $d2++
      Emit ("D2 cited-but-open: {0} :: {1} :: {2}" -f $h.Base, $kRel, $frag)
    }
  }
}

Emit ("kanban-handoff drift: {0} ready-but-done, {1} cited-but-open" -f $d1, $d2)
