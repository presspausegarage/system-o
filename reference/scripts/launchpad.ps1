#Requires -Version 7.0
<#
.SYNOPSIS
  Launchpad a new idea -- scaffold launchpad/<slug>/ from the idea template and
  register it as _meta/registry/launchpad-<slug>.md, then log to today's journal
  if one exists.
.DESCRIPTION
  Creates the launchpad-stage structure the lifecycle scripts expect (spec
  §File & folder taxonomy: launchpad is an adopter-named category root, not
  locked). Every launchpad/<idea>/ carries a README.md from
  reference/templates/idea-README.md; graduate.ps1 cleans up the
  launchpad-<slug>.md registry card on graduation. Idempotent: won't clobber an
  existing README (use -Force), always backfills a missing registry card.

  Journal logging is best-effort and optional: this reference implementation
  does not ship a `_journal/` daily-note builder, so an entry is only appended
  if `_journal/` already exists in the vault. Its absence is not an error.
.EXAMPLE
  launchpad.ps1 -Slug my-idea -Title "My Idea" -Description "What it does"
  launchpad.ps1 -Slug my-idea -Days 14
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Slug,
  [string]$Title,
  [string]$Description,
  [ValidateRange(1,30)][int]$Days = 30,
  [string]$Root = '.',
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Normalize slug to lowercase-hyphens (spec: slug IS the project ID)
$normSlug = ($Slug.Trim().ToLower() -replace '[^a-z0-9]+','-').Trim('-')
if (-not $normSlug) { throw "Invalid slug: '$Slug'" }
if ($normSlug -ne $Slug) { Write-Host "[..] Normalized slug: '$Slug' -> '$normSlug'" }

$ideaDir  = Join-Path $Root "launchpad/$normSlug"
$readme   = Join-Path $ideaDir 'README.md'
$template = Join-Path $Root '_meta/templates/idea-README.md'
if (-not (Test-Path $template)) { throw "Idea template not found: $template" }

# Dates: prose in README, ISO in frontmatter/filenames
$today        = Get-Date
$createdProse = $today.ToString('MMMM d, yyyy')
$decideBy     = $today.AddDays($Days)
$decideProse  = $decideBy.ToString('MMMM d, yyyy')
$todayIso     = $today.ToString('yyyy-MM-dd')
$decideIso    = $decideBy.ToString('yyyy-MM-dd')

$titleVal = if ($Title)       { $Title }       else { $normSlug }
$descVal  = if ($Description) { $Description } else { "TODO: describe $normSlug" }

# --- Idea folder + README from template ---
if (-not (Test-Path $ideaDir)) { New-Item -ItemType Directory -Path $ideaDir -Force | Out-Null }

if ((Test-Path $readme) -and -not $Force) {
  Write-Host "[..] README exists, left as-is: launchpad/$normSlug/README.md (use -Force to overwrite)"
} else {
  $tpl = Get-Content $template -Raw -Encoding UTF8
  $tpl = $tpl.Replace('{{IDEA_NAME}}', $titleVal).Replace('{{CREATED_DATE}}', $createdProse).Replace('{{DECIDE_BY_DATE}}', $decideProse)
  Set-Content -Path $readme -Value $tpl -Encoding utf8
  Write-Host "[OK] Created launchpad/$normSlug/README.md"
}

# --- Registry card (graduate.ps1 cleans this up on graduation) ---
$regDir = Join-Path $Root '_meta/registry'
if (-not (Test-Path $regDir)) { New-Item -ItemType Directory -Path $regDir -Force | Out-Null }
$regFile = Join-Path $regDir "launchpad-$normSlug.md"
if (-not (Test-Path $regFile)) {
$reg = @"
---
type: registry
category: launchpad
slug: $normSlug
title: $titleVal
repo:
url:
local: launchpad/$normSlug
phase: idea
risk: 2
priority: 2
description: $descVal
created: $todayIso
decide_by: $decideIso
updated: $todayIso
tags:
  - type/registry
  - category/launchpad
  - status/idea
---

# $titleVal

$descVal

## Quick links

- [[launchpad/$normSlug/README|Idea README]]
"@
  Set-Content -Path $regFile -Value $reg -Encoding utf8
  Write-Host "[OK] Created _meta/registry/launchpad-$normSlug.md"
} else {
  Write-Host "[..] Registry card exists: launchpad-$normSlug.md"
}

# --- Journal entry: best-effort only, this reference ships no journal builder ---
$journalDir = Join-Path $Root '_journal'
if (Test-Path $journalDir) {
  $journal = Join-Path $journalDir "$todayIso.md"
  if (-not (Test-Path $journal)) { New-Item -ItemType File -Path $journal -Force | Out-Null }
  Add-Content -Path $journal -Value "`n- [idea] Launchpad **$normSlug** (decide-by $decideProse) -- $(Get-Date -Format 'HH:mm')"
}

Write-Host ""
Write-Host "Next:"
Write-Host "  1. Fill in launchpad/$normSlug/README.md - idea, problem, smallest next step."
Write-Host "  2. Idle >$Days d -> graduate.ps1 (-To <category>) or bury."
