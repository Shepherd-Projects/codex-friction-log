[CmdletBinding()]
param(
    [string]$CodexHome = (Join-Path $env:USERPROFILE '.codex'),

    [ValidateSet('User', 'Process', 'None')]
    [string]$PathScope = 'User'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$install = Join-Path $PSScriptRoot 'install.ps1'
$result = & $install -CodexHome $CodexHome -PathScope $PathScope

if ($PathScope -ne 'None') {
    $probe = & powershell.exe -NoLogo -NoProfile -Command @'
$command = Get-Command friction -ErrorAction Stop
$reviewCommand = Get-Command friction-review -ErrorAction Stop
& friction 'probe-only'
[pscustomobject]@{
    Source = $command.Source
    ReviewSource = $reviewCommand.Source
    HostSurvived = $true
} | ConvertTo-Json -Compress
'@
    if ($LASTEXITCODE -ne 0) {
        throw 'Installation completed, but a fresh PowerShell process could not resolve friction.'
    }
    $probeResult = $probe | ConvertFrom-Json
    if (-not $probeResult.HostSurvived) {
        throw 'Installation probe did not complete.'
    }
}

[pscustomobject]@{
    Ready = $true
    Command = $result.Command
    ReviewCommand = $result.ReviewCommand
    Log = $result.Log
    Agents = $result.Agents
    FreshShellVerified = ($PathScope -ne 'None')
    RestartCodex = $result.RestartCodex
}
