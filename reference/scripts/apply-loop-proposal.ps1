#Requires -Version 7.0
<#
.SYNOPSIS
  Apply (or reject) one approved loop proposal from _meta/loops/proposals/.
.DESCRIPTION
  The apply arm of the loop cell — deterministic, no LLM. v2 (2026-07-22,
  system-o v0.3.0 seam refactor): repair implementations live in the loop's
  CELL SCRIPT (manifest cell: field, _meta/scripts/cells/), dot-sourced here
  and invoked via the cell contract's Invoke-LoopRepair. This applier owns the
  generic arms: proposal parsing, manifest resolution, scope re-check (same
  exact | 'dir/' prefix | '**/suffix' grammar as the runner), ledger, reject.

  Scope is enforced HERE as well as in the runner: auto-apply hands this
  script the run's manifest via -Manifest; a standalone invocation falls back
  to _meta/loops/<loop>.yaml. A proposal targeting a path outside the
  manifest's scope: is refused regardless of who invokes the apply.

  On success the proposal file is deleted (it is a machine-generated artifact;
  the ledger keeps the record). -Reject moves it to _sewerpipe/ (30d net).
  Invoked directly, per-item from apply-proposals.ps1's interactive walk, or
  inline by run-loop.ps1's auto-apply arm.

  v2 behavior change from the pre-seam applier: a missing manifest is now a
  hard refusal, not a WARN-and-proceed. Repairs live in the manifest-declared
  cell, so without the manifest there is no repair implementation to run at
  all - the manifest is load-bearing for apply, not just for scope.
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
$target = [string]($fm['target'] ?? '')
if (-not $change) { throw "File has no proposed_change field: $File" }
if (-not $loop)   { throw "File has no loop field: $File" }

function Add-Ledger {
  param([string]$Outcome)
  $ledger = Join-Path $Root ("_meta/loops/{0}.ledger.jsonl" -f $loop)
  $rec = @{ loop = $loop; change = $change; outcome = $Outcome; ts = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss' }
  foreach ($k in $fm.Keys) {
    if ($k -in 'type','loop','proposed_change','endpoint','generated','tags') { continue }
    if ([string]$fm[$k]) { $rec[$k] = [string]$fm[$k] }
  }
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

# --- Manifest resolution + scope re-check -----------------------------------
if (-not $Manifest) { $Manifest = Join-Path $Root ("_meta/loops/{0}.yaml" -f $loop) }
if (-not (Test-Path $Manifest)) { throw "Manifest not found for loop '$loop': $Manifest — cannot verify scope or resolve the cell; refusing to apply." }
$scope = [System.Collections.ArrayList]::new()
$cellFile = $null
$inScope = $false
foreach ($line in (Get-Content -Path $Manifest -Encoding UTF8)) {
  if ($line -match '^scope:\s*$') { $inScope = $true; continue }
  if ($inScope -and $line -match '^\s+-\s+(.+?)\s*$') { [void]$scope.Add($Matches[1].Trim('"').Trim("'")); continue }
  if ($line -match '^\S') { $inScope = $false }
  if ($line -match '^cell:\s*(\S+)\s*$') { $cellFile = $Matches[1].Trim('"').Trim("'") }
}
if ($scope.Count -eq 0) { throw "Manifest $Manifest declares no scope: — refusing to apply." }
if (-not $cellFile) { throw "Manifest $Manifest declares no cell: — refusing to apply (repairs live in the cell)." }

function Test-InScope {
  param([string]$T)
  $t = $T -replace '\\','/'
  foreach ($s in $scope) {
    $s = "$s" -replace '\\','/'
    if ($s.StartsWith('**/')) { if ($t -like ('*/' + $s.Substring(3)) -or $t -eq $s.Substring(3)) { return $true } }
    elseif ($s.EndsWith('/'))  { if ($t.StartsWith($s)) { return $true } }
    elseif ($t -eq $s)         { return $true }
  }
  return $false
}
if (-not (Test-InScope $target)) {
  Add-Ledger 'scope-refused'
  throw "SCOPE VIOLATION: proposal targets '$target', not in $loop's manifest scope — refused."
}

# --- Cell resolution + repair -----------------------------------------------
$cellPath = Join-Path $Root ('_meta/scripts/cells/' + $cellFile)
if (-not (Test-Path $cellPath)) { throw "Cell script not found: $cellPath" }
. $cellPath
if (-not (Get-Command Invoke-LoopRepair -ErrorAction SilentlyContinue)) { throw "Cell $cellFile does not define Invoke-LoopRepair." }
if ((Get-Variable CellContract -ErrorAction SilentlyContinue) -and ($CellContract['changes'] -notcontains $change)) {
  throw "Cell $cellFile does not implement change '$change' (declares: $($CellContract['changes'] -join ', '))."
}

$fields = @{}
foreach ($k in $fm.Keys) {
  if ($k -in 'type','loop','proposed_change','target','endpoint','generated','tags') { continue }
  $fields[$k] = $fm[$k]
}
$fields['target'] = $target   # repairs may need the target path (variable-target loops)

$msg = Invoke-LoopRepair -Change $change -Fields $fields -Body $body -Root $Root
Write-Output $msg

Remove-Item -Path $File -Force -Confirm:$false
Add-Ledger 'applied'
Write-Output "proposal file removed (ledger updated)"
