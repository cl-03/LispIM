# WScript file to create LispIM Backend shortcut

Set WshShell = WScript.CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Get the directory where this script is located
strScriptFolder = fso.GetParentFolderName(WScript.ScriptFullName)

' Create shortcut
Set oShellLink = WshShell.CreateShortcut(strScriptFolder & "\LispIM Backend.lnk")
oShellLink.TargetPath = "D:\SBCL\sbcl.exe"
oShellLink.Arguments = "--core D:\SBCL\sbcl.core --load """ & strScriptFolder & "\run-server.lisp"""
oShellLink.WorkingDirectory = strScriptFolder
oShellLink.Description = "LispIM Backend Server - Double-click to start"
oShellLink.IconLocation = "shell32.dll,13"
oShellLink.WindowStyle = 1  ' Normal window
oShellLink.Save

WScript.Echo "Shortcut created: " & strScriptFolder & "\LispIM Backend.lnk"
