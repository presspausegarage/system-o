#Requires -Version 7.0
<#
.SYNOPSIS
  Generic loop-cell runner: detect (script) -> propose (LLM or deterministic)
  -> verify (cell) -> emit proposal -> apply (gated per endpoint).
.DESCRIPTION
  Executes one loop declared in a _meta/loops/*.yaml manifest. v2 (2026-07-22,
  system-o v0.3.0 slice): the loop-specific pieces — findings adapter, draft
  verifier, proposal bodies, repair executors, cascade — live in a CELL SCRIPT
  declared by the manifest (cell: <file>, resolved in _meta/scripts/cells/),
  dot-sourced by this runner and by apply-loop-proposal.ps1. The runner owns
  everything generic: manifest parsing, detect invocation (read-only, child
  pwsh, -DryRun forced), endpoint chain + degradation + per-endpoint timeout,
  certified-endpoint reordering under apply:auto (dead-apply-leg fix
  2026-07-06), budget caps, scope gate, idempotency, proposals, ledger, STATUS.

  CELL CONTRACT — a cell script must define:
    $CellContract   @{ verifier = '<id>'; changes = @('<change>', ...) }
                    verifier must equal the manifest's verify: value; the
                    runner refuses a mismatch or a missing cell (fail-closed,
                    never treating unknown detector output as clean).
    Get-LoopFindings        -DetectOutput <string[]> -Root <path> -> finding[]
    Test-LoopDraft          -Finding <ht> -Draft <string> -Root <path>
                            -> string[] failure reasons (empty = pass)
    Get-LoopProposalBody    -Finding <ht> -Draft <string> -> body markdown
    Invoke-LoopRepair       -Change <string> -Fields <ht> -Body <string>
                            -Root <path> -> status message; throws on failure.
                            MUST work from the proposal file alone (no cell
                            state) — the applier runs in a later process.
    Get-LoopCascadeFindings -Applied <finding[]> -Root <path> -> finding[]
                            (optional; called once after the main pass with
                            the findings AUTO-APPLIED this run)
    Get-LoopStatusFields    -> string merged into the STATUS line (optional)

  FINDING SHAPE (hashtable):
    change      one of $CellContract.changes
    target      vault-relative path, forward slashes (scope-gated)
    fields      [ordered] ht -> proposal frontmatter keys + idempotency identity
    slug        proposal filename component
    needs_llm   bool; when true: prompt_vars (ht of {{VAR}} -> value) and
                clip_var (name of the var truncated to fit budget)
    body        proposal body (deterministic findings only)
    summary     short log label
    skip        optional reason string -> logged and skipped

  Scope grammar (checked here before a proposal is written, re-checked by the
  applier): exact path | 'dir/' prefix | '**/suffix' match.

  Proposals land in _meta/loops/proposals/ (NOT _inbox/ — the 02:00 triage
  chain owns _inbox and must never sweep machine-generated proposals).
  Apply via apply-loop-proposal.ps1 or the apply-proposals.ps1 walk.

  Per-endpoint auto-apply (2026-07-01, earned via the synthetic battery): when
  the manifest says 'apply: auto', a verified proposal is applied inline ONLY
  if the endpoint that served it is in auto_apply_endpoints. Trust follows the
  endpoint, not the loop.
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

# Force UTF-8 for capturing claude-cli's stdout — found 2026-07-04: pipe capture of a
# native process depends on ambient console/$OutputEncoding state, which differs between
# `pwsh -File` and `pwsh -Command`. Without this, a correct em-dash decodes as mojibake
# and trips structural verifiers — a stdout-decoding problem, not a model problem.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# --- Manifest parser -------------------------------------------------------
# Parses exactly the loop-manifest schema (not a general YAML parser).
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
    if ($block -and $line -match '^\s+-\s+(.*)$') {              # list item
      $rest = $Matches[1].Trim()
      if ($rest -match '^([\w_]+):\s*(.*)$') {                   # item is a map
        $item = @{}; $item[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
        [void]$mf[$block].Add($item)
      } else {                                                   # item is a scalar
        [void]$mf[$block].Add($rest.Trim('"').Trim("'")); $item = $null
      }
      continue
    }
    if ($block -and $line -match '^\s+([\w_]+):\s*(.*)$') {      # nested key: val
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
if ($mf.scope.Count -eq 0) { throw "Manifest has no 'scope:' entries — scope is required and enforced." }

$logDir  = Join-Path $Root '_meta/logs'
$logFile = Join-Path $logDir ("loop-{0}-{1}.log" -f $loopName, (Get-Date -Format 'yyyy-MM-dd'))
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
function Say { param([string]$m)
  $stamp = Get-Date -Format 'HH:mm:ss'
  Write-Host $m
  Add-Content -Path $logFile -Value "[$stamp] $m" -Encoding UTF8
}
Say ("starting loop={0} root={1} dry-run={2}" -f $loopName, $Root, $DryRun.IsPresent)

# --- Cell resolution (the seam) --------------------------------------------
if (-not $mf['cell']) { throw "Manifest has no 'cell:' field — v2 runner requires a cell script in _meta/scripts/cells/ implementing this loop's adapter/verifier/repairs (see .DESCRIPTION)." }
$cellPath = Join-Path $Root ('_meta/scripts/cells/' + $mf['cell'])
if (-not (Test-Path $cellPath)) { throw "Cell script not found: $cellPath" }
. $cellPath
foreach ($fn in 'Get-LoopFindings','Test-LoopDraft','Get-LoopProposalBody','Invoke-LoopRepair') {
  if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) { throw "Cell $($mf['cell']) does not define required function $fn." }
}
if (-not (Get-Variable CellContract -ErrorAction SilentlyContinue)) { throw "Cell $($mf['cell']) does not define `$CellContract." }
$verifierId = [string]($mf['verify'] ?? '')
if ($CellContract['verifier'] -ne $verifierId) {
  throw "Manifest declares verify: '$verifierId' but cell $($mf['cell']) implements '$($CellContract['verifier'])' — refusing (a manifest's declared policy must match the code that enforces it)."
}

$proposalsDir = Join-Path $Root '_meta/loops/proposals'
$ledgerFile   = Join-Path $Root ("_meta/loops/{0}.ledger.jsonl" -f $loopName)
$maxPrompt    = [int]($mf.budget['max_prompt_chars'] ?? 24000)
$maxCalls     = [int]($mf.budget['max_calls_per_run'] ?? 4)
$applyMode    = [string]($mf['apply'] ?? 'propose-only')
$autoEps      = @($mf['auto_apply_endpoints'])

# Under apply:auto, try allowlisted (certified) endpoints before the rest so a proposal
# actually lands auto-applied instead of stalling on a higher-priority but uncertified
# endpoint (dead-apply-leg bug, 2026-07-06). Degradation still holds within each tier.
$endpointOrder = @($mf.endpoints)
if ($applyMode -eq 'auto' -and $autoEps.Count -gt 0) {
  $certified = @(); $rest = @()
  foreach ($ep in $endpointOrder) {
    $key = "$($ep['driver'])/$($ep['model'])"
    if ($autoEps -contains $key) { $certified += $ep } else { $rest += $ep }
  }
  $endpointOrder = $certified + $rest
}

# --- 1. DETECT ---------------------------------------------------------------
$detector = Join-Path $Root ('_meta/scripts/' + $mf.detect['script'])
if (-not (Test-Path $detector)) { throw "Detector not found: $detector" }
# detect.args passes through from the manifest; -DryRun is forced on if absent — the
# runner's detect step is always read-only, a manifest cannot opt its detector into
# writing here. Invoked as a child pwsh so args from data bind as real parameters
# (in-process array splatting binds positionally — found 2026-07-22).
$detectArgs = @()
if ($mf.detect['args']) { $detectArgs = @("$($mf.detect['args'])" -split '\s+' | Where-Object { $_ }) }
if ($detectArgs -notcontains '-DryRun') {
  if ($mf.detect['args']) { Say "note: detect.args lacks -DryRun — forcing it (the runner's detect step is always read-only)" }
  $detectArgs += '-DryRun'
}
$detectOut = & pwsh -NoProfile -File $detector -Root $Root @detectArgs *>&1 | ForEach-Object { "$_" }
foreach ($l in $detectOut) { Say ("detect> " + $l) }

# --- Findings via the cell ---------------------------------------------------
$findings = @(Get-LoopFindings -DetectOutput $detectOut -Root $Root)
$live = @($findings | Where-Object { -not $_.ContainsKey('skip') })
foreach ($f in ($findings | Where-Object { $_.ContainsKey('skip') })) { Say ("finding $($f.summary): skipped — $($f.skip)") }

function Get-StatusExtras {
  if (Get-Command Get-LoopStatusFields -ErrorAction SilentlyContinue) { return ((Get-LoopStatusFields) + ' ') }
  return ''
}

if ($live.Count -eq 0) {
  Say ("STATUS loop=$loopName $(Get-StatusExtras)findings=0 proposals_new=0 auto_applied=0 verifier_fail=0 scope_fail=0 (clean)")
  exit 0
}
Say ("findings: {0} live, {1} skipped" -f $live.Count, ($findings.Count - $live.Count))

# --- Shared helpers ----------------------------------------------------------
function Test-PendingProposal {   # idempotency: don't re-emit what's already awaiting review
  param([string]$Change, [hashtable]$Fields)
  if (-not (Test-Path $proposalsDir)) { return $false }
  foreach ($f in (Get-ChildItem -Path $proposalsDir -Filter '*.md' -File)) {
    $head = Get-Content -Path $f.FullName -TotalCount 25 -Encoding UTF8 | Out-String
    if ($head -notmatch "loop:\s*$([regex]::Escape($loopName))") { continue }
    if ($head -notmatch "proposed_change:\s*$([regex]::Escape($Change))") { continue }
    $all = $true
    foreach ($k in $Fields.Keys) {
      $v = [string]$Fields[$k]
      if ($v -and $head -notmatch "$([regex]::Escape($k)):\s*$([regex]::Escape($v))") { $all = $false; break }
    }
    if ($all) { return $true }
  }
  return $false
}

function Write-Proposal {
  param([hashtable]$Finding, [string]$Endpoint, [string]$Body)
  if (-not (Test-Path $proposalsDir)) { New-Item -ItemType Directory -Path $proposalsDir -Force | Out-Null }
  $slug = if ($Finding.slug) { $Finding.slug } else { Get-Date -Format 'yyyy-MM-dd' }
  $file = Join-Path $proposalsDir ("loop-{0}-{1}-{2}.md" -f $loopName, $Finding.change, $slug)
  $fm = [System.Collections.ArrayList]::new()
  [void]$fm.Add('---')
  [void]$fm.Add('type: loop-proposal')
  [void]$fm.Add("loop: $loopName")
  [void]$fm.Add("proposed_change: $($Finding.change)")
  [void]$fm.Add("target: $($Finding.target)")
  foreach ($k in $Finding.fields.Keys) {
    if ([string]$Finding.fields[$k]) { [void]$fm.Add("${k}: $($Finding.fields[$k])") }
  }
  [void]$fm.Add("endpoint: $Endpoint")
  [void]$fm.Add("generated: $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')")
  [void]$fm.Add('tags:')
  [void]$fm.Add('  - type/loop-proposal')
  [void]$fm.Add('---')
  [void]$fm.Add('')
  [System.IO.File]::WriteAllText($file, ((($fm.ToArray()) -join "`n") + $Body.Trim() + "`n"), [System.Text.UTF8Encoding]::new($false))
  Say ("proposal written: " + $file.Substring($Root.Length + 1))
  return $file
}

function Add-Ledger {
  param([hashtable]$Rec)
  $Rec['ts'] = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
  Add-Content -Path $ledgerFile -Value ($Rec | ConvertTo-Json -Compress) -Encoding UTF8
}

function New-LedgerRecord {
  param([hashtable]$Finding, [string]$Endpoint, [string]$Verifier)
  $rec = @{ loop = $loopName; change = $Finding.change; endpoint = $Endpoint; verifier = $Verifier; applied = $false }
  foreach ($k in $Finding.fields.Keys) { if ([string]$Finding.fields[$k]) { $rec[$k] = [string]$Finding.fields[$k] } }
  return $rec
}

# Scope gate: exact path | 'dir/' prefix | '**/suffix'. Checked here before a proposal
# is written and re-checked by the applier (which is handed this run's manifest so the
# second check never depends on filename conventions).
function Test-InScope {
  param([string]$Target)
  $t = $Target -replace '\\','/'
  foreach ($s in $mf.scope) {
    $s = "$s" -replace '\\','/'
    if ($s.StartsWith('**/')) { if ($t -like ('*/' + $s.Substring(3)) -or $t -eq $s.Substring(3)) { return $true } }
    elseif ($s.EndsWith('/'))  { if ($t.StartsWith($s)) { return $true } }
    elseif ($t -eq $s)         { return $true }
  }
  return $false
}

function Invoke-AutoApply {   # inline apply arm — fires ONLY for allowlisted endpoints in auto mode
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

function Invoke-Endpoint {   # one attempt against one endpoint; $null on transport failure
  param([hashtable]$Ep, [string]$Prompt)
  switch ($Ep['driver']) {
    'claude-cli' {
      # Job wrapper honors timeout_sec — a hung CLI call must degrade to the next
      # endpoint, not hang the whole loop run.
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
    'stub' {   # deterministic canned response — conformance testing and loop dry runs
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
$template = $null
if ($mf['prompt']) { $template = Get-Content -Path (Join-Path $Root ('_meta/templates/' + $mf['prompt'])) -Raw -Encoding UTF8 }
$newProposals = 0; $verifierFails = 0; $scopeFails = 0; $calls = 0; $autoApplied = 0
$appliedFindings = [System.Collections.ArrayList]::new()

function Invoke-FindingPass {
  param([hashtable]$F)
  $label = $F.summary
  if (Test-PendingProposal -Change $F.change -Fields $F.fields) { Say "${label}: proposal already pending — skipped"; return }

  $accepted = $null; $usedEp = $null
  if ($F.needs_llm) {
    if ($null -eq $template) { Say "${label}: manifest has no prompt: template but finding needs an LLM — FAIL-CLOSED"; return }
    if ($script:calls -ge $maxCalls) { Say "budget: max_calls_per_run=$maxCalls reached — ${label} deferred to next run"; return }
    # render prompt: substitute every var, then clip the clip_var to fit the budget
    $prompt = $template
    foreach ($k in $F.prompt_vars.Keys) {
      if ($k -eq $F.clip_var) { continue }
      $prompt = $prompt.Replace('{{' + $k + '}}', [string]$F.prompt_vars[$k])
    }
    if ($F.ContainsKey('clip_var') -and $F.clip_var) {
      $clipVal = [string]$F.prompt_vars[$F.clip_var]
      $room = $maxPrompt - ($prompt.Length - ('{{' + $F.clip_var + '}}').Length)
      if ($clipVal.Length -gt $room) { $clipVal = $clipVal.Substring(0, [Math]::Max(0, $room)) + "`n[truncated]" }
      $prompt = $prompt.Replace('{{' + $F.clip_var + '}}', $clipVal)
    }
    foreach ($ep in $endpointOrder) {
      # cap checked where calls are counted — a multi-endpoint finding must not overshoot
      if ($script:calls -ge $maxCalls) { Say "budget: max_calls_per_run=$maxCalls reached mid-finding — remaining endpoints skipped"; break }
      $script:calls++
      Say ("${label}: proposing via {0}/{1}" -f $ep['driver'], $ep['model'])
      $draft = Invoke-Endpoint -Ep $ep -Prompt $prompt
      if (-not $draft) { continue }
      if ($draft -match '(?s)^```[a-z]*\s*(.*?)\s*```\s*$') { $draft = $Matches[1] }   # strip a fence wrap
      $fails = @(Test-LoopDraft -Finding $F -Draft $draft -Root $Root)
      if ($fails.Count -eq 0) { $accepted = $draft; $usedEp = "$($ep['driver'])/$($ep['model'])"; break }
      $script:verifierFails++
      Say ("${label}: verifier FAILED on {0}/{1}: {2}" -f $ep['driver'], $ep['model'], ($fails -join '; '))
    }
    if ($null -eq $accepted) {
      Say "${label}: FAIL-CLOSED — no endpoint produced a verifiable draft"
      if (-not $DryRun) { Add-Ledger (New-LedgerRecord -Finding $F -Endpoint 'none' -Verifier 'fail') }
      return
    }
  } else {
    $usedEp = 'deterministic'
  }

  if (-not (Test-InScope $F.target)) {
    Say "${label}: SCOPE VIOLATION — proposal targets $($F.target), not in manifest scope — suppressed"
    $script:scopeFails++
    if (-not $DryRun) { Add-Ledger (New-LedgerRecord -Finding $F -Endpoint $usedEp -Verifier 'scope-fail') }
    return
  }

  $body = if ($F.needs_llm) { Get-LoopProposalBody -Finding $F -Draft $accepted } else { $F.body }
  if (-not $DryRun) {
    $pFile = Write-Proposal -Finding $F -Endpoint $usedEp -Body $body
    Add-Ledger (New-LedgerRecord -Finding $F -Endpoint $usedEp -Verifier 'pass')
    if (Invoke-AutoApply -ProposalFile $pFile -Endpoint $usedEp) {
      $script:autoApplied++
      [void]$script:appliedFindings.Add($F)
    }
  } else { Say "${label}: [dry-run] verified proposal ready (endpoint $usedEp) — not written" }
  $script:newProposals++
}

foreach ($f in $live) { Invoke-FindingPass -F $f }

# --- 4. CASCADE — a repair that deterministically creates a new finding inside the
# same loop's scope is proposed in the SAME run, not deferred (runner semantics).
if (Get-Command Get-LoopCascadeFindings -ErrorAction SilentlyContinue) {
  $cascade = @(Get-LoopCascadeFindings -Applied @($appliedFindings) -Root $Root)
  foreach ($f in $cascade) {
    if ($f.ContainsKey('skip')) { Say ("cascade $($f.summary): skipped — $($f.skip)"); continue }
    Say ("cascade finding: " + $f.summary)
    Invoke-FindingPass -F $f
  }
}

Say ("STATUS loop=$loopName $(Get-StatusExtras)findings=$($live.Count) proposals_new=$newProposals auto_applied=$autoApplied verifier_fail=$verifierFails scope_fail=$scopeFails")
