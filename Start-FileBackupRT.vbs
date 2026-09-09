Option Explicit
Dim sh, fso, wmi, base, ps1, cfg, pidPath, stopPath, startPath, cmd
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = base & "\FileBackupRT.ps1"
cfg = base & "\config.json"
pidPath = base & "\FileBackupRT.pid"
stopPath = base & "\FileBackupRT.stop"
startPath = base & "\FileBackupRT.starting"
If Not fso.FileExists(ps1) Then
  MsgBox "FileBackupRT.ps1 not found.", 16, "FileBackupRT"
  WScript.Quit 1
End If

' The PID file is authoritative only after its process identity is checked.
If fso.FileExists(pidPath) Then
  If IsCurrentWorker(ReadPid(pidPath), ps1) Then WScript.Quit 0
  On Error Resume Next
  fso.DeleteFile pidPath, True
  On Error GoTo 0
End If

' Serialize the short worker startup window so two rapid launches cannot race.
If fso.FileExists(startPath) Then
  Dim waitIndex
  For waitIndex = 1 To 20
    WScript.Sleep 500
    If fso.FileExists(pidPath) Then
      If IsCurrentWorker(ReadPid(pidPath), ps1) Then WScript.Quit 0
    End If
    If Not fso.FileExists(startPath) Then Exit For
  Next
  On Error Resume Next
  fso.DeleteFile startPath, True
  On Error GoTo 0
End If

On Error Resume Next
Dim startup
Set startup = fso.CreateTextFile(startPath, False)
If startup Is Nothing Then WScript.Quit 0
startup.WriteLine CStr(Now)
startup.Close
On Error GoTo 0

If fso.FileExists(stopPath) Then
  On Error Resume Next
  fso.DeleteFile stopPath, True
  On Error GoTo 0
End If

cmd = "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & ps1 & Chr(34) & " -ConfigPath " & Chr(34) & cfg & Chr(34)
sh.Run cmd, 0, False
WScript.Sleep 500
On Error Resume Next
If fso.FileExists(startPath) Then fso.DeleteFile startPath, True
On Error GoTo 0
WScript.Quit 0

Function ReadPid(path)
  Dim text
  ReadPid = 0
  On Error Resume Next
  text = Trim(fso.OpenTextFile(path, 1, False).ReadAll)
  If IsNumeric(text) Then ReadPid = CLng(text)
  On Error GoTo 0
End Function

Function IsCurrentWorker(pid, scriptPath)
  Dim svc, processes, proc, commandLine
  IsCurrentWorker = False
  If pid <= 0 Then Exit Function
  On Error Resume Next
  Set svc = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
  Set processes = svc.ExecQuery("SELECT CommandLine FROM Win32_Process WHERE ProcessId=" & CStr(pid))
  For Each proc In processes
    commandLine = LCase(CStr(proc.CommandLine))
    If InStr(1, commandLine, LCase(scriptPath), vbTextCompare) > 0 Then
      IsCurrentWorker = True
      Exit For
    End If
  Next
  On Error GoTo 0
End Function
