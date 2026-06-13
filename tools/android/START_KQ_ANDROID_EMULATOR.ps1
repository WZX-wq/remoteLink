$ErrorActionPreference = "Stop"

$sdkRoot = "C:\kq-remote-link-tools\android-sdk"
$androidUserHome = "D:\AndroidUserHome"
$avdHome = Join-Path $androidUserHome "avd"
$avdName = "KQRemote_API34"

$env:ANDROID_SDK_ROOT = $sdkRoot
$env:ANDROID_HOME = $sdkRoot
$env:ANDROID_USER_HOME = $androidUserHome
$env:ANDROID_AVD_HOME = $avdHome
$env:JAVA_HOME = "E:\JDK\openjdk-17_windows-x64_bin\jdk-17"
$env:SKIP_JDK_VERSION_CHECK = "1"

$emulator = Join-Path $sdkRoot "emulator\emulator.exe"
$adb = Join-Path $sdkRoot "platform-tools\adb.exe"

if (!(Test-Path $emulator)) {
    throw "Android Emulator not found: $emulator"
}
if (!(Test-Path $adb)) {
    throw "ADB not found: $adb"
}

$devices = & $adb devices | Out-String
if ($devices -notmatch "emulator-\d+\s+device") {
    Start-Process -FilePath $emulator `
        -WorkingDirectory (Join-Path $sdkRoot "emulator") `
        -ArgumentList @(
            "-avd", $avdName,
            "-gpu", "swiftshader_indirect",
            "-no-snapshot-load",
            "-no-boot-anim",
            "-netdelay", "none",
            "-netspeed", "full"
        )
}

$deadline = (Get-Date).AddMinutes(8)
do {
    Start-Sleep -Seconds 3
    $state = (& $adb get-state 2>$null) -join ""
    $boot = (& $adb shell getprop sys.boot_completed 2>$null) -join ""
    if ($state.Trim() -eq "device" -and $boot.Trim() -eq "1") {
        Write-Host "KQ Android emulator is ready."
        & $adb devices -l
        exit 0
    }
} while ((Get-Date) -lt $deadline)

throw "Timed out waiting for emulator boot."
