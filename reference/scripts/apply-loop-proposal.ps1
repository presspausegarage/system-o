#Requires -Version 7.0
<#
.SYNOPSIS
  Apply (or reject) one loop proposal from _meta/loops/proposals/ (spec §Loop manifest).
.DESCRIPTION
  The apply arm of the loop cell — deterministic, no LLM. Supported changes:
    prepend-session-log-entry  — insert the proposal body above the newest entry
                                 in _meta/session-log.md (dupe-guarded)
    bump-home-updated          — set _meta/HOME.md frontmatter updated: to the
                                 newest ## YYYY-MM-DD date in session-log.md
  On success the proposal file is deleted (it is a machine-generated artifact;
  the ledger keeps the record). -Reject moves it to _sewerpipe/ if present,
  else deletes it.

  Scope enforcement (spec §Loop manifest: "Enforced by the runner and the
  applier"): the proposal's target must be listed under scope: in the loop's
  manifest. The manifest is taken from -Manifest when given (the runner's
  auto-apply always passes its own), else resolved from the proposal's loop
  name at _meta/loops/<loop>.yaml. An out-of-scope target is a hard refusal.
  If no manifest can be found (e.g. the loop ran from an ad-hoc manifest and
  this is a manual walk), the apply proceeds with a WARN — this path is the
  attended human gate, and the runner-side check has already run.
.EXAMPLE
  apply-loop-proposal.ps1 -File _meta/loops/proposals/loop-wrap-tail-repair-bump-home-updated-2026-07-01.md -Root .
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$File,
  [string]$Root = '.',
  [string]$Manifest,
  [switch]$Reject
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$File = (Resolve-Path $File).Path
$raw = Get-Content -Path $File -Raw -Encoding UTF8
if ($raw -notmatch '(?s)^---\r?\n(.*?)\r?\n---\r?\n(.*)$') { throw "Not a proposal file (no frontmatter): $File" }
$fmText = $Matches[1]; $body = $Matches[2].Trim()
$fm = @{}
foreach ($line in ($fmText -split "`r?`n")) {
  if ($line -match '^([\w_]+):\s*(.*)$') { $fm[$Matches[1]] = $Matches[2].Trim() }
}
$change = $fm['proposed_change']
$loop   = $fm['loop']
if (-not $change) { throw "File has no proposed_change field: $File" }

function Add-Ledger {
  param([string]$Outcome)
  $ledger = Join-Path $Root ("_meta/loops/{0}.ledger.jsonl" -f $loop)
  $rec = @{ loop = $loop; change = $change; outcome = $Outcome; ts = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss' }
  if ($fm['entry_date']) { $rec['entry_date'] = $fm['entry_date'] }
  if ($fm['handoff'])    { $rec['handoff']    = $fm['handoff'] }
  Add-Content -Path $ledger -Value ($rec | ConvertTo-Json -Compress) -Encoding UTF8
}

if ($Reject) {
  $sewer = Join-Path $Root '_sewerpipe'
  if (Test-Path $sewer) {
    Move-Item -Path $File -Destination (Join-Path $sewer (Split-Path $File -Leaf)) -Force
    Write-Output "rejected -> _sewerpipe/$(Split-Path $File -Leaf)"
  } else {
    Remove-Item -Path $File -Force -Confirm:$false
    Write-Output "rejected -> deleted (no _sewerpipe/ retention convention present)"
  }
  Add-Ledger 'rejected'
  exit 0
}

# Scope gate — see .DESCRIPTION. Applies only (a reject never touches the target).
$target = $fm['target']
$mfPath = $Manifest
if (-not $mfPath) {
  $candidate = Join-Path $Root ("_meta/loops/{0}.yaml" -f $loop)
  if (Test-Path $candidate) { $mfPath = $candidate }
}
if ($mfPath) {
  $scope = [System.Collections.Generic.List[string]]::new()
  $inScopeBlock = $false
  foreach ($line in (Get-Content -Path $mfPath -Encoding UTF8)) {
    if ($line -match '^scope:\s*$') { $inScopeBlock = $true; continue }
    if ($inScopeBlock) {
      if ($line -match '^\s+-\s+(.+?)\s*$') { $scope.Add(($Matches[1].Trim('"').Trim("'"))); continue }
      if ($line -match '^\S') { $inScopeBlock = $false }
    }
  }
  if (-not $target) { throw "Proposal has no target: field — cannot scope-check: $File" }
  if ($scope -notcontains $target) {
    throw "SCOPE VIOLATION: proposal targets '$target', which is not in the manifest's scope ($($scope -join ', ')) — refused. Manifest: $mfPath"
  }
} else {
  Write-Warning "no loop manifest found for '$loop' (no -Manifest given, no _meta/loops/$loop.yaml) — scope not verified; proceeding on the attended gate"
}

$sessionLog = Join-Path $Root '_meta/session-log.md'

switch ($change) {
  'prepend-session-log-entry' {
    $logRaw = (Get-Content -Path $sessionLog -Raw -Encoding UTF8) -replace "`r`n","`n"
    $entryFirstLine = ($body -split "`n")[0]
    if ($logRaw.Contains($entryFirstLine)) { throw "Already applied: session-log contains '$entryFirstLine'" }
    $lines = $logRaw -split "`n"
    # newest-at-top: insert above the first entry OLDER than this one (below any
    # same-date entries); falls back to top-of-entries / end-of-file.
    $entryDate = $fm['entry_date']
    $insertAt = -1; $firstEntry = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match '^## (\d{4}-\d{2}-\d{2})') {
        if ($firstEntry -lt 0) { $firstEntry = $i }
        if ($Matches[1] -lt $entryDate) { $insertAt = $i; break }
      }
    }
    if ($insertAt -lt 0) { $insertAt = if ($firstEntry -ge 0 -and -not $entryDate) { $firstEntry } else { $lines.Count } }
    # bounds-safe slicing: insertAt may be 0 (insert at top) or $lines.Count (append at end) —
    # a raw range would wrap/overrun under StrictMode
    $head = if ($insertAt -gt 0) { @($lines[0..($insertAt-1)]) } else { @() }
    $tail = if ($insertAt -lt $lines.Count) { @($lines[$insertAt..($lines.Count-1)]) } else { @() }
    $new = $head + @(($body -replace "`r`n","`n") -split "`n") + @('') + $tail
    [System.IO.File]::WriteAllText($sessionLog, (($new -join "`n").TrimEnd("`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
    Write-Output "applied: entry for $($fm['entry_date']) prepended to _meta/session-log.md"
  }
  'bump-home-updated' {
    $newest = $null
    foreach ($line in (Get-Content -Path $sessionLog -Encoding UTF8)) {
      if ($line -match '^## (\d{4}-\d{2}-\d{2})') { $newest = $Matches[1]; break }
    }
    if (-not $newest) { throw "No dated entries found in session-log.md" }
    $homeFile = Join-Path $Root '_meta/HOME.md'
    $homeRaw = Get-Content -Path $homeFile -Raw -Encoding UTF8   # NOT $home: read-only automatic var in pwsh
    if ($homeRaw -notmatch '(?m)^updated:') { throw "HOME.md has no updated: field" }
    $homeRaw = $homeRaw -replace '(?m)^updated:.*$', "updated: $newest"
    [System.IO.File]::WriteAllText($homeFile, $homeRaw, [System.Text.UTF8Encoding]::new($false))
    Write-Output "applied: HOME.md updated: -> $newest"
  }
  default { throw "Unknown proposed_change: $change" }
}

Remove-Item -Path $File -Force -Confirm:$false
Add-Ledger 'applied'
Write-Output "proposal file removed (ledger updated)"
