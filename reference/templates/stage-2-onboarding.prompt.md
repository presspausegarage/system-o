You are running Stage 2 of onboarding for a freshly-bootstrapped system-o vault (Stage 1 - `bootstrap.ps1` - already ran: locked folders exist, `_meta/GLOSSARY.md` has an empty term table, the orientation file is boilerplate, `_meta/HOME.md`/`_meta/session-log.md` are stamped with today's date).

Your job is not to guess. Stage 1 was deliberately mechanical; Stage 2 exists because some things can only be answered by the operator. Confirm genuine ambiguities - don't invent plausible-sounding answers to fill space.

## What counts as a genuine ambiguity

Check at least these standard categories before declaring Stage 2 done:

- **Undocumented folder purpose.** Any locked folder (spec §File & folder taxonomy) or extension directory that exists but has no stated purpose the orientation file or glossary can point to authoritatively. Don't leave `_sewerpipe/`-style folders present-but-unexplained.
- **Scale/axis direction.** Any numeric convention (risk tiers, priority, a 1-N scale of any kind) needs its direction stated explicitly - which end is "more," which end is "safer." A scale an agent has to infer from context is a latent bug waiting for a wrong inference.
- **Locked-vs-adopter-named boundary, for this specific vault.** The spec draws the line in general terms; confirm how it lands here - e.g. what categories this operator actually uses for graduated projects, if that's decided yet.
- **Anything the glossary or orientation-file template phrased as a placeholder** ("populate this," "describes your workspace") - each placeholder is an open question, not filler to leave as-is.

If you find an ambiguity, surface it as a short, concrete question - multiple-choice where the space of reasonable answers is small, so confirming costs the operator one click, not an essay.

## What NOT to touch

Stage 2 fills in *this operator's* answers. It does not relitigate anything spec-locked (§System architecture's layers, the loop-cell pattern, manifest schemas, the locked half of §File & folder taxonomy). If something looks wrong at the spec level, say so and stop - that's a spec bug report, not a Stage-2 edit.

## What to produce

1. `_meta/GLOSSARY.md` - real terms with real definitions specific to this vault, replacing the empty starter table. Terms should be the vocabulary this vault's own conventions, scripts, and prompts assume a reader already knows (per the file's own header).
2. The orientation file (`CLAUDE.md` or `AGENTS.md`) - prose specific to this workspace: what it's for, its conventions, how an agent should work here - replacing the generic Stage-1 boilerplate.
3. A record that Stage 2 ran and what it resolved: append a session-log entry per this vault's own convention if one exists, or otherwise note completion in a form the operator can find later. Don't invent a new logging convention if the loop layer (`_meta/loops/`) already owns this - check first.

## Exit criteria

Stage 2 is done when: no placeholder text remains in the glossary or orientation file, every ambiguity you found was either confirmed by the operator or explicitly deferred with a note (not silently guessed), and the record in step 3 exists. If you deferred anything, say so plainly rather than letting it look resolved.
