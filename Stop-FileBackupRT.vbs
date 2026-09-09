Option Explicit
Dim fso, base, ps1, pidPath, stopPath, startingPath, pid, deadline
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = base & "\FileBackupRT.ps1"
pidPath = base & "\FileBackupRT.pid"
stopPath = base & "\FileBackupRT.stop"
startingPath = base & "\FileBackupRT.starting"

If Not fso.FileExists(pidPath) Then
  DeleteIfExists stopPath
  DeleteIfExists startingPath
  WScript.Quit 0
End If
pid = ReadPid(pidPath)
If Not IsCurrentWorker(pid, ps1) Then
  DeleteIfExists pidPath
  DeleteIfExists stopPath
  DeleteIfExists startingPath
  WScript.Quit 0
End If

' Signal the worker and wait for this exact PID to disappear.
On Error Resume Next
Dim marker
Set marker = fso.CreateTextFile(stopPath, True)
If Not marker Is Nothing Then
  marker.WriteLine CStr(Now)
  marker.Close
End If
On Error GoTo 0

deadline = DateAdd("s", 60, Now)
Do While Now < deadline
  If Not IsCurrentWorker(pid, ps1) Then
    DeleteIfExists pidPath
    DeleteIfExists stopPath
    DeleteIfExists startingPath
    WScript.Quit 0
  End If
  WScript.Sleep 500
Loop

' Timeout is returned to the caller; no unrelated process is terminated.
WScript.Quit 2

Function ReadPid(path)
  Dim text
  ReadPid = 0
  On Error Resume Next
  text = Trim(fso.OpenTextFile(path, 1, False).ReadAll)
  If IsNumeric(text) Then ReadPid = CLng(text)
  On Error GoTo 0
End Function

Function IsCurrentWorker(workerPid, scriptPath)
  Dim svc, processes, proc, commandLine
  IsCurrentWorker = False
  If workerPid <= 0 Then Exit Function
  On Error Resume Next
  Set svc = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
  Set processes = svc.ExecQuery("SELECT CommandLine FROM Win32_Process WHERE ProcessId=" & CStr(workerPid))
  For Each proc In processes
    commandLine = LCase(CStr(proc.CommandLine))
    If InStr(1, commandLine, LCase(scriptPath), vbTextCompare) > 0 Then
      IsCurrentWorker = True
      Exit For
    End If
  Next
  On Error GoTo 0
End Function

Sub DeleteIfExists(path)
  On Error Resume Next
  If fso.FileExists(path) Then fso.DeleteFile path, True
  On Error GoTo 0
End Sub
