[CmdletBinding()]
param(
    [string]$CodexHome = (Join-Path $env:USERPROFILE '.codex'),

    [ValidateSet('User', 'Process', 'None')]
    [string]$PathScope = 'User',

    [switch]$RemoveData
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$binPath = Join-Path $CodexHome 'bin'
$agentsPath = Join-Path $CodexHome 'AGENTS.md'
$logPath = Join-Path $CodexHome 'friction.jsonl'
$reviewDataPath = Join-Path $CodexHome 'friction-pending'
$reviewLockPath = Join-Path $CodexHome 'friction-review.lock'
$startMarker = '<!-- codex-friction-log:start -->'
$endMarker = '<!-- codex-friction-log:end -->'
$utf8 = [Text.UTF8Encoding]::new($false)

if (Test-Path -LiteralPath $agentsPath -PathType Leaf) {
    $agents = [IO.File]::ReadAllText($agentsPath)
    $startCount = ([regex]::Matches($agents, [regex]::Escape($startMarker))).Count
    $endCount = ([regex]::Matches($agents, [regex]::Escape($endMarker))).Count
    if ($startCount -ne $endCount -or $startCount -gt 1) {
        throw "Cannot safely update $agentsPath because its managed friction block markers are malformed."
    }
    if ($startCount -eq 1) {
        $startIndex = $agents.IndexOf($startMarker, [StringComparison]::Ordinal)
        $endIndex = $agents.IndexOf($endMarker, $startIndex, [StringComparison]::Ordinal)
        if ($endIndex -lt ($startIndex + $startMarker.Length)) {
            throw "Cannot safely update $agentsPath because its managed friction block markers are out of order."
        }
        $afterIndex = $endIndex + $endMarker.Length
        $agents = $agents.Substring(0, $startIndex) + $agents.Substring($afterIndex)
        [IO.File]::WriteAllText($agentsPath, $agents, $utf8)
    }
}

foreach ($name in @('friction.ps1', 'friction-review.ps1')) {
    $path = Join-Path $binPath $name
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        Remove-Item -LiteralPath $path -Force
    }
}

function Remove-PathEntry {
    param(
        [AllowNull()][string]$PathValue,
        [Parameter(Mandatory)][string]$Entry
    )

    $normalizedEntry = $Entry.TrimEnd('\')
    $entries = @($PathValue -split ';' | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and
        -not $_.Trim().TrimEnd('\').Equals($normalizedEntry, [StringComparison]::OrdinalIgnoreCase)
    })
    return ($entries -join ';')
}

if ($PathScope -eq 'User') {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    [Environment]::SetEnvironmentVariable('Path', (Remove-PathEntry $userPath $binPath), 'User')
}
if ($PathScope -ne 'None') {
    $env:Path = Remove-PathEntry $env:Path $binPath
}

if (Test-Path -LiteralPath $binPath -PathType Container) {
    $remaining = @(Get-ChildItem -LiteralPath $binPath -Force)
    if ($remaining.Count -eq 0) { Remove-Item -LiteralPath $binPath -Force }
}

if ($RemoveData) {
    if (Test-Path -LiteralPath $logPath -PathType Leaf) {
        Remove-Item -LiteralPath $logPath -Force
    }
    if (Test-Path -LiteralPath $reviewDataPath -PathType Container) {
        Remove-Item -LiteralPath $reviewDataPath -Recurse -Force
    }
    if (Test-Path -LiteralPath $reviewLockPath -PathType Leaf) {
        Remove-Item -LiteralPath $reviewLockPath -Force
    }
}

[pscustomobject]@{
    Uninstalled = $true
    DataPreserved = (-not $RemoveData)
    Log = $logPath
    PendingReviewData = $reviewDataPath
    RestartCodex = ($PathScope -eq 'User')
}
