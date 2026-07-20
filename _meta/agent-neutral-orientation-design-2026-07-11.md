---
type: design
tags:
  - type/design
  - project/system-o
  - topic/agent-portability
date: 2026-07-11
updated: 2026-07-12
status: proposed
---

# Agent-neutral orientation design delta

## Purpose

Sketch the change from system-o v0.1's primary-agent orientation model to a model-neutral policy source with harness-specific adapters. This proposal is isolated from the in-flight VM portability test and does not change that test's design, fixtures, or acceptance criteria.

## What the current VM test proves

The current experiment compares the mature `C:\dev` workspace with a fresh system-o installation in a VM, using Claude Code in both environments. It tests whether the distribution reproduces the useful devspace behavior on a fresh machine without depending on the mature vault's accumulated state.

That is a valuable environment-fidelity test. It does not test agent-harness portability because the harness and orientation convention remain constant (`CLAUDE.md` -> Claude Code) on both sides. Its result should remain the v0.1 baseline rather than be reinterpreted or restarted.

## Field evidence from the live vault (July 12, 2026)

On July 12, 2026 the live `C:\dev` vault adopted the v0.1 canonical+transform model at full scope — root plus 6 project repos plus a Codex global adapter, with nightly regeneration wired into the 02:50 chain ([[2026-07-12g-agents-md-generation-live]]). That deployment produced the first real cross-agent field results. They are recorded here as v0.1 evidence so the post-VM-comparison session lands on facts rather than memory. Each item informs one or more of the gated questions below; none decides one.

### 1. Harness discovery semantics genuinely diverge — Codex does not walk past a repo root

Codex CLI launched inside `apps\warchest` loaded only the project `AGENTS.md`; workspace rules never arrived. Its root-to-leaf composition stops at the repo boundary. The verified fix renders root workspace policy to `~/.codex/AGENTS.md` — Codex's native global-instructions file, where global ≈ workspace on a single-user machine. The re-test in warchest cited both scopes: workspace don't-do rules, warchest hard rules, and risk-3 behaviors. Verified end-to-end the same day.

Design impact: the "loading behavior is implemented separately by each harness adapter" row is now demonstrated necessity, not defensive design. It also surfaces a requirement the proposed layout does not yet state: harness profiles must own **placement** — which filesystem or global path realizes each hierarchy scope — not just filenames and rendering. For Codex, the workspace scope compiles to a user-global path rather than a parent-directory file. Incidentally, the re-test is a live single-harness pass of the orientation-equivalence criteria (root invariant retained, project specialization applied, instruction sources cited).

### 2. Zero token renames by policy — transform-time rewriting is a demonstrated corruption vector

The root `AGENTS.md` this deployment replaced was corrupt: a hand-made blanket Claude→Codex string-replace. The replacement manifests perform **zero token renames by policy**; the only section operation strips the Claude-only memory pointer. Agent-neutrality was achieved instead by rewording the authored `CLAUDE.md` sources (root + 5 projects), leaving factual Claude mentions intact and keeping manifests near-empty.

Design impact: field evidence for thin transforms with neutrality pushed into authored sources. Bears on decision 1 (neutral source format) and decision 5 (compiler implementation) — aggressive transform-time rewriting is no longer a hypothetical risk.

### 3. Hash-only provenance caught same-day drift

Generated files carry a hash-only provenance header — no timestamps — so regeneration is byte-idempotent and produces no spurious repo diffs. This was exercised the day it shipped: warchest's generated `AGENTS.md` drifted (parallel session) and the staleness self-detected via the provenance hashes; the file was regenerated the same evening. Nightly regeneration bounds drift to ≤24h, and `-Check` exits nonzero on stale output.

Design impact: validates the drift-detection row (generated provenance, source hashes, `--check` mode) at live-vault scale on day one. The no-timestamp constraint should be carried into the compiler spec explicitly — byte-idempotence is what makes committed generated artifacts diff-clean.

### Secondary observations

- **Adapter placement in practice (data for decision 2):** the 6 generated project `AGENTS.md` files were committed into their repos the same day. v0.1 practice is generated-in-working-vault *and* committed downstream; the decision stays open.
- **Vendoring constraint (data for decision 5):** the live vault vendored `transform-orientation.ps1` byte-identical from this repo's `reference/scripts/`, with a source-SHA256 provenance note, so SYSTEM automation does not depend on this repo's branch state. Any successor compiler inherits that deployment constraint.
- **Known thin spot:** the one section operation (`remove_lines_matching '^- User-level memory'`) silently stops matching if that bullet's prose changes — the Claude-only line would leak into `AGENTS.md`. Surfaced via transform warnings in the 02:50 log; accepted as low-stakes. Line-regex section ops are fragile; a composition-first compiler should prefer structural markers.

## Design delta

| Concern | Current v0.1 design | Proposed design |
|---|---|---|
| Policy source | The primary harness's file: `CLAUDE.md` or `AGENTS.md` | Model-neutral policy modules under `_meta/agent-policy/` |
| Primary-agent choice | Determines which orientation file is canonical | Selects an adapter/profile; never changes policy ownership |
| Other harnesses | One-way textual transform from the primary file | Deterministic compilation from shared policy sources |
| Hierarchy | Subtree file replaces parent; first-found wins | Semantic order: core -> workspace -> project -> task |
| Loading behavior | Assumed to be uniform across harnesses | Implemented separately by each harness adapter |
| Claude Code | Canonical or transformed `CLAUDE.md` | Generated `CLAUDE.md` files matching Claude's discovery behavior |
| Codex | Generic transformed `AGENTS.md` | Generated `AGENTS.md` files matching root-to-leaf composition |
| Local Gemma | Treated mainly as a loop endpoint | Receives a compact compiled policy packet through its harness |
| Switching | Change the primary agent and transform direction | Select harness and model profiles; generated adapters coexist |
| Drift detection | Deterministic output only | Generated provenance, source hashes, and compiler `--check` mode |
| Conformance | Files generated successfully | Equivalent critical rules demonstrated in each target harness |

## Proposed source layout

```text
_meta/agent-policy/
|-- core.md                  # safety, risk, evidence, destructive-operation rules
|-- workspace.md             # vault layout, routing, lifecycle, read-first pointers
|-- projects/
|   |-- system-o.md          # project-specific policy source
|   `-- <slug>.md
|-- harnesses/
|   |-- claude-code.yaml     # filenames, discovery, rendering, tool vocabulary
|   |-- codex.yaml
|   `-- generic.yaml
`-- models/
    |-- frontier.yaml        # context and verification profile, not policy
    `-- compact-local.yaml
```

The policy modules own behavioral meaning. Harness profiles describe how that meaning reaches an agent. Model profiles tune context size, retrieval, retries, and verification intensity without weakening safety or lifecycle rules.

## Effective policy hierarchy

```text
system-o invariant policy
        -> adopter workspace policy
        -> project policy
        -> current task instructions
```

Later scopes may specialize earlier scopes. They may not silently remove invariant safety rules. A harness that natively concatenates files may use that behavior; a harness with different discovery semantics receives a rendered equivalent. The hierarchy is a semantic contract, not a filesystem-loading claim.

## Generated adapters

Bootstrap or an explicit compile command generates every enabled target, rather than generating only the non-primary target:

```text
policy modules + claude-code profile -> CLAUDE.md files
policy modules + codex profile       -> AGENTS.md files
policy modules + local profile       -> compact prompt packet
```

Each generated artifact should contain a machine-readable comment with:

- compiler version
- profile name
- ordered source paths
- aggregate source hash
- instruction not to edit the generated file directly

The compiler needs a read-only check mode that fails on missing, stale, manually changed, or oversized adapters.

## Harness and model selection

Harness and model are separate axes:

```yaml
harness: codex
provider: openai
model_profile: frontier
```

```yaml
harness: system-o-local
provider: ollama
model: gemma4:e4b
model_profile: compact-local
```

The harness controls instruction discovery, tools, permissions, and file rendering. The model profile controls context budget and verification posture. Changing models must not change risk tiers, secret handling, destructive-operation policy, routing rules, or evidence requirements.

## Container boundary

Keep two roles conceptually separate even if a development compose file runs both:

1. `system-o-runtime` runs deterministic scripts, cron, detectors, verifiers, and gated apply operations against the bind-mounted vault.
2. `agent-runtime` is optional and runs Claude Code, Codex, or a local harness with its own credentials, configuration, and permission boundary.

The unattended runtime must remain useful with no agent runtime installed. Cloud-agent credentials should not be required by or stored in the automation container. Bind-mount ownership should be explicit through host UID/GID mapping on the Docker path.

## Test sequence

### Baseline: finish the current experiment

Complete the mature-devspace vs fresh-VM test unchanged. Record it as environment fidelity under one harness, not as proof of cross-agent portability.

### Next: orientation equivalence

Use one small fixture vault with a root invariant, a project override, and an intentional conflict. Run it with:

1. Claude Code using generated `CLAUDE.md` files.
2. Codex using generated `AGENTS.md` files.
3. Gemma through the selected local harness using the compact policy packet.

Each run must identify the same effective critical rules, retain the root safety invariant, apply the project specialization, and cite the instruction sources it received.

### Then: task conformance

Give all three targets the same bounded task. Compare:

- forbidden-operation avoidance
- correct project command selection
- verifier pass rate
- instruction-source trace
- context size and latency
- unsupported-tool behavior

This tests the whole harness-policy path rather than asking the model to summarize rules and treating recall as compliance.

## Migration path

1. Freeze v0.1 orientation behavior until the VM test closes.
2. Specify the semantic hierarchy and invariant-policy rule.
3. Extract a minimal neutral policy fixture; do not migrate the full live vault first.
4. Build compiler provenance and `--check` before adding multiple renderers.
5. Add Claude and Codex renderers and pass the orientation-equivalence fixture.
6. Add the compact local packet and Gemma harness profile.
7. Migrate the live root orientation, then one low-risk project, before risk-3 projects.
8. Amend `SPEC.md` only after the fixture demonstrates equivalent effective policy.

## Non-goals

- Changing the in-flight VM portability test
- Making every model equally capable
- Allowing model profiles to weaken safety policy
- Requiring an LLM during bootstrap or policy compilation
- Embedding interactive cloud-agent credentials in the automation runtime
- Treating generated `CLAUDE.md` and `AGENTS.md` files as authored sources

## Decisions still needed

All five remain open. The July 12, 2026 field evidence above informs 1, 2, and 5 but decides none of them.

1. Neutral source format: markdown modules with YAML manifests, or a more structured policy schema with rendered prose.
2. Adapter placement: generated files in the working vault, release artifacts only, or both.
3. Local harness: extend the system-o loop runner, use an existing AGENTS-compatible harness, or add a dedicated sidecar.
4. Conflict semantics: which policy fields are invariant, overridable, additive, or task-local.
5. Compiler implementation: evolve `transform-orientation.ps1` or replace it with a composition-first compiler while retaining the old transform for v0.1 compatibility.
