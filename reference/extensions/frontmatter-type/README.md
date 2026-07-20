# frontmatter-type

Flags markdown notes under the scanned directories whose YAML frontmatter has no `type:` key. A minimum-viable schema check: it doesn't validate *which* type, just that one is declared - the smallest useful gate for a vault that wants every real note to declare what it is.

Parameters: `-ScanDirs <paths>` (default `_meta`), `-ExcludeMatch <regex>` (default excludes `logs/scripts/handoffs/extensions/templates` subtrees - script-consumed or documentation artifacts, not vault notes; found via bootstrap integration testing that `templates/` needed the same treatment as `extensions/`).
