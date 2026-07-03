# source-drift

Flags documents that restate a fact out of sync with its canonical source — doc rot, caught mechanically. This is the reference implementation's core answer to "N hand-authored docs quietly drift the moment only one gets updated," generalized from the registry-vs-prose drift pattern.

Policy lives entirely in `checks.yaml` (same principle as the Transform and Loop manifests — declare it, don't code it): each check names a source file + extraction pattern (the canonical value) and one or more derived files + patterns (places that restate it). A mismatch is flagged by name.

**Not enabled out of the box.** With no `checks.yaml` present, this extension reports a clean status and does nothing — it has no facts to check until you declare some. Copy `checks.example.yaml` to `checks.yaml` alongside `check.ps1` and point it at your own vault's source-of-truth pairs.

Parameters: `-Manifest <path>` if you want the manifest to live somewhere other than alongside `check.ps1`.
