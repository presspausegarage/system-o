#Requires -Version 7.0
<#
.SYNOPSIS
  Bury a project -- write a tombstone, move it to _archive/<YYYY-Qn>/<project>/.
.DESCRIPTION
  Interactive by default: prompts for whatever tombstone fields aren't passed
  as parameters (useful for batch burials and scripting).

  Discovery is generic, not category-manifest-based (spec §File & folder
  taxonomy: category roots are adopter-named, not locked). Checks
  `launchpad/<Project>` first (the one adopter-named-but-conventional root
  every reference script already assumes -- see graduate.ps1), then scans
  every other top-level directory that isn't reserved (`_`-prefixed) for a
  child folder named `<Project>`. First match wins; name a project uniquely
  across category roots if you rely on this.

  Deliberately NOT ported from the live workspace this was drawn from:
  the repo-map.md "Archived" row append and the build-project-map-canvas.ps1
  / build-roster.ps1 regeneration calls. Same rationale as graduate.ps1's
  excluded cross-linking backfill -- those are vault-hygiene conveniences
  layered onto one operator's roster/canvas docs over time (neither script
  ships in this reference), not part of the bury mechanism itself. An
  adopter who wants that can build their own extension (spec §Extension
  surface) or loop for it.
.EXAMPLE
  bury.ps1 -Project failed-thing
  bury.ps1 -Project agent-handoff -Worked "..." -Didnt "..." -Different "..." -Why "..." -Revisit no
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Project,
  [string]$Root = '.',
  [string]$Worked,
  [string]$Didnt,
  [string]$Different,
  [string]$Why,
  [ValidateSet('yes', 'no', 'maybe')][string]$Revisit
)

$ErrorActionPreference = 'Stop'

# --- Discovery: launchpad first, then any non-reserved top-level dir (generic scan, no category manifest) ---
$src = $null
$category = $null

$launchpadCandidate = Join-Path $Root "launchpad/$Project"
if (Test-Path $launchpadCandidate) {
  $src = $launchpadCandidate
  $category = 'launchpad'
}

if (-not $src) {
  foreach ($catRoot in (Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue)) {
    if ($catRoot.Name.StartsWith('_') -or $catRoot.Name -eq 'launchpad') { continue }
    $candidate = Join-Path $catRoot.FullName $Project
    if (Test-Path $candidate) {
      $src = $candidate
      $category = $catRoot.Name
      break
    }
  }
}

if (-not $src) { throw "Project not found under launchpad/ or any category root: $Project" }
Write-Host "Found at: $src"

# --- Prompt for any missing tombstone field ---
Write-Host ""
if (-not $Worked) { $Worked = Read-Host "What worked" }
if (-not $Didnt) { $Didnt = Read-Host "What didn't" }
if (-not $Different) { $Different = Read-Host "What you'd do differently" }
if (-not $Why) { $Why = Read-Host "Why now" }
if (-not $Revisit) { $Revisit = Read-Host "Revisit subject? (yes/no/maybe)" }

# --- Write tombstone.md inside the project folder before moving ---
$today = Get-Date -Format 'yyyy-MM-dd'
$tombstone = Join-Path $src 'tombstone.md'
@"
---
type: tombstone
buried: $today
project: $Project
revisit: $Revisit
tags:
  - type/tombstone
---

# RIP: $Project

**Buried:** $today

## What worked
- $Worked

## What didn't
- $Didnt

## What I'd do differently
- $Different

## Why now
$Why

## Revisit?
$Revisit
"@ | Set-Content -Path $tombstone -Encoding UTF8
Write-Host "[OK] tombstone written"

# --- Strip cross-link back-links before archiving ---
# Undoes graduate.ps1's own scaffold output (`parent: "[[<slug>]]"` in Kanban.md)
# so the archived copy is self-contained -- registry deletion below would
# otherwise leave an unresolved wikilink behind. Scoped entirely to files
# inside the folder being archived; not a vault-wide backfill.
$slug = "$category-$Project"
$escapedSlug = [regex]::Escape($slug)
$backlinkCandidates = @(
  (Join-Path $src '_meta/Kanban.md'),
  (Join-Path $src '_meta/Dashboard.md')
)
foreach ($file in $backlinkCandidates) {
  if (Test-Path $file) {
    $content = Get-Content $file -Raw -Encoding UTF8
    $original = $content
    # Strip body back-link: > Registry: [[<slug>]]
    $content = [regex]::Replace($content, "(?m)^>\s*Registry:\s*\[\[$escapedSlug\]\]\s*\r?\n", "")
    # Strip frontmatter parent: "[[<slug>]]"
    $content = [regex]::Replace($content, "(?m)^parent:\s*`"\[\[$escapedSlug\]\]`"\s*\r?\n", "")
    # Collapse 3+ consecutive newlines to 2
    $content = [regex]::Replace($content, "(?:\r?\n){3,}", "`n`n")
    if ($content -ne $original) {
      [System.IO.File]::WriteAllText($file, $content, [System.Text.UTF8Encoding]::new($false))
      Write-Host "[OK] stripped back-links from $(Split-Path $file -Leaf)"
    }
  }
}

# --- Move to _archive/<YYYY-Qn>/<Project>/ ---
$now = Get-Date
$quarter = [math]::Ceiling($now.Month / 3)
$qFolder = "{0}-Q{1}" -f $now.Year, $quarter
$dstParent = Join-Path $Root "_archive/$qFolder"
$dst = Join-Path $dstParent $Project

New-Item -ItemType Directory -Force -Path $dstParent | Out-Null
Move-Item -Path $src -Destination $dst
Write-Host "[OK] Moved to _archive/$qFolder/$Project"

# --- Journal entry: best-effort only, this reference ships no journal builder ---
$journalDir = Join-Path $Root '_journal'
if (Test-Path $journalDir) {
  $journal = Join-Path $journalDir "$today.md"
  if (-not (Test-Path $journal)) { New-Item -ItemType File -Path $journal -Force | Out-Null }
  Add-Content -Path $journal -Value "`n- [bury] Buried **$Project** -> ``_archive/$qFolder/`` (revisit: $Revisit) - $(Get-Date -Format 'HH:mm')"
}

# --- Remove the corresponding registry note if it exists ---
$regNote = Join-Path $Root "_meta/registry/$slug.md"
if (Test-Path $regNote) {
  Remove-Item -Path $regNote
  Write-Host "[OK] removed registry note: _meta/registry/$slug.md"
}

Write-Host ""
Write-Host "Done. $Project buried under _archive/$qFolder/."
