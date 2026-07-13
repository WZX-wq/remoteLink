#Requires -RunAsAdministrator
$ErrorActionPreference = 'Continue'
New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowDevelopmentWithoutDevLicense' -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowAllTrustedApps' -PropertyType DWord -Value 1 -Force | Out-Null
Write-Host 'Windows Developer Mode registry flags enabled.'
Read-Host 'Done. Press Enter to close'
