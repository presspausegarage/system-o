---
type: meta
status: draft
date: 2026-07-01
reviewed_by: fable-5
tags:
  - type/meta
  - topic/system-o
  - topic/architecture
  - topic/fable
---

# system-o architecture review — July 1, 2026 (Fable)

> **Draft — proposals only, nothing applied.** Continuation of [[2026-06-30d-system-o-fable-uplift-brainstorm]] per [[2026-07-01-system-o-fable-architecture-review]]. Run on Fable 5 as planned. Scope: system-o only (step 1 of the 3-step cycle: system-o → workspace-wide → back to system-o).

## Summary

The ask: let a frontier model (Fable) power **"looping at all levels"** — recurring review/repair/reconcile loops over system tasks, folder structure, scheduled tasks, and scripts — without breaking the vault's load-bearing commitment that **gates are local-deterministic and the LLM is a pluggable endpoint** ([[agent-portability]]).

**Verdict: the two don't conflict, and the reconciliation is already half-built.** The resolution is a single new primitive, the **loop cell**: `detect (script) → propose (LLM) → verify (script) → apply (gated)`. The LLM occupies exactly one box — the only non-deterministic one — and that box is endpoint-pluggable by construction. Fable isn't a spec dependency; it's the first and strongest *executor* of the propose role. Local quants are graded against the same verifier. This dissolves the "tiered conformance (Core/Enhanced/Fable-native)" idea from the June 30 brainstorm: capability tiers become a *measured conformance score* (verifier pass-rate per model), not a spec fork.

Second finding: the missing **"software design.md" already has a reserved slot** — the Kanban v1.0 blocker *"Spec gap: §System architecture"* (SPEC.md describes principles and two manifests but not the layered architecture). Recommendation: don't create a new standalone doc; write §System architecture into `spec/SPEC.md`, with the loop cell as its centerpiece. Skeleton proposed below. (Open question 1 confirms this with Andy before drafting spec text.)

## Findings from Wizards Handbook

Queried the corpus (18 sources: Ousterhout, Pragmatic Programmer, Evans/DDD, Fowler, Clean Code, Pocock's agentic-engineering material). What applies, mapped to this system:

1. **Gray-box delegation / deep modules.** Human (or spec) owns the interface; LLM owns the implementation inside it, verified from outside. → Each loop is a deep module: simple stable interface (findings in → proposal out), LLM internals swappable. The vault already does this for gates; extend the same stance to loops.
2. **Policy is metadata — the LLM never authors policy.** Kill-gate rules live in frontmatter/manifests, not in the agent's judgment. → Loop behavior must be declared in a **loop manifest** (declarative YAML, sibling of the existing §Transform manifest), not encoded in prompts. Directly restates agent-portability's "LLM is a participant, not the policy-maker."
3. **Never run autonomous loops on the host vault.** Pocock's sandbox warning. → The vault equivalent isn't Docker; it's **propose-only output into the existing review queue** (`proposed_*` frontmatter + `apply-proposals.ps1`). That primitive already exists for inbox triage — reuse it, don't invent a second gate.
4. **TDD as forcing function / rate of feedback is the speed limit.** A repair loop needs a failing check *before* the repair and a passing check *after*. → Only build loops where a deterministic detector and verifier already exist or are cheap to write. The wrap-tail guard is exactly this shape today (detector exists, verifier = lint).
5. **Tracer-bullet vertical slices.** One thin end-to-end loop first, then thicken. Matches the standing build-vertical preference and the slice-runbook.
6. **Ubiquitous language (CONTEXT.md).** A shared-vocabulary table saves tokens and materially improves weaker models. → The vault's jargon (handoff, wrap tail, sewerpipe, graduate, bury, radar, decide-by, risk tier, loop cell) is defined *diffusely* across conventions.md/CLAUDE.md. A compact glossary is cheap and directly serves the local-8-bit-quant migration.
7. **Smart zone (~10–20k working tokens).** Loops must be scoped to slices (one project, one handoff, one guard finding) — never "review the whole vault" in one context. Weaker models degrade first; scoping is what makes endpoint-pluggability real rather than aspirational.
8. **Warnings:** *specs-to-code is amplification, not automation* — a loop that regenerates from spec each pass compounds whatever mess exists (loops must repair in place, smallest diff). *Tactical tornado* — the LLM must not restructure chain scripts as a side effect of a repair; scope enforcement belongs in the manifest. *Temporal decomposition* — define loops by the invariant they maintain, not by their position in the nightly chain.
9. **Doc hierarchy** (what goes where — resolves overlap anxiety between SPEC/conventions/orientation files):
   | Doc | Role |
   |---|---|
   | `spec/SPEC.md` | The need + the architecture skeleton (interfaces, invariants, manifests) |
   | `conventions.md` | Standardization/discipline (naming, frontmatter tiers, lifecycle rules) |
   | `CLAUDE.md` / `AGENTS.md` | Operational harness — how *this* agent works *here* |
   | Glossary (new, small) | Ubiquitous language shared by all of the above |

## Proposed architecture changes

Specific, ordered; nothing applied in this pass.

### 1. Add §System architecture to SPEC.md (the "software design.md")

Fills the named v1.0 blocker. Proposed skeleton:

- **Layers** (already enumerated in the Kanban blocker, now +1):
  1. Vault file format — markdown + YAML frontmatter (the *published language*; stability contract)
  2. Automation chain — deterministic scripts + OS scheduler (gates live here)
  3. **Loop layer (new)** — LLM-in-the-loop maintenance cells riding on layers 1–2
  4. Editor surface — optional augmentation (Obsidian et al.)
  5. Agent harness — Claude Code / opencode / local tooling (pluggable)
  6. Optional plugins — Dataview/Templater/Kanban etc.
- **The loop cell** (canonical pattern for any LLM-in-the-loop automation):
  ```
  detect (script, deterministic) → propose (LLM, pluggable endpoint)
    → verify (script, deterministic) → apply (gated by risk tier + review queue)
  ```
  Invariants: detector and verifier are conformant scripts (same determinism guarantees as §Transform manifest: no network beyond the LLM call, byte-stable given same inputs); the propose step is the *only* non-deterministic box; a loop with no verifier is not a loop, it's vibe maintenance and is non-conformant.
- **Apply modes**, risk-tier-gated: `propose-only` (default; emits into review queue) → `auto-apply` (verifier pass + risk ≤ 2 + reversible) → never auto on risk 3.

### 2. Add §Loop manifest to SPEC.md

Declarative YAML per loop, mirroring §Transform manifest's shape and rigor:

```yaml
loop: wrap-tail-repair          # name
invariant: "every wrapped session has a session-log entry and HOME bump"
scope: ["_meta/session-log*", "_meta/HOME.md"]   # LLM may not touch outside this
detect: check-session-log.ps1    # existing guard
verify: lint-handoff-frontmatter.ps1
apply: propose-only              # propose-only | auto-apply
endpoint: $LLM_ENDPOINT          # claude CLI | ollama HTTP | any — env-configured, never hardcoded
budget: {max_context_tokens: 20000, max_calls: 3}
```

`endpoint` is env/config-resolved (the fx-engine `.env` pattern) — this is where "runs on Fable today, gemma4 tomorrow" lives. Scope enforcement and budget are script-side, not prompt-side.

### 3. Reuse the proposal queue as the loop's safety boundary

Loop proposals land as files with `proposed_*` frontmatter surfacing in HOME's "Awaiting your review," applied via `apply-proposals.ps1`. No new review machinery. This is the vault-native answer to "never run autonomous loops on the host."

### 4. First tracer-bullet loop: wrap-tail repair (recommended)

Two candidates considered:
- **(a) Wrap-tail repair** — guard (`check-session-log.ps1`) already detects missing session-log entries / stale HOME; LLM drafts the missing entry/bump as a proposal from the handoff content; existing lint verifies. Detector and verifier both already exist → purest thin slice, near-zero new deterministic code.
- (b) Kanban↔handoff reconciler — the stalled backlog item; real value but requires stable task IDs + bidirectional linking first (its own open design question). Second loop, not first.

Recommend (a). It also produces the measurement for free: run the same loop with Fable vs. gemma4:e4b and compare verifier pass-rates — the first **conformance score** datapoint (replaces the Core/Enhanced/Fable-native tiering idea with a measurement).

### 5. Ubiquitous-language glossary

One compact table (~20 terms). Placement decision belongs to the workspace pass (conventions.md §Glossary vs. standalone `_meta/GLOSSARY.md`); system-o spec then references it as a conformance artifact ("a vault ships a glossary"). Cheap, and the highest-leverage single item for the local-quant direction.

### 6. Explicitly *not* proposed

- No LLM authority over chain scripts, conventions, or spec text (policy stays human/deterministic).
- No regenerate-from-spec loops (amplification trap) — repair-in-place, smallest diff.
- No new sandbox/mirror infrastructure (OpenDev stays buried; the proposal queue is the boundary).
- o-boy/ElevenLabs voice — parked sub-thread per the June 30 handoff; untouched by this review.

## Decisions (Q+A with Andy, July 1, 2026)

All five resolved same-day; review flipped from draft to decided.

1. **Doc decision:** confirmed — §System architecture inside `spec/SPEC.md` *is* the "software design.md." No external doc exists.
2. **First loop:** wrap-tail repair. Kanban↔handoff reconciler deferred (blocked on stable task IDs + bidirectional linking).
3. **Apply-mode floor:** earned auto-apply — everything starts `propose-only`; a loop earns `auto-apply` per-manifest after N clean verifier passes, risk ≤ 2 scopes only; risk 3 never auto-applies.
4. **Build order:** workspace-first — build the loop as `_meta/scripts/` + manifest, run it for real, then write §System architecture + §Loop manifest into SPEC.md informed by the working loop.
5. **Endpoint stance:** degrade required — Fable is the quality ceiling, the configured local endpoint (gemma4) is the availability floor. Loops always run; no loop may hard-depend on frontier availability. Verifier pass-rate delta per model = the conformance measurement.

## Carries to workspace-wide pass (step 2 of the cycle)

- ~~Implement the wrap-tail repair tracer loop~~ **DONE same-day** — `_meta/loops/wrap-tail-repair.yaml` + `_meta/scripts/run-loop.ps1` + `apply-loop-proposal.ps1`; staged end-to-end pass (Fable draft → verifier → chronological apply → guard self-clear) and clean live run. See [[2026-07-01b-system-o-loop-layer-tracer]].
- ~~Extend `apply-proposals.ps1`~~ **DONE same-day** — loop-proposal walk added (proposals live in `_meta/loops/proposals/`, not `_inbox/`, so triage never touches them); HOME "Awaiting your review" gained a loop-proposals block.
- Endpoint convention: landed as the manifest `endpoints:` priority list (fable → gemma4) rather than a bare `$LLM_ENDPOINT` env var — policy-as-metadata; revisit only if a non-loop script needs the same chain.
- Still open: glossary placement + content (conventions.md vs. standalone).
- Then return to system-o (step 3): commit §System architecture + §Loop manifest spec text informed by the working loop; update README's "two things sharing a name" framing to the three-layer model (existing backlog item) at the same time.

## Reference

- [[2026-07-01-system-o-fable-architecture-review]] · [[2026-06-30d-system-o-fable-uplift-brainstorm]] — the thread
- [[agent-portability]] — gates-are-local-deterministic table; this review extends it, doesn't override it
- `apps/system-o/spec/SPEC.md` — §Transform manifest is the pattern §Loop manifest copies
- `apps/system-o/_meta/Kanban.md` — v1.0 blockers incl. the §System architecture gap
- Wizards Handbook (NotebookLM, notebook `9bf17085`) — conversation `f0e34ec0` for the underlying citations
