#Requires -RunAsAdministrator
$ErrorActionPreference = 'Continue'
$installDir = 'D:\BuildTools'
$toolsDir = 'D:\tools'
$installer = Join-Path $toolsDir 'vs_buildtools.exe'
New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null

Write-Host 'Downloading Visual Studio Build Tools bootstrapper...'
if (!(Test-Path $installer)) {
  curl.exe -L --retry 3 --retry-delay 5 -o $installer 'https://aka.ms/vs/17/release/vs_BuildTools.exe'
}

Write-Host 'Installing Visual Studio Build Tools C++ workload...'
$args = @(
  '--wait', '--norestart', '--nocache',
  '--installPath', $installDir,
  '--add', 'Microsoft.VisualStudio.Workload.VCTools',
  '--includeRecommended',
  '--add', 'Microsoft.VisualStudio.Component.Windows11SDK.26100',
  '--add', 'Microsoft.VisualStudio.Component.VC.CMake.Project',
  '--add', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
)
$p = Start-Process -FilePath $installer -ArgumentList $args -Wait -PassThru
Write-Host "VS BuildTools installer exit code: $($p.ExitCode)"

$vcvars = 'D:\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
Write-Host "vcvars64.bat exists: $(Test-Path $vcvars)"
if (Test-Path $vcvars) {
  cmd /c ""$vcvars" >nul && where cl && cl 2>&1 | findstr /C:"Microsoft" && where link && link 2>&1 | findstr /C:"Microsoft""
}

Read-Host 'Done. Press Enter to close'
