#Requires -Version 7.0
<#
.SYNOPSIS
  Extension: flag notes missing a minimum frontmatter `type:` field.
.DESCRIPTION
  Worked example of the extension contract (spec §Extension surface). Generic
  by construction: scans a configurable directory list for markdown files
  whose YAML frontmatter has no `type:` key — a minimum-viable schema check
  any vault convention can build on without naming specific note types.
.PARAMETER Root
  Vault root.
.PARAMETER ScanDirs
  Directories to scan, relative to Root (recursive). Default: _meta.
.PARAMETER ExcludeMatch
  Regex; matching full paths are skipped (e.g. logs/scripts/handoffs subtrees
  that carry their own frontmatter convention or none at all).
.PARAMETER DryRun
  Required by the extension contract; this check never writes regardless.
#>
[CmdletBinding()]
param(
  [string]$Root = '.',
  [string[]]$ScanDirs = @('_meta'),
  [string]$ExcludeMatch = '[\\/](logs|scripts|handoffs|extensions)([\\/]|$)',
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$missing = New-Object System.Collections.Generic.List[string]

foreach ($sd in $ScanDirs) {
  $dir = Join-Path $Root $sd
  if (-not (Test-Path $dir)) { continue }
  foreach ($f in (Get-ChildItem -Path $dir -Filter '*.md' -File -Recurse | Where-Object { $_.FullName -notmatch $ExcludeMatch })) {
    $head = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
    $fm = [regex]::Match($head, '(?s)\A---\s*\r?\n(.*?)\r?\n---')
    if (-not $fm.Success -or $fm.Groups[1].Value -notmatch '(?m)^type\s*:') {
      $missing.Add($f.FullName.Substring((Resolve-Path $Root).Path.Length).TrimStart('\','/'))
    }
  }
}

$flagged = $missing.Count -gt 0
if ($flagged) {
  $sample = ($missing | Select-Object -First 5) -join '; '
  Write-Host ("$($missing.Count) note(s) missing type: -- $sample" + $(if ($missing.Count -gt 5) { ' ...' }))
} else {
  Write-Host "all scanned notes carry type:"
}

Write-Host ("EXTENSION-STATUS name=frontmatter-type flagged={0}" -f $flagged.ToString().ToLower())
