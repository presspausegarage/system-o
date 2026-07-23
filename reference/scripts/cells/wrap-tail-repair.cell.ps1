#Requires -Version 7.0
<#
.SYNOPSIS
  Cell script for the wrap-tail-repair loop (see run-loop.ps1 .DESCRIPTION for
  the cell contract). Dot-sourced by run-loop.ps1 and apply-loop-proposal.ps1.
.DESCRIPTION
  Loop-specific pieces extracted from the v1 monolithic runner/applier
  (2026-07-22, system-o v0.3.0 seam refactor — behavior-preserving port):
    adapter   parses the wrap-tail detector's dry-run contract line (detect-wrap-tail.ps1 in this reference)
    verifier  'structural' — session-log entry shape (format, date, handoff
              wikilink, single header, bullet tail, no fence)
    repairs   prepend-session-log-entry (LLM-drafted, dupe-guarded insert)
              bump-home-updated (deterministic, newest-entry-at-apply-time)
    cascade   HOME bump co-emit when an auto-applied entry outdates HOME's
              stamp (synthetic battery S1/S2 finding, 2026-07-01)
#>

Set-StrictMode -Version Latest

$CellContract = @{
  verifier = 'structural'
  changes  = @('prepend-session-log-entry', 'bump-home-updated')
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
    body      = "Deterministic repair (no LLM): set ``updated:`` in ``_meta/HOME.md`` frontmatter to the newest ``## YYYY-MM-DD`` date in ``_meta/session-log.md`` **at apply time** (order-independent if session-log entries are applied first). Flagged by the wrap-tail detector."
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
      [void]$findings.Add(@{ change = 'prepend-session-log-entry'; target = '_meta/session-log.md'; fields = [ordered]@{}; summary = "gap $g"; skip = 'commit-only date — needs a human-drafted entry'; needs_llm = $true })
      continue
    }
    $hBase = $g
    $d = $g.Substring(0, 10)
    # source THIS handoff exactly (active first, then archive) — no first-sorted pick
    $handoff = @(Get-ChildItem -Path (Join-Path $Root '_meta/handoffs') -Filter "$hBase.md" -File -ErrorAction SilentlyContinue)
    if ($handoff.Count -eq 0) {
      $handoff = @(Get-ChildItem -Path (Join-Path $Root '_archive/handoffs') -Filter "$hBase.md" -File -Recurse -ErrorAction SilentlyContinue)
    }
    if ($handoff.Count -eq 0) {
      [void]$findings.Add(@{ change = 'prepend-session-log-entry'; target = '_meta/session-log.md'; fields = [ordered]@{ handoff = $hBase }; summary = "gap $g"; skip = 'handoff file not found'; needs_llm = $true })
      continue
    }
    $hContent = Get-Content -Path $handoff[0].FullName -Raw -Encoding UTF8
    [void]$findings.Add(@{
      change      = 'prepend-session-log-entry'
      target      = '_meta/session-log.md'
      fields      = [ordered]@{ entry_date = $d; handoff = $hBase }
      slug        = $hBase
      needs_llm   = $true
      prompt_vars = @{ DATE = $d; HANDOFF_BASENAME = $hBase; HANDOFF_CONTENT = $hContent }
      clip_var    = 'HANDOFF_CONTENT'
      summary     = "gap $g"
    })
  }

  # HOME bump on detect-time staleness. Emitted LAST: its body reads "newest at apply
  # time", so session-log entries must be offered first (order-independence note).
  if ($script:WrapTailHomeStale) {
    [void]$findings.Add((New-HomeBumpFinding -Summary 'home-stale'))
  }

  return $findings.ToArray()   # cells emit items; the runner collects with @() — no comma-wrap
}

function Test-LoopDraft {   # 'structural' verifier — returns failure reasons (empty = pass)
  param([hashtable]$Finding, [string]$Draft, [string]$Root)
  $Date = [string]$Finding.fields['entry_date']
  $HandoffBase = [string]$Finding.fields['handoff']
  $reasons = [System.Collections.ArrayList]::new()
  $lines = @($Draft -split "`n")
  if ($lines.Count -lt 2 -or $lines.Count -gt 40) { [void]$reasons.Add("line count $($lines.Count) outside 2..40") }
  $em = [string][char]0x2014
  if ($lines[0] -notmatch ('^## ' + [regex]::Escape($Date) + ' ' + [regex]::Escape($em) + ' .+')) {
    [void]$reasons.Add('first line is not "## <date> <em-dash> <subject>"')
  }
  if (@($lines | Where-Object { $_ -match '^## ' }).Count -ne 1) { [void]$reasons.Add('must contain exactly one "## " header') }
  if ($HandoffBase -and $Draft -notmatch [regex]::Escape("[[$HandoffBase]]")) { [void]$reasons.Add("missing [[$HandoffBase]] wikilink") }
  if ($Draft -notmatch '(?m)^- ') { [void]$reasons.Add('missing trailing bullet line(s)') }
  if ($Draft -notmatch 'Time') { [void]$reasons.Add('missing time-spent mention') }
  if ($Draft -match '```') { [void]$reasons.Add('contains a code fence') }
  return $reasons   # emit items; the runner collects with @()
}

function Get-LoopProposalBody {
  param([hashtable]$Finding, [string]$Draft)
  return $Draft   # the verified entry IS the proposal body (v1 behavior)
}

function Invoke-LoopRepair {
  param([string]$Change, [hashtable]$Fields, [string]$Body, [string]$Root)
  $sessionLog = Join-Path $Root '_meta/session-log.md'
  switch ($Change) {
    'prepend-session-log-entry' {
      $logRaw = (Get-Content -Path $sessionLog -Raw -Encoding UTF8) -replace "`r`n","`n"
      $entryFirstLine = ($Body -split "`n")[0]
      if ($logRaw.Contains($entryFirstLine)) { throw "Already applied: session-log contains '$entryFirstLine'" }
      $lines = $logRaw -split "`n"
      # newest-at-top: insert above the first entry OLDER than this one (below any
      # same-date entries); falls back to top-of-entries / end-of-file.
      $entryDate = [string]$Fields['entry_date']
      $insertAt = -1; $firstEntry = -1
      for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^## (\d{4}-\d{2}-\d{2})') {
          if ($firstEntry -lt 0) { $firstEntry = $i }
          if ($Matches[1] -lt $entryDate) { $insertAt = $i; break }
        }
      }
      if ($insertAt -lt 0) { $insertAt = if ($firstEntry -ge 0 -and -not $entryDate) { $firstEntry } else { $lines.Count } }
      # bounds-safe slicing: insertAt may be 0 (top) or $lines.Count (append) — a raw
      # range would wrap/overrun under StrictMode (found by rehearsal 2026-07-03)
      $head = if ($insertAt -gt 0) { @($lines[0..($insertAt-1)]) } else { @() }
      $tail = if ($insertAt -lt $lines.Count) { @($lines[$insertAt..($lines.Count-1)]) } else { @() }
      $new = $head + @(($Body -replace "`r`n","`n") -split "`n") + @('') + $tail
      [System.IO.File]::WriteAllText($sessionLog, (($new -join "`n").TrimEnd("`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
      return "applied: entry for $entryDate prepended to _meta/session-log.md"
    }
    'bump-home-updated' {
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
  # NOT co-emitted for still-pending (propose-only) entries — the bump reads "newest at
  # apply time", so applying it before the pending entry would recreate the staleness.
  if ($script:WrapTailHomeStale) { return @() }   # already offered in the main pass
  $maxDate = $null
  foreach ($f in $Applied) {
    if ($f.change -ne 'prepend-session-log-entry') { continue }
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
