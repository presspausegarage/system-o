# Docker (the primary install path - distribution review D1)

"Install system-o" is `docker run` (or `docker compose up`). This image is the automation-chain **runtime** only - pwsh 7, cron, and the reference scripts/extensions/templates baked in at `/opt/system-o/`. It is not the vault. The vault is a bind mount (`/vault` by default), so you edit it with whatever's on your host - none of that lives in the container (spec layers 4-5, optional and pluggable).

**Recommended: VS Code, Remote-SSH into the host running the container.** This is the concrete reason it's the default suggestion for exactly this deployment shape - Remote-SSH edits the bind-mounted vault live from your own already-installed desktop, with zero GUI app needed on the container/VM side. A plain text editor over the same SSH connection works identically for the same reason. Obsidian is fully supported too if you prefer it (`reference/scripts/install-obsidian.ps1`), but it's a full Electron GUI app that needs to actually run somewhere with display output - on a headless server or a VM without GPU passthrough, that's real friction Remote-SSH simply doesn't have.

Kanban visualization is entirely bring-your-own - no board-view tool ships or is recommended; set one up yourself if you want one (e.g. an extension that reads the same markdown-checkbox format `Kanban.md` files already use). For anyone without one, `reference/scripts/build-kanban-csv.ps1` writes a `Kanban.csv` next to every `Kanban.md` it finds - one row per task, openable in any spreadsheet app or VS Code's built-in CSV preview, no extension required. Same core-without-any-editor principle as `build-static-home.ps1`'s Dataview fallback, applied to boards instead of the registry.

## Try it

Run from `reference/docker/` (the compose file's `context: ../..` expects the repo root as the build root - the Dockerfile needs both `reference/` and `spec/` in scope):

```
cp docker-compose.example.yml docker-compose.yml
# edit docker-compose.yml: point the bind mount at a vault path OUTSIDE this clone
docker compose up -d
```

Or build directly without compose, from the repo root:
```
docker build -t system-o -f reference/docker/Dockerfile .
```

**Keep the vault outside the clone** (the example mounts `~/system-o-vault`). A vault inside the source tree risks entering Git or a Docker build context; the repo-root `.dockerignore` (allowlist-style: only `reference/` and one spec file ever reach the daemon) and `.gitignore` guard the known in-clone paths, but a path outside the clone needs no guarding at all.

First start scaffolds the bind-mounted vault with the locked folder taxonomy (spec §File & folder taxonomy), a starter `_meta/GLOSSARY.md`, `_meta/HOME.md`, `_meta/session-log.md`, and an orientation file (`CLAUDE.md` by default - set `AGENT_TARGET: AGENTS.md` for a non-Claude agent, **before first boot**: the scaffold runs once, so flipping the variable later does not create the other file). Re-running `docker compose up` against an existing vault only repairs missing locked directories and reinstalls the crontab - it never re-scaffolds over real content (`bootstrap.ps1` checks for `_meta/session-log.md` first).

## Startup contract

- **A running container means a completed install.** The entrypoint fails the container when `bootstrap.ps1` exits nonzero (including a failed crontab install) instead of starting cron over a broken install; `docker logs` carries the reason.
- **Interrupted first runs self-heal.** `_meta/session-log.md` is the install-complete sentinel and is written last, so a run that dies mid-scaffold leaves no sentinel and the next start completes the missing pieces (every write is if-absent guarded).
- **Health is checked, not assumed.** The image ships a `HEALTHCHECK` (`healthcheck.ps1`): sentinel present, locked directory set present, crontab actually installed with `$VAULT_ROOT` substituted. `docker ps` shows `unhealthy` if any of that regresses.
- **Cron fires on the container clock** - UTC unless you set `TZ` (see the commented line in the compose example; tzdata ships in the image).
- **The host-side agent works at the host path.** `/vault` exists only inside the container - point your editor and any agent harness at the bind-mount source on the host (e.g. `~/system-o-vault`).

## What's NOT on by default

- **The loop layer ships inert.** `_meta/loops/wrap-tail-repair.yaml.example` has placeholder endpoints (`<your-frontier-model>`, `<your-local-model>`) - cron-ing a loop that fail-closes every night out of the box would just be noise. Edit it, rename to `.yaml`, and uncomment its line in the crontab (`crontab -e` inside the container, or edit `crontab.example` and rebuild) once you've pointed it at real endpoints.
- **Extensions run, but check nothing until configured.** `run-extensions.ps1` is cron'd from minute one (read-only, no external dependency - safe by construction), but `source-drift` specifically no-ops until you add its `checks.yaml` (see `reference/extensions/source-drift/README.md`).
- **Stage 2 onboarding doesn't run here.** The bootstrap only does the deterministic stage-1 pass (distribution review D8) - scaffolding and starter files. Refining the glossary and orientation-file prose needs an agent harness pointed at `/vault`, working through `_meta/templates/stage-2-onboarding.prompt.md` - intentionally outside this container's job, since it provides no agent.
- **No in-place framework upgrade yet.** Scripts, extensions, and templates are copied into the vault only at first bootstrap; rebuilding a newer image against an existing vault deliberately leaves the vault-local copies alone (they are the adopter's, possibly modified). Until a versioned upgrade command ships, updating an existing vault's framework files is a manual copy with your own diff/backup discipline.
- **Nothing editor-specific is installed by default** - not VS Code, not Obsidian. The recommended VS Code + Remote-SSH path needs nothing installed on this side at all (VS Code runs on your desktop; Remote-SSH is a client-side extension). If you specifically want Obsidian instead, `reference/scripts/install-obsidian.ps1` resolves the current release dynamically from GitHub (never a pinned version), verifies the download against GitHub's own recorded checksum for that asset, and installs the AppImage (Obsidian publishes no native `.rpm`, so AppImage is the one path that works on any distro; pass `-PreferDeb` for a native `.deb` install on Debian-family hosts). Per D7, its plugins resolve at install time with your consent - this container has no opinion on your editor choice either way.

## Signal handling

Run with `--init` (`docker run --init ...`, or `init: true` in compose - already set in the example). pwsh as PID 1 doesn't reliably forward `SIGTERM` to `cron` on its own; Docker's built-in init does this correctly, so that's what's used rather than a hand-rolled trap.

## Verified

Build/run-tested for real on a Rocky Linux 9 Hyper-V VM (2026-07-03) - found and fixed a genuine build-context bug on the first attempt (see git history), then a clean build + run: bootstrap scaffolded the bind-mounted vault correctly (checked on the VM host filesystem, not just container-internal), crontab installed with `$VAULT_ROOT` substituted correctly, and manually firing the cron command reproduced the same result as the earlier Windows-side simulation. One operational note found during that test: the bootstrap runs as root inside the container, so the bind-mounted vault on the host ends up root-owned - if you plan to work in the vault as a non-root host user (including running an agent harness there), `chown -R` it to that user after first start.
