# build.ps1 — restore + build WorklogCalendar in Release for the current arch.
#
# Usage:
#   .\build.ps1                  # build x64 Release
#   .\build.ps1 -Arch arm64      # build ARM64 Release
#   .\build.ps1 -SelfContained   # produce a folder that runs on a clean Win11

param(
    [ValidateSet("x86", "x64", "arm64")]
    [string]$Arch = "x64",
    [ValidateSet("Debug", "Release")]
    [string]$Config = "Release",
    [switch]$SelfContained
)

$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Here

$rid = "win-$Arch"
$proj = Join-Path $Here "src\WorklogCalendar\WorklogCalendar.csproj"

Write-Host "==> Restoring..." -ForegroundColor Cyan
dotnet restore $proj -r $rid

Write-Host "==> Building $Config|$Arch..." -ForegroundColor Cyan
$publishArgs = @("publish", $proj,
    "-c", $Config,
    "-r", $rid,
    "--self-contained", $(if ($SelfContained) { "true" } else { "false" }),
    "-p:Platform=$Arch",
    "-p:WindowsAppSDKSelfContained=true",
    "-p:PublishSingleFile=false")

& dotnet @publishArgs
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish exited with code $LASTEXITCODE — see errors above."
}

$out = Join-Path $Here "src\WorklogCalendar\bin\$Arch\$Config\net8.0-windows10.0.19041.0\$rid\publish"
if (-not (Test-Path (Join-Path $out "WorklogCalendar.exe"))) {
    throw "Build reported success but WorklogCalendar.exe is missing in $out."
}
Write-Host ""
Write-Host "Built. Output: $out" -ForegroundColor Green
Write-Host "Run with: $out\WorklogCalendar.exe" -ForegroundColor Green
