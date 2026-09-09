# FileBackupRT

Real-time, append-only file backup for Windows PowerShell 5.1.

FileBackupRT monitors selected folders, waits for files to become stable, copies them to a backup location, and verifies every copy with SHA-256. Version 8 is the first public release under the `FileBackupRT` name. Earlier development versions were named `FileBackupTool`.

## Highlights

- Real-time monitoring with `FileSystemWatcher`
- Desktop, Downloads, and custom watch paths
- Optional recursive monitoring
- Extension filtering
- Stability checks before copying
- SHA-256 verification after copying
- Append-only backup behavior
- Timestamped versions when `KeepMultipleVersions` is enabled
- Event debouncing to reduce duplicate backups
- Hidden Start and Stop scripts
- PID validation and named Mutex protection for single-instance startup
- Graceful shutdown that releases watchers, event subscriptions, and file handles
- Stop never terminates unrelated PowerShell processes

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1
- No Python, Node.js, PowerShell 7, or additional runtime installation required

## Download

Download the latest `FileBackupRT_v8.zip` from the repository's [Releases](https://github.com/MeowLove/FileBackupRT/releases) page. Extract it to a permanent directory such as `C:\Tools\FileBackupRT`.

## Usage

1. Edit `config.json` if you need different watch or backup paths.
2. Start with `Start-FileBackupRT.vbs` or `Start-FileBackupRT.bat`.
3. Stop with `Stop-FileBackupRT.vbs` or `Stop-FileBackupRT.bat`.

The scripts run PowerShell without opening a console window. After changing the configuration, stop and start the worker again.

## Configuration

```json
{
  "BackupRoot": "D:\\FileBackupRT_BakFile",
  "WatchPaths": [
    "%USERPROFILE%\\Desktop",
    "%USERPROFILE%\\Downloads"
  ],
  "IncludeSubdirectories": true,
  "Extensions": [
    ".exe", ".dll", ".zip", ".7z", ".rar", ".bat", ".cmd",
    ".ps1", ".py", ".bin", ".img", ".dat", ".json", ".xml", ".txt"
  ],
  "StableChecks": 3,
  "StableDelaySeconds": 1,
  "KeepMultipleVersions": true,
  "ExcludeBackupRoot": true
}
```

| Field | Description |
| --- | --- |
| `BackupRoot` | Destination directory for backups. In JSON, Windows backslashes must be escaped as `\\`; forward slashes also work. |
| `WatchPaths` | Directories to monitor. `%USERPROFILE%` and other environment variables are supported. |
| `IncludeSubdirectories` | Monitors nested directories when `true`. |
| `Extensions` | File extensions to include. Use an empty array to disable extension filtering. |
| `StableChecks` | Number of consecutive stable observations required before copying. |
| `StableDelaySeconds` | Delay between stability observations. |
| `KeepMultipleVersions` | Keeps timestamped copies when `true`. |
| `ExcludeBackupRoot` | Prevents the backup directory from being monitored again. |

`WatchPaths` also accepts labeled objects:

```json
"WatchPaths": [
  { "Label": "Desktop", "Path": "%USERPROFILE%\\Desktop" },
  { "Label": "Projects", "Path": "C:\\Work\\Projects" }
]
```

Keep `BackupRoot` outside `WatchPaths` to avoid monitoring the backup output.

## Backup Layout

With `KeepMultipleVersions=true`, backups are organized by watch root and timestamp:

```text
D:\FileBackupRT_BakFile\
  Desktop\
    20260909_120000_123\
      example.exe
      example.exe.json
```

The `.json` sidecar records the original path, backup path, file size, SHA-256, and backup timestamp. Source deletion does not remove existing backups.

## Lifecycle Safety

The worker uses these runtime files in the application directory:

- `FileBackupRT.pid`: PID of the active worker
- `FileBackupRT.stop`: graceful-stop signal
- `FileBackupRT.starting`: startup race guard

Start validates that the PID belongs to the current `FileBackupRT.ps1` command line. Stop signals only that exact PID and waits for it to exit. It does not use `taskkill /IM powershell.exe`, process-name termination, or forced termination of unrelated processes.

## Repository Layout

```text
FileBackupRT/
  config.json
  FileBackupRT.ps1
  README.md
  Start-FileBackupRT.bat
  Start-FileBackupRT.vbs
  Stop-FileBackupRT.bat
  Stop-FileBackupRT.vbs
  LICENSE
```

Runtime files and backup logs are generated locally and are not part of the source package.

## License

FileBackupRT is released under the [GNU General Public License v3.0](LICENSE).
