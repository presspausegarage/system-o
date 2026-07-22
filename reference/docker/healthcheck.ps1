#Requires -Version 7.0
<#
.SYNOPSIS
  Container health check: verify the install actually completed and stayed wired.
.DESCRIPTION
  Wired into the image as HEALTHCHECK (see Dockerfile). Exits 0 (healthy) only
  when all of:
    1. the vault's install-complete sentinel (_meta/session-log.md) exists
    2. the locked directory set is present
    3. the crontab is installed, references run-extensions.ps1, and carries no
       unsubstituted $VAULT_ROOT literal
  Anything else exits 1, which Docker surfaces as an unhealthy container —
  "running" alone is not proof of a working install (that gap is exactly what
  this check exists to close).
#>
param(
  [string]$VaultRoot = $(if ($env:VAULT_ROOT) { $env:VAULT_ROOT } else { '/vault' })
)

$ErrorActionPreference = 'Stop'

function Unhealthy { param([string]$m) Write-Host "[healthcheck] UNHEALTHY: $m"; exit 1 }

if (-not (Test-Path (Join-Path $VaultRoot '_meta/session-log.md'))) {
  Unhealthy 'install-complete sentinel _meta/session-log.md missing (bootstrap incomplete)'
}

$lockedDirs = @(
  '_meta/registry', '_meta/handoffs', '_meta/loops/proposals', '_meta/extensions',
  '_meta/scripts', '_meta/templates', '_meta/logs', '_inbox', '_sewerpipe', '_archive/handoffs',
  '_meta/agent-context'
)
$missing = @($lockedDirs | Where-Object { -not (Test-Path (Join-Path $VaultRoot $_)) })
if ($missing.Count -gt 0) { Unhealthy ("locked directories missing: " + ($missing -join ', ')) }

$cronOut = & crontab -l 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Unhealthy 'no crontab installed' }
if ($cronOut -notmatch 'run-extensions\.ps1') { Unhealthy 'crontab does not schedule run-extensions.ps1' }
if ($cronOut -match '\$VAULT_ROOT') { Unhealthy 'crontab contains unsubstituted $VAULT_ROOT' }

Write-Host '[healthcheck] healthy'
exit 0
