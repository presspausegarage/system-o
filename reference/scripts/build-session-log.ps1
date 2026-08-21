<#
.SYNOPSIS
  Regenerate the GENERATED region of _meta/session-log.md from handoffs (spec v0.4).
.DESCRIPTION
  The session log's generated region is a derived index of handoffs: one entry per handoff
  dated on/after the region's `since=` cut date, newest first. Nothing is drafted - title,
  link, summary and time are read from the handoff itself. Human-authored history below the
  END marker is never touched (SPEC §Vault mutation safety, exception 2: declared generated
  region with its canonical source elsewhere, generator validates its postcondition).

  Reads BOTH _meta/handoffs/ and _archive/handoffs/**  - the 02:50 sweep archives complete
  handoffs after 7 days and the index must not forget them.

  Region markers (the START marker carries the cut date; it is the only config):
    <!-- SESSION-LOG:START since=YYYY-MM-DD -->
    ...generated entries...
    <!-- SESSION-LOG:END -->

  Fails closed when the markers are absent unless -Init is given, in which case the region
  is inserted above the first existing `## ` entry (once).

  Entry shape (parser-compatible with build-weekly-review.ps1 / check-session-log.ps1):
    ## YYYY-MM-DD <em dash> <handoff title>
    [[<handoff basename>]]
    <completion_note if complete, else first body paragraph, trimmed to ~400 chars>
    - time: N min <em dash> slug, slug
.PARAMETER Root       Vault root (default C:\dev).
.PARAMETER Init       Insert the markers if absent; requires -Since.
.PARAMETER Since      Cut date for -Init (YYYY-MM-DD). Ignored when markers exist (marker wins).
.PARAMETER OutFile    Write the result here instead of the live session-log (tracer / scratch use).
.PARAMETER DryRun     Compute, report, write nothing.
.EXAMPLE
  build-session-log.ps1 -DryRun
  build-session-log.ps1 -Init -Since 2026-08-21
  build-session-log.ps1 -Init -Since 2026-08-09 -OutFile ./session-log.tracer.md   # tracer / scratch run
#>
[CmdletBinding()]
param(
  [string]$Root = 'C:\dev',
  [switch]$Init,
  [string]$Since,
  [string]$OutFile,
  [switch]$DryRun,
  [int]$SummaryChars = 400
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Entry headings use an em dash as the subject separator (the shape every session-log parser
# in this reference expects); built from its codepoint so no literal reaches source.
$emDash = [string][char]0x2014

$logPath = Join-Path $Root '_meta/session-log.md'
if (-not (Test-Path $logPath)) { throw "session-log not found: $logPath" }
$raw = [System.IO.File]::ReadAllText($logPath)
$eol = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
$text = $raw -replace "`r`n", "`n"

$startRx = '(?m)^<!-- SESSION-LOG:START since=(\d{4}-\d{2}-\d{2}) -->$'
$endRx   = '(?m)^<!-- SESSION-LOG:END -->$'
$hasStart = [regex]::IsMatch($text, $startRx)
$hasEnd   = [regex]::IsMatch($text, $endRx)

if ($hasStart -xor $hasEnd) { throw 'session-log has one marker but not the other - refusing to guess. Fix the markers by hand.' }
if (-not $hasStart) {
  if (-not $Init) { throw 'No SESSION-LOG markers in session-log.md. Run with -Init -Since YYYY-MM-DD to declare the generated region (once).' }
  if (-not $Since -or $Since -notmatch '^\d{4}-\d{2}-\d{2}$') { throw '-Init requires -Since YYYY-MM-DD' }
  # insert above the first existing entry; if no entries, append at end
  $lines = $text -split "`n"
  $at = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^## \d{4}-\d{2}-\d{2}') { $at = $i; break } }
  $block = @("<!-- SESSION-LOG:START since=$Since -->", '<!-- SESSION-LOG:END -->', '')
  if ($at -lt 0) { $lines = $lines + @('') + $block } else {
    $head = if ($at -gt 0) { @($lines[0..($at-1)]) } else { @() }
    $tail = @($lines[$at..($lines.Count-1)])
    $lines = $head + $block + $tail
  }
  $text = ($lines -join "`n")
  Write-Host "[init] markers inserted (since=$Since)"
}

$m = [regex]::Match($text, $startRx)
$cut = $m.Groups[1].Value
$cutDate = [datetime]::ParseExact($cut, 'yyyy-MM-dd', $null)

# --- collect handoffs (live + archived), dedupe by basename -------------------------------
$dirs = @((Join-Path $Root '_meta/handoffs'), (Join-Path $Root '_archive/handoffs'))
$files = @{}
foreach ($d in $dirs) {
  if (-not (Test-Path $d)) { continue }
  foreach ($f in (Get-ChildItem -Path $d -Recurse -File -Filter '*.md')) {
    if ($f.BaseName -notmatch '^(\d{4}-\d{2}-\d{2})([a-z]?)-') { continue }
    if (-not $files.ContainsKey($f.BaseName)) { $files[$f.BaseName] = $f }
  }
}

function Read-Frontmatter {
  param([string[]]$Lines)
  $fm = @{ time_by_project = @{} }
  if ($Lines.Count -eq 0 -or $Lines[0] -ne '---') { return @{ fm = $fm; bodyStart = 0 } }
  $i = 1; $inTime = $false
  while ($i -lt $Lines.Count -and $Lines[$i] -ne '---') {
    $l = $Lines[$i]
    if ($inTime) {
      if ($l -match '^\s+([A-Za-z0-9._-]+):\s*(-?\d+)') { $fm.time_by_project[$Matches[1]] = [int]$Matches[2]; $i++; continue }
      elseif ($l -match '^\s+\S') { $i++; continue } else { $inTime = $false }
    }
    if ($l -match '^time_by_project:\s*$') { $inTime = $true; $i++; continue }
    if ($l -match '^([a-z_]+):\s*(.*)$') {
      $k = $Matches[1]; $v = $Matches[2].Trim()
      if ($v -match '^"(.*)"$') { $v = $Matches[1] -replace '\\"', '"' }
      elseif ($v -match "^'(.*)'$") { $v = $Matches[1] }
      if ($k -ne 'time_by_project') { $fm[$k] = $v }
    }
    $i++
  }
  return @{ fm = $fm; bodyStart = ($i + 1) }
}

function Trim-Summary {
  param([string]$s, [int]$max)
  $s = ($s -replace '\s+', ' ').Trim()
  if ($s.Length -le $max) { return $s }
  $cutAt = $s.LastIndexOf(' ', $max)
  if ($cutAt -lt [int]($max * 0.6)) { $cutAt = $max }
  return $s.Substring(0, $cutAt).TrimEnd(' ,;:-') + ' …'
}

$entries = New-Object System.Collections.Generic.List[object]
foreach ($kv in $files.GetEnumerator()) {
  $f = $kv.Value
  $null = $f.BaseName -match '^(\d{4}-\d{2}-\d{2})([a-z]?)-'
  $fdate = $Matches[1]; $letter = $Matches[2]
  $dd = [datetime]::ParseExact($fdate, 'yyyy-MM-dd', $null)
  if ($dd -lt $cutDate) { continue }
  $lines = ([System.IO.File]::ReadAllText($f.FullName) -replace "`r`n", "`n") -split "`n"
  $parsed = Read-Frontmatter -Lines $lines
  $fm = $parsed.fm
  $date = if ($fm.ContainsKey('date') -and $fm.date -match '^\d{4}-\d{2}-\d{2}$') { $fm.date } else { $fdate }
  # title = H1 minus the "Handoff <date><letter> <sep> " prefix; first paragraph after H1 = fallback summary
  $title = $null; $para = $null; $h1At = -1
  for ($i = $parsed.bodyStart; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^# (.+)$') { $title = $Matches[1].Trim(); $h1At = $i; break }
  }
  if (-not $title) { $title = ($f.BaseName -replace '^\d{4}-\d{2}-\d{2}[a-z]?-', '') }
  $title = $title -replace '^Handoff\s+\d{4}-\d{2}-\d{2}[a-z]?\s*[-\u2014\u2013:]+\s*', ''
  if ($h1At -ge 0) {
    $buf = New-Object System.Collections.Generic.List[string]
    for ($i = $h1At + 1; $i -lt $lines.Count; $i++) {
      $l = $lines[$i]
      if ($buf.Count -eq 0 -and $l.Trim() -eq '') { continue }
      if ($l.Trim() -eq '' -or $l -match '^#{1,6} ') { break }
      $buf.Add($l.Trim())
    }
    if ($buf.Count -gt 0) { $para = ($buf -join ' ') }
  }
  $summary = if ($fm.ContainsKey('completion_note') -and $fm.completion_note) { $fm.completion_note } elseif ($para) { $para } else { '_(no summary in handoff)_' }
  $summary = Trim-Summary -s $summary -max $SummaryChars
  $mins = 0; $slugs = @()
  foreach ($t in ($fm.time_by_project.GetEnumerator() | Sort-Object Name)) { $mins += [int]$t.Value; $slugs += $t.Name }
  $timeLine = if ($slugs.Count -gt 0) { "- time: $mins min $emDash $($slugs -join ', ')" } else { '- time: n/a' }
  $status = if ($fm.ContainsKey('status')) { $fm.status } else { '' }
  $entries.Add([pscustomobject]@{ Date = $date; Letter = $letter; Name = $f.BaseName; Title = $title; Summary = $summary; Time = $timeLine; Status = $status })
}

$sorted = $entries | Sort-Object @{e='Date';desc=$true}, @{e='Letter';desc=$true}, @{e='Name';desc=$true}
$gen = New-Object System.Collections.Generic.List[string]
$gen.Add("<!-- SESSION-LOG:START since=$cut -->")
$gen.Add("_Generated from handoffs dated on/after $cut by ``_meta/scripts/build-session-log.ps1`` $emDash do not hand-edit between the markers; hand-authored entries go below the END marker._")
$gen.Add('')
foreach ($e in $sorted) {
  $gen.Add("## $($e.Date) $emDash $($e.Title)")
  $gen.Add("[[$($e.Name)]]")
  $gen.Add($e.Summary)
  $gen.Add($e.Time)
  $gen.Add('')
}
$gen.Add('<!-- SESSION-LOG:END -->')
$region = ($gen -join "`n")

# replace the region (START..END inclusive) in one scoped edit
$regionRx = '(?s)<!-- SESSION-LOG:START since=\d{4}-\d{2}-\d{2} -->.*?<!-- SESSION-LOG:END -->'
$current = [regex]::Match($text, $regionRx).Value
$changed = ($current -ne $region)
$newText = [regex]::Replace($text, $regionRx, { param($mm) $region }, 1)

# postcondition: the written text must contain exactly one region equal to $region
$check = [regex]::Matches($newText, $regionRx)
if ($check.Count -ne 1 -or $check[0].Value -ne $region) { throw 'postcondition failed: generated region not exactly once in output' }

$target = if ($OutFile) { $OutFile } else { $logPath }
$out = ($newText -replace "`n", $eol)
Write-Host ("[session-log] since={0} handoffs={1} entries={2} changed={3} target={4}" -f $cut, $files.Count, $sorted.Count, $changed, $target)
if ($DryRun) { Write-Host '[dry-run] nothing written'; exit 0 }
if ($changed -or $OutFile -or $Init) {
  [System.IO.File]::WriteAllText($target, $out, [System.Text.UTF8Encoding]::new($false))
  Write-Host "[session-log] written"
} else { Write-Host '[session-log] unchanged' }