# system-o specification - v0.2 draft

> **Status:** draft - 10 sections committed as drafted; remaining v1.0 sections in progress. §Loop manifest carries an explicit reference-implementation status; §Pluggability conformance test has not yet run and is the stated v1.0 gate.
> **Form:** single file; hard ceiling 1500 lines, target 600-800. Split into modules above ceiling.
> **Scope:** portable spec layer only - no reference-implementation detail, no distribution mechanics.

---

## § System architecture

### Purpose

The system is layered so an adopter can reason about what they may swap without breaking conformance. Each layer has a stability contract; everything above layer 2 is replaceable. The layered model is also the boundary map for the spec itself: the spec constrains layers 1-3 and the interfaces into 4-6; it does not specify editors, agents, or plugins.

### Layers

| # | Layer | Contract | Swappable |
|---|---|---|---|
| 1 | **Vault file format** - markdown + YAML frontmatter | The published language. Stability contract for every other layer. | No - this is the spec's foundation |
| 2 | **Automation chain** - deterministic scripts + OS scheduler | Gates live here; each gate meets the determinism guarantees of the manifest it implements. The scheduler is host-native. | Per-OS reimplementation; behavior fixed by spec |
| 3 | **Loop layer** - LLM-in-the-loop maintenance cells riding on layers 1-2 | Policy declared in loop manifests (§Loop manifest); the LLM is a pluggable endpoint, never the policy-maker. | Endpoints swap freely; cells conform or don't run |
| 4 | **Editor surface** - Obsidian et al. | Optional augmentation. The vault must remain fully operable without it. | Yes, entirely |
| 5 | **Agent harness** - Claude Code, opencode, local tooling | Oriented via §Agent orientation files. | Yes - this is the portability goal |
| 6 | **Optional plugins** - Dataview, Templater, Kanban render | Render-only. No load-bearing state may live in a plugin. | Yes, entirely |

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
- Loops repair in place with the smallest sufficient diff - never regenerate content from spec or template
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

There are no capability tiers. A model's standing is its measured record against the loop's deterministic verifier - pass-rate per endpoint, kept in the loop's records (ledger and run log) - plus reviewed faithfulness evidence where auto-apply is at stake. Endpoint ranking, allowlisting, and demotion are evidence decisions, not spec forks.

### Endpoint degradation

Degradation is required design, not a fallback courtesy:

- Every loop declares an endpoint priority chain: quality ceiling first, local availability floor last
- The chain advances on transport failure **or** verification failure
- No loop may hard-depend on frontier availability; the floor endpoint keeps every loop runnable
- If all endpoints fail, the loop **fails closed**: no output, target files untouched, the failure recorded

### Shared vocabulary

A conforming vault ships a glossary (`_meta/GLOSSARY.md`): one compact table of the vault's ubiquitous language (~20 terms). The glossary is a conformance artifact, not fixed vocabulary - its terms are defined by the operator during onboarding. Loop prompt templates and orientation files reference glossary terms rather than re-defining them.

Onboarding is two stages (distribution review D8): stage 1 is the deterministic bootstrap (scaffolds locked folders and starter files, no LLM); stage 2 is an agent-guided pass that replaces the starter glossary and orientation file with content specific to the adopter's vault, confirming genuine ambiguities rather than guessing (`reference/templates/stage-2-onboarding.prompt.md`). Stage 2 fills in the operator's answers; it never relitigates anything spec-locked.

---

## § Darkloop

### Purpose

Names the system's operating cycle so an adopter - and any surface built over the vault - can visualize what the system *does*: custody of the vault alternates between an attended session and an unattended automation pass, and every crossing between the two is a vault artifact. **Darkloop** (one word) is system-o's term of art. It deliberately diverges from the *dark factory* lineage (lights-out production, human removed): in a darkloop the operator is never removed, only **time-shifted** - the unattended pass runs while they are away and re-surfaces its evidence at a fixed re-entry point. Silence is a detectable failure, never an acceptable state.

### Definition

The darkloop is a conforming vault's unattended operating cycle: the scheduled pass in which the automation chain (layer 2), the loop layer (layer 3), and the extension heartbeats maintain the vault's invariants with no operator present, terminating in a surfacing artifact the operator reads on return.

Three properties distinguish a darkloop from a set of cron entries:

1. **Closed over the vault** - it reads vault state and writes vault state (within declared scopes, through declared gates); no side channel is load-bearing
2. **Human time-shifted, not removed** - every revolution terminates in surfacing (report + review queue); unreviewed LLM output waits in the review queue per §Apply modes
3. **Silence is detectable** - heartbeats make "didn't run" distinguishable from "ran clean"; a missing heartbeat is itself a surfaced finding

### Rings

The cycle decomposes into rings by cadence, innermost (fastest) outward, each ring's period an order of magnitude or more beyond the one it contains - true nesting, not just sequence. This is why **Chain** and **Session** share one ring rather than each taking their own: a chain run and a session are the same daily timescale, alternating within a day, not one nested inside repeated cycles of the other. Real nesting resumes at **Synthesis** (folds ~7 Day revolutions) and **Retention** (folds many Synthesis revolutions). The rings are the visualization contract: any surface presenting "what the system does" presents these rings, sized by cadence (log scale) so the seconds-to-year span reads as size, not just a list.

| Ring | Name | Cadence | Custody | One revolution |
|---|---|---|---|---|
| 0 | **Cell** | seconds-minutes, per finding | dark | detect → propose → verify → apply (§System architecture) |
| 1 | **Day** | ~24h | **split** - dark arc (chain) / light arc (session) | the daily alternation: the chain runs while dark, then the operator holds custody through a session, until the next chain |
| 2 | **Synthesis** | weekly (typical) | dark | roll-up of ~7 Day revolutions into a strategic review, read attended |
| 3 | **Retention** | multi-day → quarterly/annual | dark | sweep, purge, archive - the slowest state machines |

### Crossings

Custody transfers at exactly two points on the Day ring - where its arc changes color - and each crossing **is** a vault artifact, never an out-of-band message alone:

| Crossing | Direction | Artifact |
|---|---|---|
| **Dawn** | dark arc → light arc | The surfacing bundle: built report, review queue, heartbeat summary. The operator re-enters by reading evidence, not by trusting silence. |
| **Dusk** | light arc → dark arc | The wrap tail: handoff + session-log entry + dashboard bump. The chain audits this crossing; an incomplete wrap is a detectable finding (repairable by a loop cell), not a mystery. |

### Invariants

- Custody alternates only at crossings; every crossing leaves a durable artifact in the vault
- The dark half never blocks the light half: with the chain dead, the vault remains fully operable; the outage surfaces at the next dawn crossing as a missing heartbeat
- Rings do not redefine loops - a loop cell is still defined by the invariant it maintains, not by its position in any schedule; rings describe when revolutions occur and who is present
- Clock times are adopter-chosen and host-native; the darkloop is defined by custody and the three properties, not by the clock - an operator who fires the chain by hand at noon has still run the darkloop
- `darkloop` is spec vocabulary: defined here, referenced (never re-defined) by prompts, orientation files, and glossaries

### Out of scope (post-v1.0)

- Prescribed schedule times or scheduler syntax (host-native, per layer 2)
- A darkloop visualization UI - layer 6, render-only; candidate surface is the reference HUD
- Multi-vault or federated darkloops (one vault, one cycle)

---

## § File & folder taxonomy

### Purpose

What a fresh vault needs before anything else conforms: the minimum folder set the reference scripts already depend on, and the line between what's locked (fixed by spec) and what an adopter names themselves. This is the compact, implementation-derived core - written from what the shipped reference actually requires, not an exhaustive taxonomy essay.

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

Category roots (what an adopter calls their projects: `web/`, `apps/`, `games/`, or any other top-level split) are **not** prescribed. The reference scripts discover them dynamically - `detect-wrap-tail.ps1`'s commit scan walks any top-level directory containing a `.git` folder; `build-static-home.ps1` groups by whatever `category:` values are actually present in the registry. An adopter may add, rename, or restructure these roots freely; only the locked set above is fixed.

### Determinism guarantees

- A conforming vault has every locked path present (empty is fine; absent is not)
- No reference script hardcodes a category-root name

### Out of scope (post-v1.0)

- Folder semantics (who writes, who reads, never-touch invariants per path) - a fuller treatment than this compact core
- Frontmatter rules, lifecycle state machines, inbox routing rules, registry schema, risk/priority schemas, canonical vocabulary as dedicated sections - currently covered piecemeal by other sections and `_meta/GLOSSARY.md`; consolidating them is separate future work

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
- A subtree orientation file at a project root **replaces** the parent during work inside that subtree - first-found wins, never concatenated
- Removing a per-project orientation file breaks subtree context for that project; do not remove unless replacing

### Author's working vault stays clean

Adopters must not author both `CLAUDE.md` and `AGENTS.md` in the same vault. Generated parallels live only in:

- Fresh-install bundles
- OpenDev-style vault-only mirrors (code-stripped artifacts intended for non-primary agents)
- Release artifacts

The author's working vault carries one orientation file per scope (workspace + each subtree) - the canonical one.

### Generation rules

The non-canonical orientation file is produced by deterministic transform from the canonical source. Per *gates are local-deterministic*, the transform is a script + manifest; it must not use LLM judgment to author content.

The transform applies three operation types:

1. **Token renames** - substitutions from manifest (e.g., `Claude` → `the agent`, `Claude Code` → `your agent harness`)
2. **Path overrides** - file path remappings (e.g., `~/.claude/projects/.../memory/` → `_meta/agent-context/`)
3. **Section edits** - remove or replace whole sections that don't apply to the target agent

Transform manifest format is specified in §Transform manifest. Reference implementation lives at `reference/scripts/transform-orientation.ps1`.

### Out of scope (post-v1.0)

- Per-agent files beyond `AGENTS.md` (`.aider`, `.codex`, etc.) - fragmentation; AGENTS.md serves as the open-convention default
- Bidirectional sync - not needed; one-way transform from canonical source is sufficient
- Multi-canonical setups (both files authored, kept in manual sync) - explicitly disallowed

---

## § Transform manifest

### Purpose

The transform manifest is a YAML file declaring how the canonical orientation file is transformed into a non-canonical parallel. It is consumed by the transform script. Per *gates are local-deterministic*, the manifest is purely declarative - no embedded code, no LLM-driven content.

### Location

Adopters keep their manifest at `_meta/agent-context/transform-<source>-to-<target>.yaml`. The spec ships a canonical example at `apps/system-o/spec/transform-claude-to-agents.example.yaml`.

### Schema

```yaml
source: <filename>     # required, e.g. "CLAUDE.md"
target: <filename>     # required, e.g. "AGENTS.md"
renames: [...]         # optional - token-level string substitutions
paths: [...]           # optional - file path substitutions
sections: [...]        # optional - section-level structural edits
```

### `renames` - token-level substitutions

Order within the block matters. Place longer/more-specific patterns first to prevent partial-overlap bugs.

| Field | Required | Default | Meaning |
|---|---|---|---|
| `from` | yes | - | Literal string. No regex. |
| `to` | yes | - | Replacement string. |
| `case_sensitive` | no | `true` | When `false`, case-insensitive match with **case-preserving** replacement. |
| `word_boundary` | no | `true` | When `true`, matches only at word boundaries (`\b`). Prevents "Claude" matching inside "ClaudeBot". |

### `paths` - file path substitutions

Same semantics as `renames`, kept separate for intent. `word_boundary` defaults to `false` here since paths are typically substring-matched.

### `sections` - structural edits

A section is defined as a header line plus content up to (but not including) the next same-or-higher-level header.

| Field | Required | Meaning |
|---|---|---|
| `action` | yes | One of: `remove`, `replace`, `remove_lines_matching` |
| `header` | for remove / replace | Exact header text, without `#` markers |
| `level` | for remove / replace | Header level (2 = `##`, etc.) - required to disambiguate same-named headers at different levels |
| `with` | for replace | Replacement *body*. The header itself is preserved; only content under it is replaced. |
| `pattern` | for remove_lines_matching | Regex matching whole lines (anchored). Applied globally. |
| `reason` | optional | Free-text comment; ignored by the transform |

Section boundaries:
- Starts at its header line (inclusive)
- Ends at the next same-or-higher-level header (exclusive)
- Document end terminates the section

### Operation order (fixed)

The transform script applies operations in this order, and manifests cannot override it:

1. **`sections` first** - structural edits before content rewrites
2. **`paths` second** - more specific than generic renames
3. **`renames` last** - most general

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

The loop manifest is a YAML file declaring one loop cell (§System architecture): the invariant it maintains, the paths it may touch, its detector and verifier, its apply policy, and its endpoint chain. It is consumed by the loop runner. Policy lives **here** - never in prompts, never in runner code. Per *gates are local-deterministic*, the manifest is purely declarative.

### Location

- Manifests: `_meta/loops/<loop-name>.yaml`, one per loop
- Proposals: `_meta/loops/proposals/` - deliberately **not** any capture/triage-owned path, so ingestion automation never sweeps machine-generated proposals
- Ledger: `_meta/loops/<loop-name>.ledger.jsonl`, append-only
- Prompt templates: script-consumed artifacts; they live with the vault's other script-consumed templates, referenced by filename from the manifest

### Schema

```yaml
loop: <name>                    # required
invariant: <sentence>           # required - the condition this loop maintains
scope:                          # required - the ONLY paths a proposal may target
  - <vault-relative path>
detect:                         # required - deterministic detector
  script: <script name>
  args: <arguments>
verify: <verifier id>           # required - deterministic structural check
apply: <mode>                   # required - propose-only | auto (§System architecture)
auto_apply_endpoints:           # required when apply: auto - the endpoint trust allowlist
  - <driver>/<model>
  - deterministic               # non-LLM repairs the runner computes itself
promote_after: <N>              # evidence threshold recorded for the apply-mode flip
endpoints:                      # required - priority order: quality ceiling → local floor
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
prompt: <template filename>     # required - the propose step's prompt template
```

| Field | Required | Meaning |
|---|---|---|
| `scope` | yes | Enforced by the runner and the applier, script-side. A proposal targeting any path outside `scope` is rejected regardless of verifier outcome. |
| `apply` | yes | `propose-only` emits into the review queue; `auto` applies inline for allowlisted endpoints only. |
| `auto_apply_endpoints` | when `auto` | Trust list keyed by serving endpoint. `deterministic` denotes repairs computed without an LLM. |
| `promote_after` | no | The clean-pass threshold the apply-mode flip was (or will be) earned against; documentation of evidence, not automation - a human flips `apply`. |
| `endpoints` | yes | Tried in order. The accepted proposal records which endpoint served it. |
| `budget` | no | Caps enforced script-side before and during the propose step. |
| `prompt` | yes | The propose step's template; the propose step cannot run without it. |

### Runner semantics

Conformance requirements for any loop-runner implementation:

- The endpoint chain advances on transport failure **or** verification failure; per finding, each endpoint gets one attempt
- All endpoints failing = fail-closed: no proposal, target files untouched, a failure record appended to the ledger
- Idempotency: a finding whose proposal is already pending is skipped - no duplicate proposals, no duplicate LLM calls
- Auto-apply failures leave the proposal pending in the review queue; they never retry destructively
- A repair that deterministically creates a new finding inside the same loop's scope is **proposed** in the same run - and applied where the apply mode and allowlist permit - not deferred to the next
- Every proposal event (emitted, applied, rejected) appends one ledger record; the ledger, together with the run log's per-endpoint attempt record, is the evidence base for apply-mode promotion and endpoint trust
- Ledger records are JSON objects parsed by key; consumers must not depend on key order or line position

### Determinism guarantees

- Given identical vault state and manifest, the detector and verifier produce identical findings and verdicts
- The propose call is the loop's only network/LLM operation
- The verifier is pure: it writes nothing
- The runner writes only inside `scope` (on apply) and to the loop's own artifacts (proposals, ledger, run log)

### Reference implementation status

The schema above is the portable contract. The shipped runner (`reference/scripts/run-loop.ps1`) implements it for the wrap-tail-repair reference cell, with an explicit generic/specific split:

- **Generic, enforced from any manifest:** `scope` (checked by the runner before a proposal is written and re-checked by the applier), `budget` caps, endpoint chain order and degradation, per-endpoint `timeout_sec`, `apply` gating via `auto_apply_endpoints`, and detect-step read-onlyness (`-DryRun` is forced on)
- **Wrap-tail-specific:** the findings adapter (it parses `detect-wrap-tail.ps1`'s dry-run contract line), the `structural` verifier, and the two repair types
- The runner refuses a manifest declaring a verifier id it does not implement - it never treats unrecognized detector output as a clean pass

A second, materially different loop therefore needs its manifest plus adapter/verifier/repair implementations at that seam; supplying a manifest alone is not yet sufficient. That gap is exactly what §Pluggability conformance test exists to close, and it is open until that test passes.

### Out of scope (post-v1.0)

- Cross-loop orchestration (ordering or dependencies between loops)
- Per-finding endpoint routing (the chain is declared per loop)
- Retry-within-endpoint policies (one attempt per endpoint per finding)
- LLM-authored or LLM-modified manifests - policy stays human-authored

---

## § Extension surface

### Purpose

Confirmed as the extension surface for adopters; formalized here (schema was open at spec-enumeration time). Full conformance has no minimum-viable tier - a vault either conforms or it doesn't - but conformance is not the same claim as "closed." An adopter's own domain checks (a trading system's heartbeat, an integration's auth-lapse detector, a project's doc-freshness gate) are exactly the kind of enhancement the reference implementation is built from, and stripping them out of a portable spec is not a verdict that they're clutter - it's the locked/extendable cleave doing its job. This section exists so that cleave is a documented contract, not a silent omission.

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
  check.ps1     # required - the extension's detector
  README.md     # required - one-line purpose + what it flags, for human-facing surfaces
```

### `check.ps1` contract

An extension check is a **heartbeat**, not a gate and not a loop cell:

- Accepts `-Root` and `-DryRun`; a conforming extension performs no writes when `-DryRun` is passed, and its default behavior needs no other flag to run safely
- Read-only against everything outside its own extension directory - an extension never targets loop `scope:` paths or writes vault content; that is loop-cell territory (§Loop manifest), not heartbeat territory
- Always exits `0` - an extension can flag a problem, it cannot fail the chain
- Emits one machine-readable summary line: `EXTENSION-STATUS name=<name> flagged=<true|false>` (mirrors the `STATUS` line convention used elsewhere in the automation chain), plus any number of human-readable detail lines above it
- No LLM invocation, no non-local network calls beyond what the extension's own domain legitimately requires (e.g. checking a self-hosted endpoint is reachable) - extensions inherit the automation chain's determinism stance, not the loop layer's pluggable-endpoint one

### Discovery and aggregation

A conforming reference implementation ships one runner that discovers every `_meta/extensions/*/check.ps1`, invokes each with `-Root -DryRun`, and aggregates their `EXTENSION-STATUS` lines into a single heartbeat summary - the same role the nightly automation chain plays for its own built-in checks. Aggregation is generic: adding an extension requires no change to the runner or to any other extension.

### Determinism guarantees

- Given identical vault state, an extension's findings are identical
- An extension never writes outside its own directory except a heartbeat log, if it keeps one
- A failing or missing extension does not abort discovery of the others

### Out of scope (post-v1.0)

- Extension dependency ordering (extensions are independent by construction)
- A manifest/marketplace format for distributing third-party extensions
- Extensions that gate the chain (exit nonzero) - a check that must block belongs in the automation chain proper, not the extension surface

---

## § Agent context bundle

### Purpose

Agent harnesses default to persisting long-lived context (standing facts about the operator, their preferences, their projects) *outside* the vault - e.g. a home-directory memory store keyed to the harness's own identity. That breaks portability twice over: the context doesn't travel with the vault (a fresh clone or a different machine starts blank), and it isn't agent-agnostic (a Claude-specific store is invisible to a non-Claude harness reading the same vault). `_meta/agent-context/` is the vault-native, harness-agnostic home for this material - the spec gap §Transform manifest's `paths` example already gestures at (`~/.claude/projects/.../memory/` → `_meta/agent-context/`) without this section ever having defined what lives there.

### Location

`_meta/agent-context/` - already named as the target of the example path-override in §Transform manifest, and already locked into §File & folder taxonomy's determinism guarantees by extension of that folder's presence requirement. This section is the schema that folder holds itself to.

### Schema

```
_meta/agent-context/
  MEMORY.md                              # required - the index; one row per topic file, one line each
  <topic-slug>.md                        # zero or more - one durable fact/preference per file, linked from MEMORY.md
  transform-<source>-to-<target>.yaml    # zero or more - §Transform manifest instances (that section's Location is unchanged; this is the same directory)
```

Two kinds of tenant share one directory rather than each claiming a root-level folder: standing operator memory (`MEMORY.md` + topic files) and transform manifests (`transform-*.yaml`). They're distinguishable by filename pattern (`transform-*-to-*.yaml` vs. any other `.md`/`.yaml`), so no subfolder split is required for v1.0.

### `MEMORY.md` - index contract

- One line per topic file: a short label, a one-line summary, and a relative link (`[label](topic-slug.md)` or a vault wikilink, per the adopter's linking convention)
- Ordered however the operator finds most scannable (recency, category, alphabetical) - the spec does not prescribe an order
- Never holds the full fact itself - MEMORY.md is the table of contents; the topic file is the fact

### Topic file contract

- One durable fact, decision, or standing preference per file - not a running log (that's `_meta/session-log.md`'s job) and not a one-off task note (that's a handoff's or Kanban's job)
- Filename is a slug: lowercase, hyphens or underscores, descriptive enough to be findable without opening it
- Content is freeform prose - no required frontmatter; this is agent-consumed context, not a vault note subject to the frontmatter tiers of a "real" note elsewhere in the vault
- Superseded facts are edited or replaced in place, not appended-and-left - a topic file states the current standing fact, not its history (contrast with an append-only ledger or decision log elsewhere in the vault)

### Relationship to `_meta/session-log.md` and handoffs

Three different lifespans, three different files - do not conflate them:

| Artifact | Lifespan | Answers |
|---|---|---|
| `_meta/agent-context/*.md` | Standing, until superseded | "What does the agent need to know about this operator/vault on every session, indefinitely?" |
| `_meta/handoffs/*.md` | One session-close, until swept | "What happened this session, what's next?" |
| `_meta/session-log.md` | Append-only, growing | "What sessions happened, in order?" |

### Determinism guarantees

- `_meta/agent-context/` is present in every conforming vault (empty is fine; absent is not - same rule as §File & folder taxonomy's locked set)
- No reference script writes into `_meta/agent-context/` - population is an onboarding/operator activity (stage 2, §System architecture's two-stage onboarding, or manual), never an automation-chain side effect
- A missing `MEMORY.md` with topic files present is non-conformant (orphaned context an agent has no index into is not portable context)

### Out of scope (post-v1.0)

- A required frontmatter schema for topic files (kept freeform deliberately - see §Frontmatter's "real note" scope, which this directory sits outside of)
- Automatic summarization or pruning of stale topic files - an operator/agent-guided edit, not a scripted transform
- Multi-operator or shared agent-context (one vault, one operator's standing context - same single-tenant assumption §Darkloop makes for the vault as a whole)

---

## § Template manifest

### Purpose

`reference/templates/` is the fixed, script-consumed template set the reference implementation ships and copies wholesale into every bootstrapped vault (`bootstrap.ps1`'s `Copy-Item -Path '/opt/system-o/templates/*' ... -Recurse`). Copying "whatever's in the directory" with no declared inventory is fragile: nothing catches an orphaned file that no script or manifest actually cites, and every adopter's vault inherits it silently. This section is the declared inventory - the fixed v1.0 set, what consumes each entry, and the rule that keeps the set honest.

### Canonical set (v1.0)

| Template | Consumer | Purpose |
|---|---|---|
| `idea-README.md` | `launchpad.ps1` (writes it at scaffold time); `graduate.ps1` (the idea it seeded moves on) | Scaffold for a new `launchpad/<slug>/README.md` - defensibility screen, demand evidence, decide-by clock |
| `loop-wrap-tail-repair.prompt.md` | `run-loop.ps1`, via the reference loop manifest's `prompt:` field (`wrap-tail-repair.example.yaml`) | The propose-step prompt template for the reference loop cell (§Loop manifest) |
| `stage-2-onboarding.prompt.md` | An agent harness, pointed at it directly - by `bootstrap.ps1`'s completion message and by §System architecture's two-stage-onboarding description | The Stage 2 onboarding checklist: read what Stage 1 scaffolded, populate `GLOSSARY.md`, write the real orientation file, confirm ambiguities with the operator rather than guessing |

Templates are **extendable** (§Extension surface's locked-vs-extendable table already says so: "Templates | Extendable | Adopters may add types"). This section fixes the v1.0 *canonical* set the spec itself ships and is answerable for; an adopter's own additions to their vault-local `_meta/templates/` are unaffected and untracked here.

### Location and copy semantics

- Source of truth: `reference/templates/` in the system-o repo
- At bootstrap, the entire directory is copied verbatim into the vault's `_meta/templates/` (locked path, §File & folder taxonomy) - script-consumed templates live vault-local so a bootstrapped vault is self-contained and portable off the container that built it
- Consumers resolve templates by bare filename against `_meta/templates/` (e.g. `run-loop.ps1` reads `_meta/templates/<manifest's prompt field>`) - never against `reference/templates/` directly once a vault exists

### Determinism guarantees

- Every file under `reference/templates/` is cited by name from at least one script, manifest field, or spec section - no unreferenced templates ship. (v1.0 audit finding, fixed in the same pass that added this section: `onboarding-stage2.prompt.md` was an unreferenced duplicate of `stage-2-onboarding.prompt.md` - divergent content, same purpose, only the latter was ever cited by SPEC.md or a script. Removed 2026-07-09; see `_meta/Kanban.md`.)
- The canonical set is exactly the table above for v1.0 - adding, removing, or renaming a canonical template is a spec change, not a silent `reference/templates/` edit
- No canonical template embeds vault-specific content (operator name, project slugs, real dates) - every placeholder is a `{{TOKEN}}` or generic prose an adopter's own onboarding fills in

### Out of scope (post-v1.0)

- A templates registry/marketplace for adopter-contributed templates (parallels §Extension surface's identical out-of-scope item)
- Per-template versioning or migration tooling - v1.0 has one version of each canonical template, no upgrade path yet
- Template variants keyed by adopter choice (e.g. a second `idea-README.md` flavor) - one canonical version per purpose, same rule §Agent orientation files applies to orientation files themselves

---

## § Pluggability conformance test

### Purpose

Confirms the spec/reference-implementation separation (§System architecture) is real rather than nominal: that adopter-specific content - category-root names, orientation-file prose, which loops run, which extensions are enabled - is genuinely not hardcoded into the reference scripts anywhere it claims to be adopter-named or extendable. Without a test that actually exercises divergence, "spec vs. reference implementation" is just two folders with a naming convention between them.

This section's origin is a launchpad exploration (`system-o-modular`, opened May 6 2026) that proposed a dedicated install-time spec compiler (chezmoi-based) to make pluggability structural. That specific mechanism never shipped and is superseded - system-o's actual install path is the Docker/`bootstrap.ps1` route plus two-stage onboarding, already specified in §System architecture. What survives from that exploration, and is worth locking into the spec on its own merits, is the **test** it proposed as its own graduation bar: *two materially different specs should produce two materially different, independently conformant vaults.* Porting the goal without the abandoned mechanism is the point of this section.

### The test

Run the shipped bootstrap path (`reference/docker/bootstrap.ps1` → Stage 2 onboarding, §System architecture) twice, with two materially different operator inputs, and confirm it produces two materially different vaults:

1. **Vault A - "default operator"** - e.g. the reference implementation's own shape: `web/` / `apps/` / `games/` / `tools/` category roots, Claude Code as primary agent (`CLAUDE.md` canonical), the shipped wrap-tail-repair loop as the sole active loop.
2. **Vault B - "content-publishing operator"** - a structurally different shape: different category roots (e.g. `posts/` / `drafts/` / `assets/`), a non-Claude primary agent (`AGENTS.md` canonical - exercising §Agent orientation files' transform in the direction Vault A never touches), and a different loop cell entirely (e.g. an editorial-review loop, not wrap-tail-repair).

Passing requires both properties, together:

- **Divergence** - the two vaults differ in every adopter-named surface (§File & folder taxonomy's "Adopter-named" row, orientation-file content, the active loop set, enabled extensions) in ways that trace directly to the two different inputs, not to chance or manual post-editing
- **Conformance** - both vaults independently satisfy every *locked* guarantee in this spec regardless of their divergence: §File & folder taxonomy's locked set present, §Agent orientation files' one-canonical-file rule, valid loop and transform manifests, `_meta/agent-context/` and `_meta/GLOSSARY.md` present

A reference implementation that exposes a couple of config flags but is otherwise one hardcoded shape does not pass - the divergence has to be structural (different category roots, different primary agent, different loop), not cosmetic (a renamed folder, a different color scheme).

### Relationship to the shipped install path

`bootstrap.ps1` already carries two of the seams this test exercises: it takes `-AgentTarget` as a parameter (the canonical orientation filename - Vault A vs. Vault B's `CLAUDE.md`/`AGENTS.md` split) and discovers category roots dynamically rather than hardcoding them (§File & folder taxonomy's determinism guarantee: "No reference script hardcodes a category-root name"). This test is what confirms those seams are load-bearing, not decorative - it targets the shipped path directly, not a hypothetical compiler.

### Status

Not yet run. This is breadth-testing (does the *same* reference tooling correctly serve two divergent operators) alongside the depth-testing the existing v1.0 conformance matrix already covers (§System architecture's D6: does the *one* reference vault run correctly on Docker/Windows/Linux hosts). Both are required before the "operating system, not a personal script collection" claim holds - depth alone would still permit a reference implementation quietly hardcoded to one operator's shape.

### Out of scope (post-v1.0)

- A dedicated spec-compiler or templating engine (chezmoi or otherwise) - the shipped bootstrap + two-stage onboarding is the reference mechanism this test targets; a compiler is only future work if manual Stage 2 effort proves to be the actual bottleneck, which this test has not yet established
- Runtime spec hot-swapping (the original exploration's further-out "stage 3") - out of scope until this test (its "stage 2" equivalent) has passed even once
- A public gallery of alternate operator specs - one worked second example (Vault B above) is sufficient to prove the abstraction; a gallery is distribution/marketing surface, not a conformance requirement
