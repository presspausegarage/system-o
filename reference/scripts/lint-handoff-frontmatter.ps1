#Requires -Version 7.0
<#
.SYNOPSIS
  Validate handoff frontmatter against this reference's handoff schema.
.DESCRIPTION
  Required: type=handoff, date, sprint, status (ready|complete|obsolete),
  tags, time_by_project (may be {}). When status=complete or status=obsolete:
  also completed_date (and, for complete, a verification block or
  completion_note). time_by_project keys must be valid registry slugs or the
  literal `workspace`.

  When a verification entry is `task: "<path> -- <text> -- checked <date>"`,
  the linter opens the referenced Kanban file and checks the matching task
  line is in [x] state. Catches the citation-without-verification miss.

  -HandoffsDir/-RegistryDir default relative to -Root (vault root, matching
  every other reference script) but can be pointed at an arbitrary directory
  directly -- e.g. to lint an already-archived batch instead of the active
  set.
.PARAMETER Root
  Vault root. Used only to derive the two defaults below.
.PARAMETER HandoffsDir
  Directory of handoff files to lint. Default: <Root>/_meta/handoffs.
.PARAMETER RegistryDir
  Directory of registry cards, for time_by_project slug validation. Default:
  <Root>/_meta/registry.
.EXAMPLE
  lint-handoff-frontmatter.ps1 -Root .
  lint-handoff-frontmatter.ps1 -Root . -HandoffsDir _archive/handoffs/2026-Q2
#>
[CmdletBinding()]
param(
  [string]$Root         = '.',
  [string]$HandoffsDir  = '',
  [string]$RegistryDir  = ''
)

$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path $Root).Path
if (-not $HandoffsDir) { $HandoffsDir = Join-Path $Root '_meta/handoffs' }
if (-not $RegistryDir) { $RegistryDir = Join-Path $Root '_meta/registry' }

# --- Build set of valid project slugs from registry + literal workspace ---
$validSlugs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
[void]$validSlugs.Add('workspace')
Get-ChildItem $RegistryDir -Filter '*.md' -File -ErrorAction SilentlyContinue | ForEach-Object {
  $raw = Get-Content $_.FullName -Raw -Encoding UTF8
  if ($raw -match '(?m)^slug:\s*(\S+)') {
    [void]$validSlugs.Add($Matches[1].Trim('"',"'"))
  }
}

# --- Walk handoffs ---
$files = Get-ChildItem $HandoffsDir -Filter '*.md' -File | Sort-Object Name
$issuesByFile = [ordered]@{}

foreach ($f in $files) {
  $rel    = $f.Name
  $raw    = Get-Content $f.FullName -Raw -Encoding UTF8
  $m      = [regex]::Match($raw, '(?s)\A---\s*\r?\n(.*?)\r?\n---\s*\r?\n')
  $issues = @()

  if (-not $m.Success) {
    $issuesByFile[$rel] = @('no frontmatter block')
    continue
  }
  $fm = $m.Groups[1].Value

  # type
  if ($fm -notmatch "(?m)^type\s*:\s*handoff\s*`$") {
    if ($fm -match '(?m)^type\s*:\s*(\S+)') {
      $issues += "type: '$($Matches[1])' (should be 'handoff')"
    } else {
      $issues += "missing type:"
    }
  }

  # date
  if ($fm -notmatch "(?m)^date\s*:\s*\d{4}-\d{2}-\d{2}\s*`$") {
    $issues += "missing or malformed date: (need YYYY-MM-DD)"
  }

  # sprint vs slug
  if ($fm -match '(?m)^slug\s*:') {
    $issues += "uses 'slug:' (canonical key is 'sprint:')"
  }
  if ($fm -notmatch '(?m)^sprint\s*:\s*\S') {
    $issues += "missing sprint:"
  }

  # status
  $statusMatch = [regex]::Match($fm, '(?m)^status\s*:\s*(\S+)\s*$')
  if (-not $statusMatch.Success) {
    $issues += "missing status:"
  } else {
    $status = $statusMatch.Groups[1].Value.Trim('"',"'")
    if ($status -notin @('ready','complete','obsolete')) {
      $issues += "status: '$status' is not ready|complete|obsolete"
    }
    if ($status -eq 'obsolete') {
      # Terminal abandoned/superseded state: needs the declared-dead date +
      # a note naming what killed it. No verification -- nothing shipped.
      if ($fm -notmatch "(?m)^completed_date\s*:\s*\d{4}-\d{2}-\d{2}\s*`$") {
        $issues += "status obsolete missing completed_date: (YYYY-MM-DD, date declared dead)"
      }
      if ($fm -notmatch '(?m)^completion_note\s*:') {
        $issues += "status obsolete missing completion_note: (what superseded/killed it)"
      }
    }
    if ($status -eq 'complete') {
      if ($fm -notmatch "(?m)^completed_date\s*:\s*\d{4}-\d{2}-\d{2}\s*`$") {
        $issues += "status complete missing completed_date: (YYYY-MM-DD)"
      }
      if ($fm -notmatch '(?m)^verification\s*:') {
        # completion_note is the lighter alternative on small/admin handoffs;
        # accept it as a substitute since agent judgment is allowed here.
        if ($fm -notmatch '(?m)^completion_note\s*:') {
          $issues += "status complete missing verification: block (or completion_note:)"
        }
      } else {
        # Cross-check task: entries against their referenced Kanbans.
        # task: "<kanban-path relative to Root> -- <task text> -- checked <date>"
        # Separator can be em-dash ("—") or double-hyphen ("--").
        $verLines = @()
        $inVerBlock = $false
        foreach ($l in ($fm -split "`r?`n")) {
          if ($l -match '^verification\s*:\s*$') { $inVerBlock = $true; continue }
          if ($inVerBlock) {
            if ($l -match '^[a-zA-Z_]' -and $l -notmatch '^\s') { break }
            if ($l -match '\S') { $verLines += $l }
          }
        }
        $taskRe = '^\s*-\s*task\s*:\s*"?(.+?)"?\s*$'
        $sepRe  = '\s+(?:[—]|--)\s+'
        foreach ($vl in $verLines) {
          if ($vl -notmatch $taskRe) { continue }
          $payload = $Matches[1]
          $parts = [regex]::Split($payload, $sepRe)
          if ($parts.Count -lt 2) {
            $issues += "verification task: malformed (need '<kanban> -- <text> [-- checked <date>]'): $payload"
            continue
          }
          $kanbanRel = $parts[0].Trim()
          $taskText  = $parts[1].Trim()
          $kanbanAbs = if ([System.IO.Path]::IsPathRooted($kanbanRel)) { $kanbanRel }
                       else { Join-Path $Root $kanbanRel }
          if (-not (Test-Path $kanbanAbs)) {
            $issues += "verification task: kanban not found: $kanbanRel"
            continue
          }
          $kanban = Get-Content $kanbanAbs -Raw -Encoding UTF8
          # Escape regex metachars in the task text for substring match.
          $needle = [regex]::Escape($taskText)
          $hitX = [regex]::Match($kanban, "(?m)^\s*-\s*\[x\][^\r\n]*$needle")
          $hitO = [regex]::Match($kanban, "(?m)^\s*-\s*\[\s\][^\r\n]*$needle")
          if ($hitX.Success) {
            # All good.
          } elseif ($hitO.Success) {
            $issues += "verification task: cited but kanban shows OPEN '[ ]': $taskText"
          } else {
            $issues += "verification task: no matching task line in kanban for: $taskText"
          }
        }
      }
    }
  }

  # tags
  if ($fm -notmatch '(?m)^tags\s*:') { $issues += "missing tags:" }

  # time_by_project
  if ($fm -notmatch '(?m)^time_by_project\s*:') {
    $issues += "missing time_by_project: (use '{}' if no time tracked)"
  } else {
    # Extract the block: from the line after "time_by_project:" until the next top-level key.
    $lines    = $fm -split "`r?`n"
    $inBlock  = $false
    $tbpLines = @()
    $inlineEmpty = $false
    foreach ($l in $lines) {
      if ($l -match '^time_by_project\s*:\s*(.*)$') {
        $rest = $Matches[1].Trim()
        if ($rest -eq '{}') { $inlineEmpty = $true; break }
        if ($rest -match '\S') {
          $issues += "time_by_project: has unexpected inline value '$rest'"
          break
        }
        $inBlock = $true
        continue
      }
      if ($inBlock) {
        # Top-level key (non-indented, non-blank) ends the block.
        if ($l -match '^[a-zA-Z_]' -and $l -notmatch '^\s') { break }
        if ($l -match '\S') { $tbpLines += $l }
      }
    }
    if (-not $inlineEmpty) {
      if ($tbpLines.Count -eq 0) {
        $issues += "time_by_project: present but empty (use '{}' if intentional)"
      }
      foreach ($tl in $tbpLines) {
        if ($tl -match '^\s+["'']?([^"''\s:]+)["'']?\s*:\s*(\S+)') {
          $slug = $Matches[1]
          $val  = $Matches[2]
          if (-not $validSlugs.Contains($slug)) {
            $issues += "time_by_project key '$slug' not in registry"
          }
          if ($val -notmatch '^\d+$' -or [int]$val -le 0) {
            $issues += "time_by_project '$slug' value '$val' not a positive integer"
          }
        } else {
          $issues += "time_by_project line malformed: '$($tl.Trim())'"
        }
      }
    }
  }

  if ($issues.Count -gt 0) { $issuesByFile[$rel] = $issues }
}

# --- Report ---
$totalFiles  = $files.Count
$issueFiles  = $issuesByFile.Keys.Count
$totalIssues = 0
foreach ($v in $issuesByFile.Values) { $totalIssues += $v.Count }

Write-Host "Linted $totalFiles handoffs in $HandoffsDir" -ForegroundColor Cyan
Write-Host "Valid slugs ($($validSlugs.Count)): $((@($validSlugs) | Sort-Object) -join ', ')" -ForegroundColor DarkGray
Write-Host ""

if ($issueFiles -eq 0) {
  Write-Host "[OK] All handoff frontmatter clean." -ForegroundColor Green
  exit 0
}

Write-Host "[ISSUES] $issueFiles file(s), $totalIssues finding(s):" -ForegroundColor Yellow
foreach ($k in $issuesByFile.Keys) {
  Write-Host ""
  Write-Host "  $k" -ForegroundColor Yellow
  foreach ($iss in $issuesByFile[$k]) {
    Write-Host "    - $iss"
  }
}

exit 1
