#Requires -Version 7.0
<#
.SYNOPSIS
  Cell script for the kanban-handoff-reconciler loop (loop #2 — the first
  materially different loop at the runner seam; see run-loop.ps1 .DESCRIPTION
  for the cell contract). Dot-sourced by run-loop.ps1 and
  apply-loop-proposal.ps1.
.DESCRIPTION
  Invariant: handoff status and Kanban check-state agree for every citation
  link between them (spec section Loop manifest).

    adapter   parses detect-kanban-handoff-drift.ps1's contract lines
    verifier  'status-sync' — structural check on the drafted completion note
              (single line, length bounds, YAML-safe: no double quotes, no
              fences, no leading #, no ---)
    repairs   complete-ready-handoff — replace the `status: ready` line with a
              complete block (status/completed_date/completion_note/
              verification task: citations built from the ACTUAL matched
              cards, so the lint's cross-check passes by construction). The
              drafted note is the loop's one LLM box.
              check-cited-task — flip `- [ ]` to `- [x]` on the cited task
              line (deterministic; the lint's cited-but-open error promoted
              from flag to repair).
    cascade   none (a completed handoff creates no new finding in scope)

  Repairs work from the proposal file alone: the exact replacement block
  travels in the proposal body inside a ```yaml fence (auditable in the human
  walk, applied verbatim by Invoke-LoopRepair).

  `obsolete` is deliberately NOT a repair here — supersession is a judgment
  call; it belongs to judgment sweeps, never the mechanical loop.
#>

Set-StrictMode -Version Latest

$CellContract = @{
  verifier = 'status-sync'
  changes  = @('complete-ready-handoff', 'check-cited-task')
}

$script:ReconD1 = 0
$script:ReconD2 = 0

function Get-CitationFragment {
  # A citation fragment must substring-match its Kanban line (lint contract) and
  # survive YAML double-quoting and the lint's ' -- ' split. Prefer a cleaned
  # prefix of the card text; fall back to the handoff basename, which is in the
  # card by construction (that is how D1 found it).
  param([string]$CardText, [string]$Basename)
  $frag = $CardText
  foreach ($cut in @('"', ' -- ')) {
    $idx = $frag.IndexOf($cut)
    if ($idx -ge 0) { $frag = $frag.Substring(0, $idx) }
  }
  $frag = $frag.Trim()
  if ($frag.Length -gt 70) {
    $frag = $frag.Substring(0, 70)
    # don't end mid-escape-relevant char; trim trailing partial word
    $sp = $frag.LastIndexOf(' ')
    if ($sp -gt 40) { $frag = $frag.Substring(0, $sp) }
    $frag = $frag.Trim()
  }
  if ($frag.Length -lt 15) { return $Basename }
  return $frag
}

function Get-LoopFindings {
  param([string[]]$DetectOutput, [string]$Root)

  $d1 = [ordered]@{}   # basename -> list of @{Kanban; Text}
  $d2 = [System.Collections.ArrayList]::new()
  foreach ($l in $DetectOutput) {
    $line = $l -replace '^\[dry-run\] ', ''
    if ($line -match '^D1 ready-but-done: (\S+)$') {
      if (-not $d1.Contains($Matches[1])) { $d1[$Matches[1]] = [System.Collections.ArrayList]::new() }
      continue
    }
    if ($line -match '^D1-card: (\S+) :: (.+?) :: (.+)$') {
      $b = $Matches[1]
      if (-not $d1.Contains($b)) { $d1[$b] = [System.Collections.ArrayList]::new() }
      [void]$d1[$b].Add(@{ Kanban = $Matches[2].Trim(); Text = $Matches[3].Trim() })
      continue
    }
    if ($line -match '^D2 cited-but-open: (\S+) :: (.+?) :: (.+)$') {
      [void]$d2.Add(@{ Basename = $Matches[1]; Kanban = $Matches[2].Trim(); Fragment = $Matches[3].Trim() })
      continue
    }
  }
  $script:ReconD1 = $d1.Count
  $script:ReconD2 = $d2.Count

  $findings = [System.Collections.ArrayList]::new()
  $today = Get-Date -Format 'yyyy-MM-dd'

  foreach ($b in $d1.Keys) {
    $cards = @($d1[$b])
    $target = "_meta/handoffs/$b.md"
    $hPath = Join-Path $Root $target
    if (-not (Test-Path $hPath)) {
      [void]$findings.Add(@{ change = 'complete-ready-handoff'; target = $target; fields = [ordered]@{ handoff = $b }; summary = "D1 $b"; skip = 'handoff file not found'; needs_llm = $true })
      continue
    }
    $hContent = Get-Content -Path $hPath -Raw -Encoding UTF8
    # completed_date: newest ISO date mentioned in the matched card texts, else today
    $completed = $today
    $dates = @()
    foreach ($c in $cards) { foreach ($m in [regex]::Matches($c.Text, '\b(\d{4}-\d{2}-\d{2})\b')) { $dates += $m.Groups[1].Value } }
    if ($dates.Count -gt 0) { $completed = ($dates | Sort-Object)[-1] }
    $cardLines = @($cards | ForEach-Object { "- [{0}] {1}" -f 'x', $_.Text + " (in $($_.Kanban))" })
    [void]$findings.Add(@{
      change      = 'complete-ready-handoff'
      target      = $target
      fields      = [ordered]@{ handoff = $b; completed_date = $completed }
      slug        = $b
      needs_llm   = $true
      prompt_vars = @{ HANDOFF_BASENAME = $b; TODAY = $today; CARDS = ($cardLines -join "`n"); HANDOFF_CONTENT = $hContent }
      clip_var    = 'HANDOFF_CONTENT'
      summary     = "D1 $b"
      cards       = $cards   # carried for Get-LoopProposalBody (same-process only)
    })
  }

  foreach ($item in $d2) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hash = -join ($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($item.Fragment)) | ForEach-Object { $_.ToString('x2') })
    $md5.Dispose()
    [void]$findings.Add(@{
      change    = 'check-cited-task'
      target    = $item.Kanban
      fields    = [ordered]@{ handoff = $item.Basename; kanban = $item.Kanban; task_fragment = $item.Fragment }
      slug      = "$($item.Basename)-t$($hash.Substring(0,8))"
      needs_llm = $false
      body      = "Deterministic repair: in ``$($item.Kanban)``, flip ``- [ ]`` to ``- [x]`` on the single task line containing:`n`n    $($item.Fragment)`n`nThe task is cited as checked by the complete handoff [[$($item.Basename)]] (verification block task: citation). Refuses if the line is missing, already checked, or ambiguous."
      summary   = "D2 $($item.Basename) -> $($item.Kanban)"
    })
  }

  return $findings.ToArray()   # cells emit items; the runner collects with @() — no comma-wrap
}

function Test-LoopDraft {   # 'status-sync' verifier — the draft is ONE completion-note line
  param([hashtable]$Finding, [string]$Draft, [string]$Root)
  $reasons = [System.Collections.ArrayList]::new()
  $t = $Draft.Trim()
  if ($t -match '\r|\n') { [void]$reasons.Add('must be a single line') }
  if ($t.Length -lt 40 -or $t.Length -gt 500) { [void]$reasons.Add("length $($t.Length) outside 40..500") }
  if ($t.Contains('"')) { [void]$reasons.Add('contains a double quote (breaks YAML quoting)') }
  if ($t -match '```') { [void]$reasons.Add('contains a code fence') }
  if ($t.StartsWith('#')) { [void]$reasons.Add('starts with a heading marker') }
  if ($t.Contains('---')) { [void]$reasons.Add('contains --- (frontmatter delimiter)') }
  return $reasons   # emit items; the runner collects with @()
}

function Get-LoopProposalBody {
  param([hashtable]$Finding, [string]$Draft)
  $b = [string]$Finding.fields['handoff']
  $completed = [string]$Finding.fields['completed_date']
  $note = $Draft.Trim() + ' [kanban-handoff-reconciler]'
  $cards = @($Finding.cards)
  $ver = foreach ($c in $cards) {
    $frag = Get-CitationFragment -CardText $c.Text -Basename $b
    "  - task: `"$($c.Kanban) -- $frag -- checked $completed`""
  }
  $yaml = @(
    'status: complete'
    "completed_date: $completed"
    "completion_note: `"$note`""
    'verification:'
  ) + @($ver)
  return @(
    "Kanban -> handoff drift: all $($cards.Count) Kanban card(s) citing [[$b]] are checked, but the handoff still reads ``status: ready``."
    ''
    "Repair (replaces the ``status: ready`` line in ``$($Finding.target)``):"
    ''
    '```yaml'
  ) + $yaml + @('```') -join "`n"
}

function Invoke-LoopRepair {
  param([string]$Change, [hashtable]$Fields, [string]$Body, [string]$Root)
  switch ($Change) {
    'complete-ready-handoff' {
      $target = [string]$Fields['target']
      if (-not $target) { $target = "_meta/handoffs/$($Fields['handoff']).md" }
      $path = Join-Path $Root $target
      if (-not (Test-Path $path)) { throw "Target handoff not found: $path" }
      if ($Body -notmatch '(?s)```yaml\r?\n(.*?)\r?\n```') { throw 'Proposal body carries no ```yaml repair block — nothing to apply.' }
      $block = $Matches[1] -replace "`r`n","`n"
      $raw = (Get-Content -Path $path -Raw -Encoding UTF8) -replace "`r`n","`n"
      if ($raw -match '(?m)^status:\s*complete\s*$') { throw "Already applied: $target reads status: complete" }
      $rawLines = $raw -split "`n"
      $idx = @(0..($rawLines.Count - 1) | Where-Object { $rawLines[$_] -match '^status: ready\s*$' })
      if ($idx.Count -ne 1) { throw "Expected exactly one 'status: ready' line in ${target}, found $($idx.Count) — refusing" }
      $i = $idx[0]
      $head = if ($i -gt 0) { @($rawLines[0..($i - 1)]) } else { @() }
      $tail = if ($i -lt ($rawLines.Count - 1)) { @($rawLines[($i + 1)..($rawLines.Count - 1)]) } else { @() }
      $new = $head + @($block -split "`n") + $tail
      [System.IO.File]::WriteAllText($path, (($new -join "`n").TrimEnd("`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
      return "applied: $target flipped to complete (completed_date $($Fields['completed_date']))"
    }
    'check-cited-task' {
      $kanbanRel = [string]$Fields['kanban']
      if (-not $kanbanRel) { $kanbanRel = [string]$Fields['target'] }
      $frag = [string]$Fields['task_fragment']
      if (-not $frag) { throw 'Proposal has no task_fragment field.' }
      $path = Join-Path $Root $kanbanRel
      if (-not (Test-Path $path)) { throw "Target Kanban not found: $path" }
      $lines = @(Get-Content -Path $path -Encoding UTF8)
      $esc = [regex]::Escape($frag)
      $open = @(); $checked = 0
      for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('^\s*-\s*\[ \]\s*.*' + $esc)) { $open += $i }
        elseif ($lines[$i] -match ('^\s*-\s*\[x\]\s*.*' + $esc)) { $checked++ }
      }
      if ($open.Count -eq 0 -and $checked -gt 0) { throw "Already applied: cited task is checked in $kanbanRel" }
      if ($open.Count -eq 0) { throw "No task line matching the cited fragment in $kanbanRel" }
      if ($open.Count -gt 1) { throw "Ambiguous: $($open.Count) open task lines match the fragment in $kanbanRel — refusing" }
      $i = $open[0]
      $lines[$i] = $lines[$i] -replace '\[ \]', '[x]'
      [System.IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
      return "applied: checked cited task in $kanbanRel (line $($i + 1))"
    }
    default { throw "Unknown proposed_change for kanban-handoff-reconciler cell: $Change" }
  }
}

function Get-LoopCascadeFindings {
  param([array]$Applied, [string]$Root)
  return @()   # a completed handoff creates no new finding inside this loop's scope
}

function Get-LoopStatusFields {
  return ("d1_ready_done={0} d2_cited_open={1}" -f $script:ReconD1, $script:ReconD2)
}
