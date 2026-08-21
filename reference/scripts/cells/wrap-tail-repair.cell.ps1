#Requires -Version 7.0
<#
.SYNOPSIS
  Cell script for the wrap-tail-repair loop (see run-loop.ps1 .DESCRIPTION for
  the cell contract). Dot-sourced by run-loop.ps1 and apply-loop-proposal.ps1.
.DESCRIPTION
  Loop-specific pieces extracted from the v1 monolithic runner/applier
  (2026-07-22, system-o v0.3.0 seam refactor - behavior-preserving port):
    adapter   parses detect-wrap-tail.ps1's dry-run contract line
    verifier  'structural' - session-log entry shape (format, date, handoff
              wikilink, single header, bullet tail, no fence)
    repairs   regenerate-session-log (DETERMINISTIC, spec v0.4:
              runs build-session-log.ps1, which derives the log's generated region
              from handoffs - the LLM-drafted prepend-session-log-entry repair is
              retired; commit-only / handoff-less gaps stay human work)
              bump-home-updated (deterministic, newest-entry-at-apply-time)
    stale     Test-LoopStale - re-checks at APPLY time that the gap still exists
              (queued proposals can outlive their gap; see the function)
    cascade   HOME bump co-emit when a regenerated entry outdates HOME's
              stamp (synthetic battery S1/S2 finding, 2026-07-01)
  This cell has NO LLM findings. Test-LoopDraft is kept only to satisfy the runner's
  required-function check and fails closed if ever invoked.
#>

Set-StrictMode -Version Latest

$CellContract = @{
  verifier = 'structural'
  changes  = @('regenerate-session-log', 'bump-home-updated')
}

$script:WrapTailGaps       = @()
$script:WrapTailHomeStale  = $false
$script:WrapTailHomeStamp  = $null

function New-HomeBumpFinding {
  param([string]$Summary)
  return @{
    change    = 'bump-home-updated'
    target    = '_meta/HOME.md'
    fields    = [ordered]@{}
    slug      = (Get-Date -Format 'yyyy-MM-dd')
    needs_llm = $false
    body      = "Deterministic repair (no LLM): set ``updated:`` in ``_meta/HOME.md`` frontmatter to the newest ``## YYYY-MM-DD`` date in ``_meta/session-log.md`` **at apply time** (order-independent if session-log entries are applied first). Flagged by the wrap-tail detector (HOME stale)."
    summary   = $Summary
  }
}

function Get-LoopFindings {
  param([string[]]$DetectOutput, [string]$Root)

  $gaps = @()
  foreach ($l in $DetectOutput) {
    if ($l -match '\[dry-run\] would flag in .+: (\d+) session-log gap\(s\) \[([^\]]*)\]; HOME stale: (\d+)') {
      if ($Matches[2].Trim()) { $gaps = @($Matches[2] -split ',\s*') }
      $script:WrapTailHomeStale = ([int]$Matches[3] -gt 0)
    }
  }
  $script:WrapTailGaps = $gaps

  # HOME's detect-time stamp, for the cascade check: an auto-applied entry dated newer
  # than this makes HOME stale the moment it lands.
  $homeFile = Join-Path $Root '_meta/HOME.md'
  if ((Test-Path $homeFile) -and ((Get-Content -Path $homeFile -Raw -Encoding UTF8) -match '(?m)^updated:\s*(\d{4}-\d{2}-\d{2})')) {
    $script:WrapTailHomeStamp = $Matches[1]
  }

  $findings = [System.Collections.ArrayList]::new()
  foreach ($g in $gaps) {
    # per-handoff gaps arrive as handoff BASENAMES (2026-07-03); commit-only dates arrive marked
    if ($g -like 'commit-only:*') {
      [void]$findings.Add(@{ change = 'regenerate-session-log'; target = '_meta/session-log.md'; fields = [ordered]@{}; summary = "gap $g"; skip = 'commit-only date - needs a human-drafted entry below the END marker'; needs_llm = $false })
      continue
    }
    $hBase = $g
    $d = $g.Substring(0, 10)
    # source THIS handoff exactly (active first, then archive) - no first-sorted pick
    $handoff = @(Get-ChildItem -Path (Join-Path $Root '_meta/handoffs') -Filter "$hBase.md" -File -ErrorAction SilentlyContinue)
    if ($handoff.Count -eq 0) {
      $handoff = @(Get-ChildItem -Path (Join-Path $Root '_archive/handoffs') -Filter "$hBase.md" -File -Recurse -ErrorAction SilentlyContinue)
    }
    if ($handoff.Count -eq 0) {
      [void]$findings.Add(@{ change = 'regenerate-session-log'; target = '_meta/session-log.md'; fields = [ordered]@{ handoff = $hBase }; summary = "gap $g"; skip = 'handoff file not found'; needs_llm = $false })
      continue
    }
    # Deterministic (system-o v0.4): the entry is DERIVED from the handoff by
    # build-session-log.ps1; one regenerate closes every handoff gap at once, so several
    # gaps collapse into one effective repair (the second run is a verified no-op).
    [void]$findings.Add(@{
      change      = 'regenerate-session-log'
      target      = '_meta/session-log.md'
      fields      = [ordered]@{ entry_date = $d; handoff = $hBase }
      slug        = $hBase
      needs_llm   = $false
      body        = "Deterministic repair (no LLM): run ``_meta/scripts/build-session-log.ps1`` to regenerate the SESSION-LOG generated region from handoffs; postcondition = ``[[$hBase]]`` present in ``_meta/session-log.md``. Flagged by the wrap-tail detector (detect-wrap-tail.ps1, per-handoff gap)."
      summary     = "gap $g"
    })
  }

  # HOME bump on detect-time staleness. Emitted LAST: its body reads "newest at apply
  # time", so session-log entries must be offered first (order-independence note).
  if ($script:WrapTailHomeStale) {
    [void]$findings.Add((New-HomeBumpFinding -Summary 'home-stale'))
  }

  return $findings.ToArray()   # cells emit items; the runner collects with @() - no comma-wrap
}

function Test-LoopDraft {   # required by the runner contract; this cell has no LLM findings
  param([hashtable]$Finding, [string]$Draft, [string]$Root)
  return @('wrap-tail-repair cell has no LLM-drafted findings (spec v0.4) - refusing draft')
}
function Get-LoopProposalBody {
  param([hashtable]$Finding, [string]$Draft)
  return $Draft   # the verified entry IS the proposal body (v1 behavior)
}

function Test-LoopStale {
  # Optional cell contract function (2026-08-07). A proposal served by a
  # non-auto_apply endpoint queues for the human walk and can sit for days; the gap it
  # describes may be closed by hand in the meantime. Applying it then writes a DUPLICATE
  # (2026-08-01a: queued 08-02, entry hand-written before the 08-07 walk, applied blind).
  # Re-check the invariant at apply time against the SAME signal detection uses - the
  # handoff wikilink (the detector's per-handoff check) - not the drafted subject text, which
  # differs from a hand-written entry's wording and so slid past the first-line guard.
  # Returns a reason string when the proposal is a no-op; $null when it still applies.
  param([string]$Change, [hashtable]$Fields, [string]$Body, [string]$Root)
  $sessionLog = Join-Path $Root '_meta/session-log.md'
  switch ($Change) {
    'regenerate-session-log' {
      if (-not (Test-Path $sessionLog)) { return $null }
      $logRaw = (Get-Content -Path $sessionLog -Raw -Encoding UTF8) -replace "`r`n","`n"
      $hBase = if ($Fields.ContainsKey('handoff')) { [string]$Fields['handoff'] } else { '' }
      if ($hBase -and ($logRaw.Contains("[[$hBase]]") -or $logRaw.Contains("[[$hBase|"))) {
        return "session-log already links [[$hBase]] - gap closed since this proposal was generated"
      }
      return $null
    }
    'bump-home-updated' {
      # Self-correcting by construction (recomputes newest at apply time), so it is only
      # stale when HOME's stamp already equals that value - then the write is a no-op.
      if (-not (Test-Path $sessionLog)) { return $null }
      $newest = $null
      foreach ($line in (Get-Content -Path $sessionLog -Encoding UTF8)) {
        if ($line -match '^## (\d{4}-\d{2}-\d{2})') { $newest = $Matches[1]; break }
      }
      $homeFile = Join-Path $Root '_meta/HOME.md'
      if ($newest -and (Test-Path $homeFile) -and ((Get-Content -Path $homeFile -Raw -Encoding UTF8) -match '(?m)^updated:\s*(\d{4}-\d{2}-\d{2})')) {
        if ($Matches[1] -eq $newest) { return "HOME.md updated: is already $newest - nothing to bump" }
      }
      return $null
    }
    default { return $null }
  }
}

function Invoke-LoopRepair {
  param([string]$Change, [hashtable]$Fields, [string]$Body, [string]$Root)
  $sessionLog = Join-Path $Root '_meta/session-log.md'
  switch ($Change) {
    'regenerate-session-log' {
      $staleReason = Test-LoopStale -Change $Change -Fields $Fields -Body $Body -Root $Root
      if ($staleReason) { throw "Already applied: $staleReason" }
      $builder = Join-Path (Split-Path -Parent $PSScriptRoot) 'build-session-log.ps1'
      if (-not (Test-Path $builder)) { throw "build-session-log.ps1 not found at $builder" }
      $out = & $builder -Root $Root *>&1 | ForEach-Object { "$_" }
      $hBase = if ($Fields.ContainsKey('handoff')) { [string]$Fields['handoff'] } else { '' }
      $logRaw = (Get-Content -Path $sessionLog -Raw -Encoding UTF8) -replace "`r`n","`n"
      if ($hBase -and -not ($logRaw.Contains("[[$hBase]]") -or $logRaw.Contains("[[$hBase|"))) {
        throw "regenerated, but [[$hBase]] still absent - handoff predates the generated region's since= cut or failed to parse; needs a hand entry below the END marker. builder: $($out -join ' | ')"
      }
      return ("applied: session-log generated region rebuilt from handoffs ({0})" -f (($out | Where-Object { $_ -match '\[session-log\]' } | Select-Object -First 1) -replace '^\[session-log\]\s*',''))
    }    'bump-home-updated' {
      $newest = $null
      foreach ($line in (Get-Content -Path $sessionLog -Encoding UTF8)) {
        if ($line -match '^## (\d{4}-\d{2}-\d{2})') { $newest = $Matches[1]; break }   # newest-at-top
      }
      if (-not $newest) { throw "No dated entries found in session-log.md" }
      $homeFile = Join-Path $Root '_meta/HOME.md'
      $homeRaw = Get-Content -Path $homeFile -Raw -Encoding UTF8   # NOT $home: read-only automatic var in pwsh
      if ($homeRaw -notmatch '(?m)^updated:') { throw "HOME.md has no updated: field" }
      $homeRaw = $homeRaw -replace '(?m)^updated:.*$', "updated: $newest"
      [System.IO.File]::WriteAllText($homeFile, $homeRaw, [System.Text.UTF8Encoding]::new($false))
      return "applied: HOME.md updated: -> $newest"
    }
    default { throw "Unknown proposed_change for wrap-tail-repair cell: $Change" }
  }
}

function Get-LoopCascadeFindings {
  param([array]$Applied, [string]$Root)
  # HOME bump co-emit: an entry auto-applied THIS run and dated newer than HOME's
  # detect-time stamp has just made HOME stale (co-emit fix, 2026-07-01). Deliberately
  # NOT co-emitted for still-pending (propose-only) entries - the bump reads "newest at
  # apply time", so applying it before the pending entry would recreate the staleness.
  if ($script:WrapTailHomeStale) { return @() }   # already offered in the main pass
  $maxDate = $null
  foreach ($f in $Applied) {
    if ($f.change -ne 'regenerate-session-log') { continue }
    $d = [string]$f.fields['entry_date']
    if ($d -and ($null -eq $maxDate -or $d -gt $maxDate)) { $maxDate = $d }
  }
  if ($null -ne $maxDate -and $null -ne $script:WrapTailHomeStamp -and $maxDate -gt $script:WrapTailHomeStamp) {
    return (New-HomeBumpFinding -Summary ("home cascade: auto-applied entry {0} outdates HOME stamp {1}" -f $maxDate, $script:WrapTailHomeStamp))
  }
  return @()
}

function Get-LoopStatusFields {
  return ("gaps={0} home_stale={1}" -f $script:WrapTailGaps.Count, [int]$script:WrapTailHomeStale)
}
