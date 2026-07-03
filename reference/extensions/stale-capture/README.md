# stale-capture

Flags items sitting in a capture folder (default `_inbox`) longer than a staleness threshold (default 7 days). Any capture pad that routes items out by rule accumulates a few that no rule matches — this surfaces the routing gap itself, not a specific rule's correctness. `README.md` is exempt.

Parameters: `-CaptureDir <path>` (default `_inbox`), `-StaleDays <n>` (default `7`).
