# frontmatter-type

Flags markdown notes under the scanned directories whose YAML frontmatter has no `type:` key. A minimum-viable schema check: it doesn't validate *which* type, just that one is declared — the smallest useful gate for a vault that wants every real note to declare what it is.

Parameters: `-ScanDirs <paths>` (default `_meta`), `-ExcludeMatch <regex>` (default excludes `logs/scripts/handoffs/extensions` subtrees — the last so extension `README.md` files, which are documentation rather than vault notes, aren't self-flagged).
