[CmdletBinding(DefaultParameterSetName = 'List')]
param(
    [Parameter(ParameterSetName = 'Claim', Mandatory = $true)]
    [switch]$Claim,

    [Parameter(ParameterSetName = 'List')]
    [switch]$List,

    [Parameter(ParameterSetName = 'Complete', Mandatory = $true)]
    [switch]$Complete,

    [Parameter(ParameterSetName = 'Complete', Mandatory = $true)]
    [string]$Batch
)

$mutex = $null
$locked = $false

function Get-Batches([string]$PendingDirectory) {
    @(Get-ChildItem -LiteralPath $PendingDirectory -File -Filter 'batch-*.jsonl' |
        Sort-Object LastWriteTimeUtc |
        ForEach-Object {
            [ordered]@{
                batch   = $_.Name
                path    = $_.FullName
                bytes   = $_.Length
                modified = $_.LastWriteTimeUtc.ToString('o')
            }
        })
}

try {
    if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) { throw 'USERPROFILE is required.' }

    $codexDirectory = Join-Path $env:USERPROFILE '.codex'
    $logPath = Join-Path $codexDirectory 'friction.jsonl'
    $pendingDirectory = Join-Path $codexDirectory 'friction-pending'
    $utf8 = [Text.UTF8Encoding]::new($false)
    $mutex = [Threading.Mutex]::new($false, 'Local\CodexFrictionLog')

    try {
        $locked = $mutex.WaitOne(5000)
    }
    catch [Threading.AbandonedMutexException] {
        $locked = $true
    }

    if (-not $locked) { throw 'Timed out waiting for friction log.' }

    [void][IO.Directory]::CreateDirectory($codexDirectory)
    [void][IO.Directory]::CreateDirectory($pendingDirectory)

    if ($Complete) {
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
    elseif ($Claim) {
        if (-not [IO.File]::Exists($logPath)) {
            [IO.File]::WriteAllText($logPath, '', $utf8)
            $result = [ordered]@{ batch = $null }
        }
        elseif ((Get-Item -LiteralPath $logPath -Force).Length -eq 0) {
            $result = [ordered]@{ batch = $null }
        }
        else {
            $batch = 'batch-{0}-{1}.jsonl' -f [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'), [Guid]::NewGuid().ToString('N')
            $batchPath = Join-Path $pendingDirectory $batch
            [IO.File]::Move($logPath, $batchPath)
            [IO.File]::WriteAllText($logPath, '', $utf8)
            $result = [ordered]@{ batch = $batch; path = $batchPath }
        }
    }
    else {
        $result = [ordered]@{ batches = @(Get-Batches $pendingDirectory) }
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
