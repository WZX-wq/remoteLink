$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$repo = Split-Path -Parent $PSScriptRoot
$env:Path = 'C:\Users\admin\.cargo\bin;D:\Git\cmd;D:\Git\bin;D:\tools\flutter\bin;D:\AndroidTools\sdk\cmdline-tools\latest\bin;D:\AndroidTools\sdk\platform-tools;' + $env:Path
$env:JAVA_HOME = 'D:\jdk17'
$env:ANDROID_HOME = 'D:\AndroidTools\sdk'
$env:ANDROID_SDK_ROOT = 'D:\AndroidTools\sdk'
$env:ANDROID_NDK_HOME = 'D:\AndroidTools\sdk\ndk\26.3.11579264'
$env:ANDROID_NDK_ROOT = $env:ANDROID_NDK_HOME
$env:ANDROID_NDK = $env:ANDROID_NDK_HOME
$env:VCPKG_ROOT = 'D:\tools\vcpkg'
$env:GRADLE_USER_HOME = 'C:\Users\admin\.gradle-remotelink-build'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:CARGO_BUILD_JOBS = '1'
$env:SKIP_JDK_VERSION_CHECK = '1'
$env:CLANG_PATH = 'D:\AndroidTools\sdk\ndk\26.3.11579264\toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe'
$env:BINDGEN_EXTRA_CLANG_ARGS = '--sysroot=D:\AndroidTools\sdk\ndk\26.3.11579264\toolchains\llvm\prebuilt\windows-x86_64\sysroot -isystem D:\AndroidTools\sdk\ndk\26.3.11579264\toolchains\llvm\prebuilt\windows-x86_64\lib\clang\17\include'
Set-Location -LiteralPath $repo
Write-Host '=== Tool versions ==='
git --version
rustc --version
cargo ndk --version
flutter --version
Write-Host '=== Key files ==='
$checks = [ordered]@{
  'Repo Cargo.toml' = (Test-Path -LiteralPath (Join-Path $repo 'Cargo.toml'))
  'Flutter package_config' = (Test-Path -LiteralPath (Join-Path $repo 'flutter\.dart_tool\package_config.json'))
  'Android SDK 36' = (Test-Path -LiteralPath 'D:\AndroidTools\sdk\platforms\android-36')
  'Android build-tools 28.0.3' = (Test-Path -LiteralPath 'D:\AndroidTools\sdk\build-tools\28.0.3')
  'Android license file' = (Test-Path -LiteralPath 'D:\AndroidTools\sdk\licenses\android-sdk-license')
  'NDK clang' = (Test-Path -LiteralPath 'D:\AndroidTools\sdk\ndk\26.3.11579264\toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe')
  'vcpkg' = (Test-Path -LiteralPath 'D:\tools\vcpkg\vcpkg.exe')
  'Inno Setup' = (Test-Path -LiteralPath 'D:\Program Files\Inno Setup 6\ISCC.exe')
  'VS vcvars64 D' = (Test-Path -LiteralPath 'D:\BuildTools\VC\Auxiliary\Build\vcvars64.bat')
}
$checks.GetEnumerator() | ForEach-Object { Write-Host ('{0}: {1}' -f $_.Key,$_.Value) }
Write-Host '=== Cargo metadata ==='
cargo metadata --manifest-path (Join-Path $repo 'Cargo.toml') --no-deps --format-version 1 | Out-Null
Write-Host "cargo metadata exit: $LASTEXITCODE"
Write-Host '=== Flutter doctor quick ==='
flutter doctor
