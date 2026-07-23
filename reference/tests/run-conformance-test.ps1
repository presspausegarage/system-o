#Requires -Version 7.0
<#
.SYNOPSIS
  v1.0 conformance harness (distribution-review D6 / spec §Measured conformance).
.DESCRIPTION
  Scripted pass/fail gate for "clean install, run, conventions hold" — the one
  substantive item still open on the pre-public-release blocker list. The same
  script proves all three D6 legs: run with -Target docker on a Windows Docker
  host and again on a Linux Docker host (two runs, same script), and -Target
  native regression-checks the Windows-native reference path.

  Checks, in order:
    1. Locked taxonomy present (spec §File & folder taxonomy + §Agent context
       bundle's _meta/agent-context/ extension)
    2. Exactly one orientation file (spec §Agent orientation files)
    3. GLOSSARY.md / agent-context MEMORY.md / session-log.md / HOME.md present
    4. Idempotent re-bootstrap — a second run must not touch existing content
    5. run-extensions.ps1 exits 0 with a well-formed STATUS line
    6. build-static-home.ps1 / build-kanban-csv.ps1 run clean
    7. Loop layer full circle via the stub driver (spec §Measured conformance's
       conformance vehicle, REQUIRED per D6, not optional): a seeded
       session-log gap + stale HOME is detected, proposed via a canned stub
       endpoint, verified, auto-applied, HOME cascades, and the detector
       self-clears on the next pass.
    8. Second-loop full circle (the v2 runner-seam proof): the shipped
       kanban-handoff-reconciler cell — different detector, verifier id, and
       repair types — runs through the same generic runner from a manifest +
       cell script alone: seeded D1 (ready handoff, citing cards all checked)
       and D2 (complete handoff citing an open task) drift is detected,
       proposed propose-only via the stub endpoint, applied through
       apply-loop-proposal.ps1, and the detector self-clears.
    9. (docker only) crontab installed with $VAULT_ROOT substituted

  Exits 0 only if every check passes; nonzero otherwise. Human-readable
  PASS/FAIL lines to stdout plus a summary report file.
.PARAMETER Target
  'native': runs bootstrap.ps1 directly against a temp vault, no container —
  the Windows-native reference leg (or a quick regression check on any host).
  'docker': builds the reference image and runs it with a temp bind-mounted
  vault — run this once on a Windows Docker host and once on a Linux Docker
  host to close both remaining D6 legs.
.PARAMETER VaultRoot
  Vault directory to use. Default: a fresh temp directory, removed after
  (unless -KeepVault).
.PARAMETER ImageTag
  Docker image tag to build/use. Default 'system-o-conformance'.
.PARAMETER AgentTarget
  Canonical orientation filename to bootstrap with (CLAUDE.md or AGENTS.md).
  Default CLAUDE.md; run again with -AgentTarget AGENTS.md to prove the
  non-Claude orientation leg on the same harness.
.PARAMETER KeepVault
  Don't delete the temp vault or stop the container on exit — for inspecting
  a failure by hand.
.EXAMPLE
  pwsh reference/tests/run-conformance-test.ps1 -Target native
.EXAMPLE
  pwsh reference/tests/run-conformance-test.ps1 -Target docker
.EXAMPLE
  pwsh reference/tests/run-conformance-test.ps1 -Target native -AgentTarget AGENTS.md
#>
[CmdletBinding()]
param(
  [ValidateSet('native', 'docker')]
  [string]$Target = 'native',
  [string]$VaultRoot,
  [string]$ImageTag = 'system-o-conformance',
  [ValidateSet('CLAUDE.md', 'AGENTS.md')]
  [string]$AgentTarget = 'CLAUDE.md',
  [switch]$KeepVault
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

$results = [System.Collections.Generic.List[hashtable]]::new()
function Record {
  param([string]$Name, [bool]$Pass, [string]$Detail = '')
  $results.Add(@{ name = $Name; pass = $Pass; detail = $Detail })
  $mark = if ($Pass) { 'PASS' } else { 'FAIL' }
  $line = "[$mark] $Name"
  if ($Detail) { $line += " — $Detail" }
  Write-Host $line
}

$isTempVault = -not $VaultRoot
if (-not $VaultRoot) {
  $VaultRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("system-o-conformance-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
}
$fakeOptDir = $null
$containerName = $null

function Cleanup {
  if ($containerName) {
    Write-Host "[cleanup] removing container $containerName"
    & docker rm -f $containerName *>&1 | Out-Null
  }
  if ($fakeOptDir -and (Test-Path $fakeOptDir)) {
    Remove-Item -Path $fakeOptDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  if ($isTempVault -and -not $KeepVault -and (Test-Path $VaultRoot)) {
    Write-Host "[cleanup] removing temp vault $VaultRoot"
    Remove-Item -Path $VaultRoot -Recurse -Force -ErrorAction SilentlyContinue
  } elseif ($KeepVault) {
    Write-Host "[cleanup] -KeepVault set — vault left at $VaultRoot"
  }
}

# --- Loop layer full circle (spec §Measured conformance's stub-driver vehicle) --
function Test-LoopFullCircle {
  param([string]$VaultRoot)

  $scriptsDir = Join-Path $VaultRoot '_meta/scripts'
  $today = Get-Date -Format 'yyyy-MM-dd'
  $fixDate = (Get-Date).AddDays(-3).ToString('yyyy-MM-dd')
  # Outside the detector's default 10-day window on purpose — establishes
  # $newestLogged without itself being eligible as a same-window gap.
  $preDate = (Get-Date).AddDays(-15).ToString('yyyy-MM-dd')
  $staleDate = (Get-Date).AddDays(-20).ToString('yyyy-MM-dd')
  $handoffBase = "$fixDate-conformance-fixture"

  $handoffsDir = Join-Path $VaultRoot '_meta/handoffs'
  if (-not (Test-Path $handoffsDir)) { New-Item -ItemType Directory -Path $handoffsDir -Force | Out-Null }
  @"
---
type: handoff
status: complete
updated: $fixDate
tags:
  - type/handoff
---

# Conformance fixture handoff

Synthetic handoff seeded by run-conformance-test.ps1 to exercise the
wrap-tail-repair loop cell's stub driver. Safe to delete.
"@ | Set-Content -Path (Join-Path $handoffsDir "$handoffBase.md") -Encoding UTF8

  # Seed one pre-existing session-log entry ($preDate, outside the window) so the
  # detector has a "newest logged" date to compare HOME's stamp against — with a
  # totally empty log (bootstrap's starter state) staleness can never fire, since
  # there's nothing logged yet to be stale relative to.
  $em = [char]0x2014
  $logFile = Join-Path $VaultRoot '_meta/session-log.md'
  $logRawPre = Get-Content -Path $logFile -Raw -Encoding UTF8
  $seedEntry = "`n## $preDate $em conformance fixture seed`n- Pre-existing entry seeded by run-conformance-test.ps1 to establish a newest-logged date. Time spent: n/a.`n"
  Set-Content -Path $logFile -Value ($logRawPre.TrimEnd() + "`n" + $seedEntry) -Encoding UTF8 -NoNewline

  # HOME stale relative to that seeded entry (not yet relative to the fixture gap,
  # which has no session-log entry at all — that's the gap under test)
  $homeFile = Join-Path $VaultRoot '_meta/HOME.md'
  $homeContent = Get-Content -Path $homeFile -Raw -Encoding UTF8
  $homeContent = $homeContent -replace '(?m)^updated:\s*\S+', "updated: $staleDate"
  Set-Content -Path $homeFile -Value $homeContent -Encoding UTF8 -NoNewline

  # 1. detector must find the seeded gap + stale HOME
  $detectOut1 = & pwsh -NoProfile -File (Join-Path $scriptsDir 'detect-wrap-tail.ps1') -Root $VaultRoot -DryRun -Date $today 2>&1 | Out-String
  $foundGap = $detectOut1.Contains($handoffBase)
  $foundStale = ($detectOut1 -match 'HOME stale: [1-9]')
  Record 'loop: detector finds the seeded gap + stale HOME' ($foundGap -and $foundStale) $detectOut1.Trim()

  # 2. canned stub response — deliberately built to pass run-loop.ps1's structural verifier
  $fixDir = Join-Path $VaultRoot '_meta/loops/.conformance-fixtures'
  New-Item -ItemType Directory -Path $fixDir -Force | Out-Null
  $em = [char]0x2014
  $stubResponse = "## $fixDate $em conformance fixture wrap`n- Repaired by the conformance harness's stub endpoint. Time spent: n/a.`n[[$handoffBase]]`n"
  Set-Content -Path (Join-Path $fixDir 'stub-response.md') -Value $stubResponse -Encoding UTF8 -NoNewline

  # 3. temp manifest: driver=stub, apply=auto. 'deterministic' is included in the
  #    allowlist alongside stub/canned so the HOME-cascade bump (always
  #    system-computed, never model output) also auto-applies in this fixture —
  #    this is the harness's own throwaway manifest, not the shipped example,
  #    so it's safe to earn auto here without touching real trust policy.
  $manifestFile = Join-Path $fixDir 'wrap-tail-conformance.yaml'
  @"
loop: wrap-tail-repair
invariant: conformance-test fixture
cell: wrap-tail-repair.cell.ps1
scope:
  - _meta/session-log.md
  - _meta/HOME.md
detect:
  script: detect-wrap-tail.ps1
  args: -DryRun
verify: structural
apply: auto
auto_apply_endpoints:
  - stub/canned
  - deterministic
promote_after: 5
endpoints:
  - driver: stub
    model: canned
    file: _meta/loops/.conformance-fixtures/stub-response.md
budget:
  max_prompt_chars: 24000
  max_calls_per_run: 4
prompt: loop-wrap-tail-repair.prompt.md
"@ | Set-Content -Path $manifestFile -Encoding UTF8

  # 4. run the cell for real
  $loopOut = & pwsh -NoProfile -File (Join-Path $scriptsDir 'run-loop.ps1') -Manifest $manifestFile -Root $VaultRoot 2>&1 | Out-String
  $statusLine = (($loopOut -split "`n") | Where-Object { $_ -match '^STATUS ' } | Select-Object -Last 1)
  $autoApplied = ($statusLine -match 'auto_applied=(\d+)') -and ([int]$Matches[1] -ge 1)
  $verifierClean = -not (($statusLine -match 'verifier_fail=(\d+)') -and ([int]$Matches[1] -gt 0))
  Record 'loop: stub proposal verifies + auto-applies' ($autoApplied -and $verifierClean) $statusLine

  # 5. session-log carries the applied entry + wikilink
  $logRaw = Get-Content -Path (Join-Path $VaultRoot '_meta/session-log.md') -Raw -Encoding UTF8
  Record 'loop: auto-applied entry landed in session-log.md' ($logRaw.Contains("[[$handoffBase]]"))

  # 6. HOME cascade bumped past the seeded stale date
  $homeRaw = Get-Content -Path $homeFile -Raw -Encoding UTF8
  $homeUpdatedNow = $null
  if ($homeRaw -match '(?m)^updated:\s*(\d{4}-\d{2}-\d{2})') { $homeUpdatedNow = $Matches[1] }
  $cascaded = ($null -ne $homeUpdatedNow) -and ($homeUpdatedNow -gt $staleDate)
  Record 'loop: HOME.md updated: cascaded past seeded stale date' $cascaded "updated: $homeUpdatedNow"

  # 7. guard self-clears
  $detectOut2 = & pwsh -NoProfile -File (Join-Path $scriptsDir 'detect-wrap-tail.ps1') -Root $VaultRoot -DryRun -Date $today 2>&1 | Out-String
  Record 'loop: detector self-clears after apply (guard clean)' ($detectOut2.Contains('clean:')) $detectOut2.Trim()
}

# --- Second-loop full circle: the v2 runner-seam proof. A materially different
# cell (kanban-handoff-reconciler: its own detector, verifier id, repair types)
# runs through the same generic runner from a manifest + cell script alone. ----
function Test-ReconcilerFullCircle {
  param([string]$VaultRoot)

  $scriptsDir = Join-Path $VaultRoot '_meta/scripts'
  $fixDate = (Get-Date).AddDays(-5).ToString('yyyy-MM-dd')
  $readyBase = "$fixDate-reconciler-fixture-ready"
  $completeBase = "$fixDate-reconciler-fixture-complete"
  $handoffsDir = Join-Path $VaultRoot '_meta/handoffs'
  $boardDir = Join-Path $VaultRoot 'projects/widget-fixture/_meta'
  New-Item -ItemType Directory -Path $boardDir -Force | Out-Null

  # D1 seed: a ready handoff whose citing Kanban card is already checked
  @"
---
type: handoff
status: ready
tags:
  - type/handoff
---

# Reconciler fixture handoff (ready)

Synthetic handoff seeded by run-conformance-test.ps1: its citing Kanban card is
checked, so the reconciler should propose the complete flip. Safe to delete.
"@ | Set-Content -Path (Join-Path $handoffsDir "$readyBase.md") -Encoding UTF8

  # D2 seed: a complete handoff citing a still-open task
  @"
---
type: handoff
status: complete
completed_date: $fixDate
verification:
  - task: "projects/widget-fixture/_meta/Kanban.md -- Fix the fixture doohickey -- checked $fixDate"
tags:
  - type/handoff
---

# Reconciler fixture handoff (complete)

Synthetic handoff seeded by run-conformance-test.ps1. Safe to delete.
"@ | Set-Content -Path (Join-Path $handoffsDir "$completeBase.md") -Encoding UTF8

  @"
---
type: kanban
---

## Backlog

- [ ] Fix the fixture doohickey before ship

## Done

- [x] Ship the fixture widget end to end - done $fixDate, handoff [[$readyBase]]
"@ | Set-Content -Path (Join-Path $boardDir 'Kanban.md') -Encoding UTF8

  # 1. detector finds both drift types
  $det1 = & pwsh -NoProfile -File (Join-Path $scriptsDir 'detect-kanban-handoff-drift.ps1') -Root $VaultRoot -DryRun 2>&1 | Out-String
  Record 'loop2: detector finds D1 + D2 drift' ($det1 -match '1 ready-but-done, 1 cited-but-open') $det1.Trim()

  # 2. canned stub note + throwaway manifest — propose-only like the shipped example
  $fixDir = Join-Path $VaultRoot '_meta/loops/.conformance-fixtures'
  New-Item -ItemType Directory -Path $fixDir -Force | Out-Null
  Set-Content -Path (Join-Path $fixDir 'stub-note.md') -Value 'Fixture widget shipped end to end per the checked Kanban card; seeded by the conformance harness to prove the second loop cell.' -Encoding UTF8 -NoNewline
  $manifestFile = Join-Path $fixDir 'kanban-handoff-reconciler-conformance.yaml'
  @"
loop: kanban-handoff-reconciler
invariant: conformance-test fixture
cell: kanban-handoff-reconciler.cell.ps1
scope:
  - _meta/handoffs/
  - "**/_meta/Kanban.md"
detect:
  script: detect-kanban-handoff-drift.ps1
  args: -DryRun
verify: status-sync
apply: propose-only
endpoints:
  - driver: stub
    model: canned
    file: _meta/loops/.conformance-fixtures/stub-note.md
budget:
  max_prompt_chars: 24000
  max_calls_per_run: 6
prompt: loop-kanban-handoff-reconciler.prompt.md
"@ | Set-Content -Path $manifestFile -Encoding UTF8

  # 3. run the cell — propose-only must be honored (nothing auto-applies)
  $loopOut = & pwsh -NoProfile -File (Join-Path $scriptsDir 'run-loop.ps1') -Manifest $manifestFile -Root $VaultRoot 2>&1 | Out-String
  $statusLine = (($loopOut -split "`n") | Where-Object { $_ -match '^STATUS ' } | Select-Object -Last 1)
  Record 'loop2: two proposals written, propose-only honored' (($statusLine -match 'proposals_new=2') -and ($statusLine -match 'auto_applied=0')) $statusLine

  # 4. apply both through the applier (the attended-walk arm; explicit -Manifest
  #    because the fixture manifest is not at _meta/loops/<loop>.yaml)
  $props = @(Get-ChildItem (Join-Path $VaultRoot '_meta/loops/proposals') -Filter 'loop-kanban-handoff-reconciler-*.md' -File)
  foreach ($p in $props) {
    & pwsh -NoProfile -File (Join-Path $scriptsDir 'apply-loop-proposal.ps1') -File $p.FullName -Root $VaultRoot -Manifest $manifestFile 2>&1 | ForEach-Object { Write-Host "[apply] $_" }
  }
  $flipped = Get-Content -Path (Join-Path $handoffsDir "$readyBase.md") -Raw -Encoding UTF8
  Record 'loop2: D1 handoff flipped complete with evidence block' (($flipped -match '(?m)^status: complete$') -and ($flipped -match '(?m)^\s+- task: '))
  $board = Get-Content -Path (Join-Path $boardDir 'Kanban.md') -Raw -Encoding UTF8
  Record 'loop2: D2 cited task box checked' ($board -match '- \[x\] Fix the fixture doohickey')

  # 5. detector self-clears
  $det2 = & pwsh -NoProfile -File (Join-Path $scriptsDir 'detect-kanban-handoff-drift.ps1') -Root $VaultRoot -DryRun 2>&1 | Out-String
  Record 'loop2: detector self-clears after apply' ($det2 -match '0 ready-but-done, 0 cited-but-open') $det2.Trim()
}

# --- Common assertion set, run against any bootstrapped vault (native or bind mount) --
function Test-Vault {
  param([string]$VaultRoot)

  $lockedDirs = @(
    '_meta/registry', '_meta/handoffs', '_meta/loops', '_meta/loops/proposals', '_meta/extensions',
    '_meta/scripts', '_meta/templates', '_meta/logs', '_inbox', '_sewerpipe', '_archive/handoffs',
    '_meta/agent-context'
  )
  $missingDirs = @($lockedDirs | Where-Object { -not (Test-Path (Join-Path $VaultRoot $_)) })
  Record 'locked taxonomy present' ($missingDirs.Count -eq 0) ($missingDirs -join ', ')

  $orientCandidates = @(@('CLAUDE.md', 'AGENTS.md') | Where-Object { Test-Path (Join-Path $VaultRoot $_) })
  Record 'exactly one orientation file, matching -AgentTarget' ($orientCandidates.Count -eq 1 -and $orientCandidates[0] -eq $AgentTarget) ("expected: $AgentTarget; found: " + ($orientCandidates -join ', '))

  Record 'GLOSSARY.md present' (Test-Path (Join-Path $VaultRoot '_meta/GLOSSARY.md'))
  Record 'agent-context/MEMORY.md present' (Test-Path (Join-Path $VaultRoot '_meta/agent-context/MEMORY.md'))
  Record 'session-log.md present' (Test-Path (Join-Path $VaultRoot '_meta/session-log.md'))
  Record 'HOME.md present' (Test-Path (Join-Path $VaultRoot '_meta/HOME.md'))

  try {
    $extOut = & pwsh -NoProfile -File (Join-Path $VaultRoot '_meta/scripts/run-extensions.ps1') -Root $VaultRoot 2>&1 | Out-String
    $extExit = $LASTEXITCODE
    $statusLine = (($extOut -split "`n") | Where-Object { $_ -match '^STATUS extensions=' } | Select-Object -Last 1)
    Record 'run-extensions.ps1 exits clean with STATUS line' ($extExit -eq 0 -and $null -ne $statusLine) $statusLine
  } catch { Record 'run-extensions.ps1 exits clean with STATUS line' $false $_.Exception.Message }

  try {
    $out = & pwsh -NoProfile -File (Join-Path $VaultRoot '_meta/scripts/build-static-home.ps1') -Root $VaultRoot 2>&1 | Out-String
    Record 'build-static-home.ps1 runs clean' ($LASTEXITCODE -eq 0) $(if ($LASTEXITCODE -ne 0) { $out.Trim() } else { '' })
  } catch { Record 'build-static-home.ps1 runs clean' $false $_.Exception.Message }

  try {
    $out = & pwsh -NoProfile -File (Join-Path $VaultRoot '_meta/scripts/build-kanban-csv.ps1') -Root $VaultRoot 2>&1 | Out-String
    Record 'build-kanban-csv.ps1 runs clean' ($LASTEXITCODE -eq 0) $(if ($LASTEXITCODE -ne 0) { $out.Trim() } else { '' })
  } catch { Record 'build-kanban-csv.ps1 runs clean' $false $_.Exception.Message }

  Test-LoopFullCircle -VaultRoot $VaultRoot
  Test-ReconcilerFullCircle -VaultRoot $VaultRoot
}

try {
  if ($Target -eq 'native') {
    New-Item -ItemType Directory -Path $VaultRoot -Force | Out-Null
    Write-Host "[setup] native bootstrap at $VaultRoot"

    # Stage the framework layout into a GUID-named directory under the OS temp
    # root and hand it to bootstrap via -SourceRoot. Never an absolute shared
    # path like /opt/system-o: a pre-existing real install there must be
    # untouchable by a test run, so the staging dir is created by this run,
    # refused if it somehow already exists, and the cleanup removes only it.
    # crontab.example is deliberately NOT staged: bootstrap.ps1 calls the real
    # `crontab` binary when that file is present, which native hosts (Windows
    # especially) don't have — omitting it makes bootstrap take its documented
    # WARN branch instead of failing, so native mode can test everything else.
    $fakeOptDir = Join-Path ([System.IO.Path]::GetTempPath()) ("system-o-fixture-" + [guid]::NewGuid().ToString('N'))
    if (Test-Path $fakeOptDir) { throw "staging collision: $fakeOptDir already exists — refusing to reuse a directory this run did not create" }
    New-Item -ItemType Directory -Path (Join-Path $fakeOptDir 'scripts')    -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fakeOptDir 'extensions') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fakeOptDir 'templates')  -Force | Out-Null
    Copy-Item -Path (Join-Path $RepoRoot 'reference/scripts/*')    -Destination (Join-Path $fakeOptDir 'scripts')    -Recurse -Force
    Copy-Item -Path (Join-Path $RepoRoot 'reference/extensions/*') -Destination (Join-Path $fakeOptDir 'extensions') -Recurse -Force
    Copy-Item -Path (Join-Path $RepoRoot 'reference/templates/*')  -Destination (Join-Path $fakeOptDir 'templates')  -Recurse -Force
    Copy-Item -Path (Join-Path $RepoRoot 'spec/wrap-tail-repair.example.yaml') -Destination (Join-Path $fakeOptDir 'wrap-tail-repair.example.yaml') -Force
    Copy-Item -Path (Join-Path $RepoRoot 'spec/kanban-handoff-reconciler.example.yaml') -Destination (Join-Path $fakeOptDir 'kanban-handoff-reconciler.example.yaml') -Force

    & pwsh -NoProfile -File (Join-Path $RepoRoot 'reference/docker/bootstrap.ps1') -VaultRoot $VaultRoot -AgentTarget $AgentTarget -SourceRoot $fakeOptDir 2>&1 | ForEach-Object { Write-Host "[bootstrap] $_" }
    if ($LASTEXITCODE -ne 0) { throw "bootstrap.ps1 exited $LASTEXITCODE on first run" }

    $preHash = (Get-FileHash -Path (Join-Path $VaultRoot '_meta/session-log.md') -Algorithm SHA256).Hash
    & pwsh -NoProfile -File (Join-Path $RepoRoot 'reference/docker/bootstrap.ps1') -VaultRoot $VaultRoot -AgentTarget $AgentTarget -SourceRoot $fakeOptDir 2>&1 | ForEach-Object { Write-Host "[bootstrap#2] $_" }
    $postHash = (Get-FileHash -Path (Join-Path $VaultRoot '_meta/session-log.md') -Algorithm SHA256).Hash
    Record 'idempotent re-bootstrap leaves session-log.md untouched' ($LASTEXITCODE -eq 0 -and $preHash -eq $postHash)

    Test-Vault -VaultRoot $VaultRoot

  } else {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
      throw "docker CLI not found on this host — install Docker (Desktop or Engine) before running -Target docker"
    }
    New-Item -ItemType Directory -Path $VaultRoot -Force | Out-Null
    $containerName = 'system-o-conformance-' + [guid]::NewGuid().ToString('N').Substring(0, 8)

    Write-Host "[setup] docker build -t $ImageTag -f reference/docker/Dockerfile ."
    & docker build -t $ImageTag -f (Join-Path $RepoRoot 'reference/docker/Dockerfile') $RepoRoot
    if ($LASTEXITCODE -ne 0) { throw "docker build failed (exit $LASTEXITCODE)" }

    Write-Host "[setup] docker run --init -d --name $containerName -v `"$VaultRoot`":/vault $ImageTag"
    & docker run --init -d --name $containerName -v "${VaultRoot}:/vault" -e VAULT_ROOT=/vault -e AGENT_TARGET=$AgentTarget $ImageTag
    if ($LASTEXITCODE -ne 0) { throw "docker run failed (exit $LASTEXITCODE)" }

    $sessionLog = Join-Path $VaultRoot '_meta/session-log.md'
    $deadline = (Get-Date).AddSeconds(60)
    while (-not (Test-Path $sessionLog) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 1 }
    if (-not (Test-Path $sessionLog)) {
      & docker logs $containerName 2>&1 | ForEach-Object { Write-Host "[container] $_" }
      throw "bootstrap never scaffolded the bind-mounted vault within 60s — see container logs above"
    }
    Start-Sleep -Seconds 2   # let bootstrap.ps1 finish writing every starter file

    # idempotency: restart the container against the SAME already-scaffolded vault
    $preHash = (Get-FileHash -Path $sessionLog -Algorithm SHA256).Hash
    & docker restart $containerName | Out-Null
    Start-Sleep -Seconds 5
    $postHash = (Get-FileHash -Path $sessionLog -Algorithm SHA256).Hash
    Record 'idempotent re-bootstrap leaves session-log.md untouched' ($preHash -eq $postHash)

    # Documented gap (reference/docker/README.md §Verified): bootstrap.ps1 runs
    # as root inside the container, so on a Linux host the bind-mounted vault
    # comes out root-owned — this harness writes fixtures into it from the host
    # side, so it needs the documented chown workaround before the rest of the
    # assertion suite can write anything. No-op on Windows hosts, where Docker
    # Desktop's bind-mount layer doesn't enforce POSIX ownership the same way.
    if ($IsLinux -or $IsMacOS) {
      # Probe inside a subdirectory bootstrap.ps1 actually creates (root, inside
      # the container) — the bind-mount root itself was created host-side by
      # this script BEFORE `docker run`, so it stays host-owned regardless and
      # would make this probe a false negative if tested there instead.
      $probe = Join-Path $VaultRoot '_meta/handoffs/.conformance-write-probe'
      $writable = $true
      try { 'x' | Set-Content -Path $probe -ErrorAction Stop; Remove-Item -Path $probe -Force -ErrorAction SilentlyContinue }
      catch { $writable = $false }
      if (-not $writable) {
        $hostUid = (& id -u).Trim()
        $hostGid = (& id -g).Trim()
        Write-Host "[setup] bind-mounted vault is root-owned — chowning to host uid:gid $hostUid`:$hostGid via docker exec"
        & docker exec $containerName chown -R "${hostUid}:${hostGid}" /vault
        if ($LASTEXITCODE -ne 0) { throw "chown inside container failed (exit $LASTEXITCODE)" }
      }
    }

    Test-Vault -VaultRoot $VaultRoot

    # docker-only: crontab installed with $VAULT_ROOT substituted, not left literal
    $cronOut = & docker exec $containerName crontab -l 2>&1 | Out-String
    $cronInstalled = $cronOut.Contains('run-extensions.ps1') -and -not $cronOut.Contains('$VAULT_ROOT')
    Record 'crontab installed with $VAULT_ROOT substituted' $cronInstalled $cronOut.Trim()
  }

  $failed = @($results | Where-Object { -not $_.pass })
  $reportDir = Join-Path $RepoRoot '_meta/logs'
  if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
  $reportFile = Join-Path $reportDir ("conformance-{0}-{1}.md" -f $Target, (Get-Date -Format 'yyyy-MM-dd-HHmmss'))
  $lines = @("# Conformance report — target=$Target — $(Get-Date -Format 'yyyy-MM-dd HH:mm')", '')
  foreach ($r in $results) {
    $mark = if ($r.pass) { 'PASS' } else { 'FAIL' }
    $lines += "- [$mark] $($r.name)$(if ($r.detail) { " — $($r.detail)" })"
  }
  $lines += @('', "**Result: $($results.Count - $failed.Count)/$($results.Count) passed**")
  $lines -join "`n" | Set-Content -Path $reportFile -Encoding UTF8
  Write-Host ""
  Write-Host "Report: $reportFile"
  Write-Host "Result: $($results.Count - $failed.Count)/$($results.Count) passed"

  if ($failed.Count -gt 0) { exit 1 } else { exit 0 }

} finally {
  Cleanup
}
