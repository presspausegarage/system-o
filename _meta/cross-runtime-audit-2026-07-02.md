---
type: meta
status: complete
date: 2026-07-02
tags:
  - type/meta
  - topic/system-o
  - topic/distribution
---

# Cross-runtime script audit — July 2, 2026

The v1.0 cross-platform readiness checklist (Kanban blocker). Method: one audit agent per script over all 44 `_meta/scripts/*.ps1`, line-cited Windows surfaces + bundle classification (framework-generic / operator-specific / hybrid — which also discharges the README "smallest next step" inventory for the scripts directory). Overridable `-Root C:\dev` parameter defaults were excluded by design — parameterization, not a lock.

## Headline

**The shippable core is portable.** Of the 15 framework-generic scripts, 14 are `clean-pwsh7` or `shimmable`; the single lock (`svg-to-ico.ps1`) is icon tooling that shouldn't ship anyway. **Every structural Windows dependency lives in operator-specific tooling that never ships** — 9 of 13 operator scripts are windows-locked (scheduled-task registration, .lnk shortcuts, registry, COM, WSL cleanup, fx/pilot toggles). The Windows-lock problem for the distribution is therefore ~zero; the shim problem is one mechanical pattern.

| Bundle class | clean-pwsh7 | shimmable | windows-locked |
|---|---|---|---|
| framework-generic (15) | 1 | 13 | 1 |
| hybrid (16) | 1 | 12 | 3 |
| operator-specific (13) | 0 | 4 | 9 |

## Surface profile (what "shimmable" actually means)

| Count | Category | Nature of fix |
|---|---|---|
| 118 | windows-only-path (literal `\` separators, `_meta\logs`-style joins) | **One mechanical pattern**: `/` or chained `Join-Path`. Lintable — a conformance grep can enforce it. |
| 24 | drive-letter-path | Mostly inline `C:\dev` beyond the param default; centralize vault-root resolution (env/config). |
| 15 | scheduled-task-cmdlet | **All in `register-*` scripts** (operator-specific). Chain scripts themselves are clean → registration is a per-OS layer, not a porting problem (feeds D3). |
| 12 | windows-env-var (`$env:TEMP`, `$env:APPDATA`) | `[IO.Path]::GetTempPath()`, XDG-aware config paths. |
| 15 | native-exe (robocopy, attrib, ie4uinit, wscript…) | robocopy = backup-engine seam (rsync on POSIX); the rest are Explorer cosmetics → `$IsWindows` guards or don't ship. |
| 12 | registry / COM / .lnk / HKCU | Operator-specific installers only. Never ships. |
| 5 | encoding-console / SYSTEM-account | Minor; per-site guards. |

## Per-script inventory

### Framework-generic — ships in the bundle (15)

| Script | Verdict | Surfaces |
|---|---|---|
| check-ai-tells.ps1 | ✅ clean-pwsh7 | 0 |
| apply-proposals.ps1 · _categories.ps1 · lint-handoff-frontmatter.ps1 · triage-inbox-adjacent utilities (apply-loop-proposal, purge-sewerpipe, sweep-handoffs, launchpad, link-registry, link-project-back, bury, bloat-audit, build-radar-digest, open-in-obsidian) | 🔧 shimmable | 1–11 each, overwhelmingly `\`-separator joins |
| svg-to-ico.ps1 | ❌ windows-locked | ICO/Explorer tooling — exclude from bundle |

### Hybrid — ships with operator data scrubbed/parameterized (16)

| Script | Verdict | Note |
|---|---|---|
| check-frontmatter-schemas.ps1 | ✅ clean | — |
| check-session-log.ps1 · run-loop.ps1 · graduate.ps1 · bump-updated-field.ps1 · triage-inbox.ps1 · build-roster.ps1 · build-daily-report.ps1 · build-weekly-review.ps1 · build-demand-radar.ps1 · build-project-map-canvas.ps1 · send-daily-report-email.ps1 · push-notebooklm-context.ps1 | 🔧 shimmable | separator joins + occasional TEMP/env; operator data (SMTP, category rosters, NotebookLM) parameterizes out |
| backup-dev.ps1 | ❌ locked | robocopy engine + exit-code contract → needs an engine seam (rsync/robocopy behind a neutral exclude list) |
| install-icon-pack.ps1 · rotate-pgp-security.ps1 | ❌ locked | Explorer cosmetics / gpg-Windows plumbing — optional Windows extras at most |

### Operator-specific — never ships (13)

setup-notebooklm-bridge, pull-corpus-archive, gen-caffeine-ics, block-outlook-ads (shimmable but irrelevant); register-weekly-review-task, register-claude-pilot-tasks, toggle-fx-bot, toggle-claude-loop, create-fx-toggle-shortcut, cleanup-affine-wsltray, Install-OpenInObsidian, fx-market-open-ollama, run-claude-pilot (windows-locked and irrelevant — this is where ALL the scheduler/registry/COM/.lnk mass lives).

## What this buys the distribution review

- **D2 (OS matrix)**: option (a) — OS-agnostic reference via pwsh 7 — is cheap for the shippable set: one separator lint + a vault-root resolver + TEMP shim covers ~90% of findings. No per-OS forks needed for chain logic.
- **D3 (scheduler)**: confirmed as a thin per-OS *registration* layer (Task Scheduler / cron / launchd), since zero chain scripts embed scheduling — only the operator-side `register-*` wrappers do.
- **D1 (packaging)**: the framework/hybrid/operator split above is the bundle's include-list seed.
- **One engine seam**: backup (robocopy↔rsync) is the only shippable component needing per-OS reimplementation rather than a shim.

Raw per-line findings (200+ surfaces with snippets and per-surface fixes) live in the audit run's transcript; re-derivation is one workflow re-run if ever needed — this table is the durable layer.
