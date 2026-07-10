#Requires -Version 7.0
<#
.SYNOPSIS
  Sync each note's frontmatter `updated:` field to the file's mtime date.
.DESCRIPTION
  Idempotent transform. For every markdown file under -Scopes that has an
  `updated:` line in frontmatter, rewrite that line to the file's current
  last-modified date (YYYY-MM-DD, local time). Files without an `updated:`
  field are skipped -- the field isn't imposed on notes that don't use it.

  Scopes default to vault directories where humans/agents author notes:
  `_meta/`, `_areas/`, `_resources/`, `launchpad/`, plus every project's own
  `_meta/` one level under any non-reserved top-level directory (adopter-
  named category roots, spec §File & folder taxonomy -- discovered
  generically, same pattern as bury.ps1's project search, not a fixed
  category manifest). Auto-generated folders (`_journal/`, `_inbox/`,
  `_archive/`, `_sewerpipe/`, `_radar/_digests/`) are deliberately excluded,
  as are `node_modules/`, `.git/`, `.obsidian/`.

  Pure transform (read frontmatter, compare to mtime, rewrite if drift) --
  a fit for absorption into a spec §Transform manifest instance if an
  adopter wants it declared rather than invoked directly.
.PARAMETER Root
  Vault root.
.PARAMETER Scopes
  Explicit directories to scan, overriding the default discovery above.
.PARAMETER DryRun
  Report what would change without writing.
.EXAMPLE
  bump-updated-field.ps1 -Root .
  bump-updated-field.ps1 -Root . -DryRun
  bump-updated-field.ps1 -Root . -Scopes _meta
#>
[CmdletBinding()]
param(
  [string]$Root   = '.',
  [string[]]$Scopes,
  [string]$Date   = (Get-Date -Format 'yyyy-MM-dd'),
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path $Root).Path

$logPath = Join-Path $Root "_meta/logs/bump-updated-$Date.log"
$logDir  = Split-Path $logPath -Parent
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Write-Log {
  param([string]$Message)
  $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
  Add-Content -Path $logPath -Value $line -Encoding UTF8
  Write-Host $line
}

# --- Resolve scopes ---
if (-not $Scopes -or $Scopes.Count -eq 0) {
  $Scopes = @(
    (Join-Path $Root '_meta'),
    (Join-Path $Root '_areas'),
    (Join-Path $Root '_resources'),
    (Join-Path $Root 'launchpad')
  )
  # Generic discovery: any non-reserved top-level dir is a category root
  # (spec §File & folder taxonomy) -- no fixed manifest of category names.
  foreach ($catRoot in (Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue)) {
    if ($catRoot.Name.StartsWith('_') -or $catRoot.Name -eq 'launchpad') { continue }
    Get-ChildItem $catRoot.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $metaDir = Join-Path $_.FullName '_meta'
      if (Test-Path $metaDir) { $Scopes += $metaDir }
    }
  }
} else {
  # Relative scopes join against -Root; an already-absolute scope passes through.
  $Scopes = $Scopes | ForEach-Object {
    if ([System.IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $Root $_ }
  }
}

$Scopes = $Scopes | Where-Object { Test-Path $_ }

Write-Log ("bump-updated: starting (root={0}, dry-run={1}, scopes={2})" -f $Root, $DryRun.IsPresent, $Scopes.Count)

# --- Walk and transform ---
$rxFM      = [regex]'(?s)\A(---\s*\r?\n)(.*?)(\r?\n---\s*\r?\n)'
$rxUpdated = [regex]"(?m)^(updated:\s*)(['""]?)(\d{4}-\d{2}-\d{2})(\2)(\s*)$"

$scanned = 0
$skippedNoFm = 0
$skippedNoField = 0
$inSync = 0
$bumped = 0
$bumpedFiles = @()

foreach ($scope in $Scopes) {
  Get-ChildItem $scope -Filter '*.md' -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    # Defensive exclusions even within scoped dirs (e.g. an _archive/ nested
    # somewhere). Path normalized to '/' first -- FullName uses '\' on
    # Windows and the live workspace this ported from matched literal '\',
    # which silently never fires on a POSIX host.
    $p = $_.FullName.ToLowerInvariant().Replace('\', '/')
    if ($p -match '/(_archive|_inbox|_sewerpipe|_journal|node_modules|\.git|\.obsidian)/') { return }

    $scanned++
    $raw  = Get-Content $_.FullName -Raw -Encoding UTF8
    $mFm  = $rxFM.Match($raw)
    if (-not $mFm.Success) { $skippedNoFm++; return }

    $body = $mFm.Groups[2].Value
    $mUp  = $rxUpdated.Match($body)
    if (-not $mUp.Success) { $skippedNoField++; return }

    $current = $mUp.Groups[3].Value
    $mtimeDate = $_.LastWriteTime.ToString('yyyy-MM-dd')
    if ($current -eq $mtimeDate) { $inSync++; return }

    $rel = [System.IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/')

    if ($DryRun) {
      Write-Log ("[dry-run] would bump: {0} ({1} -> {2})" -f $rel, $current, $mtimeDate)
      $bumped++
      $bumpedFiles += $rel
      return
    }

    # Rewrite the updated: line in-place. Preserve quoting style + trailing whitespace.
    $newBody = $rxUpdated.Replace($body, {
      param($mm)
      "$($mm.Groups[1].Value)$($mm.Groups[2].Value)$mtimeDate$($mm.Groups[4].Value)$($mm.Groups[5].Value)"
    }, 1)
    $newRaw = $mFm.Groups[1].Value + $newBody + $mFm.Groups[3].Value + $raw.Substring($mFm.Index + $mFm.Length)

    # Preserve mtime -- we don't want this script's own write to retrigger drift on the next run.
    $origMtime = $_.LastWriteTime
    Set-Content -Path $_.FullName -Value $newRaw -Encoding UTF8 -NoNewline
    (Get-Item $_.FullName).LastWriteTime = $origMtime

    Write-Log ("bumped: {0} ({1} -> {2})" -f $rel, $current, $mtimeDate)
    $bumped++
    $bumpedFiles += $rel
  }
}

Write-Log ("bump-updated: done. scanned={0} bumped={1} in-sync={2} no-field={3} no-frontmatter={4}" -f $scanned, $bumped, $inSync, $skippedNoField, $skippedNoFm)

if ($bumped -gt 0 -and -not $DryRun) {
  exit 0
} elseif ($bumped -gt 0 -and $DryRun) {
  exit 2  # signal "would change" to wrappers that want to know
} else {
  exit 0
}
