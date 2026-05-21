---
kanban-plugin: board
type: kanban
parent: "[[apps-system-o]]"
tags:
  - type/kanban
  - site/system-o
---

> Registry: [[apps-system-o]]

## Backlog

- [ ] Spec gap: agent-context bundle structure (`_meta/agent-context/` schema)
- [ ] Spec gap: template manifest (canonical set of templates spec ships)
- [ ] Specify `_meta/extensions/<name>/` schema (extension surface for adopters)
- [ ] Confirm locked-vs-extendable surface cleave (proposed in 04-27 handoff)
- [ ] v1.0 conformance test: clean Windows VM install + 1-day run
- [ ] `_journal/` mechanic correction in `_meta/conventions.md` (manual writes at top, carry forward)
- [ ] Update `apps/system-o/README.md` to reflect three-layer model (replace "two things sharing a name" framing)
- [ ] Decide where `reference/` lives — resolved: `apps/system-o/reference/` (committed 2026-05-20)
- [ ] **Open design question — Kanban→handoff auto-verification.** Should marking a Kanban task `[x]` auto-flip a related handoff to `status: complete` (vs. today's manual `verification:` citation)? Requires stable task IDs, bidirectional linking (handoffs → tasks, tasks → handoffs), and a reconciler. Solo-operator value is real; complexity is non-trivial. Currently solved at the doc layer: `task:` is a recognized `verification:` type and the lint cross-checks the cited Kanban entry is actually `[x]` (see `_meta/scripts/lint-handoff-frontmatter.ps1`). Decide whether v1.0 spec should formalize the bidirectional case or leave the manual citation as-is. Surfaced from 2026-04-28 session.
- [ ] **Reference primitive — frontmatter `updated:` auto-sync.** Workspace ships `_meta/scripts/bump-updated-field.ps1` that aligns each note's `updated:` field with file mtime. Idempotent pure transform, scoped to author-edited dirs (excludes `_journal/`, `_archive/`, etc.), preserves quoting style and mtime so it doesn't retrigger itself. Fits system-o's "schema applied by automation, not human" principle. Candidate for `reference/scripts/` once that path is decided. Currently wired into the nightly chain via `sweep-handoffs.ps1` tail (sweep → bump → lint). Surfaced from 2026-04-28 session.
- [ ] Public release scrub of `presspausegarage/system-o` repo (now urgent — `github` command on live site links to a private repo) — **gated on the v1.0/pre-public block below; do NOT scrub-and-flip until those are answered**

## v1.0 / pre-public release blockers (architecture + distribution)

- [ ] **Spec gap: §System architecture.** Spec currently describes principles, taxonomy, lifecycle, and conventions, but not the *layered architecture* — vault file format ↔ automation chain ↔ editor surface ↔ agent harness ↔ optional plugins. Without this, an adopter can't reason about which layers they can swap. Add §System architecture to SPEC.md before publishing.
- [ ] **Distribution: packaging shape.** Decide the canonical bundle. Candidates: (a) git clone + bootstrap script, (b) Docker image, (c) devcontainer for Codespaces / VS Code, (d) tarball + scaffolder, (e) some combination. Likely answer is multiple paths, but spec must state which is *primary*.
- [ ] **Distribution: cross-platform reference impl.** Current reference is Windows-only (Task Scheduler, robocopy backup, Windows paths, HKCU autostart). Decide: (a) make reference impl OS-agnostic via pwsh 7 + cron/launchd abstraction, (b) ship per-OS reference impls (Win / Linux / macOS) with single spec, (c) declare Windows the v1.0 reference and Linux/macOS as v1.1+. Each option has trade-offs for the conformance test.
- [ ] **Distribution: GitHub Codespaces path.** Devcontainer.json that pre-installs pwsh, git, ollama-or-equivalent, opens the vault. Open Q: is the "vault" in Codespaces a cloned-and-mounted repo, an ephemeral scratch, or persisted in a Codespace volume? What does daily-note continuity look like across ephemeral spins?
- [ ] **Distribution: Linux native path.** Cron replaces Task Scheduler. bash or pwsh 7 for scripts (memory says pwsh-7-default — verify it covers all current chain calls). systemd vs cron for daemon-like behavior (VaultCast). Path conventions (no drive letters, `~/dev` not `C:\dev`).
- [ ] **Editor independence — Obsidian as augmentation, not requirement.** Spec is markdown + YAML; should run editor-agnostic. Obsidian-specific surfaces today: Canvas dashboards, plugin manifest, Dataview queries on HOME, Templater. Decide: (a) spec defines core (any editor) + Obsidian-augmented (optional layer) — preferred; (b) Obsidian declared a v1.0 dependency; revisit later. (a) implies fallbacks for HOME-as-Dataview and Canvas — likely a static-generated HOME.md as default with Dataview as an upgrade.
- [ ] **PowerShell scripts cross-runtime audit.** Per `pwsh_default` memory, scripts are built for pwsh 7 (cross-runtime). Audit the whole `_meta/scripts/` set against actual Linux execution: any Windows-specific cmdlets (e.g. `Get-ScheduledTask`, COM, registry), drive-letter assumptions, line-ending assumptions, robocopy. Ship the audit findings as the v1.0 cross-platform readiness checklist.
- [ ] **v1.0 conformance test — expand from "Windows VM" to all supported targets.** Apr 27 handoff defined v1.0 as "spin clean Windows VM, install, run for one day, verify conventions hold." Now expanded: same test on (Windows native | Linux native | Codespaces). Whichever combinations are declared v1.0-supported per the cross-platform decision above must each pass independently.

(End v1.0 / pre-public release blockers — return to general Backlog below)
- [ ] Add `tree` command to landing terminal once §File & folder taxonomy is locked in SPEC.md
- [ ] Wire `o-boy` audit to live data (read `_meta/logs/qa-status.json` emitted by PowerShell chain) — post-v1.0
- [ ] HUD collapsed pill mode — minimal always-on state: o-boy eyes + clock, expands on click (post-v1.0)
- [ ] HUD o-boy additional expressions: `thinking` (`. .` / ` ? `), `sleep` (`- -` / ` z `), `error` (`x  x` / ` ! `) — wire `error` to pipeline non-zero status (post-v1.0)
- [ ] Draft §ISO alignment section in SPEC.md using "sources" (data, feeds, APIs) framing — locked terminology, not "suppliers"

## Active

## Blocked

## Done

- [x] system-o.org **live** — Cloudflare Pages, Direct Upload from `apps/system-o/dist/` (index.html + favicon.svg + robots.txt) — 2026-04-28
- [x] Top-bar removed + boot-banner box swapped to ASCII pipes (font-fallback alignment fix) — 2026-04-28
- [x] system-o.org landing page v1 shipped — interactive terminal, single-file deliverable — 2026-04-28
- [x] Locked terminology: ISO §7.4 "supplier controls" → "source controls" (data, feeds, APIs) — 2026-04-28
- [x] Architectural reframe: three-layer model (spec / reference / distribution) — 2026-04-27
- [x] v1.0 spec enumeration (10 sections + 5 gaps identified) — 2026-04-27
- [x] Drafted § Agent orientation files spec text — 2026-04-27
- [x] Drafted § Transform manifest spec text + canonical example — 2026-04-27
- [x] Confirmed cascade behavior unifies CLAUDE.md / AGENTS.md — 2026-04-27
- [x] Resolved gap: spec versioning (v1.0 = VM portability test) — 2026-04-27
- [x] Resolved gap: conformance levels (full conformance + extensions) — 2026-04-27
- [x] Resolved gap: AGENTS.md spec (filename + location + transform model) — 2026-04-27
- [x] Commit §Agent orientation files + §Transform manifest to `spec/SPEC.md` — 2026-05-20
- [x] Implement `reference/scripts/transform-orientation.ps1` (deterministic transform, tested) — 2026-05-20

**Complete**

%% kanban:settings
```
{"kanban-plugin":"board","list-collapse":[false,false,false,false]}
```
%%
