# RemoteLink local environment helper
# 用法：在 PowerShell 中执行：. D:\demo\远程桌面\remoteLink\scripts\local-env-remotelink.ps1
$env:Path='C:\Users\admin\.cargo\bin;D:\Git\cmd;D:\Git\bin;D:\tools\flutter\bin;D:\AndroidTools\sdk\cmdline-tools\latest\bin;D:\AndroidTools\sdk\platform-tools;' + $env:Path
$env:JAVA_HOME='D:\jdk17'
$env:ANDROID_HOME='D:\AndroidTools\sdk'
$env:ANDROID_SDK_ROOT='D:\AndroidTools\sdk'
$env:ANDROID_NDK_HOME='D:\AndroidTools\sdk\ndk\26.3.11579264'
$env:ANDROID_NDK_ROOT=$env:ANDROID_NDK_HOME
$env:ANDROID_NDK=$env:ANDROID_NDK_HOME
$env:VCPKG_ROOT='D:\tools\vcpkg'
$env:GRADLE_USER_HOME='C:\Users\admin\.gradle-remotelink-build'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
$env:CARGO_BUILD_JOBS='1'
$env:SKIP_JDK_VERSION_CHECK='1'
$env:FLUTTER_GIT_URL='https://ghproxy.com/https://github.com/flutter/flutter.git'
$env:CLANG_PATH='D:\AndroidTools\sdk\ndk\26.3.11579264\toolchains\llvm\prebuilt\windows-x86_64\bin\clang.exe'
$env:BINDGEN_EXTRA_CLANG_ARGS='--sysroot=D:\AndroidTools\sdk\ndk\26.3.11579264\toolchains\llvm\prebuilt\windows-x86_64\sysroot -isystem D:\AndroidTools\sdk\ndk\26.3.11579264\toolchains\llvm\prebuilt\windows-x86_64\lib\clang\17\include'
Write-Host 'RemoteLink environment loaded.'

$env:LIBCLANG_PATH='C:\Program Files\LLVM\bin'
$env:Path='C:\Program Files\LLVM\bin;' + $env:Path



