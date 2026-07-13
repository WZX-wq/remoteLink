#Requires -RunAsAdministrator
$ErrorActionPreference = 'Continue'
$repo = 'D:\demo\远程桌面\remoteLink'
$docs = Join-Path $repo 'docs'
New-Item -ItemType Directory -Path $docs -Force | Out-Null
$logPath = Join-Path $docs ('admin-handover-finish-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
Start-Transcript -Path $logPath -Force

Write-Host '=== RemoteLink admin handover finish ==='
Write-Host "Log: $logPath"

Write-Host '=== Enable Windows Developer Mode registry flags ==='
New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowDevelopmentWithoutDevLicense' -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowAllTrustedApps' -PropertyType DWord -Value 1 -Force | Out-Null

Write-Host '=== Download Visual Studio Build Tools bootstrapper ==='
$toolsDir = 'D:\tools'
$installer = Join-Path $toolsDir 'vs_buildtools.exe'
New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
if (!(Test-Path $installer)) {
  curl.exe -L --retry 3 --retry-delay 5 -o $installer 'https://aka.ms/vs/17/release/vs_BuildTools.exe'
}
Get-Item $installer | Select-Object FullName,Length,LastWriteTime | Format-List

Write-Host '=== Install VS Build Tools C++ workload (minimal valid args) ==='
$installDir = 'D:\BuildTools'
$args = @(
  '--quiet',
  '--wait',
  '--norestart',
  '--installPath', $installDir,
  '--add', 'Microsoft.VisualStudio.Workload.VCTools',
  '--includeRecommended'
)
Write-Host ('Command: ' + $installer + ' ' + ($args -join ' '))
$p = Start-Process -FilePath $installer -ArgumentList $args -Wait -PassThru
Write-Host "VS BuildTools installer exit code: $($p.ExitCode)"

Write-Host '=== Verify Visual Studio C++ toolchain ==='
$locations = @(
  'D:\BuildTools\VC\Auxiliary\Build\vcvars64.bat',
  'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat',
  'C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat'
)
$found = $null
foreach ($loc in $locations) {
  Write-Host "$loc exists: $(Test-Path $loc)"
  if ((Test-Path $loc) -and !$found) { $found = $loc }
}
if ($found) {
  cmd /c ""$found" >nul && where cl && cl 2>&1 | findstr /C:"Microsoft" && where link && link 2>&1 | findstr /C:"Microsoft""
}

Write-Host '=== Run local handover verification ==='
$verify = Join-Path $repo 'scripts\verify-local-handover.ps1'
Write-Host "verify path: $verify exists: $(Test-Path $verify)"
if (Test-Path $verify) { powershell -NoProfile -ExecutionPolicy Bypass -File $verify }

Write-Host '=== Append handover status ==='
$docPath = Join-Path $repo 'docs\local-handover-status.md'
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$lines = @(
  '',
  "## 管理员收尾执行记录（$stamp）",
  '',
  "- VS Build Tools installer exit code：$($p.ExitCode)",
  "- vcvars64.bat：$found",
  "- Developer Mode key：$(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock')",
  "- 日志：$logPath"
)
Add-Content -LiteralPath $docPath -Encoding UTF8 -Value $lines

Stop-Transcript
Write-Host ''
Write-Host 'Admin handover finish script completed.'
Read-Host 'Press Enter to close'
