#Requires -Version 7.0
<#
.SYNOPSIS
  Container entrypoint: run the bootstrap, then run cron in the foreground.
.DESCRIPTION
  PID 1 in this container. Runs bootstrap.ps1 (idempotent — safe on every
  container start, not just the first), installs the crontab, then execs
  `cron -f` as the long-running foreground process.

  Signal handling note: this container should be started with `docker run
  --init` (or `init: true` in compose) so SIGTERM reaches this process
  correctly through Docker's own init — pwsh as PID 1 does not reliably
  forward signals to child processes on its own. Documented, not silently
  worked around, since a hand-rolled signal trap would be more fragile than
  the well-tested flag Docker already ships.
#>
$ErrorActionPreference = 'Stop'
Write-Host "[entrypoint] running bootstrap"
& pwsh -NoProfile -File /opt/system-o/bootstrap.ps1
if ($LASTEXITCODE -ne 0) { Write-Host "[entrypoint] bootstrap exited $LASTEXITCODE — continuing anyway (cron still starts)" }

Write-Host "[entrypoint] starting cron (foreground)"
& cron -f
