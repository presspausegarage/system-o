#Requires -Version 7.0
<#
.SYNOPSIS
  Loop-cell runner (spec §System architecture): detect (script) -> propose
  (LLM, pluggable endpoint) -> verify (deterministic) -> apply (gated per
  endpoint).
.DESCRIPTION
  Executes one loop declared in a loop-manifest YAML (spec §Loop manifest).
  The LLM occupies exactly one box (propose); detection and verification are
  deterministic, and the endpoint chain degrades in manifest priority order
  (quality ceiling -> availability floor). An endpoint attempt that fails
  transport OR verification advances to the next endpoint. If all endpoints
  fail, the loop fails closed: no proposal, logged, nonzero finding count.

  REFERENCE-CELL SCOPE (honest boundary, not small print): this runner is the
  wrap-tail-repair reference cell. What it enforces generically from any
  manifest: scope (a proposal targeting a path outside scope: is suppressed,
  and auto-apply hands the manifest to the applier so it re-checks), budget
  (max_prompt_chars truncation, max_calls_per_run counted per LLM call),
  endpoint chain order + degradation, per-endpoint timeout, apply gating via
  auto_apply_endpoints, detect-step inertness (-DryRun is forced on). What is
  wrap-tail-SPECIFIC: the findings adapter (it parses detect-wrap-tail.ps1's
  dry-run contract line and nothing else), the 'structural' verifier, and the
  two repair types (prepend-session-log-entry, bump-home-updated). A second,
  materially different loop needs its findings adapter, verifier id, and
  repair types implemented here — that is the seam, and the runner refuses
  manifests declaring a verifier it does not implement rather than silently
  treating unknown output as clean.

  Proposals land in <root>/_meta/loops/proposals/ — kept out of any
  capture/triage-owned path so ingestion automation never sweeps
  machine-generated proposals. Apply via apply-loop-proposal.ps1.

  Per-endpoint auto-apply: when the manifest says 'apply: auto', a verified
  proposal is applied inline by the runner ONLY if the endpoint that served
  it is in auto_apply_endpoints; proposals from any other endpoint (e.g. the
  local floor) stay pending for the human walk. Trust follows the endpoint,
  not the loop.

  A `driver: stub` endpoint (canned response from a file) exercises the full
  cell deterministically with no LLM — the conformance-test vehicle (spec
  §Measured conformance) and a loop test harness.
.PARAMETER Manifest
  Path to the loop manifest YAML.
.PARAMETER Root
  Vault root. Default '.'. Point at a staged copy to rehearse safely.
.PARAMETER DryRun
  Detect + propose + verify, but write no proposals and no ledger entry.
.EXAMPLE
  run-loop.ps1 -Manifest spec/wrap-tail-repair.example.yaml -Root . -DryRun
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Manifest,
  [string]$Root = '.',
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Force UTF-8 for capturing claude-cli's stdout — found on the reference vault
# 2026-07-04: PowerShell's pipe capture of a native process's output depends on
# ambient console/$OutputEncoding state, which can differ between invocation modes
# (e.g. `pwsh -File` vs `pwsh -Command`, or a scheduled task's console allocation
# vs an interactive session). Without this forced, an endpoint's correct em-dash
# can decode as mojibake, tripping the verifier's structural check even though the
# model's output was correct — not a model or prompt bug, a stdout-decoding one.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# --- Manifest parser -------------------------------------------------------
# Parses exactly the loop-manifest schema (not a general YAML parser) — same
# stance as transform-orientation.ps1's manifest reader.
function Read-LoopManifest {
  param([string]$Path)
  $mf = @{ scope = [System.Collections.ArrayList]::new(); endpoints = [System.Collections.ArrayList]::new(); auto_apply_endpoints = [System.Collections.ArrayList]::new(); budget = @{}; detect = @{} }
  $lines = (Get-Content $Path -Raw -Encoding UTF8) -replace "`r`n","`n" -split "`n"
  $block = ''; $item = $null
  foreach ($line in $lines) {
    if ($line -match '^\s*(#.*)?$') { continue }
    if ($line -match '^([\w_]+):\s*$') { $block = $Matches[1]; $item = $null; continue }
    if ($line -match '^([\w_]+):\s*(.+?)\s*$') {
      $v = $Matches[2].Trim('"').Trim("'")
      $mf[$Matches[1]] = $v; $block = ''; $item = $null; continue
    }
    if ($block -and $line -match '^\s+-\s+(.*)$') {
      $rest = $Matches[1].Trim()
      if ($rest -match '^([\w_]+):\s*(.*)$') {
        $item = @{}; $item[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
        [void]$mf[$block].Add($item)
      } else {
        [void]$mf[$block].Add($rest.Trim('"').Trim("'")); $item = $null
      }
      continue
    }
    if ($block -and $line -match '^\s+([\w_]+):\s*(.*)$') {
      $k = $Matches[1]; $v = $Matches[2].Trim().Trim('"').Trim("'")
      if ($null -ne $item) { $item[$k] = $v }
      else { $mf[$block][$k] = $v }
      continue
    }
  }
  return $mf
}

# --- Setup -----------------------------------------------------------------
$manifestPath = (Resolve-Path $Manifest).Path
$mf = Read-LoopManifest $manifestPath
$loopName = $mf['loop']
if (-not $loopName) { throw "Manifest has no 'loop:' field." }
if ($mf.scope.Count -eq 0) { throw "Manifest has no 'scope:' entries — scope is required and enforced (spec §Loop manifest)." }
$verifierId = [string]($mf['verify'] ?? '')
if ($verifierId -ne 'structural') {
  throw "Unsupported verify: '$verifierId'. This reference runner implements the 'structural' verifier (wrap-tail-repair cell); a different verifier id needs an implementation here before its manifest can run (see .DESCRIPTION)."
}

$logDir  = Join-Path $Root '_meta/logs'
$logFile = Join-Path $logDir ("loop-{0}-{1}.log" -f $loopName, (Get-Date -Format 'yyyy-MM-dd'))
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
function Say { param([string]$m)
  $stamp = Get-Date -Format 'HH:mm:ss'
  Write-Host $m
  Add-Content -Path $logFile -Value "[$stamp] $m" -Encoding UTF8
}
Say ("starting loop={0} root={1} dry-run={2}" -f $loopName, $Root, $DryRun.IsPresent)

$proposalsDir = Join-Path $Root '_meta/loops/proposals'
$ledgerFile   = Join-Path $Root ("_meta/loops/{0}.ledger.jsonl" -f $loopName)
$maxPrompt    = [int]($mf.budget['max_prompt_chars'] ?? 24000)
$maxCalls     = [int]($mf.budget['max_calls_per_run'] ?? 4)
$applyMode    = [string]($mf['apply'] ?? 'propose-only')
$autoEps      = @($mf['auto_apply_endpoints'])

# --- 1. DETECT ---------------------------------------------------------------
$detector = Join-Path $Root ('_meta/scripts/' + $mf.detect['script'])
if (-not (Test-Path $detector)) { throw "Detector not found: $detector" }
# detect.args passes through from the manifest; -DryRun is forced on if absent,
# because the runner's detect step must be read-only (spec §Loop manifest's
# determinism guarantees) — a manifest cannot opt its detector into writing here.
$detectArgs = @()
if ($mf.detect['args']) { $detectArgs = @("$($mf.detect['args'])" -split '\s+' | Where-Object { $_ }) }
if ($detectArgs -notcontains '-DryRun') {
  if ($mf.detect['args']) { Say "note: detect.args lacks -DryRun — forcing it (the runner's detect step is always read-only)" }
  $detectArgs += '-DryRun'
}
# Invoked as a child pwsh so the manifest's args bind as real parameters —
# in-process array splatting would pass '-DryRun' positionally, not as a switch.
$detectOut = & pwsh -NoProfile -File $detector -Root $Root @detectArgs *>&1 | ForEach-Object { "$_" }
foreach ($l in $detectOut) { Say ("detect> " + $l) }

$gaps = @(); $homeStale = $false
foreach ($l in $detectOut) {
  if ($l -match '\[dry-run\] would flag in .+: (\d+) session-log gap\(s\) \[([^\]]*)\]; HOME stale: (\d+)') {
    if ($Matches[2].Trim()) { $gaps = @($Matches[2] -split ',\s*') }
    $homeStale = ([int]$Matches[3] -gt 0)
  }
}
if ($gaps.Count -eq 0 -and -not $homeStale) {
  Say "STATUS loop=$loopName gaps=0 home_stale=0 proposals_new=0 auto_applied=0 verifier_fail=0 scope_fail=0 (clean)"
  exit 0
}
Say ("findings: {0} session-log gap(s) [{1}]; HOME stale: {2}" -f $gaps.Count, ($gaps -join ', '), $homeStale)

# --- Shared helpers ----------------------------------------------------------
function Test-PendingProposal {
  param([string]$Change, [string]$EntryDate, [string]$Handoff)
  if (-not (Test-Path $proposalsDir)) { return $false }
  foreach ($f in (Get-ChildItem -Path $proposalsDir -Filter '*.md' -File)) {
    $head = Get-Content -Path $f.FullName -TotalCount 15 -Encoding UTF8 | Out-String
    if ($head -match "loop:\s*$([regex]::Escape($loopName))" -and
        $head -match "proposed_change:\s*$([regex]::Escape($Change))" -and
        (-not $Handoff -or $head -match "handoff:\s*$([regex]::Escape($Handoff))") -and
        (-not $EntryDate -or $head -match "entry_date:\s*$([regex]::Escape($EntryDate))")) { return $true }
  }
  return $false
}

function Write-Proposal {
  param([string]$Change, [string]$Target, [string]$EntryDate, [string]$Endpoint, [string]$Body, [string]$Handoff)
  if (-not (Test-Path $proposalsDir)) { New-Item -ItemType Directory -Path $proposalsDir -Force | Out-Null }
  $slug = if ($Handoff) { $Handoff } elseif ($EntryDate) { $EntryDate } else { Get-Date -Format 'yyyy-MM-dd' }
  $file = Join-Path $proposalsDir ("loop-{0}-{1}-{2}.md" -f $loopName, $Change, $slug)
  $fm = @(
    '---'
    'type: loop-proposal'
    "loop: $loopName"
    "proposed_change: $Change"
    "target: $Target"
    $(if ($EntryDate) { "entry_date: $EntryDate" })
    $(if ($Handoff) { "handoff: $Handoff" })
    "endpoint: $Endpoint"
    "generated: $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')"
    'tags:'
    '  - type/loop-proposal'
    '---'
    ''
  ) | Where-Object { $null -ne $_ }
  [System.IO.File]::WriteAllText($file, (($fm -join "`n") + $Body.Trim() + "`n"), [System.Text.UTF8Encoding]::new($false))
  Say ("proposal written: " + $file.Substring($Root.Length + 1))
  return $file
}

function Add-Ledger {
  param([hashtable]$Rec)
  $Rec['ts'] = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
  Add-Content -Path $ledgerFile -Value ($Rec | ConvertTo-Json -Compress) -Encoding UTF8
}

function Test-SessionLogEntry {
  param([string]$Text, [string]$Date, [string]$HandoffBase)
  $reasons = [System.Collections.ArrayList]::new()
  $lines = @($Text -split "`n")
  if ($lines.Count -lt 2 -or $lines.Count -gt 40) { [void]$reasons.Add("line count $($lines.Count) outside 2..40") }
  $em = [string][char]0x2014
  if ($lines[0] -notmatch ('^## ' + [regex]::Escape($Date) + ' ' + [regex]::Escape($em) + ' .+')) {
    [void]$reasons.Add('first line is not "## <date> <em-dash> <subject>"')
  }
  if (@($lines | Where-Object { $_ -match '^## ' }).Count -ne 1) { [void]$reasons.Add('must contain exactly one "## " header') }
  if ($HandoffBase -and $Text -notmatch [regex]::Escape("[[$HandoffBase]]")) { [void]$reasons.Add("missing [[$HandoffBase]] wikilink") }
  if ($Text -notmatch '(?m)^- ') { [void]$reasons.Add('missing trailing bullet line(s)') }
  if ($Text -notmatch 'Time') { [void]$reasons.Add('missing time-spent mention') }
  if ($Text -match '```') { [void]$reasons.Add('contains a code fence') }
  return ,$reasons
}

# Scope gate (spec §Loop manifest: "Enforced by the runner and the applier"):
# a proposal may only ever target a manifest scope: path. Checked here before a
# proposal is written, and re-checked by the applier (auto-apply hands it this
# run's manifest so the second check never depends on filename conventions).
function Test-InScope {
  param([string]$Target)
  return ($mf.scope -contains $Target)
}

function Invoke-AutoApply {
  param([string]$ProposalFile, [string]$Endpoint)
  if ($applyMode -ne 'auto' -or $autoEps -notcontains $Endpoint) { return $false }
  try {
    $out = & (Join-Path $PSScriptRoot 'apply-loop-proposal.ps1') -File $ProposalFile -Root $Root -Manifest $manifestPath *>&1 | ForEach-Object { "$_" }
    foreach ($l in $out) { Say ("apply> " + $l) }
    return $true
  } catch {
    Say ("auto-apply FAILED (proposal kept pending for the human walk): " + $_.Exception.Message)
    return $false
  }
}

function Invoke-Endpoint {
  param([hashtable]$Ep, [string]$Prompt)
  switch ($Ep['driver']) {
    'claude-cli' {
      # Run in a job so the manifest's timeout_sec is honored — a hung CLI call
      # must degrade to the next endpoint, not hang the whole loop run.
      $timeoutSec = [int]($Ep['timeout_sec'] ?? 180)
      $job = Start-Job -ScriptBlock {
        param($Prompt, $Model)
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
        $out = ($Prompt | & claude -p --model $Model 2>&1 | Out-String).Trim()
        @{ out = $out; code = $LASTEXITCODE }
      } -ArgumentList $Prompt, $Ep['model']
      if (-not (Wait-Job -Job $job -Timeout $timeoutSec)) {
        Stop-Job -Job $job
        Remove-Job -Job $job -Force
        Say ("endpoint claude-cli/{0} timed out after {1}s — degrading to next endpoint" -f $Ep['model'], $timeoutSec)
        return $null
      }
      $r = Receive-Job -Job $job
      Remove-Job -Job $job -Force
      $rOut = [string]($r['out'] ?? '')
      if ([int]($r['code'] ?? 1) -eq 0 -and $rOut) { return $rOut }
      Say ("endpoint claude-cli/{0} failed (exit={1}): {2}" -f $Ep['model'], $r['code'], $rOut.Substring(0, [Math]::Min(160, $rOut.Length)))
      return $null
    }
    'stub' {   # deterministic canned response — conformance testing (spec §Measured
               # conformance) and loop-cell dry runs, no LLM/network dependency.
      $f = $Ep['file']
      if (-not $f) { Say 'endpoint stub: manifest entry has no file:'; return $null }
      if (-not [System.IO.Path]::IsPathRooted($f)) { $f = Join-Path $Root $f }
      if (-not (Test-Path $f)) { Say ("endpoint stub: response file not found: " + $f); return $null }
      return (Get-Content -Path $f -Raw -Encoding UTF8).Trim()
    }
    'ollama' {
      try {
        $body = @{ model = $Ep['model']; prompt = $Prompt; stream = $false
                   options = @{ num_ctx = [int]($Ep['num_ctx'] ?? 8192) } } | ConvertTo-Json -Depth 4
        $r = Invoke-RestMethod -Uri ($Ep['url'] + '/api/generate') -Method Post -Body $body `
               -ContentType 'application/json' -TimeoutSec ([int]($Ep['timeout_sec'] ?? 120))
        if ($r.response) { return $r.response.Trim() }
      } catch { Say ("endpoint ollama/{0} unreachable: {1}" -f $Ep['model'], $_.Exception.Message) }
      return $null
    }
    default { Say ("unknown driver: " + $Ep['driver']); return $null }
  }
}

# --- 2+3. PROPOSE + VERIFY per finding --------------------------------------
$template = Get-Content -Path (Join-Path $Root ('_meta/templates/' + $mf['prompt'])) -Raw -Encoding UTF8
$newProposals = 0; $verifierFails = 0; $scopeFails = 0; $calls = 0; $autoApplied = 0; $appliedMaxDate = $null

$homeUpdated = $null
$homeFile = Join-Path $Root '_meta/HOME.md'
if ((Test-Path $homeFile) -and ((Get-Content -Path $homeFile -Raw -Encoding UTF8) -match '(?m)^updated:\s*(\d{4}-\d{2}-\d{2})')) {
  $homeUpdated = $Matches[1]
}

foreach ($g in $gaps) {
  if ($g -like 'commit-only:*') { Say "gap ${g}: commit-only date — needs a human-drafted entry, skipped"; continue }
  if ($calls -ge $maxCalls) { Say "budget: max_calls_per_run=$maxCalls reached — remaining gaps deferred to next run"; break }
  if (Test-PendingProposal -Change 'prepend-session-log-entry' -Handoff $g) { Say "gap ${g}: proposal already pending — skipped"; continue }

  $hBase = $g
  $d = $g.Substring(0, 10)
  $handoff = @(Get-ChildItem -Path (Join-Path $Root '_meta/handoffs') -Filter "$hBase.md" -File -ErrorAction SilentlyContinue)
  if ($handoff.Count -eq 0) {
    $handoff = @(Get-ChildItem -Path (Join-Path $Root '_archive/handoffs') -Filter "$hBase.md" -File -Recurse -ErrorAction SilentlyContinue)
  }
  if ($handoff.Count -eq 0) { Say "gap ${g}: handoff file not found — skipped"; continue }
  $hContent = Get-Content -Path $handoff[0].FullName -Raw -Encoding UTF8

  $prompt = $template -replace '\{\{DATE\}\}', $d -replace '\{\{HANDOFF_BASENAME\}\}', $hBase
  $room = $maxPrompt - ($prompt.Length - '{{HANDOFF_CONTENT}}'.Length)
  if ($hContent.Length -gt $room) { $hContent = $hContent.Substring(0, $room) + "`n[truncated]" }
  $prompt = $prompt.Replace('{{HANDOFF_CONTENT}}', $hContent)

  $accepted = $null; $usedEp = $null
  foreach ($ep in $mf.endpoints) {
    # Cap checked here, where calls are counted — the per-gap check alone lets
    # one multi-endpoint finding overshoot the budget.
    if ($calls -ge $maxCalls) { Say "budget: max_calls_per_run=$maxCalls reached mid-finding — remaining endpoints skipped"; break }
    $calls++
    Say ("gap ${g}: proposing via {0}/{1}" -f $ep['driver'], $ep['model'])
    $draft = Invoke-Endpoint -Ep $ep -Prompt $prompt
    if (-not $draft) { continue }
    if ($draft -match '(?s)^```[a-z]*\s*(.*?)\s*```\s*$') { $draft = $Matches[1] }
    $fails = Test-SessionLogEntry -Text $draft -Date $d -HandoffBase $hBase
    if ($fails.Count -eq 0) { $accepted = $draft; $usedEp = "$($ep['driver'])/$($ep['model'])"; break }
    $verifierFails++
    Say ("gap ${g}: verifier FAILED on {0}/{1}: {2}" -f $ep['driver'], $ep['model'], ($fails -join '; '))
  }

  if ($accepted) {
    if (-not (Test-InScope '_meta/session-log.md')) {
      Say "gap ${g}: SCOPE VIOLATION — proposal targets _meta/session-log.md, which is not in manifest scope — suppressed"
      $scopeFails++
      if (-not $DryRun) { Add-Ledger @{ loop = $loopName; change = 'prepend-session-log-entry'; entry_date = $d; handoff = $hBase; endpoint = $usedEp; verifier = 'scope-fail'; applied = $false } }
    } else {
      if (-not $DryRun) {
        $pFile = Write-Proposal -Change 'prepend-session-log-entry' -Target '_meta/session-log.md' -EntryDate $d -Endpoint $usedEp -Body $accepted -Handoff $hBase
        Add-Ledger @{ loop = $loopName; change = 'prepend-session-log-entry'; entry_date = $d; handoff = $hBase; endpoint = $usedEp; verifier = 'pass'; applied = $false }
        if (Invoke-AutoApply -ProposalFile $pFile -Endpoint $usedEp) {
          $autoApplied++
          if ($null -eq $appliedMaxDate -or $d -gt $appliedMaxDate) { $appliedMaxDate = $d }
        }
      } else { Say "gap ${g}: [dry-run] verified draft ready (endpoint $usedEp) — not written" }
      $newProposals++
    }
  } else {
    Say "gap ${g}: FAIL-CLOSED — no endpoint produced a verifiable entry"
    if (-not $DryRun) { Add-Ledger @{ loop = $loopName; change = 'prepend-session-log-entry'; entry_date = $d; handoff = $hBase; endpoint = 'none'; verifier = 'fail'; applied = $false } }
  }
}

# HOME bump fires on detect-time staleness OR the cascade: an entry auto-applied this run
# and dated newer than HOME's stamp has just made HOME stale. Deliberately NOT co-emitted
# for still-pending (propose-only) entries — the bump reads "newest at apply time", so
# applying it before the pending entry would recreate the staleness on human apply.
$needHomeBump = $homeStale -or ($null -ne $appliedMaxDate -and $null -ne $homeUpdated -and $appliedMaxDate -gt $homeUpdated)
if ($needHomeBump -and -not $homeStale) {
  Say ("home cascade: auto-applied entry {0} outdates HOME stamp {1} — co-emitting bump" -f $appliedMaxDate, $homeUpdated)
}
if ($needHomeBump -and -not (Test-InScope '_meta/HOME.md')) {
  Say "home-stale: SCOPE VIOLATION — bump targets _meta/HOME.md, which is not in manifest scope — suppressed"
  $scopeFails++
  $needHomeBump = $false
}
if ($needHomeBump) {
  if (Test-PendingProposal -Change 'bump-home-updated' -EntryDate '') { Say "home-stale: proposal already pending — skipped" }
  else {
    $body = "Deterministic repair (no LLM): set ``updated:`` in ``_meta/HOME.md`` frontmatter to the newest ``## YYYY-MM-DD`` date in ``_meta/session-log.md`` **at apply time** (order-independent if session-log entries are applied first)."
    if (-not $DryRun) {
      $pFile = Write-Proposal -Change 'bump-home-updated' -Target '_meta/HOME.md' -EntryDate '' -Endpoint 'deterministic' -Body $body
      Add-Ledger @{ loop = $loopName; change = 'bump-home-updated'; endpoint = 'deterministic'; verifier = 'pass'; applied = $false }
      if (Invoke-AutoApply -ProposalFile $pFile -Endpoint 'deterministic') { $autoApplied++ }
    } else { Say "home-stale: [dry-run] bump proposal ready — not written" }
    $newProposals++
  }
}

Say ("STATUS loop=$loopName gaps=$($gaps.Count) home_stale=$([int]$homeStale) proposals_new=$newProposals auto_applied=$autoApplied verifier_fail=$verifierFails scope_fail=$scopeFails")
