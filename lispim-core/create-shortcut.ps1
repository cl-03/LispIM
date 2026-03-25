# Create Desktop Shortcut for LispIM Backend
$WshShell = New-Object -ComObject WScript.Shell
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Create shortcut in same directory
$shortcutPath = Join-Path $scriptDir "LispIM Backend.lnk"
$targetPath = "D:\SBCL\sbcl.exe"
$arguments = "--core `"D:\SBCL\sbcl.core`" --load `"$scriptDir\run-server.lisp`""

$shortcut = $WshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $targetPath
$shortcut.Arguments = $arguments
$shortcut.WorkingDirectory = $scriptDir
$shortcut.Description = "LispIM Backend Server - Double-click to start"
# Use cmd.exe as icon since we're running a batch file
$shortcut.IconLocation = "shell32.dll,13"
$shortcut.WindowStyle = 1
$shortcut.Save()

Write-Host "Shortcut created: $shortcutPath"
