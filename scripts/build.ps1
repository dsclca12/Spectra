#!/usr/bin/env pwsh
# Build helper for Spectra on Windows
<#
.SYNOPSIS
    Build Spectra for Windows.
.DESCRIPTION
    Convenience script for common build tasks.
.PARAMETER Mode
    Build mode: release (default), debug, or profile.
.PARAMETER Clean
    Clean build artifacts before building.
.PARAMETER Run
    Run the app after building.
.EXAMPLE
    ./scripts/build.ps1 -Mode release
    ./scripts/build.ps1 -Clean -Run
#>

param(
    [ValidateSet('release', 'debug', 'profile')]
    [string]$Mode = 'release',
    [switch]$Clean,
    [switch]$Run
)

$ErrorActionPreference = 'Stop'

if ($Clean) {
    Write-Host "🧹 Cleaning build artifacts..." -ForegroundColor Yellow
    flutter clean
    flutter pub get
}

Write-Host "🏗️  Building Spectra ($Mode)..." -ForegroundColor Cyan
flutter build windows --$Mode

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build failed!" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "✅ Build succeeded!" -ForegroundColor Green

$exePath = "build\windows\x64\runner\$Mode\spectra.exe"
if (Test-Path $exePath) {
    Write-Host "📦 $exePath" -ForegroundColor Green
}

if ($Run) {
    Write-Host "🚀 Launching Spectra..." -ForegroundColor Cyan
    & $exePath
}
