# FileBackupRT v8

FileBackupRT 是一个面向 Windows 的开源静默实时文件备份工具。它监控指定目录，在文件稳定后复制到备份目录，并对复制结果执行 SHA-256 校验。

v7 及更早版本使用的项目名称是 `FileBackupTool`。从 v8 开始，项目正式改名为 `FileBackupRT`（Real-Time），并以开源项目形式发布。

## 特性

- 基于 Windows PowerShell 5.1 和 `FileSystemWatcher`
- 默认监控当前用户的 Desktop 和 Downloads
- 支持子目录监控和扩展名过滤
- 文件大小和 `LastWriteTime` 稳定后再复制
- 复制完成后校验 SHA-256
- 只增不减：删除源文件不会删除已有备份
- `KeepMultipleVersions=true` 时保留时间戳版本
- Changed/Created/Renamed 事件防抖，减少重复备份
- Start/Stop 全程无控制台窗口
- 基于 PID、命令行身份和命名 Mutex 的单实例保护
- Stop 使用信号文件，等待 Worker 完整释放 watcher、事件订阅和文件句柄
- 不会按进程名终止其它 PowerShell 进程

## 运行环境

- Windows 10/11
- Windows PowerShell 5.1
- 不需要 Python、Node.js、PowerShell 7 或其它额外运行时

## 快速开始

1. 将发布包解压到固定目录，例如 `C:\Tools\FileBackupRT`。
2. 编辑 `config.json`。
3. 双击 `Start-FileBackupRT.vbs`，或运行 `Start-FileBackupRT.bat`。
4. 停止时双击 `Stop-FileBackupRT.vbs`，或运行 `Stop-FileBackupRT.bat`。

启动和停止脚本都会隐藏 PowerShell 窗口。修改配置后，先 Stop，再重新 Start。

## 配置

发布包中的当前配置示例：

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

字段说明：

| 字段 | 说明 |
| --- | --- |
| `BackupRoot` | 备份根目录。JSON 中 Windows 反斜杠需要写成 `\\`，也可以使用 `/`。 |
| `WatchPaths` | 要监控的目录列表，支持 `%USERPROFILE%` 等环境变量。 |
| `IncludeSubdirectories` | 是否包含子目录。 |
| `Extensions` | 要备份的扩展名；空数组表示不按扩展名过滤。 |
| `StableChecks` | 连续稳定检查次数。 |
| `StableDelaySeconds` | 每次稳定检查之间的秒数。 |
| `KeepMultipleVersions` | `true` 表示每次复制保留时间戳版本。 |
| `ExcludeBackupRoot` | 防止备份目录被再次监控和备份。 |

`WatchPaths` 也支持对象格式：

```json
"WatchPaths": [
  { "Label": "Desktop", "Path": "%USERPROFILE%\\Desktop" },
  { "Label": "Projects", "Path": "C:\\Work\\Projects" }
]
```

不要把 `BackupRoot` 放在 `WatchPaths` 中。当前发布配置使用 `D:\FileBackupRT_BakFile` 作为备份目录；旧的 `D:\FileBackup_BakFile` 数据不会自动迁移或删除。

## 备份结构

当 `KeepMultipleVersions=true` 时，备份按监控根目录和时间戳组织，例如：

```text
D:\FileBackup_BakFile\
  Desktop\
    20260909_120000_123\
      example.exe
      example.exe.json
```

旁边的 `.json` 文件记录原始路径、备份路径、文件大小、SHA-256 和首次备份时间。

## 生命周期和安全停止

Worker 使用以下运行时文件，均位于工具目录：

- `FileBackupRT.pid`：当前 Worker 的 PID
- `FileBackupRT.stop`：Stop 脚本创建的停止信号
- `FileBackupRT.starting`：防止快速连续启动竞争

Start 会验证 PID 对应进程的命令行确实指向当前 `FileBackupRT.ps1`。Stop 只向这个精确 Worker 写入停止信号，并等待进程消失；不会使用 `taskkill /IM powershell.exe`，也不会强制结束其它 PowerShell。

## 发布包文件

```text
FileBackupRT/
  config.json
  FileBackupRT.ps1
  README.md
  Start-FileBackupRT.bat
  Start-FileBackupRT.vbs
  Stop-FileBackupRT.bat
  Stop-FileBackupRT.vbs
```

运行期间生成的 `FileBackupRT.pid`、`FileBackupRT.stop`、`FileBackupRT.starting` 和 `FileBackupRT.log` 不应提交到 Git；发布包不包含这些运行时文件。

## GitHub 发布建议

- 将 `FileBackupRT` 目录中的文件上传到仓库根目录。
- 将本 README 作为 GitHub 首页说明。
- 建议添加 `LICENSE` 文件后再声明具体开源许可证。
- 可将 `FileBackupRT_v8.zip` 作为 GitHub Release 附件。

## 故障排查

- 无法启动：检查 `config.json` 是否是有效 JSON，以及 `WatchPaths` 是否存在。
- 没有备份：确认文件扩展名在 `Extensions` 中，并等待稳定检查完成。
- Stop 后仍有 PID：再次运行 `Stop-FileBackupRT.vbs` 会清理陈旧的生命周期文件；不会终止无关进程。
- 备份目录空间不足：将 `BackupRoot` 改到容量更大的磁盘，并重新启动工具。

## 许可证

本发布包预留 LICENSE 文件位置。公开发布到 GitHub 前，请根据你的授权意图添加合适的 LICENSE 文件。
