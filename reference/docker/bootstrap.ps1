#Requires -Version 7.0
<#
.SYNOPSIS
  First-start bootstrap (spec §Extension surface's sibling concern: distribution
  review D8, onboarding stage 1 — deterministic, no LLM).
.DESCRIPTION
  Scaffolds the locked folder taxonomy (spec §File & folder taxonomy) into a
  fresh vault root, writes starter GLOSSARY.md / HOME.md / orientation file /
  session-log.md from templates, and installs the crontab.

  Idempotent, with an ordering guarantee: `_meta/session-log.md` is the
  install-complete sentinel and is written LAST on the fresh path. An
  interrupted first run therefore leaves no sentinel, and the next start
  re-runs the scaffold — every individual write is if-absent guarded, so a
  partial vault is completed rather than re-created or skipped forever.
  If the sentinel exists, this is an existing vault: the scaffold is skipped
  (never re-scaffolds over real content), but the locked directory set is
  still repaired if anything is missing, and the crontab install re-runs.

  Stage 2 (optional agent pass — refining the glossary and orientation-file
  prose) is NOT run here; it needs an agent harness this container does not
  provide. This script prints what to do next instead of guessing at it.
.PARAMETER VaultRoot
  Where the vault lives. Default: $env:VAULT_ROOT or /vault.
.PARAMETER AgentTarget
  Canonical orientation filename. Default: $env:AGENT_TARGET or CLAUDE.md.
.PARAMETER SourceRoot
  Where the framework files (scripts/, extensions/, templates/, the example
  loop manifest, crontab.example) live. Default: /opt/system-o — the baked-in
  container layout. The conformance harness passes a staged temp directory
  here so native runs never touch an absolute shared path.
.EXAMPLE
  bootstrap.ps1 -VaultRoot /vault -AgentTarget CLAUDE.md
#>
[CmdletBinding()]
param(
  [string]$VaultRoot = $(if ($env:VAULT_ROOT) { $env:VAULT_ROOT } else { '/vault' }),
  [string]$AgentTarget = $(if ($env:AGENT_TARGET) { $env:AGENT_TARGET } else { 'CLAUDE.md' }),
  [string]$SourceRoot = $(if ($env:SYSTEM_O_SOURCE) { $env:SYSTEM_O_SOURCE } else { '/opt/system-o' })
)

$ErrorActionPreference = 'Stop'
function Say { param([string]$m) Write-Host "[bootstrap] $m" }

$sessionLog = Join-Path $VaultRoot '_meta/session-log.md'
$fresh = -not (Test-Path $sessionLog)

# Locked folders (spec §File & folder taxonomy; §Agent context bundle locks
# _meta/agent-context/ "by extension of §File & folder taxonomy's determinism
# guarantee" — not listed in the taxonomy table itself, easy to miss).
# Ensured on EVERY start, fresh or existing: repairing a missing locked dir on
# an existing vault is safe (New-Item only fires when absent) and keeps one
# early-created file from masking an incomplete install.
$dirs = @(
  '_meta/registry', '_meta/handoffs', '_meta/loops/proposals', '_meta/extensions',
  '_meta/scripts', '_meta/templates', '_meta/logs', '_inbox', '_sewerpipe', '_archive/handoffs',
  '_meta/agent-context'
)
foreach ($d in $dirs) {
  $p = Join-Path $VaultRoot $d
  if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

if ($fresh) {
  Say "fresh vault at $VaultRoot — scaffolding locked taxonomy"

  # Framework scripts/extensions/templates: copied in, not symlinked, so an
  # adopter's vault is self-contained and portable off this container.
  Copy-Item -Path (Join-Path $SourceRoot 'scripts/*')    -Destination (Join-Path $VaultRoot '_meta/scripts')    -Recurse -Force
  Copy-Item -Path (Join-Path $SourceRoot 'extensions/*') -Destination (Join-Path $VaultRoot '_meta/extensions') -Recurse -Force
  Copy-Item -Path (Join-Path $SourceRoot 'templates/*')  -Destination (Join-Path $VaultRoot '_meta/templates')  -Recurse -Force

  $today = Get-Date -Format 'yyyy-MM-dd'

  # Starter HOME.md — carries the marker build-static-home.ps1 targets, so the
  # editor-agnostic core (spec §System architecture layer 4) works from minute one.
  $homeFile = Join-Path $VaultRoot '_meta/HOME.md'
  if (-not (Test-Path $homeFile)) {
    @"
---
type: dashboard
tags:
  - type/dashboard
updated: $today
---

# Home

## Projects

<!-- STATIC-HOME:START -->
<!-- STATIC-HOME:END -->
"@ | Set-Content -Path $homeFile -Encoding UTF8
  }

  # Starter GLOSSARY.md — empty term table; populated during onboarding (Andy's
  # decision, 2026-07-01: the artifact is required, the vocabulary is the
  # adopter's own, not shipped pre-filled).
  $glossaryFile = Join-Path $VaultRoot '_meta/GLOSSARY.md'
  if (-not (Test-Path $glossaryFile)) {
    @"
---
type: meta
tags:
  - type/meta
  - topic/glossary
updated: $today
---

# Glossary — ubiquitous language

Populate this during onboarding (stage 2 — an agent-guided pass, or by hand): the terms your own vault's conventions, scripts, and prompts assume a reader already knows. Loop prompt templates and orientation files should reference terms here rather than re-defining them.

| Term | Definition |
|---|---|
"@ | Set-Content -Path $glossaryFile -Encoding UTF8
  }

  # Starter agent-context MEMORY.md (spec §Agent context bundle — required,
  # the index; empty is fine, absent is not).
  $memoryFile = Join-Path $VaultRoot '_meta/agent-context/MEMORY.md'
  if (-not (Test-Path $memoryFile)) {
    @"
---
type: meta
tags:
  - type/meta
  - topic/agent-context
updated: $today
---

# Agent context index

One line per topic file: a short label, a one-line summary, a link. Populate during onboarding or as an agent harness accumulates durable facts about this workspace (spec §Agent context bundle). Never holds the fact itself — this is the table of contents.
"@ | Set-Content -Path $memoryFile -Encoding UTF8
  }

  # Orientation file (spec §Agent orientation files) — the canonical file for
  # whichever agent is primary. Minimal starter; stage 2 refines the prose.
  $orientFile = Join-Path $VaultRoot $AgentTarget
  if (-not (Test-Path $orientFile)) {
    @"
# Workspace orientation

This is the canonical agent-orientation file for this vault (spec §Agent orientation files). Read on session start.

- Glossary: `_meta/GLOSSARY.md`
- Session log: `_meta/session-log.md`
- Loop layer: `_meta/loops/` (manifests), `_meta/loops/proposals/` (awaiting review)
- Extensions: `_meta/extensions/` (see each extension's README.md)

_Stage-2 onboarding (an agent-guided pass) should replace this with prose specific to your workspace — conventions, risk tiers, project registry, and how you want an agent to work here._
"@ | Set-Content -Path $orientFile -Encoding UTF8
  }

  # Example loop manifest, shipped INERT (.yaml.example, not .yaml): its endpoints
  # are placeholders, and cron-ing a loop that fail-closes every night out of the
  # box is noise, not a feature. Rename + fill in real endpoints to activate.
  $exampleManifest = Join-Path $SourceRoot 'wrap-tail-repair.example.yaml'
  if (Test-Path $exampleManifest) {
    Copy-Item -Path $exampleManifest -Destination (Join-Path $VaultRoot '_meta/loops/wrap-tail-repair.yaml.example') -Force
  }

  # Starter session-log.md — written LAST: it is the install-complete sentinel,
  # so nothing above may run after it exists. Do not move this write earlier.
  @"
---
type: session-log
tags:
  - type/session-log
updated: $today
---

# Session log

Running record of work sessions — one entry per session, newest at top.
"@ | Set-Content -Path $sessionLog -Encoding UTF8

  Say "scaffold complete: $($dirs.Count) folders, orientation file ($AgentTarget), starter GLOSSARY/HOME/session-log/agent-context"
  Say "loop layer shipped INERT: edit _meta/loops/wrap-tail-repair.yaml.example, rename to .yaml, to activate"
  Say "STAGE 2 NOT RUN: this container provides no agent. Point an agent harness at $VaultRoot and have it work through _meta/templates/stage-2-onboarding.prompt.md to refine the glossary and orientation-file prose."
} else {
  Say "existing vault detected at $VaultRoot (session-log.md present) — skipping scaffold (locked dirs repaired if missing), installing the crontab"
}

# Crontab install — idempotent (crontab replaces wholesale each run, no duplication).
# A real install failure is fatal: a container that looks healthy while nothing is
# scheduled is worse than one that stops and says why.
$cronFile = Join-Path $SourceRoot 'crontab.example'
if (Test-Path $cronFile) {
  $cronText = (Get-Content -Path $cronFile -Raw) -replace '\$VAULT_ROOT', $VaultRoot
  $cronText | & crontab -
  if ($LASTEXITCODE -ne 0) {
    Say "ERROR crontab install failed (crontab exited $LASTEXITCODE)"
    exit 1
  }
  Say "crontab installed"
} else {
  Say "WARN crontab.example not found at $cronFile — no schedule installed"
}
