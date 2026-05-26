param(
    [switch]$SkipPortablePack = $true,
    [string]$ToolsRoot = "C:\kq-remote-link-tools",
    [string]$CustomClientPublicKey = $env:KQ_CUSTOM_CLIENT_PUBKEY,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$build = Join-Path $PSScriptRoot "build-windows-flutter.ps1"
$log = Join-Path $ToolsRoot "build-admin.log"

New-Item -ItemType Directory -Force -Path $ToolsRoot | Out-Null

$buildArgs = @()
if ($SkipPortablePack) {
    $buildArgs += "-SkipPortablePack"
}
$adminNoPause = if ($NoPause) { '$true' } else { '$false' }

$adminCommand = @"
`$ErrorActionPreference = 'Stop'
Set-Location '$repo'
`$env:Path = '$ToolsRoot\flutter\bin;$ToolsRoot\cmake\bin;$ToolsRoot\ninja;' + `$env:USERPROFILE + '\.cargo\bin;' + `$env:Path
`$env:VCPKG_ROOT = '$ToolsRoot\vcpkg'
`$env:KQ_CUSTOM_CLIENT_PUBKEY = '$CustomClientPublicKey'
Start-Transcript -Path '$log' -Force
try {
    & '$build' $($buildArgs -join ' ')
    Write-Host ''
    Write-Host 'KQ Remote Link build completed.'
} catch {
    Write-Host ''
    Write-Host "Build failed: `$(`$_.Exception.Message)" -ForegroundColor Red
    throw
} finally {
    Stop-Transcript
    Write-Host ''
    if (-not $adminNoPause) {
        Read-Host 'Press Enter to close this Administrator window'
    }
}
"@

$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($adminCommand))
Start-Process powershell.exe `
    -Verb RunAs `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encoded)

Write-Host "Started an elevated build window. Accept the UAC prompt if Windows shows one."
Write-Host "Log file: $log"
