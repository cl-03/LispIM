# LispIM Backend Server
# Double-click to start the backend server

$exePath = "D:\SBCL\sbcl.exe"
$corePath = "D:\SBCL\sbcl.core"
$scriptPath = Join-Path $PSScriptRoot "run-server.lisp"

Write-Host "================================"
Write-Host "  LispIM Enterprise Server"
Write-Host "================================"
Write-Host ""
Write-Host "Starting server..."
Write-Host ""

Start-Process -FilePath $exePath -ArgumentList "--core", $corePath, "--load", $scriptPath -WindowStyle Normal

Write-Host "Server is starting..."
Write-Host ""
Write-Host "Status: Visit http://localhost:8443/healthz"
Write-Host ""
Write-Host "To stop: Close the SBCL window"
