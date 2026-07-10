# system-o — markdown OS

> Created/Graduated: April 26, 2026 → `apps/system-o/` • Phase: pre-mvp • **Risk: 3** (highest care for destructive ops) • **Priority: 1** (ongoing, less work per sprint — long-arc, sustained investment — *"we'll keep adding resources as they make sense and continue to track with agent portability"*)

## What's the idea?

A **"markdown OS"** — the generic, installable layer of vault scaffolding, automation, conventions, plugin set, and agent-portability primitives validated at `C:\dev\` over months of operator-vault work. Not Andy's specific projects or web operation; the underlying OS-like substrate any AI-augmented operator could install fresh and run on. Bundles:

- **Vault skeleton** — folder structure, `_meta/` scaffolding, conventions, system-map, registry templates, daily-note template, idea-README template. Editor-agnostic by design (spec §System architecture layer 4) — any markdown-capable editor works against it unmodified.
- **Offline-first automation chain** — PowerShell scripts in `_meta/scripts/` (triage, sweep-handoffs, backup-dev, build-radar-digest, build-daily-report, graduate, bury, apply-proposals, plus reminder-template) configured against generic placeholders rather than hardcoded paths. **Load-bearing principle**: the OS runs without cloud or network — local Task Scheduler + local scripts only. Cloud is optional augmentation, never a dependency. This is what makes the containerization idea coherent — a "markdown OS" that requires constant cloud isn't an OS, it's a UI.
- **Recommended editor: VS Code, via Remote-SSH or a local clone.** Decided July 4, 2026, mirroring Andy's day job (VS Code is "the standard" there — a designated default, not a mandate). Concretely the better fit for this stack: Remote-SSH edits a container/VM-hosted vault live from the operator's own already-installed desktop, with no GUI app needed on the remote host at all — the exact class of problem (Electron/GPU/display-passthrough into a Linux VM) that a full day of Hyper-V DDA work couldn't cleanly solve for Obsidian. **Obsidian remains fully supported as an operator preference** — `reference/scripts/install-obsidian.ps1` installs it for anyone who wants it specifically — just no longer the augmentation layer's default suggestion.
- **Obsidian plugin set + manifest** (optional, for operators who choose Obsidian) — Dataview, Templater, Kanban, Canvas, etc., as a community-plugin spec that an installer can resolve
- **HTML / Canvas views** — `system-map.canvas`, HOME dashboard, per-project Dashboard skeletons that don't depend on user-specific content
- **Lifecycle conventions** — handoffs (verification-block mechanic), frontmatter tiers, risk tiers (1/2/3), decide-by clocks, sweep windows (7d), sewerpipe (30d), surveillance radar
- **Agent-portability stance** — gates as local-deterministic, LLM as pluggable endpoint, `CLAUDE.md` canonical for Claude with parallel `AGENTS.md` slot for other agents (deferred to OpenDev's design)

Strip the operator's specific content (projects, drafts, journal entries, business-specific tooling like webmaster, vertical workflows like email-driven editorial), leave the OS, package it for fresh install.

## Scope: three layers

**system-o is one thing in three layers** (reframed July 2, 2026, from the earlier "two things sharing a name"; the loop-cell architecture review made the split legible):

1. **Spec** — `spec/SPEC.md`. The portable contracts: layered architecture, loop cell, orientation files, transform + loop manifests, determinism guarantees. What an adopter conforms *to*, independent of any implementation.
2. **Reference implementation** — the live workspace at `C:\dev`. The automation chain, loop layer, lifecycle conventions, and guards running in production; every spec section is written from a working instance, not prospectively. *Explicitly out of scope:* Andy's own web operation (`web/webmaster/`, the sites) and vertical workflows — siblings that **use** the OS, not part of it.
3. **Distribution** — the installable bundle (future; this project at `apps/system-o/` is where that packaging engineering happens). Fresh-install scaffolding plus an onboarding process — including populating the vault's own `_meta/GLOSSARY.md` — that instantiates the spec for someone other than Andy.

The layers feed forward: the reference implementation hardens the spec; the spec is what the distribution installs. OpenDev — formerly proposed as an umbrella child on the reference-implementation side — was buried 2026-05-17 (see [[_archive/2026-Q2/opendev/tombstone|tombstone]]); no successor is currently in flight for that role.

## What problem does it solve?

- The operator-vault pattern validated here (per [[agent-portability]] and the strategic findings in handoffs [[2026-04-26d-handoff-lifecycle-portability-and-launchpad-spinoffs|04-26d]] / [[2026-04-26e-agent-portability-test-and-graduate-fixes|04-26e]]) currently has no widely-adopted name and no installable distribution. It exists only as Andy's specific instance.
- Adjacent ecosystems (PKM tools, agent harnesses, runbooks, AgentOps platforms) each cover ≤2 of the four roles the vault plays — operator manual the agent reads, operator manual the agent writes, workspace where work happens, audit log of what happened. None bundle all four.
- Without a packaged form: can't be tested by other operators, can't gather feedback that hardens the conventions, can't generate income or collaboration leverage, can't validate that the agent-portability story actually holds when removed from Andy's specific surroundings.
- Packages this as something that CAN be evaluated, forked, and pulled from — without exposing Andy's specific projects or memory.

## Smallest next step

In <2 hours: inventory **what would actually go in the bundle vs. what's user-specific**. Walk `_meta/`, `_areas/`, `_resources/`, `_inbox/`, `_journal/`, `_radar/`, `_sewerpipe/`, root-level files, and `.obsidian/` plugin config. Tag each entry: (a) framework-generic (ships in the bundle), (b) user-content (does NOT ship), (c) hybrid (ships with user-data scrubbed). The inventory IS the proto-spec — once we see the framework-vs-content split, the packaging strategy follows.

## Decision criteria

- **Graduate** signal: framework-vs-content split is cleanly separable in the inventory pass, AND at least one concrete second use case surfaces (someone other than Andy tries to install it, OR a non-Claude agent loads it as orientation, OR an external demo opportunity opens up). Move to `apps/system-o/`.
- **Bury** signal: framework is too entangled with Andy's specific content to extract cleanly without a rebuild (conventions reference user-specific projects in load-bearing ways that don't generalize), OR the audience for a packaged operator-vault is too narrow to justify maintenance burden, OR adjacent tooling lands first and covers the same ground better.

## Open questions

- ~~**Architecture vs. project — same name?**~~ Resolved July 2, 2026 by the three-layer reframe (§Scope): one name, three layers — spec / reference implementation / distribution. No split needed; the layers, not separate names, carry the distinction.
- **Distribution form** — git template repo? `npx create-systemo`-style scaffold? Downloadable installer that drops `_meta/` skeleton + conventions (and `.obsidian/` config only if the operator opts into the Obsidian layer)? Something else?
- ~~**Plugin licensing**~~ Resolved by D7 (install-time manifest, per the distribution review): third-party Obsidian plugins (Dataview, Templater, Kanban) resolve at install time with operator consent, never redistributed. Moot for the VS Code default path — plugin licensing only applies to operators who opt into the Obsidian layer.
- **`CLAUDE.md` / `AGENTS.md` story** — package can't ship Andy's specific `CLAUDE.md`, but probably ships a template version adopters customize. How does the agent-portability story (per [[agent-portability]]) land in the package?
- **Relationship to OpenDev** — OpenDev's vault-mirror approach effectively produces a generic vault artifact (vault separated from code). Is OpenDev's output the input to system-o's packaging? Or do they diverge in scope?
- **Public-availability check** — domain `system-o.org` registered (April 26, 2026); not yet pointed. Repo lives at `presspausegarage/system-o` — open question whether a dedicated `system-o` GitHub org makes sense once contributors arrive. npm package name TBD if a scaffolder ships.
- **Cross-references from sibling launchpad items** — OpenDev should reference system-o as parent umbrella once stable. Defer until system-o has its `apps/system-o/_meta/` scaffolding so the back-reference resolves cleanly.

## Notes

Captured April 26, 2026, in the same session that produced [[apps-mobile-copy-edits|mobile-copy-edits]]. The architectural concept itself emerged earlier the same day across two handoffs:

- [[2026-04-26d-handoff-lifecycle-portability-and-launchpad-spinoffs]] — first time the "five standout patterns" + "no widely-accepted term" finding landed
- [[2026-04-26e-agent-portability-test-and-graduate-fixes]] — fresh-agent portability test passed; alternative name "operator's vault" surfaced (not adopted by user); three more patterns added (#6 capture-then-route, #7 vault-as-quadral-role, #8 gates-are-local-deterministic)

**Children of system-o's umbrella** (cross-references to wire post-graduation):

Formerly in-flight, generic to the OS layer:
- [[_archive/2026-Q2/opendev/README|OpenDev]] (buried 2026-05-17 — [[_archive/2026-Q2/opendev/tombstone|tombstone]]) — vault-only mirror; was to absorb the agent-agnostic vault mission per user direction (April 26, 2026)

Folded in (no longer separate launchpad items):
- **WTS2** — rolled into system-o on April 26, 2026; tombstone at `_archive/2026-Q2/wts2/tombstone.md`. The unified offline scheduling + observability concept. User-confirmed load-bearing: *"WTS2 would be built into this system as the ps1 scripts and other bits controlling the operator os; offline automation is critical for the containerization idea."* The work continues inside system-o as the offline-first automation chain (see bundle list above).

**Explicitly siblings, not children** (use the OS, but aren't part of it):
- `web/webmaster/` — Andy's cross-site web operation; the brain of his web work
- ~~mobile-copy-edits~~ — post-edit gates for editorial QC (Phase 3 of cfladu Content QC); a vertical use case. **Archived 2026-05-02** (cascading from Syncthing decomm).

Strategic cross-references:

- [[automation_vs_calendar_clock|Automation reframes project-grind math]] — operator-bandwidth lens
- [[local_llm_direction|Local LLM direction]] — LLM as pluggable endpoint, framework portable across models
- [[conventions|Workspace conventions]] — the conventions document IS the framework spec
- [[system-map|Nightly automation chain]] — the operational diagram IS the framework's runtime model
