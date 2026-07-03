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
RUN apt-get update \
    && apt-get install -y --no-install-recommends git cron ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# The framework ships here, immutable, separate from the operator's vault.
COPY scripts/     /opt/system-o/scripts/
COPY extensions/  /opt/system-o/extensions/
COPY templates/   /opt/system-o/templates/
COPY spec/wrap-tail-repair.example.yaml /opt/system-o/wrap-tail-repair.example.yaml
COPY docker/entrypoint.ps1  /opt/system-o/entrypoint.ps1
COPY docker/bootstrap.ps1   /opt/system-o/bootstrap.ps1
COPY docker/crontab.example /opt/system-o/crontab.example

# Bind-mounted at runtime — see docker-compose.example.yml. Declaring the
# volume here documents the contract even for a plain `docker run`.
VOLUME ["/vault"]
ENV VAULT_ROOT=/vault
ENV AGENT_TARGET=CLAUDE.md

ENTRYPOINT ["pwsh", "-NoProfile", "-File", "/opt/system-o/entrypoint.ps1"]
