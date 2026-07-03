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
- [ ] v1.0 conformance test: clean Windows VM install + 1-day run
- [ ] `_journal/` mechanic correction in `_meta/conventions.md` (manual writes at top, carry forward)
- [ ] **Open design question — Kanban→handoff auto-verification.** Should marking a Kanban task `[x]` auto-flip a related handoff to `status: complete` (vs. today's manual `verification:` citation)? Requires stable task IDs, bidirectional linking (handoffs → tasks, tasks → handoffs), and a reconciler. Solo-operator value is real; complexity is non-trivial. Currently solved at the doc layer: `task:` is a recognized `verification:` type and the lint cross-checks the cited Kanban entry is actually `[x]` (see `_meta/scripts/lint-handoff-frontmatter.ps1`). Decide whether v1.0 spec should formalize the bidirectional case or leave the manual citation as-is. Surfaced from 2026-04-28 session.
- [ ] **Reference primitive — frontmatter `updated:` auto-sync.** Workspace ships `_meta/scripts/bump-updated-field.ps1` that aligns each note's `updated:` field with file mtime. Idempotent pure transform, scoped to author-edited dirs (excludes `_journal/`, `_archive/`, etc.), preserves quoting style and mtime so it doesn't retrigger itself. Fits system-o's "schema applied by automation, not human" principle. Candidate for `reference/scripts/` once that path is decided. Currently wired into the nightly chain via `sweep-handoffs.ps1` tail (sweep → bump → lint). Surfaced from 2026-04-28 session.
- [ ] Public release scrub of `presspausegarage/system-o` repo (now urgent — `github` command on live site links to a private repo) — **gated on the v1.0/pre-public block below; do NOT scrub-and-flip until those are answered**

## v1.0 / pre-public release blockers (architecture + distribution)

- [ ] **Build: Dockerfile + first-start bootstrap** (D1/D8 — Docker is THE primary: vault scaffolds into bind mount, onboarding in-container incl. GLOSSARY + orientation-file prompts, cron inside; plugin manifest resolution per D7)
- [ ] **Build: separator shims** on the LIVE vault copies — lint SHIPPED 2026-07-02 (`reference/scripts/lint-portability.ps1`); its output is the worklist. Daylight pass with per-script smoke tests, not pre-nightly. (The reference/ copies get shimmed at port time regardless — this card is only about keeping live and reference from drifting.)
- [ ] **Roadmap (post-v1.0): Codespaces path** — deferred per D5 (Andy: insufficient basis to call it a target); revisit with real Codespaces experience
- [x] **PowerShell scripts cross-runtime audit** — shipped as `_meta/cross-runtime-audit-2026-07-02.md`: 44 scripts, framework core 14/15 portable (1 separator lint + root resolver + TEMP shim ≈ 90% of findings), all structural locks in operator-only tooling, backup = the one engine seam — 2026-07-02
- [ ] **v1.0 conformance test — matrix decided (D6, 2026-07-02):** Docker primary path from a Windows host AND a Linux host + the Windows-native reference path; loop layer REQUIRED, tested via stub endpoint driver (offline, deterministic). Build the harness once the Dockerfile exists.

(End v1.0 / pre-public release blockers — return to general Backlog below)
- [ ] Add `tree` command to landing terminal once §File & folder taxonomy is locked in SPEC.md
- [ ] Wire `o-boy` audit to live data (read `_meta/logs/qa-status.json` emitted by PowerShell chain) — post-v1.0
- [ ] HUD collapsed pill mode — minimal always-on state: o-boy eyes + clock, expands on click (post-v1.0)
- [ ] HUD o-boy additional expressions: `thinking` (`. .` / ` ? `), `sleep` (`- -` / ` z `), `error` (`x  x` / ` ! `) — wire `error` to pipeline non-zero status (post-v1.0)
- [ ] Draft §ISO alignment section in SPEC.md using "sources" (data, feeds, APIs) framing — locked terminology, not "suppliers"

## Active

- [ ] Loop layer next steps (workspace side): ~~ledger evidence~~ **superseded by synthetic battery + haiku cert (2026-07-01, see `_meta/loops/wrap-tail-repair-synthetic-validation-2026-07-01.md`)** — per-endpoint auto-apply LIVE (fable/haiku auto, gemma propose-only). Remaining: one real unsandboxed rep (next wrap seeds it) → wire into nightly chain as a **user** task (claude CLI auth is user-scoped, NotebookLM-push pattern) → drop fable endpoint July 6 (scheduled). Then: Kanban↔handoff reconciler as loop #2.

## Blocked

## Done

- [x] **Static-HOME generator shipped** (D4 Dataview fallback) — `reference/scripts/build-static-home.ps1`: reads `_meta/registry/*.md`, groups by whatever `category:` values are actually present (no fixed category list), emits plain-markdown tables between `<!-- STATIC-HOME:START/END -->` markers; idempotent, pipe-in-description escaped, never guesses marker placement. Rehearsed in a staged vault; caught and fixed a real cross-platform bug in the process — PowerShell's `-match`/`-notmatch` operators silently ignore `RegexOptions.Singleline`, so the marker-presence check never matched across the multi-line block (the later `[regex]::Replace` call was already correct via explicit Singleline) — 2026-07-03
- [x] **§Extension surface specified + shipped** — closes two open items from 04-27 (schema was confirmed-but-unspecified; locked-vs-extendable cleave was proposed-but-uncontested). SPEC.md §Extension surface (contract: `check.ps1` + `README.md`, `EXTENSION-STATUS` line, read-only/flag-only/exit-0-always, never a loop cell). `reference/scripts/run-extensions.ps1` (generic discovery + aggregation) + two portable worked examples (`stale-capture`, `frontmatter-type`) + a narrative gallery documenting what the STRIPPED operator-specific checks (trading-bot heartbeat, NotebookLM auth-lapse detector, nimpse doc-freshness, registry-roster drift, launchpad integrity) prove is possible — so cutting them from the reference reads as the locked/extendable cleave working, not as deleting good ideas. Rehearsed in a staged vault; caught and fixed a real gap (extension READMEs self-flagging the frontmatter check) in the process — 2026-07-03
- [x] **Loop layer ported into `reference/`** — `reference/scripts/{detect-wrap-tail,run-loop,apply-loop-proposal}.ps1`, `reference/templates/loop-wrap-tail-repair.prompt.md`, `spec/wrap-tail-repair.example.yaml`. Detector scrubbed to session-log/HOME only (drift/launchpad/frontmatter/PARA/demand-radar/notebooklm/nimpse checks stay operator-specific, not ported); generic `.git`-folder repo scan replaces the category-manifest dependency; ships `propose-only` + empty allowlist (adopter earns auto-apply, doesn't inherit Andy's). Lint-clean (one false-positive found + fixed in the lint itself: `\d`-style regex escapes no longer trip the backslash rule). Full-circle rehearsed via the stub driver in a staged vault: draft → verify → auto-apply → HOME cascade → guard self-clear — 2026-07-03
- [x] **Portability lint shipped** — `reference/scripts/lint-portability.ps1` (path-context backslash, Windows env vars, scheduler/COM cmdlets, Windows exes, review-tagged drive letters); reproduces the audit findings on the framework set — 2026-07-02
- [x] **Stub endpoint driver shipped** — `driver: stub` in the loop runner; verified full offline circle (canned entry → verify → auto-apply → cascade bump → guard clean) + fail-closed on garbage — 2026-07-02
- [x] **Distribution review decided (D1–D8)** — Docker THE primary (chain-in-container, bind-mounted vault, cron inside; dissolves scheduler abstraction), OS-agnostic pwsh 7 reference, core+Obsidian-augmented, install-time plugin manifest, stub-driver loop conformance, bootstrap+optional-agent onboarding, Codespaces → roadmap — `_meta/distribution-review-2026-07-02.md` — 2026-07-02
- [x] **Cross-runtime audit shipped** — 44 scripts, framework core 14/15 portable, all structural locks operator-only, backup = sole engine seam — `_meta/cross-runtime-audit-2026-07-02.md` — 2026-07-02
- [x] **§System architecture + §Loop manifest committed to SPEC.md** (v1.0 blocker cleared) — six-layer table, loop cell + invariants, per-endpoint apply modes, measured conformance, degrade-required, as-built manifest schema + runner semantics; written from the working loop per the workspace-first decision — 2026-07-02
- [x] README three-layer reframe: "two things sharing a name" → spec / reference implementation / distribution; "same name?" open question resolved — 2026-07-02
- [x] Glossary shipped standalone at `_meta/GLOSSARY.md` (23 terms, referenced from conventions.md + SPEC §Shared vocabulary; terms populate at onboarding in the distribution) — 2026-07-02
- [x] Loop layer hardened: per-endpoint auto-apply (`auto_apply_endpoints` allowlist) + HOME-cascade co-emit fix + 7-scenario synthetic battery (mechanics 7/7, fable 4/4 faithful, gemma 0/2) + haiku certified as post-fable ceiling (4/4 with template fidelity rules) — 2026-07-01
- [x] Fable architecture review run + decided: loop-cell pattern (detect→propose→verify→apply), §System architecture = the design doc, conformance = measured verifier pass-rate per model (replaces Core/Enhanced/Fable-native tiering) — `_meta/architecture-review-2026-07-01.md` — 2026-07-01
- [x] Loop layer tracer **shipped workspace-side**: `_meta/loops/wrap-tail-repair.yaml` + `run-loop.ps1` + `apply-loop-proposal.ps1` + apply-proposals walk + HOME review block; staged end-to-end pass (Fable draft, verifier, chronological apply, guard self-clear) + live run clean — 2026-07-01
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
- [x] Decide where `reference/` lives — `apps/system-o/reference/` (committed 2026-05-20)

**Complete**

%% kanban:settings
```
{"kanban-plugin":"board","list-collapse":[false,false,false,false]}
```
%%
