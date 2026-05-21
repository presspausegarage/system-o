#Requires -Version 7.0
<#
.SYNOPSIS
    Transform a canonical orientation file using a declarative YAML manifest.

.DESCRIPTION
    Reads a canonical orientation file (e.g. CLAUDE.md), applies the transforms
    declared in a manifest YAML, and writes the result to a target file.

    Operations are applied in fixed order (spec §Transform manifest §Operation order):
      1. sections  — structural edits (remove / replace / remove_lines_matching)
      2. paths     — file-path substring substitutions
      3. renames   — token-level substitutions

    Determinism guarantee: same Source + same Manifest → byte-identical output
    (modulo trailing newline normalisation to a single LF). No network calls,
    no LLM invocation, no writes outside the Target file.

.PARAMETER Source
    Path to the canonical orientation file (e.g. CLAUDE.md).

.PARAMETER Manifest
    Path to the transform manifest YAML file.

.PARAMETER Target
    Output path. If omitted, resolved from the manifest's `target:` field
    relative to the Source file's directory.

.PARAMETER DryRun
    Print the transformed content to stdout instead of writing to disk.

.EXAMPLE
    .\transform-orientation.ps1 -Source CLAUDE.md -Manifest _meta/agent-context/transform-claude-to-agents.yaml

.EXAMPLE
    .\transform-orientation.ps1 -Source CLAUDE.md -Manifest transform.yaml -DryRun
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$Manifest,

    [string]$Target = '',

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Manifest YAML parser ────────────────────────────────────────────────────
# Handles exactly the schema defined in spec §Transform manifest.
# Not a general YAML parser.

function Read-Manifest {
    param([string]$Path)

    $lines = (Get-Content $Path -Raw -Encoding UTF8) -replace "`r`n","`n" -replace "`r","`n" -split "`n"

    $out = @{
        source   = ''
        target   = ''
        renames  = [System.Collections.ArrayList]::new()
        paths    = [System.Collections.ArrayList]::new()
        sections = [System.Collections.ArrayList]::new()
    }

    $block = ''
    $i = 0

    while ($i -lt $lines.Count) {
        $line = $lines[$i]

        # Skip blank lines and comments
        if ($line -match '^\s*(#.*)?$') { $i++; continue }

        # Top-level scalar
        if ($line -match '^(source|target):\s*(.+)$') {
            $out[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
            $block = ''; $i++; continue
        }

        # Block header
        if ($line -match '^(renames|paths|sections):\s*$') {
            $block = $Matches[1]; $i++; continue
        }

        # Array item inside a known block
        if ($block -ne '' -and $line -match '^\s*-\s+') {
            $rest = ($line -replace '^\s*-\s+', '').Trim()

            if ($rest -match '^\{') {
                # Inline flow-style: { key: "val", key: val, ... }
                $inner = $rest -replace '^\{' -replace '\}\s*$'
                $item  = Parse-FlowFields $inner
                [void]$out[$block].Add($item)
                $i++; continue
            }

            # Block-style: first key is on the `- key: val` line; rest is indented
            $item = @{}
            if ($rest -match '^([\w_]+):\s*(.*)$') {
                $k = $Matches[1]; $v = $Matches[2].Trim().Trim('"').Trim("'")
                $item[$k] = Coerce-Value $k $v
            }
            $i++

            while ($i -lt $lines.Count -and $lines[$i] -match '^[ \t]{2,}([\w_]+):\s*(.*)$') {
                $k = $Matches[1]; $v = $Matches[2].Trim()

                if ($v -eq '|' -or $v -eq '>') {
                    # Block-scalar — collect body until de-indent
                    $minIndent = ($lines[$i] -replace '^(\s+).*','$1').Length + 2
                    $bodyLines = [System.Collections.ArrayList]::new()
                    $i++
                    while ($i -lt $lines.Count) {
                        $bl = $lines[$i]
                        if ($bl -match '^\s*$') {
                            [void]$bodyLines.Add(''); $i++; continue
                        }
                        $blIndent = ($bl -replace '^(\s+).*','$1').Length
                        if ($blIndent -lt $minIndent) { break }
                        [void]$bodyLines.Add($bl -replace "^\s{$minIndent}")
                        $i++
                    }
                    $item[$k] = ($bodyLines -join "`n").TrimEnd("`n")
                    continue
                }

                $item[$k] = Coerce-Value $k $v.Trim('"').Trim("'")
                $i++
            }

            [void]$out[$block].Add($item)
            continue  # $i already advanced
        }

        # Non-indented non-matched line resets block context
        if ($line -notmatch '^[ \t]') { $block = '' }
        $i++
    }

    return $out
}

function Parse-FlowFields {
    param([string]$text)
    $item = @{}
    $parts = Split-CSV $text
    foreach ($part in $parts) {
        $part = $part.Trim()
        if ($part -match '^([\w_]+)\s*:\s*(.*)$') {
            $k = $Matches[1]; $v = $Matches[2].Trim().Trim('"').Trim("'")
            $item[$k] = Coerce-Value $k $v
        }
    }
    return $item
}

function Coerce-Value {
    param([string]$key, [string]$val)
    # Coerce known boolean fields and integer fields
    if ($key -in @('case_sensitive','word_boundary')) {
        return $val -ne 'false'  # default true; only false when explicitly "false"
    }
    if ($key -eq 'level' -and $val -match '^\d+$') { return [int]$val }
    return $val
}

function Split-CSV {
    # Split on commas that are not inside single or double quotes
    param([string]$text)
    $parts  = [System.Collections.ArrayList]::new()
    $cur    = [System.Text.StringBuilder]::new()
    $inQ    = $false
    $qChar  = [char]0
    foreach ($ch in $text.ToCharArray()) {
        if (-not $inQ -and ($ch -eq '"' -or $ch -eq "'")) {
            $inQ = $true; $qChar = $ch; [void]$cur.Append($ch)
        } elseif ($inQ -and $ch -eq $qChar) {
            $inQ = $false; [void]$cur.Append($ch)
        } elseif (-not $inQ -and $ch -eq ',') {
            [void]$parts.Add($cur.ToString()); [void]$cur.Clear()
        } else {
            [void]$cur.Append($ch)
        }
    }
    if ($cur.Length -gt 0) { [void]$parts.Add($cur.ToString()) }
    return $parts
}

# ─── Section operations ───────────────────────────────────────────────────────

function Get-SectionBounds {
    param([string[]]$lines, [string]$header, [int]$level)
    $prefix = ('#' * $level) + ' '
    $startIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq ($prefix + $header)) { $startIdx = $i; break }
    }
    if ($startIdx -lt 0) { return $null }
    # End = next header at same-or-higher level (fewer # chars), or EOF
    $endIdx = $lines.Count
    for ($i = $startIdx + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('^#{1,' + $level + '} ')) { $endIdx = $i; break }
    }
    return @{ Start = $startIdx; End = $endIdx }
}

function Invoke-SectionOps {
    param([string[]]$lines, [System.Collections.ArrayList]$ops)
    foreach ($op in $ops) {
        switch ($op['action']) {
            'remove' {
                $b = Get-SectionBounds $lines $op['header'] ([int]$op['level'])
                if ($null -eq $b) {
                    Write-Warning "Section not found (remove): '$($op['header'])' level $($op['level'])"
                    break
                }
                $r = [System.Collections.ArrayList]::new()
                for ($j = 0; $j -lt $lines.Count; $j++) {
                    if ($j -lt $b.Start -or $j -ge $b.End) { [void]$r.Add($lines[$j]) }
                }
                $lines = @($r | ForEach-Object { $_ })
            }
            'replace' {
                $b = Get-SectionBounds $lines $op['header'] ([int]$op['level'])
                if ($null -eq $b) {
                    Write-Warning "Section not found (replace): '$($op['header'])' level $($op['level'])"
                    break
                }
                $r = [System.Collections.ArrayList]::new()
                for ($j = 0; $j -lt $b.Start;   $j++) { [void]$r.Add($lines[$j]) }
                [void]$r.Add($lines[$b.Start])  # keep header
                $withLines = ($op['with'] -replace "`r`n","`n" -replace "`r","`n") -split "`n"
                foreach ($wl in $withLines) { [void]$r.Add($wl) }
                for ($j = $b.End; $j -lt $lines.Count; $j++) { [void]$r.Add($lines[$j]) }
                $lines = @($r | ForEach-Object { $_ })
            }
            'remove_lines_matching' {
                $pat = $op['pattern']
                $lines = @($lines | Where-Object { $_ -notmatch $pat })
            }
            default { Write-Warning "Unknown section action: $($op['action'])" }
        }
    }
    return $lines
}

# ─── Substitution operations ──────────────────────────────────────────────────

function Invoke-SubstitutionOps {
    param([string]$text, [System.Collections.ArrayList]$ops, [bool]$defaultWordBoundary)

    foreach ($op in $ops) {
        $from = $op['from']
        $to   = $op['to']

        # Read flags — Coerce-Value already applied bool coercion
        $caseSensitive = if ($op.ContainsKey('case_sensitive')) { [bool]$op['case_sensitive'] } else { $true }
        $wordBoundary  = if ($op.ContainsKey('word_boundary'))  { [bool]$op['word_boundary'] }  else { $defaultWordBoundary }

        $escaped = [regex]::Escape($from)
        if ($wordBoundary) { $escaped = '\b' + $escaped + '\b' }

        $reOpts = if ($caseSensitive) {
            [System.Text.RegularExpressions.RegexOptions]::None
        } else {
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        }

        if ($caseSensitive) {
            # Escape $ in replacement so .NET doesn't treat it as a backreference
            $escapedTo = $to -replace '\$', '$$$$'
            $text = [regex]::Replace($text, $escaped, $escapedTo, $reOpts)
        } else {
            # Case-preserving: first-char case of match propagates to first char of replacement
            $capturedTo = $to
            $evaluatorBlock = {
                param($m)
                if ($capturedTo.Length -gt 0 -and $m.Value.Length -gt 0 -and [char]::IsUpper($m.Value[0])) {
                    return [char]::ToUpper($capturedTo[0]).ToString() + $capturedTo.Substring(1)
                }
                return $capturedTo
            }.GetNewClosure()
            $text = [regex]::Replace($text, $escaped, [System.Text.RegularExpressions.MatchEvaluator]$evaluatorBlock, $reOpts)
        }
    }

    return $text
}

# ─── Main ─────────────────────────────────────────────────────────────────────

$sourcePath   = (Resolve-Path $Source).Path
$manifestPath = (Resolve-Path $Manifest).Path

$mf = Read-Manifest $manifestPath

if ($mf['source'] -and $mf['source'] -ne (Split-Path $sourcePath -Leaf)) {
    Write-Warning "Manifest source '$($mf['source'])' does not match input '$( Split-Path $sourcePath -Leaf)'"
}

$targetPath = if ($Target -ne '') {
    $Target
} elseif ($mf['target'] -ne '') {
    Join-Path (Split-Path $sourcePath -Parent) $mf['target']
} else {
    throw "No -Target specified and manifest has no 'target:' field."
}

# Read source — normalise to LF
$raw   = (Get-Content $sourcePath -Raw -Encoding UTF8) -replace "`r`n","`n" -replace "`r","`n"
$lines = $raw -split "`n"
# Trim trailing empty element from final-newline split
if ($lines.Count -gt 0 -and $lines[-1] -eq '') { $lines = $lines[0..($lines.Count - 2)] }

# 1. Section ops
if ($mf['sections'].Count -gt 0) {
    $lines = Invoke-SectionOps $lines $mf['sections']
}

# 2. Paths (word_boundary default: false)
$body = $lines -join "`n"
if ($mf['paths'].Count -gt 0) {
    $body = Invoke-SubstitutionOps $body $mf['paths'] $false
}

# 3. Renames (word_boundary default: true)
if ($mf['renames'].Count -gt 0) {
    $body = Invoke-SubstitutionOps $body $mf['renames'] $true
}

# Normalise: single trailing newline
$output = $body.TrimEnd("`n") + "`n"

if ($DryRun) {
    Write-Output $output
} else {
    [System.IO.File]::WriteAllText($targetPath, $output, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Wrote $targetPath ($($output.Length) bytes, no BOM)"
}
