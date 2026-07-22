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
if ($LASTEXITCODE -ne 0) {
  # Fail the container rather than start cron over a broken install: a running
  # container must mean a completed bootstrap. With `restart: unless-stopped`
  # Docker retries; `docker logs` carries the bootstrap error. (bootstrap.ps1
  # writes its session-log sentinel last, so a failed run re-scaffolds cleanly
  # on the next start.)
  Write-Host "[entrypoint] bootstrap FAILED (exit $LASTEXITCODE) — not starting cron"
  exit $LASTEXITCODE
}

Write-Host "[entrypoint] starting cron (foreground)"
& cron -f
