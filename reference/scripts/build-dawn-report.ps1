#Requires -Version 7.0
<#
.SYNOPSIS
  Build the system-o dawn crossing report as HTML and plain text evidence.
.DESCRIPTION
  Reads the reference darkloop's dated logs, active loop manifests, ledgers,
  optional schedule, and inbox. Writes both artifacts to _meta/logs before
  any email delivery is considered. Missing heartbeats are first-class
  findings. Email is not required and this script never reads secrets.
.PARAMETER Root
  Vault root.
.PARAMETER Date
  Report date in YYYY-MM-DD form.
.PARAMETER VaultName
  Name used by obsidian:// links. Defaults to the vault folder name.
.PARAMETER OutPath
  HTML evidence path. Defaults to _meta/logs/dawn-report-<date>.html.
.PARAMETER TextOutPath
  Plain-text evidence path. Defaults to _meta/logs/dawn-report-<date>.txt.
#>
[CmdletBinding()]
param(
  [string]$Root = '.',
  [string]$Date = (Get-Date -Format 'yyyy-MM-dd'),
  [string]$VaultName = '',
  [string]$OutPath = '',
  [string]$TextOutPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try { $reportDate = [datetime]::ParseExact($Date, 'yyyy-MM-dd', $null) }
catch { throw "Date must use YYYY-MM-DD: $Date" }
$Root = (Resolve-Path $Root).Path
if (-not $VaultName) { $VaultName = Split-Path $Root -Leaf }
$logsDir = Join-Path $Root '_meta/logs'
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
if (-not $OutPath) { $OutPath = Join-Path $logsDir "dawn-report-$Date.html" }
if (-not $TextOutPath) { $TextOutPath = Join-Path $logsDir "dawn-report-$Date.txt" }
$builtAt = Get-Date

. (Join-Path $PSScriptRoot '_dawn-status.ps1')

$glyph = @{ clean = '&#10003;'; applied = '&#8677;'; proposed = '&#8594;'; held = '&#8214;'; finding = '&#9650;'; skipped = '&#215;' }
$word = @{ clean = 'CLEAN'; applied = 'APPLIED'; proposed = 'PROPOSED'; held = 'HELD'; finding = 'FINDING'; skipped = 'SKIPPED' }
$color = @{ clean = '#00c8a0'; applied = '#00c8a0'; proposed = '#5c86d6'; held = '#d88a3a'; finding = '#d9534f'; skipped = '#5e6884' }

function ConvertTo-DawnHtml {
  param([AllowNull()][string]$Value)
  return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function ConvertTo-DawnHref {
  param([string]$Value)
  return $Value -replace '&', '&amp;'
}

function Get-DawnVaultLink {
  param([string]$NotePath)
  $vault = [Uri]::EscapeDataString($VaultName)
  $file = [Uri]::EscapeDataString($NotePath)
  return "obsidian://open?vault=$vault&file=$file"
}

function ConvertFrom-DawnMarkdownInline {
  param([string]$Value)
  $Value = $Value -replace '\[\[([^\]\|]+)\|([^\]]+)\]\]', '$2'
  $Value = $Value -replace '\[\[([^\]]+)\]\]', '$1'
  return $Value -replace '\*\*(.+?)\*\*', '$1'
}

function Get-DawnTemplateBlock {
  param([string]$Document, [string]$Name)
  $match = [regex]::Match($Document, "(?s)<!-- BEGIN:$Name -->\r?\n(.*?)\r?\n<!-- END:$Name -->")
  if (-not $match.Success) { throw "Template block missing: $Name" }
  return $match.Groups[1].Value
}

function Set-DawnTemplateSection {
  param([string]$Document, [string]$Name, [string]$Content)
  return [regex]::Replace(
    $Document,
    "(?s)\r?\n?<!-- BEGIN:$Name -->.*?<!-- END:$Name -->\r?\n?",
    [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $Content }
  )
}

function New-DawnCard {
  param(
    [string]$StateKey,
    [string]$Source,
    [string]$Title,
    [string]$Detail,
    [string[]]$Evidence = @(),
    [string]$LinkHref = '',
    [string]$LinkText = '',
    [string[]]$PlainItems = @()
  )
  [pscustomobject]@{
    StateKey = $StateKey
    Source = $Source
    Title = $Title
    Detail = $Detail
    Evidence = @($Evidence)
    LinkHref = $LinkHref
    LinkText = $LinkText
    PlainItems = @($PlainItems)
  }
}

# Gather the fixed layer-2 reference surfaces.
$surfaceSpecs = @(
  [pscustomobject]@{ Name = 'triage-inbox'; Type = 'triage'; Prefix = 'triage'; LogPath = (Join-Path $logsDir "triage-$Date.log") }
  [pscustomobject]@{ Name = 'purge-sewerpipe'; Type = 'purge'; Prefix = 'purge-sewerpipe'; LogPath = (Join-Path $logsDir "purge-sewerpipe-$Date.log") }
  [pscustomobject]@{ Name = 'sweep-handoffs'; Type = 'sweep'; Prefix = 'sweep-handoffs'; LogPath = (Join-Path $logsDir "sweep-handoffs-$Date.log") }
  [pscustomobject]@{ Name = 'extensions'; Type = 'extensions'; Prefix = 'extensions'; LogPath = (Join-Path $logsDir "extensions-$Date.log") }
)

# Each active loop manifest is another registered heartbeat. Example manifests
# end in .yaml.example and remain inert, so they are not discovered here.
$loopsDir = Join-Path $Root '_meta/loops'
$loopManifests = @(Get-ChildItem -Path $loopsDir -Filter '*.yaml' -File -ErrorAction SilentlyContinue | Sort-Object Name)
foreach ($manifest in $loopManifests) {
  $manifestText = Get-Content -Path $manifest.FullName -Raw -Encoding UTF8
  if ($manifestText -notmatch '(?m)^loop:\s*([^\s#]+)') { continue }
  $loopName = $Matches[1].Trim('"').Trim("'")
  $surfaceSpecs += [pscustomobject]@{
    Name = "loop/$loopName"
    Type = 'loop'
    Prefix = "loop-$loopName"
    LogPath = (Join-Path $logsDir "loop-$loopName-$Date.log")
  }
}

$surfaces = [System.Collections.Generic.List[object]]::new()
foreach ($spec in $surfaceSpecs) {
  $status = Read-DawnTaskStatus -Name $spec.Name -Type $spec.Type -LogPath $spec.LogPath
  $lastBeat = $null
  if ($status.State -eq 'silence') {
    $lastBeat = Get-DawnLastBeat -LogsDir $logsDir -Prefix $spec.Prefix -BeforeDate $Date
  }
  if ($spec.Type -eq 'loop') {
    $loopName = $spec.Name.Substring(5)
    $ledgerPath = Join-Path $loopsDir "$loopName.ledger.jsonl"
    $ledgerEvents = @()
    if (Test-Path $ledgerPath) {
      $ledgerEvents = @(Get-Content -Path $ledgerPath -Encoding UTF8 | ForEach-Object {
        try {
          $record = $_ | ConvertFrom-Json
          if ([string]$record.ts -like "$Date*") { $record }
        } catch {}
      })
    }
    $pending = @(Get-ChildItem -Path (Join-Path $loopsDir 'proposals') -Filter '*.md' -File -ErrorAction SilentlyContinue | Where-Object {
      (Get-Content -Path $_.FullName -TotalCount 25 -Encoding UTF8 | Out-String) -match "(?m)^loop:\s*$([regex]::Escape($loopName))\s*$"
    }).Count
    $extra = @()
    if ($ledgerEvents.Count -gt 0) { $extra += "ledger: $($ledgerEvents.Count) events on $Date" }
    if ($pending -gt 0) { $extra += "review queue: $pending pending" }
    if ($extra.Count -gt 0) { $status.Evidence = @($status.Evidence) + $extra }
  }
  $surfaces.Add([pscustomobject]@{ Spec = $spec; Status = $status; LastBeat = $lastBeat })
}

$needsYou = [System.Collections.Generic.List[object]]::new()
$todayCards = [System.Collections.Generic.List[object]]::new()
$silence = [System.Collections.Generic.List[object]]::new()
$cleanRows = [System.Collections.Generic.List[object]]::new()

foreach ($surface in $surfaces) {
  $status = $surface.Status
  switch ($status.State) {
    'silence' {
      $missed = 'no earlier beat on record'
      if ($surface.LastBeat) {
        $days = ($reportDate - [datetime]::ParseExact($surface.LastBeat, 'yyyy-MM-dd', $null)).Days
        $missed = "$days night$(if ($days -ne 1) { 's' })"
      }
      $silence.Add([pscustomobject]@{ Name = $status.Name; LastBeat = $surface.LastBeat; Missed = $missed })
    }
    { $_ -in @('clean', 'applied') } {
      $cleanRows.Add([pscustomobject]@{ Name = $status.Name; Measure = $status.Detail; StateKey = $status.State })
    }
    default {
      $title = switch ($status.State) {
        'finding' { "$($status.Name) raised a finding" }
        'proposed' { "$($status.Name) wrote a proposal" }
        'held' { "$($status.Name) is held for review" }
      }
      $needsYou.Add((New-DawnCard -StateKey $status.State -Source $status.Name.ToUpperInvariant() -Title $title -Detail $status.Detail -Evidence $status.Evidence -LinkHref (Get-DawnVaultLink '_meta/HOME') -LinkText 'open HOME'))
    }
  }
}

# Optional schedule surface. Its absence is not silence because schedule.md is
# not part of the locked taxonomy.
$schedulePath = Join-Path $Root '_meta/schedule.md'
if (Test-Path $schedulePath) {
  try {
    $sections = [ordered]@{}
    $currentDate = $null
    foreach ($line in (Get-Content -Path $schedulePath -Encoding UTF8)) {
      $heading = [regex]::Match($line, '^##\s+(\d{4}-\d{2}-\d{2})(?:\s+\S+\s*(.*))?$')
      if ($heading.Success) {
        $currentDate = $heading.Groups[1].Value
        $sections[$currentDate] = [pscustomobject]@{ Title = $heading.Groups[2].Value.Trim(); Open = [System.Collections.Generic.List[string]]::new() }
        continue
      }
      if ($currentDate -and $line -match '^\s*-\s*\[\s\]\s*(.+?)\s*$') {
        $sections[$currentDate].Open.Add($Matches[1])
      }
    }
    $overdue = @($sections.Keys | Where-Object { $_ -lt $Date -and $sections[$_].Open.Count -gt 0 } | Sort-Object)
    if ($overdue.Count -gt 0) {
      $items = @($overdue | ForEach-Object { $day = $_; $sections[$day].Open | ForEach-Object { "${day}: $(ConvertFrom-DawnMarkdownInline $_)" } })
      $todayCards.Add((New-DawnCard -StateKey held -Source 'SCHEDULE.MD' -Title "$($items.Count) overdue schedule item$(if ($items.Count -ne 1) { 's' })" -Detail 'Check off completed work or remove work that is no longer real.' -Evidence $items -LinkHref (Get-DawnVaultLink '_meta/schedule') -LinkText 'open schedule' -PlainItems $items))
    }
    if ($sections.Contains($Date) -and $sections[$Date].Open.Count -gt 0) {
      $items = @($sections[$Date].Open | ForEach-Object { ConvertFrom-DawnMarkdownInline $_ })
      $focus = if ($sections[$Date].Title) { $sections[$Date].Title } else { 'scheduled work' }
      $todayCards.Add((New-DawnCard -StateKey held -Source 'SCHEDULE.MD' -Title "today: $focus" -Detail "$($items.Count) open item$(if ($items.Count -ne 1) { 's' }) dated today." -Evidence $items -LinkHref (Get-DawnVaultLink '_meta/schedule') -LinkText 'open schedule' -PlainItems $items))
    }
  } catch {
    $needsYou.Add((New-DawnCard -StateKey finding -Source 'SCHEDULE.MD' -Title 'schedule could not be read' -Detail $_.Exception.Message))
  }
}

$inboxItems = @(Get-ChildItem -Path (Join-Path $Root '_inbox') -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @('README.md', 'desktop.ini') })
if ($inboxItems.Count -gt 0) {
  $todayCards.Add((New-DawnCard -StateKey held -Source '_INBOX' -Title "$($inboxItems.Count) capture$(if ($inboxItems.Count -ne 1) { 's' }) awaiting triage" -Detail 'Review proposed destinations in HOME or leave unclassified captures for the next triage pass.' -LinkHref (Get-DawnVaultLink '_meta/HOME') -LinkText 'open HOME'))
}

$rank = @{ finding = 0; held = 1; proposed = 2 }
$needsYou = [System.Collections.Generic.List[object]]@($needsYou | Sort-Object { $rank[$_.StateKey] })
$todayCards = [System.Collections.Generic.List[object]]@($todayCards | Sort-Object { $rank[$_.StateKey] })
$reportedCount = @($surfaces | Where-Object { $_.Status.State -ne 'silence' }).Count
$findingCount = @($needsYou | Where-Object StateKey -eq 'finding').Count
$heldCount = @($needsYou | Where-Object StateKey -in @('held', 'proposed')).Count + $todayCards.Count
$silenceCount = $silence.Count

if ($reportedCount -eq 0) {
  $verdictKey = 'incomplete'
  $verdictWord = 'INCOMPLETE'
  $verdictGlyph = $glyph.finding
  $verdictColor = $color.finding
  $verdictProse = 'No registered surface reported. The vault is operable, but the darkloop pass is unverified.'
} elseif ($findingCount -gt 0 -or $silenceCount -gt 0) {
  $verdictKey = 'attention'
  $verdictWord = 'ATTENTION'
  $verdictGlyph = $glyph.finding
  $verdictColor = $color.finding
  $verdictProse = 'The pass produced evidence, but at least one finding or missing heartbeat needs review.'
} elseif ($heldCount -gt 0) {
  $verdictKey = 'held'
  $verdictWord = 'HELD'
  $verdictGlyph = $glyph.held
  $verdictColor = $color.held
  $verdictProse = 'The pass completed and wrote its evidence. Items are waiting on the operator.'
} else {
  $verdictKey = 'clean'
  $verdictWord = 'CLEAN'
  $verdictGlyph = $glyph.clean
  $verdictColor = $color.clean
  $verdictProse = 'The pass completed and wrote its evidence. Nothing is waiting on the operator.'
}

$countParts = @()
if ($findingCount -gt 0) { $countParts += "$findingCount finding$(if ($findingCount -ne 1) { 's' }) raised" }
if ($heldCount -gt 0) { $countParts += "$heldCount held for you" }
if ($silenceCount -gt 0) { $countParts += "$silenceCount heartbeat$(if ($silenceCount -ne 1) { 's' }) missing" }
$countsPlain = if ($countParts.Count -gt 0) { $countParts -join ', ' } else { 'nothing waiting' }
$countsHtml = if ($countParts.Count -gt 0) { $countParts -join ' &nbsp;&#183;&nbsp; ' } else { 'nothing waiting' }

$subject = if ($verdictKey -eq 'incomplete') {
  'dawn: the chain did not run'
} elseif ($silenceCount -gt 0) {
  "dawn: $($silence[0].Name) went quiet$(if (($findingCount + $silenceCount) -gt 1) { " and $($findingCount + $silenceCount - 1) more findings" })"
} elseif ($findingCount -gt 0) {
  "dawn: $($needsYou[0].Source.ToLowerInvariant()) raised a finding"
} elseif ($heldCount -gt 0) {
  "dawn: $heldCount waiting on you"
} else {
  'dawn: clean, nothing needs you'
}
$preheader = "$($verdictWord.ToLowerInvariant()). $countsPlain."

$machine = [ordered]@{
  schema = 'system-o.dawn-report.v1'
  date = $Date
  verdict = $verdictWord.ToLowerInvariant()
  subject = $subject
  summary = $countsPlain
  counts = [ordered]@{ findings = $findingCount; held = $heldCount; silence = $silenceCount }
  action_items = @(@($needsYou) + @($todayCards) | ForEach-Object {
    [ordered]@{
      state = $word[$_.StateKey].ToLowerInvariant()
      source = $_.Source.ToLowerInvariant()
      title = $_.Title
      detail = $_.Detail
      items = @($_.PlainItems)
    }
  })
  silence = @($silence | ForEach-Object { [ordered]@{ task = $_.Name; last_beat = $_.LastBeat; missed = $_.Missed } })
  links = [ordered]@{ home = (Get-DawnVaultLink '_meta/HOME') }
}
$machineJson = $machine | ConvertTo-Json -Depth 6 -Compress

$templatePath = Join-Path $Root '_meta/templates/dawn-report.html'
if (-not (Test-Path $templatePath)) { throw "Dawn report template missing: $templatePath" }
$template = Get-Content -Path $templatePath -Raw -Encoding UTF8
$cardTemplate = Get-DawnTemplateBlock $template 'CARD'
$evidenceTemplate = Get-DawnTemplateBlock $template 'EVIDENCE'
$linkTemplate = Get-DawnTemplateBlock $template 'LINK'
$silenceCardTemplate = Get-DawnTemplateBlock $template 'SILENCE_CARD'
$cleanRowTemplate = Get-DawnTemplateBlock $template 'RAN_CLEAN_ROW'
foreach ($block in 'CARD', 'EVIDENCE', 'LINK', 'SILENCE_CARD', 'RAN_CLEAN_ROW') {
  $template = Set-DawnTemplateSection $template $block ''
}

function ConvertTo-DawnCardHtml {
  param($Card)
  $evidenceHtml = ''
  if ($Card.Evidence.Count -gt 0) {
    $lines = @($Card.Evidence | ForEach-Object { ConvertTo-DawnHtml $_ }) -join "<br>`n                          "
    $evidenceHtml = $evidenceTemplate.Replace('{{EVIDENCE_LINES}}', $lines)
  }
  $linkHtml = ''
  if ($Card.LinkHref) {
    $linkHtml = $linkTemplate.Replace('{{LINK_HREF}}', (ConvertTo-DawnHref $Card.LinkHref)).Replace('{{LINK_TEXT}}', (ConvertTo-DawnHtml $Card.LinkText))
  }
  return $cardTemplate.
    Replace('{{STATE_COLOR}}', $color[$Card.StateKey]).
    Replace('{{STATE_GLYPH}}', $glyph[$Card.StateKey]).
    Replace('{{STATE_WORD}}', $word[$Card.StateKey]).
    Replace('{{SOURCE}}', (ConvertTo-DawnHtml $Card.Source)).
    Replace('{{TITLE}}', (ConvertTo-DawnHtml $Card.Title)).
    Replace('{{DETAIL}}', (ConvertTo-DawnHtml $Card.Detail)).
    Replace('{{EVIDENCE}}', $evidenceHtml).
    Replace('{{LINK}}', $linkHtml)
}

if ($needsYou.Count -gt 0) {
  $inner = Get-DawnTemplateBlock $template 'NEEDS_YOU'
  $inner = $inner.Replace('{{NEEDS_YOU_COUNT}}', "$($needsYou.Count) ITEM$(if ($needsYou.Count -ne 1) { 'S' })")
  $inner = $inner.Replace('{{NEEDS_YOU_CARDS}}', (@($needsYou | ForEach-Object { ConvertTo-DawnCardHtml $_ }) -join "`n"))
  $template = Set-DawnTemplateSection $template 'NEEDS_YOU' $inner
} else { $template = Set-DawnTemplateSection $template 'NEEDS_YOU' '' }

if ($silence.Count -gt 0) {
  $inner = Get-DawnTemplateBlock $template 'SILENCE'
  $cards = @($silence | ForEach-Object {
    $lastBeatText = if ($_.LastBeat) { "no beat since $($_.LastBeat)" } else { 'never seen a beat' }
    $silenceCardTemplate.
      Replace('{{NAME}}', (ConvertTo-DawnHtml $_.Name.ToUpperInvariant())).
      Replace('{{LAST_BEAT}}', (ConvertTo-DawnHtml $lastBeatText)).
      Replace('{{MISSED_COUNT}}', (ConvertTo-DawnHtml $_.Missed))
  }) -join "`n"
  $inner = $inner.Replace('{{SILENCE_CARDS}}', $cards)
  $template = Set-DawnTemplateSection $template 'SILENCE' $inner
} else { $template = Set-DawnTemplateSection $template 'SILENCE' '' }

if ($todayCards.Count -gt 0) {
  $inner = Get-DawnTemplateBlock $template 'TODAY'
  $inner = $inner.Replace('{{TODAY_COUNT}}', "$($todayCards.Count) ITEM$(if ($todayCards.Count -ne 1) { 'S' })")
  $inner = $inner.Replace('{{TODAY_CARDS}}', (@($todayCards | ForEach-Object { ConvertTo-DawnCardHtml $_ }) -join "`n"))
  $template = Set-DawnTemplateSection $template 'TODAY' $inner
} else { $template = Set-DawnTemplateSection $template 'TODAY' '' }

if ($cleanRows.Count -gt 0) {
  $inner = Get-DawnTemplateBlock $template 'RAN_CLEAN'
  $rows = for ($index = 0; $index -lt $cleanRows.Count; $index++) {
    $row = $cleanRows[$index]
    $border = if ($index -lt $cleanRows.Count - 1) { 'border-bottom: 1px solid #242d4c; ' } else { '' }
    $cleanRowTemplate.
      Replace('{{ROW_BORDER}}', $border).
      Replace('{{NAME}}', (ConvertTo-DawnHtml $row.Name)).
      Replace('{{MEASURE}}', (ConvertTo-DawnHtml $row.Measure)).
      Replace('{{STATE_COLOR}}', $color[$row.StateKey]).
      Replace('{{STATE_GLYPH}}', $glyph[$row.StateKey]).
      Replace('{{STATE_WORD}}', $word[$row.StateKey])
  }
  $inner = $inner.Replace('{{RAN_CLEAN_ROWS}}', ($rows -join "`n"))
  $template = Set-DawnTemplateSection $template 'RAN_CLEAN' $inner
} else { $template = Set-DawnTemplateSection $template 'RAN_CLEAN' '' }

$windowEntries = @($surfaces | Where-Object { Test-Path $_.Spec.LogPath } | ForEach-Object {
  [pscustomobject]@{ Time = (Get-Item $_.Spec.LogPath).LastWriteTime; Name = $_.Status.Name; Detail = $_.Status.Detail }
} | Sort-Object Time)
if ($verdictKey -eq 'clean') {
  $template = Set-DawnTemplateSection $template 'WINDOW' ''
  $summary = if ($windowEntries.Count -gt 0) {
    "$($windowEntries[0].Time.ToString('HH:mm'))&#8594;$($windowEntries[-1].Time.ToString('HH:mm')) &nbsp;&#183;&nbsp; $($windowEntries.Count) beats &nbsp;&#183;&nbsp; all clean"
  } else { 'no beats recorded' }
  $custodyWindow = "<span style=`"color: #9aa5c3;`">window:</span> $summary<br>`n        "
} else {
  $windowLines = @($windowEntries | Select-Object -First 8 | ForEach-Object {
    "<span style=`"color: #5e6884;`">$($_.Time.ToString('HH:mm:ss'))</span> &nbsp;<span style=`"color: #5c86d6;`">[$(ConvertTo-DawnHtml $_.Name)]</span> $(ConvertTo-DawnHtml $_.Detail)"
  })
  $windowLines += "<span style=`"color: #5e6884;`">$($builtAt.ToString('HH:mm:ss'))</span> &nbsp;<span style=`"color: #00c8a0;`">dawn report built, custody to operator</span>"
  $inner = (Get-DawnTemplateBlock $template 'WINDOW').Replace('{{WINDOW_LINES}}', ($windowLines -join "<br>`n              "))
  $template = Set-DawnTemplateSection $template 'WINDOW' $inner
  $custodyWindow = ''
}

$html = $template.
  Replace('{{PREHEADER}}', (ConvertTo-DawnHtml $preheader)).
  Replace('{{DATE}}', (ConvertTo-DawnHtml $Date)).
  Replace('{{BUILT_TIME}}', $builtAt.ToString('HH:mm')).
  Replace('{{VERDICT_COLOR}}', $verdictColor).
  Replace('{{VERDICT_GLYPH}}', $verdictGlyph).
  Replace('{{VERDICT_WORD}}', $verdictWord).
  Replace('{{VERDICT_COUNTS}}', $countsHtml).
  Replace('{{VERDICT_PROSE}}', (ConvertTo-DawnHtml $verdictProse)).
  Replace('{{HOME_HREF}}', (ConvertTo-DawnHref (Get-DawnVaultLink '_meta/HOME'))).
  Replace('{{VAULT_NAME}}', (ConvertTo-DawnHtml $VaultName)).
  Replace('{{CUSTODY_WINDOW}}', $custodyWindow).
  Replace('{{MACHINE_JSON}}', (ConvertTo-DawnHtml $machineJson))

$plain = [System.Text.StringBuilder]::new()
[void]$plain.AppendLine("DAWN REPORT - $Date - $verdictWord")
[void]$plain.AppendLine("subject: $subject")
[void]$plain.AppendLine($verdictProse)
[void]$plain.AppendLine("counts: $countsPlain")
if ($needsYou.Count -gt 0) {
  [void]$plain.AppendLine()
  [void]$plain.AppendLine("NEEDS YOU ($($needsYou.Count))")
  foreach ($card in $needsYou) {
    [void]$plain.AppendLine("- [$($word[$card.StateKey])] $($card.Source): $($card.Title). $($card.Detail)")
    foreach ($item in $card.PlainItems) { [void]$plain.AppendLine("  - $item") }
  }
}
if ($silence.Count -gt 0) {
  [void]$plain.AppendLine()
  [void]$plain.AppendLine("SILENCE ($($silence.Count))")
  foreach ($item in $silence) { [void]$plain.AppendLine("- $($item.Name): $($item.Missed)") }
}
if ($todayCards.Count -gt 0) {
  [void]$plain.AppendLine()
  [void]$plain.AppendLine("TODAY ($($todayCards.Count))")
  foreach ($card in $todayCards) {
    [void]$plain.AppendLine("- [$($word[$card.StateKey])] $($card.Title)")
    foreach ($item in $card.PlainItems) { [void]$plain.AppendLine("  - $item") }
  }
}
if ($cleanRows.Count -gt 0) {
  [void]$plain.AppendLine()
  [void]$plain.AppendLine('RAN CLEAN')
  foreach ($row in $cleanRows) { [void]$plain.AppendLine("- $($row.Name): $($row.Measure) ($($word[$row.StateKey]))") }
}
[void]$plain.AppendLine()
[void]$plain.AppendLine("HOME: $(Get-DawnVaultLink '_meta/HOME')")
[void]$plain.AppendLine()
[void]$plain.AppendLine('MACHINE READ - canonical action-item summary as JSON')
[void]$plain.AppendLine($machineJson)

$unresolved = @([regex]::Matches($html, '\{\{[A-Z0-9_]+\}\}') | ForEach-Object { $_.Value } | Sort-Object -Unique)
if ($unresolved.Count -gt 0) {
  throw "Dawn report template has unresolved tokens: $($unresolved -join ', ')"
}

foreach ($path in @($OutPath, $TextOutPath)) {
  $parent = Split-Path $path -Parent
  if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
}
[System.IO.File]::WriteAllText($OutPath, $html, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($TextOutPath, $plain.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Host "STATUS dawn-report verdict=$verdictWord findings=$findingCount held=$heldCount silence=$silenceCount delivery=file-only html=$OutPath text=$TextOutPath"
