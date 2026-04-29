---
kanban-plugin: board
type: kanban
parent: "[[apps-system-o]]"
tags:
  - type/kanban
  - site/system-o
---
## Backlog

- [ ] Spec gap: agent-context bundle structure (`_meta/agent-context/` schema)
- [ ] Spec gap: template manifest (canonical set of templates spec ships)
- [ ] Specify `_meta/extensions/<name>/` schema (extension surface for adopters)
- [ ] Confirm locked-vs-extendable surface cleave (proposed in 04-27 handoff)
- [ ] v1.0 conformance test: clean Windows VM install + 1-day run
- [ ] `_journal/` mechanic correction in `_meta/conventions.md` (manual writes at top, carry forward)
- [ ] Update `apps/system-o/README.md` to reflect three-layer model (replace "two things sharing a name" framing)
- [ ] Decide where `reference/` lives (likely `apps/system-o/reference/`)
- [ ] **Open design question — Kanban→handoff auto-verification.** Should marking a Kanban task `[x]` auto-flip a related handoff to `status: complete` (vs. today's manual `verification:` citation)? Requires stable task IDs, bidirectional linking (handoffs → tasks, tasks → handoffs), and a reconciler. Solo-operator value is real; complexity is non-trivial. Currently solved at the doc layer: `task:` is a recognized `verification:` type and the lint cross-checks the cited Kanban entry is actually `[x]` (see `_meta/scripts/lint-handoff-frontmatter.ps1`). Decide whether v1.0 spec should formalize the bidirectional case or leave the manual citation as-is. Surfaced from 2026-04-28 session.
- [ ] **Reference primitive — frontmatter `updated:` auto-sync.** Workspace ships `_meta/scripts/bump-updated-field.ps1` that aligns each note's `updated:` field with file mtime. Idempotent pure transform, scoped to author-edited dirs (excludes `_journal/`, `_archive/`, etc.), preserves quoting style and mtime so it doesn't retrigger itself. Fits system-o's "schema applied by automation, not human" principle. Candidate for `reference/scripts/` once that path is decided. Currently wired into the nightly chain via `sweep-handoffs.ps1` tail (sweep → bump → lint). Surfaced from 2026-04-28 session.
- [ ] Public release scrub of `presspausegarage/system-o` repo (now urgent — `github` command on live site links to a private repo)
- [ ] Add `tree` command to landing terminal once §File & folder taxonomy is locked in SPEC.md
- [ ] Wire `o-boy` audit to live data (read `_meta/logs/qa-status.json` emitted by PowerShell chain) — post-v1.0
- [ ] Draft §ISO alignment section in SPEC.md using "sources" (data, feeds, APIs) framing — locked terminology, not "suppliers"

## Active

- [ ] Implement `reference/scripts/transform-orientation.ps1` against manifest schema (next-session pickup, see [[2026-04-27-system-o-spec-agent-orientation|04-27 handoff]])
- [ ] Commit drafted spec text to `apps/system-o/spec/SPEC.md` (sections: Agent orientation files, Transform manifest)

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

**Complete**

%% kanban:settings
```
{"kanban-plugin":"board","list-collapse":[false,false,false,false]}
```
%%
