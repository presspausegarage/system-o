# system-o - markdown OS

A **"markdown OS"** for AI-augmented operators: the generic, installable layer of vault scaffolding, offline-first automation, agent-portability conventions, and a loop-cell architecture for self-repairing vault state - extracted from months of real operator-vault use, not designed in the abstract.

Not any one operator's specific projects, journal, or business tooling. The underlying substrate: a vault any operator (human or AI-augmented) can install fresh, run, and extend.

## Three layers, one name

1. **Spec** (`spec/SPEC.md`) - the portable contracts an adopter conforms *to*: layered architecture, the loop-cell pattern, orientation files, transform + loop manifests, extension surface, determinism guarantees. Independent of any one implementation.
2. **Reference implementation** (`reference/`) - pwsh 7 scripts, extensions, templates, and the Docker distribution that implement the spec. Every spec section is written from a working instance, not prospectively.
3. **Distribution** (`reference/docker/`) - the installable bundle. `docker run` scaffolds a fresh vault, runs the automation chain via cron inside the container, and leaves the vault itself as a bind mount you edit with whatever's on your host.

The layers feed forward: the reference implementation hardens the spec; the spec is what the distribution installs.

## Quick start

```
git clone https://github.com/presspausegarage/system-o.git
cd system-o/reference/docker
cp docker-compose.example.yml docker-compose.yml
docker compose up -d
```

First start scaffolds `./my-vault` with the locked folder taxonomy, a starter glossary, session log, HOME dashboard, and an orientation file (`CLAUDE.md` by default - set `AGENT_TARGET: AGENTS.md` for a non-Claude agent). **Recommended editor: VS Code + Remote-SSH** into whatever host is running the container - no GUI app needed on that side at all. Obsidian is fully supported too (`reference/scripts/install-obsidian.ps1`) if you prefer it; neither is required (spec core is editor-agnostic).

Full walkthrough, signal handling, and what's deliberately not on by default: [`reference/docker/README.md`](reference/docker/README.md).

## What's in the spec

`spec/SPEC.md` (§ sections):

- **System architecture** - the six-layer model, loop-cell pattern (detect → propose → verify → apply), endpoint degradation, measured conformance
- **Darkloop** - the vault's unattended operating cycle; custody alternates between an attended session and automation, every crossing is a vault artifact
- **File & folder taxonomy** - the locked minimum a fresh vault needs vs. what an adopter names themselves
- **Agent orientation files** - the canonical `CLAUDE.md`/`AGENTS.md` cascade
- **Transform manifest** - deterministic source→target path/content rewrites for porting an orientation file between agents
- **Loop manifest** - how a loop cell is declared: detect script, propose endpoints (with required degradation chain), structural verify, gated apply
- **Extension surface** - read-only, flag-only heartbeat checks any adopter can add without touching core
- **Agent context bundle** - `_meta/agent-context/`, the vault-native home for durable agent memory (portable across machines and harnesses, unlike a home-directory memory store)
- **Template manifest** - script-consumed templates (loop prompts, orientation scaffolds)
- **Pluggability conformance test** - proves the reference tooling serves two materially different adopters, not just one hardcoded shape

## Status

**v1.0 conformance: closed.** The install-and-run-clean gate (Docker from a Windows host, Docker from a Linux host, plus the Windows-native reference path; loop layer required, tested via a deterministic stub endpoint - no LLM dependency) is scripted end-to-end at [`reference/tests/run-conformance-test.ps1`](reference/tests/run-conformance-test.ps1) and passing on all three targets.

Live showcase + spec walkthrough: [system-o.org](https://system-o.org).

## License

[MIT](LICENSE).
