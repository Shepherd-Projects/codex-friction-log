[CmdletBinding()]
param(
    [string]$CodexHome = (Join-Path $env:USERPROFILE '.codex'),

    [ValidateSet('User', 'Process', 'None')]
    [string]$PathScope = 'User'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceScript = Join-Path $PSScriptRoot 'src\friction.ps1'
$sourceReviewScript = Join-Path $PSScriptRoot 'review-batch.ps1'
$sourceSnippet = Join-Path $PSScriptRoot 'AGENTS.snippet.md'
if (-not (Test-Path -LiteralPath $sourceScript -PathType Leaf)) {
    throw "Missing source file: $sourceScript"
}
if (-not (Test-Path -LiteralPath $sourceReviewScript -PathType Leaf)) {
    throw "Missing source file: $sourceReviewScript"
}
if (-not (Test-Path -LiteralPath $sourceSnippet -PathType Leaf)) {
    throw "Missing source file: $sourceSnippet"
}

$binPath = Join-Path $CodexHome 'bin'
$targetScript = Join-Path $binPath 'friction.ps1'
$targetReviewScript = Join-Path $binPath 'friction-review.ps1'
$agentsPath = Join-Path $CodexHome 'AGENTS.md'
$logPath = Join-Path $CodexHome 'friction.jsonl'
$startMarker = '<!-- codex-friction-log:start -->'
$endMarker = '<!-- codex-friction-log:end -->'
$utf8 = [Text.UTF8Encoding]::new($false)

$snippet = [IO.File]::ReadAllText($sourceSnippet).Trim()
$agents = if (Test-Path -LiteralPath $agentsPath) {
    [IO.File]::ReadAllText($agentsPath)
}
else {
    ''
}

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
    $agents = $agents.Substring(0, $startIndex) + $snippet + $agents.Substring($afterIndex)
}
else {
    $separator = if ([string]::IsNullOrWhiteSpace($agents)) {
        ''
    }
    elseif ($agents.EndsWith("`r`n`r`n") -or $agents.EndsWith("`n`n")) {
        ''
    }
    elseif ($agents.EndsWith("`r`n") -or $agents.EndsWith("`n")) {
        [Environment]::NewLine
    }
    else {
        [Environment]::NewLine + [Environment]::NewLine
    }
    $agents += $separator + $snippet + [Environment]::NewLine
}

New-Item -ItemType Directory -Force -Path $CodexHome, $binPath | Out-Null
Copy-Item -LiteralPath $sourceScript -Destination $targetScript -Force
Copy-Item -LiteralPath $sourceReviewScript -Destination $targetReviewScript -Force
if (-not (Test-Path -LiteralPath $logPath)) {
    [IO.File]::WriteAllText($logPath, '', $utf8)
}
[IO.File]::WriteAllText($agentsPath, $agents, $utf8)

function Add-PathEntry {
    param(
        [AllowNull()][string]$PathValue,
        [Parameter(Mandatory)][string]$Entry
    )

    $entries = @($PathValue -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $normalizedEntry = $Entry.TrimEnd('\')
    $present = $false
    foreach ($item in $entries) {
        if ($item.Trim().TrimEnd('\').Equals($normalizedEntry, [StringComparison]::OrdinalIgnoreCase)) {
            $present = $true
            break
        }
    }
    if (-not $present) { $entries += $Entry }
    return ($entries -join ';')
}

if ($PathScope -eq 'User') {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    [Environment]::SetEnvironmentVariable('Path', (Add-PathEntry $userPath $binPath), 'User')
}
if ($PathScope -ne 'None') {
    $env:Path = Add-PathEntry $env:Path $binPath
}

[pscustomobject]@{
    Installed = $true
    Command = $targetScript
    ReviewCommand = $targetReviewScript
    Log = $logPath
    Agents = $agentsPath
    PathScope = $PathScope
    RestartCodex = ($PathScope -eq 'User')
}
