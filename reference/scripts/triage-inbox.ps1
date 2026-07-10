#Requires -Version 7.0
<#
.SYNOPSIS
  Daily inbox classifier -- walks _inbox/, auto-routes obvious junk to
  _sewerpipe/, and proposes destinations for human review.
.DESCRIPTION
  Two things this script does NOT do, by design (spec §Inbox routing,
  covered piecemeal today -- see §File & folder taxonomy's out-of-scope
  note): it never auto-moves anything ambiguous, and folders are never
  considered for rule-based auto-routing, only files. A human applies
  proposals via apply-proposals.ps1.

  Stale sweep: anything still unrouted after -StaleDays (no
  proposed_destination set) moves to _sewerpipe/ with its mtime reset, so
  purge-sewerpipe.ps1's full retention window applies from the move, not
  from original capture. Items already carrying a proposal are never swept
  -- they're awaiting human review, not abandoned.

  Classification is intentionally minimal and adopter-extended, not
  manifest-driven like Transform/Loop (spec §Transform manifest, §Loop
  manifest): Get-ProposedDestination holds two generic filename-pattern
  rules (handoff, meeting) an adopter is expected to edit directly for
  their own vocabulary. The live workspace this was ported from also
  carried a hardcoded site-name lookup table for its own SEO-audit
  captures -- operator content, not a portable rule, and dropped rather
  than generalized (spec §System architecture: "strip the operator's
  specific content"). -JunkSources plays the same role for the
  auto-capture-noise filter: the live workspace's `vaultcast` daemon tags
  its own drops `source: vaultcast`; an adopter with a different capture
  tool overrides this list rather than editing code.
.PARAMETER Root
  Vault root.
.PARAMETER StaleDays
  Days an unrouted, un-proposed item may sit in _inbox/ before the stale
  sweep moves it to _sewerpipe/.
.PARAMETER JunkSources
  Frontmatter `source:` values treated as auto-capture noise when paired
  with a body under 200 characters.
.PARAMETER DryRun
  Report what would happen without moving or editing anything.
.EXAMPLE
  triage-inbox.ps1 -Root .
  triage-inbox.ps1 -Root . -JunkSources vaultcast,my-capture-tool -DryRun
#>
[CmdletBinding()]
param(
  [string]$Root = '.',
  [int]$StaleDays = 14,
  [string[]]$JunkSources = @('vaultcast'),
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$inboxPath     = Join-Path $Root '_inbox'
$sewerpipePath = Join-Path $Root '_sewerpipe'
$logDir        = Join-Path $Root '_meta/logs'
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logFile = Join-Path $logDir ("triage-{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))

$skipNames = @('README.md', 'desktop.ini')

function Write-Log {
    param([string]$msg)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Write-Output $line
    Add-Content -Path $logFile -Value $line -Encoding utf8
}

function Read-Frontmatter {
    param([string]$path)
    $lines = Get-Content -Path $path -ErrorAction SilentlyContinue
    if (-not $lines -or $lines[0] -ne '---') { return @{} }
    $fm = @{}
    $i = 1
    while ($i -lt $lines.Count -and $lines[$i] -ne '---') {
        if ($lines[$i] -match '^([a-zA-Z_][a-zA-Z0-9_-]*):\s*(.*)$') {
            $fm[$matches[1]] = $matches[2].Trim()
        }
        $i++
    }
    return $fm
}

function Get-BodyLength {
    param([string]$path)
    $content = Get-Content -Path $path -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return 0 }
    $body = $content -replace '(?s)^---.*?---\s*', ''
    return $body.Trim().Length
}

function Test-CaptureJunk {
    param([hashtable]$fm, [string]$path, [string[]]$sources)
    if ($sources -notcontains $fm['source']) { return $false }
    $bodyLen = Get-BodyLength $path
    # Auto-capture junk: a recognized source tag AND a tiny body (< 200 chars excluding frontmatter)
    return ($bodyLen -lt 200)
}

function Get-ProposedDestination {
    param([string]$name)
    if ($name -match 'handoff') {
        return @{ destination = "_meta/handoffs/$name"; type = 'handoff' }
    }
    if ($name -match '(meeting|standup|1:1)') {
        return @{ destination = "_journal/$name"; type = 'meeting' }
    }
    return $null
}

function Add-FrontmatterField {
    param([string]$path, [string]$key, [string]$value)
    $content = Get-Content -Path $path -Raw
    if ($content -match '(?s)^(---\r?\n)(.*?)(\r?\n---)(.*)$') {
        $head = $matches[1] + $matches[2] + "`n${key}: $value" + $matches[3]
        $tail = $matches[4]
        Set-Content -Path $path -Value ($head + $tail) -Encoding utf8 -NoNewline
    } else {
        $newContent = "---`n${key}: $value`n---`n$content"
        Set-Content -Path $path -Value $newContent -Encoding utf8 -NoNewline
    }
}

# ---- Main ----

Write-Log "triage-inbox: starting (root=$Root, dry-run=$DryRun)"

$items = Get-ChildItem -Path $inboxPath -File -ErrorAction SilentlyContinue |
    Where-Object { $skipNames -notcontains $_.Name }

$junk = 0; $proposed = 0; $skipped = 0
foreach ($item in $items) {
    $fm = Read-Frontmatter $item.FullName

    if ($fm['proposed_destination']) {
        Write-Log "skip (already proposed): $($item.Name)"
        $skipped++
        continue
    }

    if (Test-CaptureJunk -fm $fm -path $item.FullName -sources $JunkSources) {
        $dest = Join-Path $sewerpipePath $item.Name
        if (-not $DryRun) { Move-Item -Path $item.FullName -Destination $dest -Force }
        Write-Log "junk -> sewerpipe: $($item.Name)"
        $junk++
        continue
    }

    $proposal = Get-ProposedDestination $item.Name
    if ($proposal) {
        if (-not $DryRun) {
            Add-FrontmatterField -path $item.FullName -key 'proposed_destination' -value $proposal.destination
            Add-FrontmatterField -path $item.FullName -key 'proposed_type'        -value $proposal.type
        }
        Write-Log "proposed: $($item.Name) -> $($proposal.destination)"
        $proposed++
        continue
    }

    Write-Log "no rule matched: $($item.Name) (left in _inbox/)"
    $skipped++
}

# ---- Stale sweep: unrouted items idle > $StaleDays -> _sewerpipe (mtime reset) ----

$staleCutoff = (Get-Date).AddDays(-$StaleDays)
$stale = 0
$staleItems = Get-ChildItem -Path $inboxPath -ErrorAction SilentlyContinue |
    Where-Object { $skipNames -notcontains $_.Name -and $_.LastWriteTime -lt $staleCutoff }
foreach ($item in $staleItems) {
    if (-not $item.PSIsContainer) {
        $fm = Read-Frontmatter $item.FullName
        if ($fm['proposed_destination']) { continue }   # awaiting human review, never sweep
    }
    $dest = Join-Path $sewerpipePath $item.Name
    if (Test-Path $dest) { $dest = Join-Path $sewerpipePath ("{0}-{1}" -f (Get-Date -Format 'yyyyMMddHHmmss'), $item.Name) }
    if (-not $DryRun) {
        try {
            Move-Item -Path $item.FullName -Destination $dest
            (Get-Item $dest).LastWriteTime = Get-Date   # reset: full retention window from the move
        } catch {
            Write-Log "ERROR stale move failed: $($item.Name) -- $($_.Exception.Message)"
            continue
        }
    }
    Write-Log "stale (>$StaleDays d, unrouted) -> sewerpipe: $($item.Name)"
    $stale++
}

Write-Log "triage-inbox: done. junk=$junk proposed=$proposed stale=$stale skipped=$skipped"
exit 0
