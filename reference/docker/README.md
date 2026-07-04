# Docker (the primary install path — distribution review D1)

"Install system-o" is `docker run` (or `docker compose up`). This image is the automation-chain **runtime** only — pwsh 7, cron, and the reference scripts/extensions/templates baked in at `/opt/system-o/`. It is not the vault. The vault is a bind mount (`/vault` by default), so you edit it with whatever's on your host: Obsidian, a plain text editor, an agent harness — none of that lives in the container (spec layers 4–5, optional and pluggable).

## Try it

Run from `reference/docker/` (the compose file's `context: ../..` expects `apps/system-o/` as the build root — the Dockerfile needs both `reference/` and `spec/` in scope):

```
cp docker-compose.example.yml docker-compose.yml
docker compose up -d
```

Or build directly without compose, from the `apps/system-o/` repo root:
```
docker build -t system-o -f reference/docker/Dockerfile .
```

First start scaffolds `./my-vault` with the locked folder taxonomy (spec §File & folder taxonomy), a starter `_meta/GLOSSARY.md`, `_meta/HOME.md`, `_meta/session-log.md`, and an orientation file (`CLAUDE.md` by default — set `AGENT_TARGET: AGENTS.md` for a non-Claude agent). Re-running `docker compose up` against an existing vault only reinstalls the crontab — it never re-scaffolds over real content (`bootstrap.ps1` checks for `_meta/session-log.md` first).

## What's NOT on by default

- **The loop layer ships inert.** `_meta/loops/wrap-tail-repair.yaml.example` has placeholder endpoints (`<your-frontier-model>`, `<your-local-model>`) — cron-ing a loop that fail-closes every night out of the box would just be noise. Edit it, rename to `.yaml`, and uncomment its line in the crontab (`crontab -e` inside the container, or edit `crontab.example` and rebuild) once you've pointed it at real endpoints.
- **Extensions run, but check nothing until configured.** `run-extensions.ps1` is cron'd from minute one (read-only, no external dependency — safe by construction), but `source-drift` specifically no-ops until you add its `checks.yaml` (see `reference/extensions/source-drift/README.md`).
- **Stage 2 onboarding doesn't run here.** The bootstrap only does the deterministic stage-1 pass (distribution review D8) — scaffolding and starter files. Refining the glossary and orientation-file prose needs an agent harness pointed at `/vault`, working through `_meta/templates/onboarding-stage2.prompt.md` — intentionally outside this container's job, since it provides no agent.
- **Obsidian plugins aren't installed.** Per D7 (install-time manifest), plugin resolution happens on the host side where Obsidian actually runs — this container has no opinion on your editor.
- **Obsidian itself isn't installed either.** If your host is Linux and doesn't already have it, `reference/scripts/install-obsidian.ps1` resolves the current release dynamically from GitHub (never a pinned version), verifies the download against GitHub's own recorded checksum for that asset, and installs the AppImage (Obsidian publishes no native `.rpm`, so AppImage is the one path that works on any distro; pass `-PreferDeb` for a native `.deb` install on Debian-family hosts).

## Signal handling

Run with `--init` (`docker run --init ...`, or `init: true` in compose — already set in the example). pwsh as PID 1 doesn't reliably forward `SIGTERM` to `cron` on its own; Docker's built-in init does this correctly, so that's what's used rather than a hand-rolled trap.

## Verified

Build/run-tested for real on a Rocky Linux 9 Hyper-V VM (2026-07-03) — found and fixed a genuine build-context bug on the first attempt (see git history), then a clean build + run: bootstrap scaffolded the bind-mounted vault correctly (checked on the VM host filesystem, not just container-internal), crontab installed with `$VAULT_ROOT` substituted correctly, and manually firing the cron command reproduced the same result as the earlier Windows-side simulation. One operational note found during that test: the bootstrap runs as root inside the container, so the bind-mounted vault on the host ends up root-owned — if you plan to work in the vault as a non-root host user (including running an agent harness there), `chown -R` it to that user after first start.
