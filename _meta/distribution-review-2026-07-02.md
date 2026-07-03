---
type: meta
status: decided
date: 2026-07-02
tags:
  - type/meta
  - topic/system-o
  - topic/distribution
---

# system-o distribution review — July 2, 2026

> **Status: decided — Q+A with Andy completed same day (fable-reviewed).** Successor to [[architecture-review-2026-07-01|the loop-cell architecture review]]; second big design pass of the fable window. Scope: the v1.0/pre-public blocker cluster on the [[Kanban|system-o Kanban]] — all distribution-layer decisions. All eight resolved below.

## Scope

The seven interlocking v1.0 blockers, treated as one design problem: **what does "install system-o" mean, on what platforms, with what editor assumptions, verified how?** Per the three-layer reframe (README §Scope), this is the distribution layer's founding design pass — spec and reference implementation are now solid enough to package against.

## Inputs

- `cross-runtime-audit-2026-07-02.md` — per-script Windows-surface findings + framework/operator/hybrid bundle classification (44 scripts; also discharges the README "smallest next step" inventory for `_meta/scripts/`)
- `spec/SPEC.md` §System architecture — the six-layer table; distribution installs layers 1–3, declares 4–6
- README §Scope (three layers) + §Open questions (distribution form, plugin licensing, CLAUDE.md/AGENTS.md story, OpenDev relationship)
- `_meta/GLOSSARY.md` — onboarding must populate an operator glossary (decided July 2, 2026)

## Decisions to resolve

1. **D1 — Packaging primary path.** git template repo / `npx create-`-style scaffolder / bootstrap script on clone / devcontainer / tarball. Multiple paths likely ship; spec must name ONE primary. Interlocks: D2 (matrix), D7 (plugins can't be redistributed → install-time resolution favors scaffolder/bootstrap shapes).
2. **D2 — OS support matrix for v1.0.** (a) OS-agnostic reference via pwsh 7 + scheduler abstraction, (b) per-OS reference impls under one spec, (c) Windows-declared-reference, Linux/macOS v1.1+. **Audit verdict is in (see [[cross-runtime-audit-2026-07-02]]): (a) is cheap** — 14 of 15 framework-generic scripts are clean/shimmable, the dominant surface is one mechanical separator pattern (118 of ~200 findings, lintable), all structural Windows locks live in operator-only tooling that never ships, and the sole per-OS engine seam is backup (robocopy↔rsync).
3. **D3 — Scheduler abstraction.** Task Scheduler ↔ cron/systemd/launchd mapping for the nightly chain. The chain's *ordering* semantics (02:00→03:30 dependency order) are spec content; the trigger mechanism is layer-2 host-native. Depends directly on D2 + audit's scheduled-task-cmdlet findings.
4. **D4 — Editor independence.** Kanban card already leans (a): spec defines core (any editor) + Obsidian-augmented (optional layer). Implies a static-generated HOME.md fallback for the Dataview blocks and declaring Canvas views augmentation-only. Confirm (a) and scope the fallback's cost, or accept Obsidian as v1.0 dependency.
5. **D5 — Codespaces path.** Devcontainer pre-installing pwsh + git + a local-LLM-or-none story; the real question is vault persistence across ephemeral spins (cloned repo vs volume) and what daily-note continuity means there. May be demoted to post-v1.0 by D2.
6. **D6 — Conformance test matrix.** "Clean VM, install, run 1 day, conventions hold" — expanded to whichever targets D2 declares supported, each passing independently. Also: does the loop layer join the v1.0 conformance test (a conforming install can run a loop cell against a local endpoint), or is layer 3 optional-at-install?
7. **D7 — Plugin licensing.** Third-party Obsidian plugins can't be redistributed: install-time manifest resolution vs documented prerequisite. Collapses to trivial if D4 lands on core+augmented (plugins live entirely in the optional layer).
8. **D8 — Onboarding process design.** New since the glossary decision: onboarding populates `_meta/GLOSSARY.md` (operator's own terms), instantiates the orientation-file template (the CLAUDE.md/AGENTS.md story from README open questions), sets vault root + schedule registration. Decide the shape: interactive script? guided first-session with an agent? checklist doc? This is also where the transform manifest gets its per-adopter source/target choice.

## Constraints (standing, not up for re-decision)

- **Offline-first is load-bearing** — the OS runs without cloud or network; cloud (incl. frontier LLM endpoints) is augmentation, never dependency. Degrade-to-local is spec law (SPEC §Endpoint degradation).
- **OSS by design** — no paid tiers, no hosted wrap; distribution decisions must not smuggle in monetization shapes.
- **pwsh 7 is the scripting baseline** — cross-runtime portability is exactly this project's scope; no 5.1 compat contortions.
- **Unsigned binaries for pilot** — no code-signing dependency in any packaging path.
- **Leanness** — prefer fewer artifacts; the bundle is a skeleton plus conventions, not a product install.

## Findings

1. **Portability is a solved problem for the shippable set** ([[cross-runtime-audit-2026-07-02]]): 14/15 framework-generic scripts clean or shimmable; the dominant surface is one lintable separator pattern; every structural Windows lock lives in operator-only tooling; backup's robocopy engine is the sole per-OS seam.
2. **Containerization was always latent in the concept** — README's offline-first framing ("what makes the containerization idea coherent") predates this review. The load-bearing seam: the **vault cannot live inside the container** — operators edit it with host tools (Obsidian, agents, any editor) — so any Docker shape is *chain runtime against a bind-mounted host vault*. Interactive lifecycle scripts (graduate, bury, apply-proposals) run host-side pwsh or `docker exec`; both work per the audit.
3. **Docker-primary dissolves D3**: cron inside the container is the scheduler; per-OS Task Scheduler/launchd registration drops to alternative-path documentation. It also makes the backup seam natural (rsync in-container; robocopy stays native-Windows-path only).
4. **Loops-in-conformance needs no LLM**: a deterministic stub endpoint driver (canned proposals) exercises the full cell — detect, propose, verify, apply, fail-closed — keeping conformance offline and deterministic; real endpoints are operator config graded by measured conformance in production.
5. Noted risk, accepted knowingly: Docker Desktop + WSL2 on Windows hosts is heavyweight and was purged from the operator's own box for stability — the reference implementation itself runs the native path. Reference ≠ primary distribution; both are conformant.

## Decisions (Q+A with Andy, July 2, 2026)

1. **D1 — Docker is THE primary, full stop.** "Install system-o" = `docker run`: first start scaffolds the vault into a bind mount and runs onboarding inside the container; cron inside the container is the scheduler. Template-repo internals exist beneath (the image has to carry the skeleton) but the *product answer* is the container. Native host scheduling (what the reference box runs) remains a documented, conformant alternative path.
2. **D2 — OS-agnostic reference via pwsh 7** (from the audit; pre-Q+A). One codebase, separator lint + vault-root resolver + TEMP shim; no per-OS forks of chain logic.
3. **D3 — dissolved by D1**: scheduler = cron in the container on the primary path; native registration scripts are per-OS alternative documentation, not spec surface.
4. **D4 — Core + Obsidian-augmented.** Spec core = fully operable with any editor; Obsidian layer (Dataview HOME, Canvas, Templater, Kanban render) optional. Requires a static-HOME generator as the Dataview fallback.
5. **D5 — Codespaces: roadmap, not v1.0.** Andy: insufficient basis to call it a desirable target — future enhancement. (Supersedes the Codespaces element of the earlier D6 selection.)
6. **D6 — Conformance matrix**: the Docker primary path passes the install-and-run-1-day test from a Windows host and a Linux host, plus the Windows-native reference path (continuously proven by the operator's own box). **Loop layer is required conformance**, tested against the **stub endpoint driver** (deterministic, offline); real model endpoints are never a conformance dependency.
7. **D7 — Plugins: install-time manifest.** Bundle ships a manifest; onboarding resolves community plugins at install time with operator consent. Entirely within the optional Obsidian layer per D4 — nothing redistributed.
8. **D8 — Onboarding: deterministic bootstrap + optional agent pass.** Stage 1 (required, in-container on first start): pwsh bootstrap prompts for vault root/bind mount, plugin consent, scaffolds `_meta/GLOSSARY.md` and the orientation file from templates with prompted placeholders. Stage 2 (optional): a guided first agent session refines glossary terms and orientation prose. The agent is never an install dependency — gates stay deterministic.

## Build order (follows from decisions)

1. Separator lint + shims across the framework-generic set (mechanical; the audit's fix table is the worklist)
2. Stub endpoint driver in the loop runner (new `driver:` value; also useful for loop testing generally)
3. Static-HOME generator (D4 fallback)
4. Dockerfile + first-start bootstrap (D1/D8 stage 1) — the big one; includes plugin manifest (D7)
5. Conformance harness per D6; then the public-repo scrub gate re-opens
