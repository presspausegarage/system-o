#Requires -Version 7.0
<#
.SYNOPSIS
  Generate a plain-CSV fallback view of every Kanban.md board — the same
  core-without-any-editor principle build-static-home.ps1 applies to the
  registry (spec §System architecture layer 4), applied to Kanban boards.
.DESCRIPTION
  Kanban boards in this vault are markdown (Obsidian's Kanban plugin format:
  `## <Column>` headers, `- [ ]`/`- [x]` items beneath each) — readable as
  plain text, but not as a structured table without a board-view tool. This
  writes a `Kanban.csv` next to every `Kanban.md` it finds, one row per task,
  openable in any spreadsheet app, VS Code's built-in CSV preview, or a text
  editor — no extension, no plugin, no specific tool assumed.

  Parses top-level `## ColumnName` headers and top-level `- [ ] Task` /
  `- [x] Task` lines beneath them into Column/Done/Task rows. v1 scope,
  stated plainly: captures each item's first line only (its card title) —
  multi-line card bodies (indented continuation text some Kanban cards
  carry) are not captured in the CSV. That's the useful granularity for a
  fallback task list; the full card body still lives in the source
  Kanban.md for anyone who needs it.

  Idempotent and read-only against its input: regenerating overwrites only
  the Kanban.csv sibling, never touches Kanban.md.
.PARAMETER Root
  Vault root to sweep for Kanban.md files. Default: current directory.
.PARAMETER Path
  Target a single Kanban.md directly instead of sweeping the vault.
.EXAMPLE
  build-kanban-csv.ps1 -Root .
  build-kanban-csv.ps1 -Path apps/some-project/_meta/Kanban.md
#>
[CmdletBinding()]
param(
  [string]$Root = '.',
  [string]$Path
)

$ErrorActionPreference = 'Stop'
function Say { param([string]$m) Write-Host "[build-kanban-csv] $m" }

function Convert-KanbanToCsv {
  param([string]$KanbanPath)

  $csvPath = Join-Path (Split-Path $KanbanPath -Parent) 'Kanban.csv'
  $rows = [System.Collections.Generic.List[object]]::new()
  $column = ''

  foreach ($line in (Get-Content -Path $KanbanPath -Encoding UTF8)) {
    if ($line -match '^##\s+(.+?)\s*$') { $column = $Matches[1]; continue }
    if ($line -match '^-\s+\[([ xX])\]\s+(.*)$') {
      $rows.Add([pscustomobject]@{
        Column = $column
        Done   = ($Matches[1] -ne ' ')
        Task   = $Matches[2].Trim()
      })
    }
  }

  if ($rows.Count -eq 0) {
    Say "no task items found in $KanbanPath — skipped (no Kanban.csv written)"
    return
  }
  $rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
  Say ("wrote {0} row(s) to {1}" -f $rows.Count, $csvPath)
}

if ($Path) {
  if (-not (Test-Path $Path)) { throw "not found: $Path" }
  Convert-KanbanToCsv -KanbanPath (Resolve-Path $Path).Path
  exit 0
}

$found = @(Get-ChildItem -Path $Root -Filter 'Kanban.md' -Recurse -File -ErrorAction SilentlyContinue)
if ($found.Count -eq 0) { Say "no Kanban.md files found under $Root"; exit 0 }
foreach ($f in $found) { Convert-KanbanToCsv -KanbanPath $f.FullName }
Say ("done — {0} Kanban.md file(s) processed" -f $found.Count)
