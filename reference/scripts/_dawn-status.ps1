#Requires -Version 7.0
<#
.SYNOPSIS
  Parse system-o darkloop evidence for the dawn report.
.DESCRIPTION
  Dot-sourced by build-dawn-report.ps1. Each parser returns a stable object
  with Name, State, Detail, and Evidence fields. State uses the dawn report
  vocabulary: clean, applied, proposed, held, finding, or silence.
#>

function New-DawnStatus {
  param(
    [string]$Name,
    [ValidateSet('clean', 'applied', 'proposed', 'held', 'finding', 'skipped', 'silence')]
    [string]$State,
    [string]$Detail,
    [string[]]$Evidence = @()
  )
  [pscustomobject]@{
    Name = $Name
    State = $State
    Detail = $Detail
    Evidence = @($Evidence)
  }
}

function Read-DawnChainManifest {
  <#
    Parses _meta/chain.yaml (spec §Automation chain manifest). Deliberately a
    small hand-rolled reader, matching how the loop runner reads its own
    manifests: the reference depends on no YAML module.

    chain:
      - task: triage-inbox
        log: triage
        parser: triage
  #>
  param([Parameter(Mandatory)][string]$Path)

  $entries = [System.Collections.Generic.List[object]]::new()
  $current = $null
  foreach ($raw in (Get-Content -Path $Path -Encoding UTF8)) {
    $line = ($raw -replace '\s+#.*$', '').TrimEnd()
    if ($line -match '^\s*-\s+task:\s*(\S+)\s*$') {
      if ($current) { $entries.Add($current) }
      $current = [pscustomobject]@{ Task = $Matches[1].Trim('"', "'"); Log = ''; Parser = 'heartbeat' }
      continue
    }
    if (-not $current) { continue }
    if ($line -match '^\s+log:\s*(\S+)\s*$') { $current.Log = $Matches[1].Trim('"', "'") }
    elseif ($line -match '^\s+parser:\s*(\S+)\s*$') { $current.Parser = $Matches[1].Trim('"', "'") }
  }
  if ($current) { $entries.Add($current) }
  foreach ($entry in $entries) { if (-not $entry.Log) { $entry.Log = $entry.Task } }
  return @($entries)
}

function Read-DawnTaskStatus {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Type,
    [Parameter(Mandatory)][string]$LogPath
  )

  if (-not (Test-Path $LogPath)) {
    return New-DawnStatus -Name $Name -State silence -Detail 'log missing'
  }

  $body = Get-Content -Path $LogPath -Raw -Encoding UTF8
  switch ($Type) {
    'triage' {
      if ($body -notmatch 'triage-inbox:\s*done\.\s*junk=(\d+)\s+proposed=(\d+)\s+stale=(\d+)\s+skipped=(\d+)') {
        return New-DawnStatus -Name $Name -State finding -Detail 'ran but emitted no completion evidence'
      }
      $changed = [int]$Matches[1] + [int]$Matches[2] + [int]$Matches[3]
      $detail = "junk=$($Matches[1]) proposed=$($Matches[2]) stale=$($Matches[3]) skipped=$($Matches[4])"
      return New-DawnStatus -Name $Name -State $(if ($changed -gt 0) { 'applied' } else { 'clean' }) -Detail $detail
    }
    'purge' {
      if ($body -notmatch 'purge-sewerpipe:\s*done\.\s*deleted=(\d+)\s+total=([^\r\n\s]+)') {
        return New-DawnStatus -Name $Name -State finding -Detail 'ran but emitted no completion evidence'
      }
      $deleted = [int]$Matches[1]
      $total = $Matches[2]
      # A dry run counts what it WOULD have removed, so reporting it as applied
      # would put a false statement in the evidence artifact.
      if ($body -match 'purge-sewerpipe:\s*done\..*dry-run=\s*(?i:true)') {
        return New-DawnStatus -Name $Name -State skipped -Detail "would-delete=$deleted total=$total; dry run, nothing removed"
      }
      $detail = "deleted=$deleted total=$total"
      return New-DawnStatus -Name $Name -State $(if ($deleted -gt 0) { 'applied' } else { 'clean' }) -Detail $detail
    }
    'sweep' {
      if ($body -notmatch 'sweep-handoffs:\s*done\.\s*swept=(\d+)\s+kept=(\d+)\s+skipped=(\d+)') {
        return New-DawnStatus -Name $Name -State finding -Detail 'ran but emitted no completion evidence'
      }
      $swept = [int]$Matches[1]
      $kept = [int]$Matches[2]
      $skipped = [int]$Matches[3]
      $detail = "swept=$swept kept=$kept skipped=$skipped"
      $findings = @($body -split "`r?`n" | Where-Object {
        $_ -match 'lint:\s+WARN findings present|\bERROR:'
      })
      if ($findings.Count -gt 0) {
        return New-DawnStatus -Name $Name -State finding -Detail "$detail; downstream findings present" -Evidence $findings
      }
      return New-DawnStatus -Name $Name -State $(if ($swept -gt 0) { 'applied' } else { 'clean' }) -Detail $detail
    }
    'extensions' {
      $line = @($body -split "`r?`n" | Where-Object { $_ -match '^STATUS\s+extensions=' } | Select-Object -Last 1)
      if ($line.Count -eq 0 -or $line[0] -notmatch '^STATUS\s+extensions=(\d+)\s+flagged=(\d+)(?:\s+\[([^\]]+)\])?') {
        return New-DawnStatus -Name $Name -State finding -Detail 'ran but emitted no STATUS evidence'
      }
      $total = [int]$Matches[1]
      $flagged = [int]$Matches[2]
      $names = $Matches[3]
      if ($flagged -gt 0) {
        $evidence = if ($names) { @($names -split ',' | ForEach-Object { $_.Trim() }) } else { @() }
        return New-DawnStatus -Name $Name -State finding -Detail "$flagged of $total extensions flagged" -Evidence $evidence
      }
      return New-DawnStatus -Name $Name -State clean -Detail "$total extensions checked, none flagged"
    }
    'loop' {
      $line = @($body -split "`r?`n" | Where-Object { $_ -match '^STATUS\s+loop=' } | Select-Object -Last 1)
      if ($line.Count -eq 0 -or $line[0] -notmatch '^STATUS\s+loop=(\S+).*?findings=(\d+)\s+proposals_new=(\d+)\s+auto_applied=(\d+)\s+verifier_fail=(\d+)\s+scope_fail=(\d+)') {
        return New-DawnStatus -Name $Name -State finding -Detail 'ran but emitted no STATUS evidence'
      }
      $findings = [int]$Matches[2]
      $proposed = [int]$Matches[3]
      $applied = [int]$Matches[4]
      $verifierFail = [int]$Matches[5]
      $scopeFail = [int]$Matches[6]
      $detail = "findings=$findings proposed=$proposed applied=$applied verifier_fail=$verifierFail scope_fail=$scopeFail"
      if ($verifierFail -gt 0 -or $scopeFail -gt 0) {
        return New-DawnStatus -Name $Name -State finding -Detail $detail
      }
      if ($findings -eq 0) {
        return New-DawnStatus -Name $Name -State clean -Detail $detail
      }
      if ($proposed -gt $applied) {
        return New-DawnStatus -Name $Name -State proposed -Detail $detail
      }
      if ($applied -gt 0) {
        return New-DawnStatus -Name $Name -State applied -Detail $detail
      }
      return New-DawnStatus -Name $Name -State held -Detail "$detail; no new repair was written"
    }
    'heartbeat' {
      # The portable default: any registered task whose log format the
      # reference does not know. Presence of the log is the beat; a STATUS
      # line, if the task emits one, is the detail.
      $lines = @($body -split "`r?`n" | Where-Object { $_.Trim() })
      $statusLine = @($lines | Where-Object { $_ -match '^\s*STATUS\s' } | Select-Object -Last 1)
      if ($statusLine.Count -gt 0) {
        return New-DawnStatus -Name $Name -State clean -Detail ($statusLine[0].Trim() -replace '^STATUS\s+', '')
      }
      if ($lines.Count -gt 0) {
        $last = $lines[-1].Trim()
        if ($last.Length -gt 120) { $last = $last.Substring(0, 117) + '...' }
        return New-DawnStatus -Name $Name -State clean -Detail $last
      }
      return New-DawnStatus -Name $Name -State clean -Detail 'ran, empty log'
    }
    default {
      # A typo in one manifest entry must not take the whole surfacing
      # artifact down with it. Report it as a finding and keep building.
      return New-DawnStatus -Name $Name -State finding -Detail "unknown parser '$Type' declared in the chain manifest"
    }
  }
}

function Get-DawnLastBeat {
  param(
    [Parameter(Mandatory)][string]$LogsDir,
    [Parameter(Mandatory)][string]$Prefix,
    [Parameter(Mandatory)][string]$BeforeDate
  )
  $dates = @(Get-ChildItem -Path $LogsDir -Filter "$Prefix-*.log" -File -ErrorAction SilentlyContinue |
    ForEach-Object {
      if ($_.Name -match '(\d{4}-\d{2}-\d{2})\.log$' -and $Matches[1] -lt $BeforeDate) {
        $Matches[1]
      }
    } | Sort-Object)
  if ($dates.Count -gt 0) { return $dates[-1] }
  return $null
}
