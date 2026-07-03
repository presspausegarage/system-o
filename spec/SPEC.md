# system-o specification — v0.1 draft

> **Status:** draft — sections committed as drafted; remaining 6 of 10 v1.0 sections in progress.
> **Form:** single file; hard ceiling 1500 lines, target 600–800. Split into modules above ceiling.
> **Scope:** portable spec layer only — no reference-implementation detail, no distribution mechanics.

---

## § System architecture

### Purpose

The system is layered so an adopter can reason about what they may swap without breaking conformance. Each layer has a stability contract; everything above layer 2 is replaceable. The layered model is also the boundary map for the spec itself: the spec constrains layers 1–3 and the interfaces into 4–6; it does not specify editors, agents, or plugins.

### Layers

| # | Layer | Contract | Swappable |
|---|---|---|---|
| 1 | **Vault file format** — markdown + YAML frontmatter | The published language. Stability contract for every other layer. | No — this is the spec's foundation |
| 2 | **Automation chain** — deterministic scripts + OS scheduler | Gates live here; each gate meets the determinism guarantees of the manifest it implements. The scheduler is host-native. | Per-OS reimplementation; behavior fixed by spec |
| 3 | **Loop layer** — LLM-in-the-loop maintenance cells riding on layers 1–2 | Policy declared in loop manifests (§Loop manifest); the LLM is a pluggable endpoint, never the policy-maker. | Endpoints swap freely; cells conform or don't run |
| 4 | **Editor surface** — Obsidian et al. | Optional augmentation. The vault must remain fully operable without it. | Yes, entirely |
| 5 | **Agent harness** — Claude Code, opencode, local tooling | Oriented via §Agent orientation files. | Yes — this is the portability goal |
| 6 | **Optional plugins** — Dataview, Templater, Kanban render | Render-only. No load-bearing state may live in a plugin. | Yes, entirely |

### The loop cell

The canonical pattern for any LLM-in-the-loop automation. Nothing at layer 3 may take another shape.

```
detect (script, deterministic) → propose (LLM, pluggable endpoint)
  → verify (script, deterministic) → apply (gated)
```

Invariants:

- The detector and verifier are conformant scripts meeting §Loop manifest's determinism guarantees; the propose call is the loop's only permitted LLM/network operation
- The propose step is the **only** non-deterministic box, and it is endpoint-pluggable by construction
- A loop with no verifier is not a loop; it is non-conformant
- Loops repair in place with the smallest sufficient diff — never regenerate content from spec or template
- Scope and budget are enforced script-side from the manifest, never prompt-side
- A loop is defined by the invariant it maintains, not by its position in any schedule

### Apply modes

| Mode | Behavior |
|---|---|
| `propose-only` | Default. Verified proposals emit into the vault's review queue for human apply/reject. |
| `auto` | Verified proposals from **trusted endpoints only** are applied inline by the runner; all others stay in the review queue. |

Gating rules:

- Every loop starts `propose-only`. `auto` is earned on recorded evidence, and a human flips the field
- Trust is **per endpoint**: the manifest carries an allowlist, and a verified proposal auto-applies only when the endpoint that served it is on that list
- Auto-apply is permitted only on scopes at risk tier ≤ 2; risk-3 scopes never auto-apply
- Structural verification is not content fidelity. The verifier proves shape; faithfulness of unreviewed content is what the endpoint allowlist gates, and the review queue remains the fidelity check for every endpoint off the list

### Measured conformance

There are no capability tiers. A model's standing is its measured record against the loop's deterministic verifier — pass-rate per endpoint, kept in the loop's records (ledger and run log) — plus reviewed faithfulness evidence where auto-apply is at stake. Endpoint ranking, allowlisting, and demotion are evidence decisions, not spec forks.

### Endpoint degradation

Degradation is required design, not a fallback courtesy:

- Every loop declares an endpoint priority chain: quality ceiling first, local availability floor last
- The chain advances on transport failure **or** verification failure
- No loop may hard-depend on frontier availability; the floor endpoint keeps every loop runnable
- If all endpoints fail, the loop **fails closed**: no output, target files untouched, the failure recorded

### Shared vocabulary

A conforming vault ships a glossary (`_meta/GLOSSARY.md`): one compact table of the vault's ubiquitous language (~20 terms). The glossary is a conformance artifact, not fixed vocabulary — its terms are defined by the operator during onboarding. Loop prompt templates and orientation files reference glossary terms rather than re-defining them.

---

## § File & folder taxonomy

### Purpose

What a fresh vault needs before anything else conforms: the minimum folder set the reference scripts already depend on, and the line between what's locked (fixed by spec) and what an adopter names themselves. This is the compact, implementation-derived core — written from what the shipped reference actually requires, not an exhaustive taxonomy essay.

### Locked

Every conforming vault has these, at these paths, holding this role. Adopters do not rename them.

| Path | Role |
|---|---|
| `_meta/registry/` | One card per project (spec §Loop manifest's `run-loop.ps1`, `build-static-home.ps1` read this as canonical) |
| `_meta/handoffs/` | Session-close records; `_archive/handoffs/` is their long-term home once swept |
| `_meta/session-log.md` | Chronological index; newest-at-top |
| `_meta/HOME.md` | The workspace dashboard; carries an `updated:` stamp checked against the session log |
| `_meta/loops/` | Loop manifests; `_meta/loops/proposals/` and `_meta/loops/<name>.ledger.jsonl` are runner-owned artifacts beneath it |
| `_meta/extensions/` | One directory per extension (spec §Extension surface) |
| `_meta/scripts/` | Automation-chain scripts (layer 2) |
| `_meta/templates/` | Script-consumed templates (loop prompts, orientation-file scaffolds) |
| `_meta/logs/` | Run logs for the automation chain and loop runners |
| `_inbox/` | Capture pad; triage or an adopter's own routing empties it |
| `_sewerpipe/` | Retention window before hard delete; the applier moves rejected loop proposals here if present |
| `CLAUDE.md` or `AGENTS.md` (workspace root) | The canonical orientation file (spec §Agent orientation files) |

### Adopter-named

Category roots (what an adopter calls their projects: `web/`, `apps/`, `games/`, or any other top-level split) are **not** prescribed. The reference scripts discover them dynamically — `detect-wrap-tail.ps1`'s commit scan walks any top-level directory containing a `.git` folder; `build-static-home.ps1` groups by whatever `category:` values are actually present in the registry. An adopter may add, rename, or restructure these roots freely; only the locked set above is fixed.

### Determinism guarantees

- A conforming vault has every locked path present (empty is fine; absent is not)
- No reference script hardcodes a category-root name

### Out of scope (post-v1.0)

- Folder semantics (who writes, who reads, never-touch invariants per path) — a fuller treatment than this compact core
- Frontmatter rules, lifecycle state machines, inbox routing rules, registry schema, risk/priority schemas, canonical vocabulary as dedicated sections — currently covered piecemeal by other sections and `_meta/GLOSSARY.md`; consolidating them is separate future work

---

## § Agent orientation files

### Purpose

The orientation file is the workspace's entry point for any agent. It is read on session start and used to orient before acting. It carries the workspace map, conventions, lifecycle rules, project risk levels, command vocabulary, and pointers to deeper documentation.

### Filename convention

| Agent | Filename | Load behavior |
|---|---|---|
| Claude Code | `CLAUDE.md` | Auto-loaded on session start |
| Codex CLI | `AGENTS.md` | Read per agent's own convention |
| Aider | `AGENTS.md` | Read per agent's own convention |
| Other / fallback | `AGENTS.md` | Default for any non-Claude agent |

`AGENTS.md` is the canonical filename for non-Claude agents. The spec follows the open convention already used by Codex and Aider.

### Source-of-truth rule

A vault must have **exactly one** canonical orientation file at the workspace root. All other agent-orientation files at that level are generated by transform from the canonical source.

The canonical source is whichever filename matches the **primary agent** for that vault:

- Claude Code as primary → `CLAUDE.md` is canonical; `AGENTS.md` (if present) is generated
- Non-Claude agent as primary → `AGENTS.md` is canonical; `CLAUDE.md` (if present) is generated

Same rule applies at subtree level: each subtree's canonical orientation file follows the workspace's primary-agent choice.

### Cascade behavior

- The workspace-root orientation file applies during work anywhere in the vault unless a closer file overrides it
- A subtree orientation file at a project root **replaces** the parent during work inside that subtree — first-found wins, never concatenated
- Removing a per-project orientation file breaks subtree context for that project; do not remove unless replacing

### Author's working vault stays clean

Adopters must not author both `CLAUDE.md` and `AGENTS.md` in the same vault. Generated parallels live only in:

- Fresh-install bundles
- OpenDev-style vault-only mirrors (code-stripped artifacts intended for non-primary agents)
- Release artifacts

The author's working vault carries one orientation file per scope (workspace + each subtree) — the canonical one.

### Generation rules

The non-canonical orientation file is produced by deterministic transform from the canonical source. Per *gates are local-deterministic*, the transform is a script + manifest; it must not use LLM judgment to author content.

The transform applies three operation types:

1. **Token renames** — substitutions from manifest (e.g., `Claude` → `the agent`, `Claude Code` → `your agent harness`)
2. **Path overrides** — file path remappings (e.g., `~/.claude/projects/.../memory/` → `_meta/agent-context/`)
3. **Section edits** — remove or replace whole sections that don't apply to the target agent

Transform manifest format is specified in §Transform manifest. Reference implementation lives at `reference/scripts/transform-orientation.ps1`.

### Out of scope (post-v1.0)

- Per-agent files beyond `AGENTS.md` (`.aider`, `.codex`, etc.) — fragmentation; AGENTS.md serves as the open-convention default
- Bidirectional sync — not needed; one-way transform from canonical source is sufficient
- Multi-canonical setups (both files authored, kept in manual sync) — explicitly disallowed

---

## § Transform manifest

### Purpose

The transform manifest is a YAML file declaring how the canonical orientation file is transformed into a non-canonical parallel. It is consumed by the transform script. Per *gates are local-deterministic*, the manifest is purely declarative — no embedded code, no LLM-driven content.

### Location

Adopters keep their manifest at `_meta/agent-context/transform-<source>-to-<target>.yaml`. The spec ships a canonical example at `apps/system-o/spec/transform-claude-to-agents.example.yaml`.

### Schema

```yaml
source: <filename>     # required, e.g. "CLAUDE.md"
target: <filename>     # required, e.g. "AGENTS.md"
renames: [...]         # optional — token-level string substitutions
paths: [...]           # optional — file path substitutions
sections: [...]        # optional — section-level structural edits
```

### `renames` — token-level substitutions

Order within the block matters. Place longer/more-specific patterns first to prevent partial-overlap bugs.

| Field | Required | Default | Meaning |
|---|---|---|---|
| `from` | yes | — | Literal string. No regex. |
| `to` | yes | — | Replacement string. |
| `case_sensitive` | no | `true` | When `false`, case-insensitive match with **case-preserving** replacement. |
| `word_boundary` | no | `true` | When `true`, matches only at word boundaries (`\b`). Prevents "Claude" matching inside "ClaudeBot". |

### `paths` — file path substitutions

Same semantics as `renames`, kept separate for intent. `word_boundary` defaults to `false` here since paths are typically substring-matched.

### `sections` — structural edits

A section is defined as a header line plus content up to (but not including) the next same-or-higher-level header.

| Field | Required | Meaning |
|---|---|---|
| `action` | yes | One of: `remove`, `replace`, `remove_lines_matching` |
| `header` | for remove / replace | Exact header text, without `#` markers |
| `level` | for remove / replace | Header level (2 = `##`, etc.) — required to disambiguate same-named headers at different levels |
| `with` | for replace | Replacement *body*. The header itself is preserved; only content under it is replaced. |
| `pattern` | for remove_lines_matching | Regex matching whole lines (anchored). Applied globally. |
| `reason` | optional | Free-text comment; ignored by the transform |

Section boundaries:
- Starts at its header line (inclusive)
- Ends at the next same-or-higher-level header (exclusive)
- Document end terminates the section

### Operation order (fixed)

The transform script applies operations in this order, and manifests cannot override it:

1. **`sections` first** — structural edits before content rewrites
2. **`paths` second** — more specific than generic renames
3. **`renames` last** — most general

### Determinism guarantees

Conformance requirements for any transform script implementation:

- Same input + same manifest → byte-identical output (modulo trailing newline normalization)
- No external network calls
- No LLM invocation
- No filesystem writes outside the target file

### Out of scope (post-v1.0)

- Multi-target manifests (one manifest emitting multiple agent files in one pass)
- Conditional operations (`if target == "aider"`)
- Includes / inheritance between manifests
- Regex in the `from` field (literal matching is sufficient)

---

## § Loop manifest

### Purpose

The loop manifest is a YAML file declaring one loop cell (§System architecture): the invariant it maintains, the paths it may touch, its detector and verifier, its apply policy, and its endpoint chain. It is consumed by the loop runner. Policy lives **here** — never in prompts, never in runner code. Per *gates are local-deterministic*, the manifest is purely declarative.

### Location

- Manifests: `_meta/loops/<loop-name>.yaml`, one per loop
- Proposals: `_meta/loops/proposals/` — deliberately **not** any capture/triage-owned path, so ingestion automation never sweeps machine-generated proposals
- Ledger: `_meta/loops/<loop-name>.ledger.jsonl`, append-only
- Prompt templates: script-consumed artifacts; they live with the vault's other script-consumed templates, referenced by filename from the manifest

### Schema

```yaml
loop: <name>                    # required
invariant: <sentence>           # required — the condition this loop maintains
scope:                          # required — the ONLY paths a proposal may target
  - <vault-relative path>
detect:                         # required — deterministic detector
  script: <script name>
  args: <arguments>
verify: <verifier id>           # required — deterministic structural check
apply: <mode>                   # required — propose-only | auto (§System architecture)
auto_apply_endpoints:           # required when apply: auto — the endpoint trust allowlist
  - <driver>/<model>
  - deterministic               # non-LLM repairs the runner computes itself
promote_after: <N>              # evidence threshold recorded for the apply-mode flip
endpoints:                      # required — priority order: quality ceiling → local floor
  - driver: <driver id>         # e.g. a CLI driver
    model: <model>
    timeout_sec: <N>
  - driver: <driver id>         # e.g. an HTTP driver
    url: <endpoint url>
    model: <model>
    num_ctx: <N>
    timeout_sec: <N>
budget:
  max_prompt_chars: <N>         # oversize source material is truncated deterministically
  max_calls_per_run: <N>        # remaining findings defer to the next run
prompt: <template filename>     # required — the propose step's prompt template
```

| Field | Required | Meaning |
|---|---|---|
| `scope` | yes | Enforced by the runner and the applier, script-side. A proposal targeting any path outside `scope` is rejected regardless of verifier outcome. |
| `apply` | yes | `propose-only` emits into the review queue; `auto` applies inline for allowlisted endpoints only. |
| `auto_apply_endpoints` | when `auto` | Trust list keyed by serving endpoint. `deterministic` denotes repairs computed without an LLM. |
| `promote_after` | no | The clean-pass threshold the apply-mode flip was (or will be) earned against; documentation of evidence, not automation — a human flips `apply`. |
| `endpoints` | yes | Tried in order. The accepted proposal records which endpoint served it. |
| `budget` | no | Caps enforced script-side before and during the propose step. |
| `prompt` | yes | The propose step's template; the propose step cannot run without it. |

### Runner semantics

Conformance requirements for any loop-runner implementation:

- The endpoint chain advances on transport failure **or** verification failure; per finding, each endpoint gets one attempt
- All endpoints failing = fail-closed: no proposal, target files untouched, a failure record appended to the ledger
- Idempotency: a finding whose proposal is already pending is skipped — no duplicate proposals, no duplicate LLM calls
- Auto-apply failures leave the proposal pending in the review queue; they never retry destructively
- A repair that deterministically creates a new finding inside the same loop's scope is **proposed** in the same run — and applied where the apply mode and allowlist permit — not deferred to the next
- Every proposal event (emitted, applied, rejected) appends one ledger record; the ledger, together with the run log's per-endpoint attempt record, is the evidence base for apply-mode promotion and endpoint trust
- Ledger records are JSON objects parsed by key; consumers must not depend on key order or line position

### Determinism guarantees

- Given identical vault state and manifest, the detector and verifier produce identical findings and verdicts
- The propose call is the loop's only network/LLM operation
- The verifier is pure: it writes nothing
- The runner writes only inside `scope` (on apply) and to the loop's own artifacts (proposals, ledger, run log)

### Out of scope (post-v1.0)

- Cross-loop orchestration (ordering or dependencies between loops)
- Per-finding endpoint routing (the chain is declared per loop)
- Retry-within-endpoint policies (one attempt per endpoint per finding)
- LLM-authored or LLM-modified manifests — policy stays human-authored

---

## § Extension surface

### Purpose

Confirmed as the extension surface for adopters; formalized here (schema was open at spec-enumeration time). Full conformance has no minimum-viable tier — a vault either conforms or it doesn't — but conformance is not the same claim as "closed." An adopter's own domain checks (a trading system's heartbeat, an integration's auth-lapse detector, a project's doc-freshness gate) are exactly the kind of enhancement the reference implementation is built from, and stripping them out of a portable spec is not a verdict that they're clutter — it's the locked/extendable cleave doing its job. This section exists so that cleave is a documented contract, not a silent omission.

### Locked vs. extendable

| Surface | Status | Rule |
|---|---|---|
| Folder taxonomy, canonical vocabulary (§Shared vocabulary) | Locked | Fixed by spec |
| Operating principles, state machines (handoff lifecycle, risk tiers, apply modes) | Locked | Fixed by spec |
| Frontmatter | Extendable | Adopters may add fields; required fields cannot be removed |
| Templates | Extendable | Adopters may add types |
| Scripts | Extendable | Adopters may add automation |
| Folders | Extendable | Adopters may add new folders under existing roots; canonical roots cannot be renamed |

Extensions are how "extendable scripts" and "extendable folders" combine into one addressable surface, rather than ad hoc bolt-ons with no shared contract.

### Location

`_meta/extensions/<name>/`, one directory per extension:

```
_meta/extensions/<name>/
  check.ps1     # required — the extension's detector
  README.md     # required — one-line purpose + what it flags, for human-facing surfaces
```

### `check.ps1` contract

An extension check is a **heartbeat**, not a gate and not a loop cell:

- Accepts `-Root` and `-DryRun`; a conforming extension performs no writes when `-DryRun` is passed, and its default behavior needs no other flag to run safely
- Read-only against everything outside its own extension directory — an extension never targets loop `scope:` paths or writes vault content; that is loop-cell territory (§Loop manifest), not heartbeat territory
- Always exits `0` — an extension can flag a problem, it cannot fail the chain
- Emits one machine-readable summary line: `EXTENSION-STATUS name=<name> flagged=<true|false>` (mirrors the `STATUS` line convention used elsewhere in the automation chain), plus any number of human-readable detail lines above it
- No LLM invocation, no non-local network calls beyond what the extension's own domain legitimately requires (e.g. checking a self-hosted endpoint is reachable) — extensions inherit the automation chain's determinism stance, not the loop layer's pluggable-endpoint one

### Discovery and aggregation

A conforming reference implementation ships one runner that discovers every `_meta/extensions/*/check.ps1`, invokes each with `-Root -DryRun`, and aggregates their `EXTENSION-STATUS` lines into a single heartbeat summary — the same role the nightly automation chain plays for its own built-in checks. Aggregation is generic: adding an extension requires no change to the runner or to any other extension.

### Determinism guarantees

- Given identical vault state, an extension's findings are identical
- An extension never writes outside its own directory except a heartbeat log, if it keeps one
- A failing or missing extension does not abort discovery of the others

### Out of scope (post-v1.0)

- Extension dependency ordering (extensions are independent by construction)
- A manifest/marketplace format for distributing third-party extensions
- Extensions that gate the chain (exit nonzero) — a check that must block belongs in the automation chain proper, not the extension surface
