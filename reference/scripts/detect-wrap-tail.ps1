#Requires -Version 7.0
<#
.SYNOPSIS
  Reference detector for the wrap-tail-repair loop cell (spec §Loop manifest).
.DESCRIPTION
  Deterministic detect step: finds handoffs in the window not linked by any
  `_meta/session-log.md` entry, plus commit-only dates with no handoff and no
  entry, plus a stale `_meta/HOME.md` stamp. Emits the exact single-line
  contract the loop runner parses:

    [dry-run] would flag in <handoff.md>: N session-log gap(s) [<items>]; HOME stale: N

  Per-HANDOFF detection (not per-date): a gap is a handoff whose basename is
  not `[[wikilinked]]` by any session-log entry. Per-date detection is blind
  to a second same-date session once any sibling session logs — this is the
  minimum viable fix, found in production use of the reference implementation.

  This is the SESSION-LOG/HOME slice only — the portable core the loop cell
  needs. It intentionally omits vault-hygiene heartbeat checks (registry
  drift, launchpad integrity, frontmatter linting, PARA structure, etc.):
  those are operator-specific conventions layered on top of the reference
  vault, not part of the loop cell's detector contract.

  Self-clearing UX: when gaps exist, writes (or clears) a managed comment
  block in the newest handoff, so resuming a session surfaces the repair
  work. This mirrors what the loop runner already treats as inert: it always
  invokes -DryRun and never sees this side effect.

  Repo scan for commit-only dates is generic: any top-level directory
  containing a `.git` folder, one level deep. No category manifest required.
.PARAMETER Root
  Vault root.
.PARAMETER WindowDays
  How many days back to reconcile. Default 10.
.PARAMETER DryRun
  Report findings without writing to any handoff (required by the loop runner).
.EXAMPLE
  detect-wrap-tail.ps1 -Root . -DryRun
#>
[CmdletBinding()]
param(
  [string]$Root = '.',
  [int]$WindowDays = 10,
  [string]$Date = (Get-Date -Format 'yyyy-MM-dd'),
  [string]$IgnoreCommitPattern = '^chore\((audit|data)\)',
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
function Say { param([string]$m) Write-Host $m }

function Get-UpdatedDate {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $null }
  $inFm = $false
  foreach ($line in (Get-Content -Path $Path -Encoding UTF8)) {
    if ($line.Trim() -eq '---') { if ($inFm) { break } else { $inFm = $true; continue } }
    if ($inFm -and $line -match '^\s*updated:\s*(\d{4}-\d{2}-\d{2})') { return $Matches[1] }
  }
  return $null
}

$handoffsDir = Join-Path $Root '_meta/handoffs'
$archiveDir  = Join-Path $Root '_archive/handoffs'
$logFile     = Join-Path $Root '_meta/session-log.md'

$today = [datetime]::ParseExact($Date, 'yyyy-MM-dd', $null)
$windowStart = $today.AddDays(-$WindowDays)
Say ("starting (window {0}..{1}, dry-run={2})" -f $windowStart.ToString('yyyy-MM-dd'), $Date, $DryRun.IsPresent)

# 1) raw session-log text (for wikilink checks)
$logRaw = ''
if (Test-Path $logFile) { $logRaw = Get-Content -Path $logFile -Raw -Encoding UTF8 }
else { Say "WARN session-log.md missing at $logFile" }

# 2) handoff files in window
$handoffFiles = @()
if (Test-Path $handoffsDir) { $handoffFiles += Get-ChildItem -Path $handoffsDir -Filter '*.md' -File }
if (Test-Path $archiveDir)  { $handoffFiles += Get-ChildItem -Path $archiveDir  -Filter '*.md' -File -Recurse }
$handoffByDate = @{}
foreach ($h in $handoffFiles) {
  if ($h.BaseName -match '^(\d{4}-\d{2}-\d{2})') {
    $d = $Matches[1]
    if (-not $handoffByDate.ContainsKey($d)) { $handoffByDate[$d] = $h.BaseName }
  }
}

# 3) commit dates — generic scan: any top-level dir with a .git folder
$commitByDate = @{}
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
  $since = $windowStart.ToString('yyyy-MM-dd')
  foreach ($repo in (Get-ChildItem -Path $Root -Directory | Where-Object { Test-Path (Join-Path $_.FullName '.git') })) {
    try {
      $out = & $gitCmd.Source -C $repo.FullName log "--since=$since" "--pretty=format:%ad%x09%s" '--date=format:%Y-%m-%d' 2>$null
      foreach ($row in $out) {
        if (-not $row) { continue }
        $parts = $row -split "`t", 2
        $d = $parts[0]; $subj = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        if ($subj -match $IgnoreCommitPattern) { continue }
        if ($d -and -not $commitByDate.ContainsKey($d)) { $commitByDate[$d] = $repo.Name }
      }
    } catch { }
  }
} else {
  Say "note: git not found - commit scan skipped (handoff-only detection)"
}

# 4) gaps, PER HANDOFF: an in-window handoff (not today's — may be unwrapped) whose
#    basename is not wikilinked by any session-log entry. Commit-only dates (no
#    handoff exists) keep a per-date check, marked for a human-drafted entry.
$gaps = New-Object System.Collections.Generic.List[string]
foreach ($h in ($handoffFiles | Sort-Object BaseName)) {
  if ($h.BaseName -notmatch '^(\d{4}-\d{2}-\d{2})') { continue }
  $d = $Matches[1]
  $dd = $null
  try { $dd = [datetime]::ParseExact($d, 'yyyy-MM-dd', $null) } catch { continue }
  if ($dd -lt $windowStart) { continue }
  if ($d -eq $Date) { continue }
  if ($logRaw.Contains("[[$($h.BaseName)]]") -or $logRaw.Contains("[[$($h.BaseName)|")) { continue }
  $gaps.Add($h.BaseName)
}
foreach ($d in ($commitByDate.Keys | Sort-Object)) {
  $dd = $null
  try { $dd = [datetime]::ParseExact($d, 'yyyy-MM-dd', $null) } catch { continue }
  if ($dd -lt $windowStart) { continue }
  if ($d -eq $Date) { continue }
  if ($handoffByDate.ContainsKey($d)) { continue }
  if ($logRaw -match ('(?m)^##\s+' + [regex]::Escape($d) + '\b')) { continue }
  $gaps.Add("commit-only:$d")
}

# 5) stale HOME
$staleHome = New-Object System.Collections.Generic.List[string]
$logged = @{}
foreach ($line in ($logRaw -split "`r?`n")) {
  if ($line -match '^##\s+(\d{4}-\d{2}-\d{2})\b') { $logged[$Matches[1]] = $true }
}
$newestLogged = ($logged.Keys | Sort-Object -Descending | Select-Object -First 1)
$homeUpdated = Get-UpdatedDate (Join-Path $Root '_meta/HOME.md')
if ($newestLogged -and (-not $homeUpdated -or $homeUpdated -lt $newestLogged)) {
  $staleHome.Add("**_meta/HOME.md** (updated $homeUpdated; newest session-log entry $newestLogged)")
}

# locate the newest active handoff (self-clearing annotation target)
$active = @()
if (Test-Path $handoffsDir) { $active = @(Get-ChildItem -Path $handoffsDir -Filter '*.md' -File | Sort-Object Name) }
if ($active.Count -eq 0) {
  Say "WARN no active handoff to annotate; gaps=$($gaps.Count) staleHome=$($staleHome.Count)"
  exit 0
}
$newest = $active[-1]

$START = '<!-- SESSION-LOG-CHECK:START -->'
$END   = '<!-- SESSION-LOG-CHECK:END -->'
$original = Get-Content -Path $newest.FullName -Raw -Encoding UTF8
$pattern  = [regex]::Escape($START) + '.*?' + [regex]::Escape($END)
$stripped = [regex]::Replace($original, $pattern, '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$stripped = $stripped.TrimEnd() + "`n"

if ($gaps.Count -eq 0 -and $staleHome.Count -eq 0) {
  Say "clean: no session-log gaps or stale HOME in window"
  if (-not $DryRun -and $stripped -ne $original) {
    Set-Content -Path $newest.FullName -Value $stripped -Encoding UTF8 -NoNewline
    Say "cleared a stale check block from $($newest.Name)"
  }
  exit 0
}

if ($DryRun) {
  Say "[dry-run] would flag in $($newest.Name): $($gaps.Count) session-log gap(s) [$($gaps -join ', ')]; HOME stale: $($staleHome.Count)"
  foreach ($x in $staleHome) { Say ("    " + ($x -replace '\*\*','')) }
  exit 0
}

$nl = "`n"
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append($nl + $START + $nl)
[void]$sb.Append("## Wrap-checklist follow-ups (auto-flagged $Date)" + $nl + $nl)
if ($gaps.Count -gt 0) {
  [void]$sb.Append("**Missing session-log entries** — each item below has no session-log entry linking it (commit-only dates have no entry at all). Prepend one per item, sourced from its handoff:" + $nl + $nl)
  foreach ($g in ($gaps | Sort-Object -Descending)) {
    if ($g -like 'commit-only:*') {
      $d = $g.Substring(12)
      [void]$sb.Append("- **$d** - commits in $($commitByDate[$d]); no handoff exists - needs a human-drafted entry" + $nl)
    } else {
      [void]$sb.Append("- **[[$g]]** ($($g.Substring(0,10))) - handoff not linked by any session-log entry" + $nl)
    }
  }
  [void]$sb.Append($nl)
}
if ($staleHome.Count -gt 0) {
  [void]$sb.Append("**HOME not bumped** - update _meta/HOME.md updated: to match the latest logged session:" + $nl + $nl)
  foreach ($x in $staleHome) { [void]$sb.Append("- $x" + $nl) }
  [void]$sb.Append($nl)
}
[void]$sb.Append("_Self-clears on the next run once addressed. Auto-generated by detect-wrap-tail.ps1; window = last $WindowDays days._" + $nl)
[void]$sb.Append($END + $nl)

$final = $stripped.TrimEnd() + $nl + $sb.ToString()
Set-Content -Path $newest.FullName -Value $final -Encoding UTF8 -NoNewline
Say "flagged in $($newest.Name): $($gaps.Count) session-log gap(s); HOME stale: $($staleHome.Count)"
