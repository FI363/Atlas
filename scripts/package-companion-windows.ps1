# Atlas Companion Windows Launcher & Startup Installer
param(
    [switch]$InstallStartup,
    [switch]$UninstallStartup
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$projectRoot = Split-Path -Parent $scriptDir
$vbsPath = Join-Path $scriptDir "AtlasCompanionSilent.vbs"
$batPath = Join-Path $scriptDir "AtlasCompanion.bat"

# 1. Generate AtlasCompanion.bat
$batContent = "@echo off`r`ntitle Atlas Laptop Companion Server`r`ncd /d `"$projectRoot`"`r`nnode scripts/start-companion.js`r`npause`r`n"
[System.IO.File]::WriteAllText($batPath, $batContent)
Write-Host "[OK] Created AtlasCompanion.bat" -ForegroundColor Green

# 2. Generate silent VBScript launcher (runs in background without popping up CMD window)
$vbsContent = "Set WshShell = CreateObject(`"WScript.Shell`")`r`nWshShell.Run `"`"`"$batPath`"`"`", 0`r`nSet WshShell = Nothing`r`n"
[System.IO.File]::WriteAllText($vbsPath, $vbsContent)
Write-Host "[OK] Created AtlasCompanionSilent.vbs" -ForegroundColor Green

# 3. Optional Windows Startup Registry integration
$regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$regValueName = "AtlasCompanionServer"

if ($InstallStartup) {
    Set-ItemProperty -Path $regKey -Name $regValueName -Value "wscript.exe `"$vbsPath`""
    Write-Host "[OK] Added Atlas Companion to Windows Startup!" -ForegroundColor Cyan
} elseif ($UninstallStartup) {
    Remove-ItemProperty -Path $regKey -Name $regValueName -ErrorAction SilentlyContinue
    Write-Host "[OK] Removed Atlas Companion from Windows Startup." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "To run companion server in foreground: Double-click AtlasCompanion.bat" -ForegroundColor White
    Write-Host "To run companion in background:       wscript.exe AtlasCompanionSilent.vbs" -ForegroundColor White
    Write-Host "To add to Windows Startup:           .\scripts\package-companion-windows.ps1 -InstallStartup" -ForegroundColor White
}
