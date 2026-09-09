# FileBackupRT v8 - silent real-time, append-only file backup for Windows PowerShell 5.1+
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config.json"
)

$ErrorActionPreference = 'Stop'

$script:PidPath = Join-Path $PSScriptRoot 'FileBackupRT.pid'
$script:StopPath = Join-Path $PSScriptRoot 'FileBackupRT.stop'
$script:StartingPath = Join-Path $PSScriptRoot 'FileBackupRT.starting'
$script:SingleInstanceMutex = $null
$script:PidWritten = $false

function Remove-LifecycleFiles {
    try { if (Test-Path -LiteralPath $script:StartingPath) { Remove-Item -LiteralPath $script:StartingPath -Force -ErrorAction SilentlyContinue } } catch {}
    try { if (Test-Path -LiteralPath $script:StopPath) { Remove-Item -LiteralPath $script:StopPath -Force -ErrorAction SilentlyContinue } } catch {}
    try {
        if (Test-Path -LiteralPath $script:PidPath) {
            $pidText = (Get-Content -LiteralPath $script:PidPath -Raw -ErrorAction SilentlyContinue).Trim()
            if ($pidText -eq [string]$PID) { Remove-Item -LiteralPath $script:PidPath -Force -ErrorAction SilentlyContinue }
        }
    } catch {}
}

function Test-StopRequested {
    return (Test-Path -LiteralPath $script:StopPath)
}

function Initialize-Lifecycle {
    $script:SingleInstanceMutex = New-Object System.Threading.Mutex($false, 'Local\FileBackupRT')
    if (-not $script:SingleInstanceMutex.WaitOne(0, $false)) {
        $script:SingleInstanceMutex.Dispose()
        $script:SingleInstanceMutex = $null
        return $false
    }

    $createdPid = $false
    try {
        $pidFile = [IO.File]::Open($script:PidPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        $createdPid = $true
        try {
            $writer = New-Object IO.StreamWriter($pidFile)
            try { $writer.WriteLine([string]$PID) } finally { $writer.Dispose() }
        } finally { $pidFile.Dispose() }
        $script:PidWritten = $true
        try { if (Test-Path -LiteralPath $script:StartingPath) { Remove-Item -LiteralPath $script:StartingPath -Force -ErrorAction SilentlyContinue } } catch {}
        return $true
    } catch {
        if ($createdPid) {
            try { if (Test-Path -LiteralPath $script:PidPath) { Remove-Item -LiteralPath $script:PidPath -Force -ErrorAction SilentlyContinue } } catch {}
        }
        try { $script:SingleInstanceMutex.ReleaseMutex() } catch {}
        $script:SingleInstanceMutex.Dispose()
        $script:SingleInstanceMutex = $null
        return $false
    }
}

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
    try { Add-Content -Path $script:LogPath -Value $line -Encoding UTF8 } catch {}
}

function Ensure-Directory([string]$Path) {
    if (-not (Test-Path -Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Sanitize-RelativePath([string]$RelativePath) {
    return ($RelativePath -replace '^[\\/]+','' -replace '[<>:"\|\?\*]','_')
}

if (-not (Test-Path -Path $ConfigPath)) {
    $default = [ordered]@{
        BackupRoot = 'D:\FileBackupRT'
        WatchPaths = @(
            "$env:USERPROFILE\Desktop",
            "$env:USERPROFILE\Downloads"
        )
        Extensions = @('.exe','.dll','.zip','.7z','.rar','.bat','.cmd','.ps1','.py','.bin','.img','.dat','.json','.xml','.txt')
        StableChecks = 3
        StableDelaySeconds = 1
        IncludeSubdirectories = $true
        KeepMultipleVersions = $true
        ExcludeBackupRoot = $true
    }
    $default | ConvertTo-Json -Depth 4 | Set-Content -Path $ConfigPath -Encoding UTF8
}

$config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$backupRoot = [Environment]::ExpandEnvironmentVariables([string]$config.BackupRoot)
$watchPaths = @($config.WatchPaths | ForEach-Object {
    if ($_ -is [string]) { [Environment]::ExpandEnvironmentVariables([string]$_) }
    elseif ($null -ne $_.Path) { [Environment]::ExpandEnvironmentVariables([string]$_.Path) }
})
$extensions = @($config.Extensions | ForEach-Object { ([string]$_).ToLowerInvariant() })
$stableChecksValue = if ($null -ne $config.StableChecks) { [int]$config.StableChecks } else { 1 }
$stableDelayValue = if ($null -ne $config.StableDelaySeconds) { [int]$config.StableDelaySeconds } elseif ($null -ne $config.StableSeconds) { [int]$config.StableSeconds } else { 2 }
$stableChecks = [Math]::Max(1, $stableChecksValue)
$stableDelay = [Math]::Max(1, $stableDelayValue)
$includeSubdirectories = if ($null -ne $config.IncludeSubdirectories) { [bool]$config.IncludeSubdirectories } else { $true }
$keepVersions = [bool]$config.KeepMultipleVersions

Ensure-Directory $backupRoot
$script:LogPath = Join-Path $backupRoot 'FileBackupRT.log'

$queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
$processing = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$recentEvents = [hashtable]::Synchronized(@{})
$debounceSeconds = 2
$watchers = New-Object System.Collections.Generic.List[object]
$subscriptions = New-Object System.Collections.Generic.List[object]

function Should-ProcessFile([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path -Path $Path -PathType Leaf)) { return $false }
    if ($config.ExcludeBackupRoot -and $Path.StartsWith($backupRoot, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extensions.Count -gt 0 -and $extensions -notcontains $ext) { return $false }
    return $true
}

function Queue-Path([string]$Path) {
    if (Should-ProcessFile $Path) {
        $signature = $null
        try {
            $info = Get-Item -LiteralPath $Path -ErrorAction Stop
            $signature = '{0}|{1}' -f ([int64]$info.Length), $info.LastWriteTimeUtc.Ticks
        } catch {}
        if ($null -ne $signature) {
            $now = [DateTime]::UtcNow
            $previous = $recentEvents[$Path]
            if ($null -ne $previous -and $previous.Signature -eq $signature -and (($now - $previous.When).TotalSeconds -lt $debounceSeconds)) { return }
            $recentEvents[$Path] = [pscustomobject]@{ Signature = $signature; When = $now }
        }
        if ($processing.Add($Path)) { [void]$queue.Enqueue($Path) }
    }
}

function Wait-UntilStable([string]$Path) {
    $lastLength = -1L
    $lastWrite = [DateTime]::MinValue
    $stable = 0
    for ($i = 0; $i -lt 120; $i++) {
        if (Test-StopRequested) { return $false }
        if (-not (Test-Path -Path $Path -PathType Leaf)) { return $false }
        try {
            $fi = Get-Item -Path $Path -ErrorAction Stop
            $len = [int64]$fi.Length
            $lw = $fi.LastWriteTimeUtc
            if ($len -eq $lastLength -and $lw -eq $lastWrite) {
                $stable++
                if ($stable -ge $stableChecks) { return $true }
            } else {
                $stable = 0
                $lastLength = $len
                $lastWrite = $lw
            }
        } catch { $stable = 0 }
        Start-Sleep -Seconds $stableDelay
    }
    return $false
}

function Get-RelativePath([string]$FilePath, [string]$Root) {
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $fullPath = [IO.Path]::GetFullPath($FilePath)
    if ($fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return $fullPath.Substring($fullRoot.Length)
    }
    return [IO.Path]::GetFileName($fullPath)
}

function Backup-File([string]$Path) {
    try {
        if (-not (Wait-UntilStable $Path)) {
            Write-Log "Skipped (not stable or disappeared): $Path"
            return
        }

        $matchedRoot = $null
        foreach ($root in $watchPaths) {
            try {
                $rootFull = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
                $pathFull = [IO.Path]::GetFullPath($Path)
                if ($pathFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
                    if ($null -eq $matchedRoot -or $rootFull.Length -gt $matchedRoot.Length) { $matchedRoot = $rootFull.TrimEnd('\') }
                }
            } catch {}
        }
        if ($null -eq $matchedRoot) { $matchedRoot = [IO.Path]::GetDirectoryName($Path) }
        $relative = Sanitize-RelativePath (Get-RelativePath $Path $matchedRoot)
        $rootName = Split-Path -Leaf $matchedRoot
        $hash = (Get-FileHash -Path $Path -Algorithm SHA256).Hash
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'

        if ($keepVersions) {
            $destDir = Join-Path $backupRoot (Join-Path $rootName $stamp)
            $dest = Join-Path $destDir $relative
        } else {
            $dest = Join-Path $backupRoot (Join-Path $rootName $relative)
        }

        Ensure-Directory (Split-Path -Parent $dest)
        Copy-Item -Path $Path -Destination $dest -Force

        $copiedHash = (Get-FileHash -Path $dest -Algorithm SHA256).Hash
        if ($hash -ne $copiedHash) {
            Write-Log "HASH MISMATCH: $Path"
            return
        }

        try { $size = (Get-Item -Path $Path).Length } catch { $size = $null }
        $meta = [ordered]@{
            OriginalPath = $Path
            BackupPath = $dest
            Size = $size
            SHA256 = $hash
            FirstSeenBackup = (Get-Date).ToString('o')
        }
        ($meta | ConvertTo-Json -Depth 3) | Set-Content -Path ($dest + '.json') -Encoding UTF8
        Write-Log "BACKED UP: $Path -> $dest [$hash]"
    } catch {
        Write-Log "ERROR: $Path :: $($_.Exception.Message)"
    } finally {
        [void]$processing.Remove($Path)
    }
}

foreach ($root in $watchPaths) {
    if (-not (Test-Path -Path $root -PathType Container)) {
        Write-Log "Watch path does not exist: $root"
        continue
    }
    $fsw = New-Object IO.FileSystemWatcher
    $fsw.Path = [IO.Path]::GetFullPath($root)
    $fsw.Filter = '*.*'
    $fsw.IncludeSubdirectories = $includeSubdirectories
    $fsw.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, Size, CreationTime'

    $sub1 = Register-ObjectEvent -InputObject $fsw -EventName Created -Action { Queue-Path $Event.SourceEventArgs.FullPath }
    $sub2 = Register-ObjectEvent -InputObject $fsw -EventName Changed -Action { Queue-Path $Event.SourceEventArgs.FullPath }
    $sub3 = Register-ObjectEvent -InputObject $fsw -EventName Renamed -Action { Queue-Path $Event.SourceEventArgs.FullPath }
    $subscriptions.Add($sub1); $subscriptions.Add($sub2); $subscriptions.Add($sub3)
    $watchers.Add($fsw)
    $fsw.EnableRaisingEvents = $true
    Write-Log "Watching: $root"
}

if ($watchers.Count -eq 0) { Write-Log 'No valid watch paths. Exiting.'; exit 2 }
if (-not (Initialize-Lifecycle)) { exit 0 }

Write-Log "Backup root: $backupRoot"
Write-Log "Append-only mode: $keepVersions"

foreach ($root in $watchPaths) {
    if (Test-Path -Path $root -PathType Container) {
        Get-ChildItem -Path $root -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object { Queue-Path $_.FullName }
    }
}

try {
    while ($true) {
        if (Test-StopRequested) { break }
        while ($true) {
            if (Test-StopRequested) { break }
            $path = $null
            if (-not $queue.TryDequeue([ref]$path)) { break }
            Backup-File $path
        }
        Start-Sleep -Milliseconds 500
    }
} finally {
    foreach ($sub in $subscriptions) { try { Unregister-Event -SubscriptionId $sub.Id -Force -ErrorAction SilentlyContinue } catch {} }
    foreach ($w in $watchers) { try { $w.EnableRaisingEvents = $false; $w.Dispose() } catch {} }
    Remove-LifecycleFiles
    if ($null -ne $script:SingleInstanceMutex) {
        try { $script:SingleInstanceMutex.ReleaseMutex() } catch {}
        $script:SingleInstanceMutex.Dispose()
        $script:SingleInstanceMutex = $null
    }
}
