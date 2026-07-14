[CmdletBinding()]
param(
    [Parameter(ParameterSetName = 'Claim', Mandatory = $true)]
    [switch]$Claim,

    [Parameter(ParameterSetName = 'List', Mandatory = $true)]
    [switch]$List,

    [Parameter(ParameterSetName = 'Complete', Mandatory = $true)]
    [switch]$Complete,

    [Parameter(ParameterSetName = 'Release', Mandatory = $true)]
    [switch]$Release,

    [Parameter(ParameterSetName = 'List', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Complete', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Release', Mandatory = $true)]
    [string]$Lease,

    [Parameter(ParameterSetName = 'Complete', Mandatory = $true)]
    [string]$Batch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$mutex = $null
$locked = $false

function Get-Batches {
    param([string]$PendingDirectory)

    @(Get-ChildItem -LiteralPath $PendingDirectory -File -Filter 'batch-*.jsonl' |
        Sort-Object LastWriteTimeUtc |
        ForEach-Object {
            [ordered]@{
                batch    = $_.Name
                path     = $_.FullName
                bytes    = $_.Length
                modified = $_.LastWriteTimeUtc.ToString('o')
            }
        })
}

function Get-LeaseRecord {
    param([string]$LeasePath)

    if (-not [IO.File]::Exists($LeasePath)) { return $null }
    try {
        [IO.File]::ReadAllText($LeasePath) | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw 'The review lease is unreadable; preserve it and inspect manually.'
    }
}

function Assert-LeaseOwner {
    param([string]$LeasePath, [string]$ExpectedToken)

    $record = Get-LeaseRecord $LeasePath
    if ($null -eq $record -or [string]::IsNullOrWhiteSpace([string]$record.token) -or
        -not ([string]$record.token).Equals($ExpectedToken, [StringComparison]::Ordinal)) {
        throw 'Lease token does not own the current review.'
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) { throw 'USERPROFILE is required.' }

    $codexDirectory = Join-Path $env:USERPROFILE '.codex'
    $logPath = [IO.Path]::GetFullPath((Join-Path $codexDirectory 'friction.jsonl'))
    $pendingDirectory = Join-Path $codexDirectory 'friction-pending'
    $leasePath = Join-Path $codexDirectory 'friction-review.lock'
    $utf8 = [Text.UTF8Encoding]::new($false)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $pathHash = [BitConverter]::ToString(
            $hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($logPath.ToUpperInvariant()))
        ).Replace('-', '')
    }
    finally { $hasher.Dispose() }
    $mutex = [Threading.Mutex]::new($false, 'Local\CodexFrictionLog-' + $pathHash)

    try {
        $locked = $mutex.WaitOne(5000)
    }
    catch [Threading.AbandonedMutexException] {
        $locked = $true
    }

    if (-not $locked) { throw 'Timed out waiting for friction log.' }

    [void][IO.Directory]::CreateDirectory($codexDirectory)
    [void][IO.Directory]::CreateDirectory($pendingDirectory)

    if ($Claim) {
        $now = [DateTimeOffset]::UtcNow
        $existing = Get-LeaseRecord $leasePath
        if ($null -ne $existing) {
            $acquired = [DateTimeOffset]::Parse([string]$existing.acquired)
            if (($now - $acquired).TotalHours -lt 24) {
                $result = [ordered]@{
                    busy     = $true
                    acquired = $acquired.ToString('o')
                    lease    = $null
                    batch    = $null
                    path     = $null
                }
            }
            else {
                [IO.File]::Delete($leasePath)
                $existing = $null
            }
        }

        if ($null -eq $existing) {
            $token = [Guid]::NewGuid().ToString('N')
            $leaseRecord = [ordered]@{
                token    = $token
                acquired = $now.ToString('o')
            }
            [IO.File]::WriteAllText(
                $leasePath,
                (ConvertTo-Json -InputObject $leaseRecord -Compress),
                $utf8
            )

            try {
                if (-not [IO.File]::Exists($logPath)) {
                    [IO.File]::WriteAllText($logPath, '', $utf8)
                    $batch = $null
                    $batchPath = $null
                }
                elseif ((Get-Item -LiteralPath $logPath -Force).Length -eq 0) {
                    $batch = $null
                    $batchPath = $null
                }
                else {
                    $batch = 'batch-{0}-{1}.jsonl' -f $now.ToString('yyyyMMddTHHmmssfffffffZ'), [Guid]::NewGuid().ToString('N')
                    $batchPath = Join-Path $pendingDirectory $batch
                    [IO.File]::Move($logPath, $batchPath)
                    [IO.File]::WriteAllText($logPath, '', $utf8)
                }
            }
            catch {
                [IO.File]::Delete($leasePath)
                throw
            }

            $result = [ordered]@{
                busy  = $false
                lease = $token
                batch = $batch
                path  = $batchPath
            }
        }
    }
    elseif ($List) {
        Assert-LeaseOwner $leasePath $Lease
        $result = [ordered]@{ batches = @(Get-Batches $pendingDirectory) }
    }
    elseif ($Complete) {
        Assert-LeaseOwner $leasePath $Lease
        if ($Batch -ne [IO.Path]::GetFileName($Batch) -or $Batch -notmatch '^batch-[0-9TZ-]+-[0-9a-f]{32}\.jsonl$') {
            throw 'Batch must be an owned batch filename.'
        }

        $batchPath = Join-Path $pendingDirectory $Batch
        if (-not [IO.File]::Exists($batchPath)) { throw 'Batch does not exist.' }
        if (((Get-Item -LiteralPath $batchPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Batch must not be a reparse point.'
        }

        [IO.File]::Delete($batchPath)
        $result = [ordered]@{ completed = $Batch }
    }
    else {
        Assert-LeaseOwner $leasePath $Lease
        [IO.File]::Delete($leasePath)
        $result = [ordered]@{ released = $true }
    }
}
finally {
    if ($null -ne $mutex) {
        if ($locked) {
            try { $mutex.ReleaseMutex() }
            catch {}
        }
        try { $mutex.Dispose() }
        catch {}
    }
}

Write-Output (ConvertTo-Json -InputObject $result -Compress -Depth 3)
