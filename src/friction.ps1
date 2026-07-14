if ($args.Count -ne 2) { return }

$blocked = [string]$args[0]
$friction = [string]$args[1]
if ([string]::IsNullOrWhiteSpace($blocked) -or [string]::IsNullOrWhiteSpace($friction)) { return }

$mutex = $null
$locked = $false

try {
    $record = [ordered]@{
        ts       = [DateTimeOffset]::UtcNow.ToString('o')
        cwd      = (Get-Location).Path
        blocked  = $blocked
        friction = $friction
    }
    $line = ConvertTo-Json -InputObject $record -Compress -ErrorAction Stop
    $logPath = [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.codex\friction.jsonl' -ErrorAction Stop))
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

    if ($locked) {
        $utf8 = [Text.UTF8Encoding]::new($false)
        [IO.File]::AppendAllText($logPath, $line + [Environment]::NewLine, $utf8)
    }
}
catch {
    # Logging friction must never create more friction.
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
