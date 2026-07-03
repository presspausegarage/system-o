You are running Stage 2 onboarding for a freshly bootstrapped system-o vault (spec §Extension surface's sibling concern: distribution review D8). Stage 1 already ran deterministically (`bootstrap.ps1`, no LLM) and produced placeholder starter files. Your job is to turn those placeholders into real content — nothing here should require inventing facts; everything you need to write is derivable from what's already shipped in this vault plus the spec sections it implements.

Work through these steps in order. This is a one-time pass — once done, this vault behaves like any other system-o vault and these steps don't repeat.

## 1. Read what's already here

- `CLAUDE.md` (or `AGENTS.md`) — the starter orientation file. It's boilerplate; you're about to replace it.
- `_meta/GLOSSARY.md` — an empty term table. You're about to fill it.
- `_meta/HOME.md`, `_meta/session-log.md` — starter dashboards, fine as-is.
- `_meta/loops/wrap-tail-repair.yaml.example` — the loop cell, shipped inert.
- `_meta/extensions/` — three worked examples (`stale-capture`, `frontmatter-type`, `source-drift`), none configured yet.
- `_meta/scripts/` — the full reference toolkit: `launchpad.ps1`, `graduate.ps1` (project lifecycle), `run-loop.ps1`/`detect-wrap-tail.ps1`/`apply-loop-proposal.ps1` (the loop cell), `run-extensions.ps1` (extension aggregation), `build-static-home.ps1` (editor-agnostic dashboard).

## 2. Populate `_meta/GLOSSARY.md`

Write one table row per term this vault's own conventions and scripts actually use — not invented vocabulary, the load-bearing words a future session or a new contributor would otherwise have to infer from reading code. At minimum, cover: handoff, session log, HOME, launchpad, graduate, decide-by, risk tier, registry, category root, loop cell, loop manifest, extension, proposal, ledger, apply mode, endpoint chain, measured conformance. Keep definitions to one line each, matching the existing table's column shape. If this vault later adopts vocabulary specific to what it's actually building, add those terms too — the glossary grows with the vault, it isn't fixed at onboarding.

## 3. Write the real `CLAUDE.md`

Replace the placeholder with orientation content covering:
- **Folder taxonomy**: which paths are locked (per spec §File & folder taxonomy) vs. adopter-named (category roots — created on demand by `graduate.ps1`, not pre-declared).
- **Lifecycle**: `launchpad.ps1 -Slug <name>` to start an idea → fill in its README (defensibility, demand evidence, kill threshold) → `graduate.ps1 -Project <slug> -To <category>` to promote it → build.
- **Loop layer**: what's here, that it ships inert, how to activate it (rename `.yaml.example` → `.yaml`, fill in real endpoints).
- **Extensions**: what's here, that `run-extensions.ps1` discovers and runs them, that `source-drift` specifically needs a `checks.yaml` to do anything.
- **Operating principles**: offline-first (cloud/LLM is augmentation, never a dependency), gates are local-deterministic, the LLM is a pluggable endpoint and never the policy-maker.
- Point at `_meta/GLOSSARY.md` for vocabulary rather than re-explaining terms inline.

## 4. Confirm, don't assume

If anything about how this specific vault should work is genuinely ambiguous — a naming convention, a risk-tier default, whether to enable an extension now — ask the operator rather than guessing. Stage 2 is agent-guided precisely so real judgment calls surface instead of getting silently decided by whichever way an LLM happened to phrase a placeholder.

## Done when

`_meta/GLOSSARY.md` has real terms, `CLAUDE.md` describes this vault's actual lifecycle and layout (not generic boilerplate), and you could hand this vault to a fresh agent session with no other context and have it correctly orient itself.
