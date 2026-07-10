[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Get-Fingerprint {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'missing' }
    $item = Get-Item -LiteralPath $Path
    return ('{0}:{1}' -f $item.Length, (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash)
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$scripts = @(
    'src\friction.ps1',
    'review-batch.ps1',
    'install.ps1',
    'setup.ps1',
    'uninstall.ps1',
    'tests\verify.ps1'
) | ForEach-Object { Join-Path $repoRoot $_ }

foreach ($script in $scripts) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors)
    Assert-True ($errors.Count -eq 0) "PowerShell syntax: $script"
}

$productionCodex = Join-Path $env:USERPROFILE '.codex'
$productionPaths = @(
    (Join-Path $productionCodex 'AGENTS.md'),
    (Join-Path $productionCodex 'bin\friction.ps1'),
    (Join-Path $productionCodex 'bin\friction-review.ps1'),
    (Join-Path $productionCodex 'friction.jsonl')
)
$productionBefore = @{}
foreach ($path in $productionPaths) { $productionBefore[$path] = Get-Fingerprint $path }
$userPathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')

$root = Join-Path $env:TEMP ('codex-friction-tests-' + [Guid]::NewGuid().ToString('N'))
$oldProfile = $env:USERPROFILE
$oldPath = $env:Path
$failure = $null
$summary = $null

try {
    $env:USERPROFILE = $root
    $codex = Join-Path $root '.codex'
    New-Item -ItemType Directory -Force -Path $codex | Out-Null
    [IO.File]::WriteAllText((Join-Path $codex 'AGENTS.md'), "before-rule`r`nafter-rule`r`n", [Text.UTF8Encoding]::new($false))

    $setup = & (Join-Path $repoRoot 'setup.ps1') -CodexHome $codex -PathScope Process
    Assert-True $setup.Ready 'setup reports ready'
    Assert-True $setup.FreshShellVerified 'fresh shell command resolution'
    Assert-True ((Get-Item -LiteralPath $setup.Log).Length -eq 0) 'setup probe does not add a friction row'

    $null = & (Join-Path $repoRoot 'install.ps1') -CodexHome $codex -PathScope Process
    $agents = [IO.File]::ReadAllText((Join-Path $codex 'AGENTS.md'))
    Assert-True (([regex]::Matches($agents, '<!-- codex-friction-log:start -->')).Count -eq 1) 'one managed AGENTS block after repeated install'
    Assert-True ($agents.Contains('before-rule') -and $agents.Contains('after-rule')) 'surrounding AGENTS content preserved'
    $pathTokenCount = @($env:Path -split ';' | Where-Object {
        $_.TrimEnd('\').Equals((Join-Path $codex 'bin').TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)
    }).Count
    Assert-True ($pathTokenCount -eq 1) 'one process PATH token after repeated install'

    $malformedCodex = Join-Path $root 'malformed\.codex'
    New-Item -ItemType Directory -Force -Path $malformedCodex | Out-Null
    $malformedAgents = Join-Path $malformedCodex 'AGENTS.md'
    [IO.File]::WriteAllText($malformedAgents, "keep`r`n<!-- codex-friction-log:start -->`r`n", [Text.UTF8Encoding]::new($false))
    $malformedBefore = [IO.File]::ReadAllText($malformedAgents)
    $malformedRejected = $false
    try { $null = & (Join-Path $repoRoot 'install.ps1') -CodexHome $malformedCodex -PathScope None }
    catch { $malformedRejected = $true }
    Assert-True $malformedRejected 'malformed managed markers reject install'
    Assert-True ([IO.File]::ReadAllText($malformedAgents) -eq $malformedBefore) 'malformed AGENTS file remains unchanged'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $malformedCodex 'bin'))) 'malformed install creates no commands'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $malformedCodex 'friction.jsonl'))) 'malformed install creates no log'

    $reversedCodex = Join-Path $root 'reversed\.codex'
    $reversedBin = Join-Path $reversedCodex 'bin'
    New-Item -ItemType Directory -Force -Path $reversedBin | Out-Null
    $reversedAgents = Join-Path $reversedCodex 'AGENTS.md'
    $reversedWriter = Join-Path $reversedBin 'friction.ps1'
    $reversedReviewer = Join-Path $reversedBin 'friction-review.ps1'
    $reversedLog = Join-Path $reversedCodex 'friction.jsonl'
    [IO.File]::WriteAllText($reversedAgents, "keep`r`n<!-- codex-friction-log:end -->`r`nbody`r`n<!-- codex-friction-log:start -->`r`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($reversedWriter, 'writer-sentinel', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($reversedReviewer, 'reviewer-sentinel', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($reversedLog, 'log-sentinel', [Text.UTF8Encoding]::new($false))
    $reversedBefore = @{
        Agents = Get-Fingerprint $reversedAgents
        Writer = Get-Fingerprint $reversedWriter
        Reviewer = Get-Fingerprint $reversedReviewer
        Log = Get-Fingerprint $reversedLog
    }
    $reversedInstallRejected = $false
    try { $null = & (Join-Path $repoRoot 'install.ps1') -CodexHome $reversedCodex -PathScope None }
    catch { $reversedInstallRejected = $true }
    Assert-True $reversedInstallRejected 'reversed managed markers reject install'
    Assert-True ((Get-Fingerprint $reversedAgents) -eq $reversedBefore.Agents) 'reversed install preserves AGENTS'
    Assert-True ((Get-Fingerprint $reversedWriter) -eq $reversedBefore.Writer) 'reversed install preserves existing writer'
    Assert-True ((Get-Fingerprint $reversedReviewer) -eq $reversedBefore.Reviewer) 'reversed install preserves existing reviewer'
    Assert-True ((Get-Fingerprint $reversedLog) -eq $reversedBefore.Log) 'reversed install preserves log'
    $reversedUninstallRejected = $false
    try { $null = & (Join-Path $repoRoot 'uninstall.ps1') -CodexHome $reversedCodex -PathScope None }
    catch { $reversedUninstallRejected = $true }
    Assert-True $reversedUninstallRejected 'reversed managed markers reject uninstall'
    Assert-True ((Get-Fingerprint $reversedAgents) -eq $reversedBefore.Agents) 'reversed uninstall preserves AGENTS'
    Assert-True ((Get-Fingerprint $reversedWriter) -eq $reversedBefore.Writer) 'reversed uninstall preserves writer'
    Assert-True ((Get-Fingerprint $reversedReviewer) -eq $reversedBefore.Reviewer) 'reversed uninstall preserves reviewer'
    Assert-True ((Get-Fingerprint $reversedLog) -eq $reversedBefore.Log) 'reversed uninstall preserves log'

    $writer = Join-Path $codex 'bin\friction.ps1'
    $reviewer = Join-Path $codex 'bin\friction-review.ps1'
    $log = Join-Path $codex 'friction.jsonl'
    Assert-True ((Get-FileHash $writer).Hash -eq (Get-FileHash (Join-Path $repoRoot 'src\friction.ps1')).Hash) 'installed writer matches source'
    Assert-True ((Get-FileHash $reviewer).Hash -eq (Get-FileHash (Join-Path $repoRoot 'review-batch.ps1')).Hash) 'installed reviewer matches source'

    $validOutput = @(& $writer 'run formatter' 'formatter executable was missing' 2>&1)
    Assert-True ($validOutput.Count -eq 0) 'valid logger call is silent'
    $rows = @(Get-Content -LiteralPath $log)
    Assert-True ($rows.Count -eq 1) 'valid logger call appends one row'
    $row = $rows[0] | ConvertFrom-Json
    Assert-True (($row.PSObject.Properties.Name -join ',') -eq 'ts,cwd,blocked,friction') 'exact JSONL schema and key order'
    Assert-True ([DateTimeOffset]::Parse($row.ts).Offset -eq [TimeSpan]::Zero) 'UTC timestamp'

    $beforeInvalid = (Get-Item -LiteralPath $log).Length
    $invalidOutput = @(
        & $writer 'one-argument'
        & $writer '' 'empty-intent'
        & $writer 'one' 'two' 'three'
    )
    Assert-True ($invalidOutput.Count -eq 0) 'invalid calls are silent and host survives'
    Assert-True ((Get-Item -LiteralPath $log).Length -eq $beforeInvalid) 'invalid calls do not append'

    [IO.File]::WriteAllText($log, '', [Text.UTF8Encoding]::new($false))
    $projectA = Join-Path $root 'project-a'
    $projectB = Join-Path $root 'project-b'
    New-Item -ItemType Directory -Force -Path $projectA, $projectB | Out-Null
    Push-Location $projectA
    try {
        $expectedProjectA = (Get-Location).Path
        & $writer 'build project A' 'tool A was unavailable'
    }
    finally { Pop-Location }
    Push-Location $projectB
    try {
        $expectedProjectB = (Get-Location).Path
        & $writer 'build project B' 'tool B rejected input'
    }
    finally { Pop-Location }
    $projectRows = @(Get-Content -LiteralPath $log | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-True ($projectRows.Count -eq 2) 'two projects share one log'
    Assert-True ($projectRows[0].cwd -eq $expectedProjectA -and $projectRows[1].cwd -eq $expectedProjectB) 'rows retain exact provider CWDs'

    [IO.File]::WriteAllText($log, '', [Text.UTF8Encoding]::new($false))
    $processes = @()
    foreach ($index in 1..32) {
        $arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $writer), "intent-$index", "obstacle-$index")
        $processes += Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WorkingDirectory $projectA -WindowStyle Hidden -PassThru
    }
    foreach ($process in $processes) {
        $process.WaitForExit()
        Assert-True ($process.ExitCode -eq 0) "concurrent writer process $($process.Id) exits zero"
        $process.Dispose()
    }
    $concurrentRows = @(Get-Content -LiteralPath $log | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-True ($concurrentRows.Count -eq 32) '32 concurrent calls produce 32 rows'
    Assert-True (@($concurrentRows.blocked | Sort-Object -Unique).Count -eq 32) 'concurrent rows are unique and parseable'

    [IO.File]::WriteAllText($log, '', [Text.UTF8Encoding]::new($false))
    & $writer 'old intent 1' 'old obstacle 1'
    & $writer 'old intent 2' 'old obstacle 2'
    $claim = (& $reviewer -Claim) | ConvertFrom-Json
    Assert-True (-not [string]::IsNullOrWhiteSpace($claim.batch)) 'non-empty active log produces a pending batch'
    & $writer 'new intent' 'new obstacle'
    $pendingBefore = (& $reviewer -List) | ConvertFrom-Json
    Assert-True (@($pendingBefore.batches).Count -eq 1) 'claimed batch remains pending until completion'
    Assert-True (@(Get-Content -LiteralPath $claim.path).Count -eq 2) 'claimed batch contains all reviewed rows'
    $activeAfterClaim = @(Get-Content -LiteralPath $log | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-True ($activeAfterClaim.Count -eq 1 -and $activeAfterClaim[0].blocked -eq 'new intent') 'new append survives batch claim'
    $null = & $reviewer -Complete -Batch $claim.batch
    Assert-True (-not (Test-Path -LiteralPath $claim.path)) 'completed batch is removed'
    Assert-True (@(((& $reviewer -List) | ConvertFrom-Json).batches).Count -eq 0) 'completed batch cannot be reviewed again'

    & $writer 'recoverable intent' 'recoverable obstacle'
    $recoverable = (& $reviewer -Claim) | ConvertFrom-Json
    Assert-True (Test-Path -LiteralPath $recoverable.path) 'uncompleted batch remains recoverable'

    $uninstall = & (Join-Path $repoRoot 'uninstall.ps1') -CodexHome $codex -PathScope Process
    Assert-True $uninstall.Uninstalled 'uninstall reports success'
    Assert-True $uninstall.DataPreserved 'uninstall preserves data by default'
    Assert-True (-not (Test-Path -LiteralPath $writer)) 'writer removed'
    Assert-True (-not (Test-Path -LiteralPath $reviewer)) 'reviewer removed'
    Assert-True (Test-Path -LiteralPath $log) 'active log preserved'
    Assert-True (Test-Path -LiteralPath $recoverable.path) 'pending review data preserved'
    $agentsAfter = [IO.File]::ReadAllText((Join-Path $codex 'AGENTS.md'))
    Assert-True (-not $agentsAfter.Contains('codex-friction-log:start')) 'managed AGENTS block removed'
    Assert-True ($agentsAfter.Contains('before-rule') -and $agentsAfter.Contains('after-rule')) 'uninstall preserves surrounding AGENTS content'

    $summary = [ordered]@{
        status = 'PASS'
        scriptsParsed = $scripts.Count
        concurrentRows = $concurrentRows.Count
        multiProjectRows = $projectRows.Count
        reviewedRows = 2
        newRowsPreserved = $activeAfterClaim.Count
        incompleteBatchRecoverable = $true
        productionUntouched = $true
    }
}
catch {
    $failure = $_
}
finally {
    $env:USERPROFILE = $oldProfile
    $env:Path = $oldPath
    if (Test-Path -LiteralPath $root) {
        $resolvedRoot = [IO.Path]::GetFullPath($root).TrimEnd('\')
        $resolvedTemp = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
        if (-not $resolvedRoot.StartsWith($resolvedTemp + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unexpected test path: $resolvedRoot"
        }
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
}

foreach ($path in $productionPaths) {
    Assert-True ((Get-Fingerprint $path) -eq $productionBefore[$path]) "production file unchanged: $path"
}
Assert-True ([Environment]::GetEnvironmentVariable('Path', 'User') -eq $userPathBefore) 'user PATH unchanged by tests'

if ($null -ne $failure) { throw $failure }
$summary | ConvertTo-Json -Compress
