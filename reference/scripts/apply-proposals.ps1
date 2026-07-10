#Requires -Version 7.0
<#
.SYNOPSIS
  Interactive applier for triage-inbox.ps1's proposals, plus the loop
  layer's own review queue.
.DESCRIPTION
  Reads each file in _inbox/ carrying proposed_destination + proposed_type
  frontmatter, shows it, prompts Yes/No/Skip/Edit, then either moves it to
  the proposed destination (stripping the proposed_* fields, applying
  `type`), leaves it with the proposal cleared, leaves it untouched for a
  later run, or takes an operator-supplied destination override.

  Also walks _meta/loops/proposals/ (spec §Loop manifest) -- the loop
  runner's machine-generated repair proposals, a different review queue
  living outside _inbox/ so triage never touches them. Apply/reject is
  delegated to apply-loop-proposal.ps1, expected alongside this script in
  the same directory.

  Run manually after reviewing HOME's "Awaiting your review" block (or
  whatever surfaces proposals in an adopter's vault).
.PARAMETER Root
  Vault root.
.EXAMPLE
  apply-proposals.ps1 -Root .
#>
[CmdletBinding()]
param(
    [string]$Root = '.'
)

$ErrorActionPreference = 'Stop'

$inboxPath = Join-Path $Root '_inbox'

function Read-Frontmatter {
    param([string]$path)
    $lines = Get-Content -Path $path -ErrorAction SilentlyContinue
    if (-not $lines -or $lines[0] -ne '---') { return @{ fm = @{}; bodyStart = 0 } }
    $fm = @{}
    $i = 1
    while ($i -lt $lines.Count -and $lines[$i] -ne '---') {
        if ($lines[$i] -match '^([a-zA-Z_][a-zA-Z0-9_-]*):\s*(.*)$') {
            $fm[$matches[1]] = $matches[2].Trim()
        }
        $i++
    }
    return @{ fm = $fm; bodyStart = $i + 1 }
}

function Strip-ProposalFields {
    param([string]$path)
    $content = Get-Content -Path $path -Raw
    if ($content -notmatch '(?s)^---\r?\n(.*?)\r?\n---') { return }
    $fmText  = $matches[1]
    $rest    = $content.Substring($matches[0].Length)
    $newFm = $fmText -split "`n" |
        Where-Object { $_ -notmatch '^proposed_(destination|type):' } |
        Out-String
    $newContent = "---`n$($newFm.TrimEnd())`n---$rest"
    Set-Content -Path $path -Value $newContent -Encoding utf8 -NoNewline
}

function Add-OrUpdate-FrontmatterField {
    param([string]$path, [string]$key, [string]$value)
    $content = Get-Content -Path $path -Raw
    if ($content -match "(?s)^(---\r?\n)(.*?)(\r?\n---)(.*)$") {
        $fmText = $matches[2]
        $rest   = $matches[4]
        if ($fmText -match "(?m)^${key}:") {
            $fmText = $fmText -replace "(?m)^${key}:.*$", "${key}: $value"
        } else {
            $fmText = $fmText.TrimEnd() + "`n${key}: $value"
        }
        $newContent = "---`n$fmText`n---$rest"
    } else {
        $newContent = "---`n${key}: $value`n---`n$content"
    }
    Set-Content -Path $path -Value $newContent -Encoding utf8 -NoNewline
}

# ---- Main ----

$items = Get-ChildItem -Path $inboxPath -File |
    Where-Object { $_.Extension -eq '.md' -and $_.Name -ne 'README.md' } |
    ForEach-Object {
        $info = Read-Frontmatter $_.FullName
        if ($info.fm['proposed_destination']) {
            [PSCustomObject]@{
                File        = $_
                Destination = $info.fm['proposed_destination']
                Type        = $info.fm['proposed_type']
            }
        }
    }

if (-not $items) {
    Write-Output "No proposals waiting. Inbox is clean."
    exit 0
}

Write-Output ""
Write-Output "$($items.Count) proposal(s) waiting."
Write-Output ""

foreach ($p in $items) {
    Write-Output "============================================================"
    Write-Output "FILE:        $($p.File.Name)"
    Write-Output "DESTINATION: $($p.Destination)"
    Write-Output "TYPE:        $($p.Type)"
    Write-Output "------------------------------------------------------------"
    Get-Content $p.File.FullName -TotalCount 30 | ForEach-Object { "  $_" }
    Write-Output "------------------------------------------------------------"
    $choice = $Host.UI.PromptForChoice(
        'Action',
        'Apply this proposal?',
        @(
            (New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Move to proposed destination'),
            (New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Leave in inbox; clear proposal'),
            (New-Object System.Management.Automation.Host.ChoiceDescription '&Skip', 'Leave proposal; decide later'),
            (New-Object System.Management.Automation.Host.ChoiceDescription '&Edit', 'Override the destination path')
        ),
        0
    )

    switch ($choice) {
        0 {
            $destAbs = Join-Path $Root $p.Destination
            $destDir = Split-Path $destAbs -Parent
            if (-not (Test-Path $destDir)) { New-Item -Path $destDir -ItemType Directory -Force | Out-Null }
            Strip-ProposalFields $p.File.FullName
            if ($p.Type) { Add-OrUpdate-FrontmatterField -path $p.File.FullName -key 'type' -value $p.Type }
            Move-Item -Path $p.File.FullName -Destination $destAbs -Force
            Write-Output "  -> moved to $($p.Destination)"
        }
        1 {
            Strip-ProposalFields $p.File.FullName
            Write-Output "  -> proposal cleared; file stays in inbox"
        }
        2 {
            Write-Output "  -> skipped"
        }
        3 {
            $newDest = Read-Host "  New destination (relative to vault root)"
            if ($newDest) {
                $destAbs = Join-Path $Root $newDest
                $destDir = Split-Path $destAbs -Parent
                if (-not (Test-Path $destDir)) { New-Item -Path $destDir -ItemType Directory -Force | Out-Null }
                Strip-ProposalFields $p.File.FullName
                if ($p.Type) { Add-OrUpdate-FrontmatterField -path $p.File.FullName -key 'type' -value $p.Type }
                Move-Item -Path $p.File.FullName -Destination $destAbs -Force
                Write-Output "  -> moved to $newDest"
            } else {
                Write-Output "  -> empty path; skipped"
            }
        }
    }
    Write-Output ""
}

# ---- Loop proposals (machine-generated repairs from run-loop.ps1, spec §Loop manifest) ----
# These are edit-in-place actions, not file moves; apply/reject is delegated to
# apply-loop-proposal.ps1. They live outside _inbox so triage never touches them.

$loopDir = Join-Path $Root '_meta/loops/proposals'
$loopItems = @()
if (Test-Path $loopDir) {
    $loopItems = @(Get-ChildItem -Path $loopDir -Filter '*.md' -File | Where-Object {
        (Read-Frontmatter $_.FullName).fm['proposed_change']
    })
}
foreach ($lp in $loopItems) {
    $info = Read-Frontmatter $lp.FullName
    Write-Output "============================================================"
    Write-Output "LOOP PROPOSAL: $($lp.Name)"
    Write-Output "CHANGE:        $($info.fm['proposed_change'])  ->  $($info.fm['target'])"
    Write-Output "ENDPOINT:      $($info.fm['endpoint'])"
    Write-Output "------------------------------------------------------------"
    Get-Content $lp.FullName -TotalCount 30 | ForEach-Object { "  $_" }
    Write-Output "------------------------------------------------------------"
    $choice = $Host.UI.PromptForChoice(
        'Action',
        'Apply this loop proposal?',
        @(
            (New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Apply the change to the target file'),
            (New-Object System.Management.Automation.Host.ChoiceDescription '&Reject', 'Move proposal to _sewerpipe (30d net)'),
            (New-Object System.Management.Automation.Host.ChoiceDescription '&Skip', 'Decide later')
        ),
        0
    )
    switch ($choice) {
        0 { & (Join-Path $PSScriptRoot 'apply-loop-proposal.ps1') -File $lp.FullName -Root $Root }
        1 { & (Join-Path $PSScriptRoot 'apply-loop-proposal.ps1') -File $lp.FullName -Root $Root -Reject }
        2 { Write-Output "  -> skipped" }
    }
    Write-Output ""
}

Write-Output "Done."
