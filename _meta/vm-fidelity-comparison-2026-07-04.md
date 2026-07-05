---
type: meta
status: complete
date: 2026-07-04
tags:
  - type/meta
  - topic/system-o
  - topic/distribution
---

# VM fidelity comparison — databreachsettlements.com (July 4, 2026)

Phase 5 of the plan (`C:\Users\Administrator\.claude\plans\pure-wobbling-piglet.md`): one idea, one frozen brief (`handoff/` package — `PRD.md`, `fixtures.json`, `acceptance-criteria.md`, `design-tokens.md`), built independently in two environments, graded against the same rubric. This report distinguishes **facts I independently verified** from **claims relayed to me** (chat transcript, not a committed artifact) — that distinction matters more than the scores themselves.

## Setup

- **Path A — the Rocky Linux 9 Hyper-V VM** (`system-o-rocky-test`), Andy's own Claude Code session, repo `presspausegarage/data-breach-settlements-vm`, branch `vmbuild`, commit `31676c4`.
- **Path B — live `C:\dev`**, this session, repo `presspausegarage/data-breach-settlements-live`, commits `d117752` + `ab240e1`.
- Both built from the identical frozen `handoff/` package — fidelity starts at the launchpad boundary, per the design refinement in [[2026-07-03e-databreachsettlements-brainstorm-vm-fidelity-setup]].

## Path A (VM) — what I independently verified

Connected to the VM directly and re-ran the checks myself rather than trust the pasted summary:

| Check | Result |
|---|---|
| Git history | Real: 2 commits (graduate, build). Verified via `git log`. |
| `npx tsc --noEmit` | Clean — no output, no errors. |
| `npx tsx scripts/verify-acceptance.ts` | **43/43 checks pass** — re-ran it myself, exact match to the claimed result (same fixtures, same two traps handled: Google Assistant excluded from all in-scope collections, `official_claim_url: null` on Fidelity/Labcorp with no fabricated link). |
| `npm run build` | Succeeds cleanly — 18 pages built, no errors. |
| Claimed nit-fix | Genuinely applied — `BaseLayout.astro`'s subtype nav now derives from `subtypes.map(...)`, not hardcoded, confirmed by reading the file. |

**Not independently verified — relayed via chat transcript only, no committed artifact:**
- **Lighthouse 100/100** (Performance + Accessibility) — Andy reported one of "two independent graders" re-ran this; I did not run Lighthouse myself, and no report file exists in the repo to inspect.
- **The grading methodology itself** (two independent graders + a tie-break synthesis, i.e. a proper judge-panel pattern) — a real, more rigorous process than Path B's, *if* it happened as described. But it produced no durable scoring-sheet file in the repo — only chat output. Worth committing one for parity if this comparison needs to be re-checked later.
- Code-quality rubric as reported: 5/5 on data isolation, type safety, scope handling, readability, testability; 4/5 on routing-DRY (the nit, since fixed).

## Path B (live) — what's recorded

Fully committed, citable: `web/data-breach-settlements-live/_meta/handoff/build-result-claude-code.md`.

| Section | Result |
|---|---|
| A–F (data layer, scope, routing/SEO, filter/sort, eligibility incl. both traps, trust rules) | **PASS**, each with its specific verification method logged (automated script section, manual in-browser checks for others). |
| G (Lighthouse/quality bars) | **Explicitly NOT measured** — no headless Chrome wired up in that pass. Stated as an expectation ("no structural reason to expect below ≥95"), not a measurement, and not glossed over. |
| Code-quality rubric | Self-assessed 1–5 across the same six dimensions: 5, 4, 5, 5, 4, 5 (type safety and readability marked down one point each, with specific reasons given — a loosely-typed `Payout` grab-bag, and direct-DOM-manipulation in the eligibility form's client script). Average ≈4.67/5. |
| Disclosed confounds | Two, unprompted: (1) wall-clock (~15 min) bundled surrounding vault-admin work, not an isolated build timing; (2) this environment's prior exposure to Astro conventions *and* incidental access to sibling-project deployment patterns already in this vault (deviceclearance/friction.ceo's Cloudflare Workers setup) — an assist a colder environment wouldn't have, explicitly flagged as relevant to interpreting the comparison. |

## Side-by-side

| Dimension | Path A (VM) | Path B (live) |
|---|---|---|
| Logic/data layer (the 43-point script) | PASS, independently re-verified | PASS (A) |
| Scope/traps (Google Assistant, null claim URLs) | PASS, independently re-verified | PASS (B, F) |
| Routing/SEO | Implied by clean build + verify script; not separately itemized in what I saw | PASS (C), itemized: sitemap, JSON-LD, canonical tags |
| Quality bars (Lighthouse) | Claimed 100/100 — **unverified by me, no artifact** | Explicitly not measured — **honestly disclosed, not claimed** |
| Code-quality average (same 6-dimension rubric) | ~4.83/5 as reported | ~4.67/5, committed |
| Grading process | Reportedly two independent graders + tie-break — **more rigorous if true, but unrecorded** | Single self-assessment — less rigorous by design, but fully recorded with reasons |
| Confounds disclosed | None mentioned in the transcript | Two, specific and unprompted |

## Divergence classification

- **Expected, not a gap**: both builds pass the shared logic/data/trap layer identically — this is exactly what a portable, well-specified frozen brief should produce, and it did, in both a from-scratch VM environment and the live reference vault.
- **Real methodology gap, Path A**: the more rigorous-sounding grading process left no durable trace. A judge-panel pattern is genuinely stronger evidence *if it happened as described* — but "if" is the operative word until it's a file, not a transcript. Recommend: if this comparison is ever revisited or cited, ask for (or write) an equivalent `build-result.md` on the VM side so both paths carry the same evidentiary weight.
- **Real honesty gap, favoring Path B**: Path B disclosed its own confounds (bundled timing, Astro-familiarity assist) without being asked. Path A's transcript didn't surface anything comparable — which may mean there wasn't anything comparable to disclose, or may just mean it wasn't asked. Can't tell from what exists; worth asking directly if it matters for the fidelity conclusion specifically (the whole point of this experiment is measuring environment fidelity, and an unstated capability assist would undermine that more than an disclosed one).

## Verdict

**Both builds work, pass the identical hard grading script, and pass the two deliberately planted traps.** On the concrete, independently-checkable layer — the thing this whole experiment actually set out to test — the reference implementation and the from-scratch VM distribution produced **equivalent results**. That's the headline finding, and it's a real point in the distribution's favor: portability didn't cost correctness.

The softer layers (Lighthouse, code-quality nuance, grading rigor) lean slightly toward each side in different ways that mostly cancel out — Path A's numbers are marginally higher but less verifiable; Path B's numbers are marginally lower but fully accountable. Not enough to call a winner on "which environment is better" — and that was never really the question. The question was "does the portable distribution hold up," and on the evidence gathered here, yes.

## Recommendation

Per Stage rules, `databreachsettlements-com` is a normal graduate-or-bury candidate on its own merits now (registry `decide_by: 2026-08-02`) — that's Andy's call, separate from this experiment's outcome. For the experiment itself: no further action required to close it out; the one optional follow-up is committing a VM-side scoring sheet if this comparison needs to survive scrutiny later.

## Reference

- `launchpad/data-breach-settlements/handoff/` (live) / VM equivalent — the frozen brief both paths built from
- `web/data-breach-settlements-live/_meta/handoff/build-result-claude-code.md` — Path B's full scoring sheet
- `presspausegarage/data-breach-settlements-vm` (`vmbuild` branch) — Path A's repo
- [[2026-07-03e-databreachsettlements-brainstorm-vm-fidelity-setup]] — where the experiment's design was set
- `C:\Users\Administrator\.claude\plans\pure-wobbling-piglet.md` — the approved plan this closes out
