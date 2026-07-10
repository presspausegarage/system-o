#Requires -Version 7.0
<#
.SYNOPSIS
  Graduate a launchpad idea to an active category.
.DESCRIPTION
  Moves launchpad/<slug>/ to <category>/<slug>/, scaffolds _meta/Kanban.md and
  _meta/registry/<category>-<slug>.md, removes the old
  _meta/registry/launchpad-<slug>.md entry, then logs to today's journal if
  one exists.

  Category roots are adopter-named, not locked (spec §File & folder taxonomy)
  -- unlike the live workspace this was ported from, -To is NOT validated
  against a fixed category manifest. Any lowercase-hyphen slug is accepted;
  the folder is created if it doesn't already exist as a category root.

  Cross-linking backfill (registry Quick Links regeneration, Kanban
  back-links, a project-map canvas, roster-doc sync) is deliberately NOT
  ported: those are vault-hygiene conveniences layered onto a specific
  operator's workspace over time, not part of the graduate mechanism itself.
  An adopter who wants that can build their own extension (spec §Extension
  surface) for it.
.EXAMPLE
  graduate.ps1 -Project my-idea -To apps
  graduate.ps1 -Project my-idea -To apps -CreateRepo -Org my-github-org
  graduate.ps1 -Project my-idea -To apps -Risk 3 -Priority 1
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Project,
  [Parameter(Mandatory)][string]$To,
  [string]$Title,
  [string]$Description,
  [ValidateSet('1','2','3')][string]$Risk = '2',
  [ValidateSet('1','2','3')][string]$Priority = '2',
  [string]$Root = '.',
  [string]$Org,
  [switch]$CreateRepo
)

$ErrorActionPreference = 'Stop'

$normTo = ($To.Trim().ToLower() -replace '[^a-z0-9]+','-').Trim('-')
if (-not $normTo) { throw "Invalid -To '$To'" }
if ($normTo -ne $To) { Write-Host "[..] Normalized category: '$To' -> '$normTo'"; $To = $normTo }
if ($CreateRepo -and -not $Org) { throw "-CreateRepo requires -Org <github-org-or-user>" }

$src = Join-Path $Root "launchpad/$Project"
$catRoot = Join-Path $Root $To
$dst = Join-Path $catRoot $Project
if (-not (Test-Path $src)) { throw "Project not found in launchpad: $src" }
if (Test-Path $dst)         { throw "Destination already exists: $dst" }

# Category roots are adopter-named (spec §File & folder taxonomy), so this may
# be the first project ever graduated into $To -- create the root if needed
# (Move-Item can't create a missing parent directory in the same call).
if (-not (Test-Path $catRoot)) {
  New-Item -ItemType Directory -Path $catRoot -Force | Out-Null
  Write-Host "[OK] Created new category root: $To/"
}

Move-Item -Path $src -Destination $dst
Write-Host "[OK] Moved $Project -> $To/"

$meta = Join-Path $dst '_meta'
if (-not (Test-Path $meta)) { New-Item -ItemType Directory -Path $meta -Force | Out-Null }

$regSlug   = "$To-$Project"
$today     = Get-Date -Format 'yyyy-MM-dd'
$titleVal  = if ($Title)       { $Title }       else { $Project }
$descVal   = if ($Description) { $Description } else { "TODO: describe $Project" }
$repoUrl   = if ($CreateRepo)  { "https://github.com/$Org/$Project" } else { "" }

# --- Kanban file ---
$kanban = Join-Path $meta 'Kanban.md'
if (-not (Test-Path $kanban)) {
$kanbanHead = @"
---
kanban-plugin: board
type: kanban
parent: "[[$regSlug]]"
tags:
  - type/kanban
  - site/$Project
---
"@
$kanbanBody = @'

## Backlog

## Active

## Blocked

## Done

**Complete**

%% kanban:settings
```
{"kanban-plugin":"board","list-collapse":[false,false,false,false]}
```
%%
'@
  Set-Content -Path $kanban -Value ($kanbanHead + $kanbanBody) -Encoding utf8
  Write-Host "[OK] Created _meta/Kanban.md"
}

# --- Registry entry ---
$regDir = Join-Path $Root '_meta/registry'
if (-not (Test-Path $regDir)) { New-Item -ItemType Directory -Path $regDir -Force | Out-Null }
$regFile = Join-Path $regDir "$regSlug.md"
if (-not (Test-Path $regFile)) {
$regHead = @"
---
type: registry
category: $To
slug: $Project
title: $titleVal
repo: $repoUrl
url:
local: $To/$Project
phase: pre-mvp
risk: $Risk
priority: $Priority
description: $descVal
updated: $today
tags:
  - type/registry
  - category/$To
  - status/active
---

# $titleVal

$descVal

## Quick links

- [[$To/$Project/_meta/Kanban|Kanban board]]

## External services

-
"@
  Set-Content -Path $regFile -Value $regHead -Encoding utf8
  Write-Host "[OK] Created _meta/registry/$regSlug.md"
}

# --- Cleanup old launchpad registry entry ---
$oldRegFile = Join-Path $regDir "launchpad-$Project.md"
if (Test-Path $oldRegFile) {
  Remove-Item -Path $oldRegFile -Force
  Write-Host "[OK] Removed old launchpad registry entry: launchpad-$Project.md"
}

if ($CreateRepo) {
  Push-Location $dst
  try {
    if (-not (Test-Path .git)) {
      git init -b main | Out-Null
      git add -A
      git commit -m "Initial commit on graduation from launchpad" | Out-Null
      Write-Host "[OK] git init + initial commit"
    }
    if (Get-Command gh -ErrorAction SilentlyContinue) {
      gh repo create "$Org/$Project" --private --source=. --remote=origin --push
      Write-Host "[OK] GitHub repo created: $Org/$Project"
    } else {
      Write-Warning "gh CLI not found - repo not created remotely. Run: gh repo create $Org/$Project --private --source=. --push"
    }
  } finally { Pop-Location }
}

# --- Journal entry: best-effort only, this reference ships no journal builder ---
$journalDir = Join-Path $Root '_journal'
if (Test-Path $journalDir) {
  $journal = Join-Path $journalDir "$today.md"
  if (-not (Test-Path $journal)) { New-Item -ItemType File -Path $journal -Force | Out-Null }
  Add-Content -Path $journal -Value "`n- [grad] Graduated **$Project** to ``$To/`` - $(Get-Date -Format 'HH:mm')"
}

Write-Host ""
Write-Host "Next:"
Write-Host "  1. Edit _meta/registry/$regSlug.md - fill in description, repo URL (if not -CreateRepo)."
Write-Host "  2. Open $To/$Project/_meta/Kanban.md and add starter tasks."
