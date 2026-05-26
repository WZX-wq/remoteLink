param(
    [string]$ToolsRoot = "C:\kq-remote-link-tools",
    [switch]$InstallVcpkgPackages
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$bootstrap = Join-Path $PSScriptRoot "bootstrap-windows-build-env.ps1"
$check = Join-Path $PSScriptRoot "check-build-env.ps1"
$log = Join-Path $ToolsRoot "bootstrap-admin.log"

New-Item -ItemType Directory -Force -Path $ToolsRoot | Out-Null

$bootstrapArgs = @(
    "-ToolsRoot", "'$ToolsRoot'",
    "-InstallMsvcBuildTools",
    "-EnableDeveloperMode"
)
if ($InstallVcpkgPackages) {
    $bootstrapArgs += "-InstallVcpkgPackages"
}

$adminCommand = @"
`$ErrorActionPreference = 'Stop'
Set-Location '$repo'
Start-Transcript -Path '$log' -Force
try {
    & '$bootstrap' $($bootstrapArgs -join ' ')
    & '$check'
    Write-Host ''
    Write-Host 'Bootstrap and build-environment check completed.'
} catch {
    Write-Host ''
    Write-Host "Bootstrap failed: `$(`$_.Exception.Message)" -ForegroundColor Red
    throw
} finally {
    Stop-Transcript
    Write-Host ''
    Read-Host 'Press Enter to close this Administrator window'
}
"@

$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($adminCommand))
Start-Process powershell.exe `
    -Verb RunAs `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encoded)

Write-Host "Started an elevated bootstrap window. Accept the UAC prompt if Windows shows one."
Write-Host "Log file: $log"
