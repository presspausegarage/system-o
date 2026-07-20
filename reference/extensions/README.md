# Extensions

The extension surface (spec §Extension surface) is how you bolt your own domain checks onto the automation chain without touching locked spec territory. This directory ships three portable worked examples:

- **`stale-capture/`** - flags capture-folder items stuck past an age threshold
- **`frontmatter-type/`** - flags notes missing a minimum frontmatter field
- **`source-drift/`** - **doc rot prevention as a core, shipped routine, not an afterthought.** Declares canonical-fact ↔ derived-restatement pairs in a manifest (`checks.yaml`, same "policy lives in a manifest" principle as the Transform and Loop manifests) and flags any pair that's drifted. This generalizes the single most valuable heartbeat pattern in the reference operator's own vault - three hand-authored docs silently drifting from a project registry - into something declarative any adopter configures for their own vault, with zero code per check added. See `source-drift/README.md`.

All three run as-is with no editing (`source-drift` no-ops cleanly until you add a `checks.yaml`, since it has no facts to check yet - copy `checks.example.yaml` to enable it).

It does **not** ship every extension that motivated this surface. A few live in the reference operator's own vault, tied to specific tools that wouldn't generalize as code - but the *pattern* they demonstrate is exactly what this surface is for, and worth knowing before you write your own extension off as unnecessary:

- **A weekly background job's heartbeat.** A recurring task (in this case, a trading-signal scan) writes a dated log on every run. The extension doesn't care what the job does - it checks that a fresh log exists and ends clean. When the underlying scheduled task silently died, this was the check that surfaced it, days before anyone would have noticed the job simply hadn't run.
- **A third-party auth session's freshness.** An integration (in this case, a browser-session bridge to an external AI tool) authenticates as a human user, and that session can lapse without any error in the integration code itself - the next run just silently no-ops. The extension tails the integration's own log for a specific failure marker and flags it, turning a silent no-op into a visible one-line fix (“re-authenticate”).
- **Structural drift in a specific codebase.** A project ships its own doc-freshness checker (module map vs. actual code, a stale “verified against” stamp) as a Python script it already runs in CI. The extension is nothing more than "run that script, capture its exit code" - reusing project-specific tooling as a vault-level heartbeat costs almost nothing once the extension contract exists.

None of these needed the loop layer, an LLM, or a spec change - each is `check.ps1` plus a `README.md`, discovered automatically by `run-extensions.ps1`. If you have a background process, an integration, or a convention worth watching, that's the shape to reach for: read-only, flag-only, exits `0` always, emits one `EXTENSION-STATUS` line. Copy `stale-capture/` as the starting skeleton for a simple check, or `source-drift/` for anything shaped like "does this doc still agree with its source."
