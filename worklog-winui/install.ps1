# install.ps1 -- build a Release publish bundle and copy it to
# %LOCALAPPDATA%\Programs\WorklogCalendar, then create a Start-menu shortcut.
#
# Usage:
#   .\install.ps1                # build + install for current user (x64)
#   .\install.ps1 -Arch arm64    # ARM64 build
#   .\install.ps1 -NoBuild       # reuse existing publish folder
#   .\install.ps1 -Uninstall     # remove the installed copy

param(
    [ValidateSet("x86", "x64", "arm64")]
    [string]$Arch = "x64",
    [switch]$NoBuild,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallRoot = Join-Path $env:LOCALAPPDATA "Programs\WorklogCalendar"
$ShortcutPath = Join-Path ([Environment]::GetFolderPath("StartMenu")) "Programs\Worklog Calendar.lnk"

if ($Uninstall) {
    if (Test-Path $InstallRoot) {
        Write-Host "Removing $InstallRoot" -ForegroundColor Yellow
        Remove-Item -Recurse -Force $InstallRoot
    }
    if (Test-Path $ShortcutPath) {
        Write-Host "Removing $ShortcutPath" -ForegroundColor Yellow
        Remove-Item $ShortcutPath
    }
    Write-Host "Uninstalled." -ForegroundColor Green
    return
}

if (-not $NoBuild) {
    Write-Host "==> Building self-contained $Arch Release..." -ForegroundColor Cyan
    & (Join-Path $Here "build.ps1") -Arch $Arch -Config Release -SelfContained
}

$publish = Join-Path $Here "src\WorklogCalendar\bin\$Arch\Release\net8.0-windows10.0.19041.0\win-$Arch\publish"
if (-not (Test-Path $publish)) {
    throw "Publish folder not found: $publish. Re-run without -NoBuild."
}

Write-Host "==> Installing to $InstallRoot" -ForegroundColor Cyan
if (Test-Path $InstallRoot) { Remove-Item -Recurse -Force $InstallRoot }
New-Item -ItemType Directory -Path $InstallRoot | Out-Null
Copy-Item -Recurse -Force "$publish\*" $InstallRoot

$exe = Join-Path $InstallRoot "WorklogCalendar.exe"
if (-not (Test-Path $exe)) { throw "WorklogCalendar.exe not found in publish output." }

Write-Host "==> Creating Start menu shortcut..." -ForegroundColor Cyan
$startProgramsDir = Split-Path $ShortcutPath -Parent
if (-not (Test-Path $startProgramsDir)) { New-Item -ItemType Directory -Path $startProgramsDir | Out-Null }
$wsh = New-Object -ComObject WScript.Shell
$sc  = $wsh.CreateShortcut($ShortcutPath)
$sc.TargetPath = $exe
$sc.WorkingDirectory = $InstallRoot
$sc.Description = "Jira / Clockify worklog calendar"
$sc.Save()

Write-Host ""
Write-Host "Installed: $exe"          -ForegroundColor Green
Write-Host "Shortcut:  $ShortcutPath" -ForegroundColor Green
Write-Host "Run it from the Start menu or by double-clicking the .exe."
