# system-o reference container (distribution review D1: Docker is the primary
# install path). This image is the automation-chain RUNTIME — pwsh 7 + cron +
# the reference scripts/extensions/templates. It is NOT the vault: the vault
# is a bind mount (see docker-compose.example.yml), edited by whatever editor
# and agent harness the adopter chooses on the host (spec layers 4-5, optional
# and pluggable). This container only ever touches layers 1-3.

FROM mcr.microsoft.com/powershell:7.4-debian-12

# git: needed by detect-wrap-tail.ps1's commit-only-date scan.
# cron: the in-container scheduler (dissolves per-OS scheduler registration —
# distribution review D1/D3).
# tzdata: so `TZ` (compose environment) actually shifts the container clock —
# cron fires on container time, which is UTC unless you set TZ.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git cron ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

# Build context MUST be apps/system-o/ (the parent of both reference/ and
# spec/) -- NOT reference/ itself. spec/wrap-tail-repair.example.yaml lives
# outside reference/, and Docker can't reach outside its context via '../'.
# docker-compose.example.yml and the README set `context: ..` for this reason
# (found the hard way: this mismatch went unnoticed until the first real
# `docker build`, since nothing had ever actually built this image before).
#
# The framework ships here, immutable, separate from the operator's vault.
COPY reference/scripts/     /opt/system-o/scripts/
COPY reference/extensions/  /opt/system-o/extensions/
COPY reference/templates/   /opt/system-o/templates/
COPY spec/wrap-tail-repair.example.yaml /opt/system-o/wrap-tail-repair.example.yaml
COPY reference/docker/entrypoint.ps1  /opt/system-o/entrypoint.ps1
COPY reference/docker/bootstrap.ps1   /opt/system-o/bootstrap.ps1
COPY reference/docker/healthcheck.ps1 /opt/system-o/healthcheck.ps1
COPY reference/docker/crontab.example /opt/system-o/crontab.example

# Bind-mounted at runtime — see docker-compose.example.yml. Declaring the
# volume here documents the contract even for a plain `docker run`.
VOLUME ["/vault"]
ENV VAULT_ROOT=/vault
ENV AGENT_TARGET=CLAUDE.md

# "Running" is not "installed": the entrypoint fails the container on bootstrap
# errors, and this check keeps guarding after startup (sentinel + locked dirs +
# crontab actually installed).
HEALTHCHECK --interval=5m --timeout=30s --start-period=2m --retries=3 \
  CMD ["pwsh", "-NoProfile", "-File", "/opt/system-o/healthcheck.ps1"]

ENTRYPOINT ["pwsh", "-NoProfile", "-File", "/opt/system-o/entrypoint.ps1"]
