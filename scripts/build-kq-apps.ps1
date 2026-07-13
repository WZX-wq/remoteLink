<#
.SYNOPSIS
Builds KQ Remote Link Windows and Android packages through one stable local entrypoint.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\build-kq-apps.ps1 -Target Android -Offline

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\build-kq-apps.ps1 -Target Windows -SkipWindowsNative -SkipWindowsFlutter

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\build-kq-apps.ps1 -Target All -Offline -UpdateStableNames

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\build-kq-apps.ps1 -Target Android -Offline -UpdateStableNames -KeepTimestampedArtifacts

.NOTES
Use -Target Check first when the machine state is uncertain. Check mode performs preflight checks
without starting a long native, Flutter, Gradle, or installer build.
#>

param(
    [string[]]$Target = @("All"),

    [string]$OutputRoot,
    [string]$AsciiRepoPath = "D:\remotelink_build",
    [string]$WindowsCargoFeatures = "flutter",
    [string]$FlutterSdk,
    [int]$FlutterStartupTimeoutSeconds = 45,
    [int]$AndroidApiLevel = 21,

    [switch]$ForceWindowsNative,
    [switch]$SkipWindowsNative,
    [switch]$SkipWindowsFlutter,
    [switch]$SkipWindowsInstaller,

    [switch]$ForceAndroidNative,
    [switch]$SkipAndroidNative,
    [switch]$BuildAndroidAab,
    [switch]$NoAndroidObfuscate,
    [switch]$SkipFlutterPubGet,

    [switch]$Offline,
    [switch]$UpdateStableNames,
    [switch]$KeepTimestampedArtifacts
)

$ErrorActionPreference = "Stop"

$Repo = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $Repo "dist"
}
$OutputRoot = (New-Item -ItemType Directory -Force -Path $OutputRoot).FullName
$Stamp = Get-Date -Format "yyyyMMdd-HHmm"
$LogRoot = New-Item -ItemType Directory -Force -Path (Join-Path $Repo "build-logs")
if (-not $UpdateStableNames) {
    $UpdateStableNames = $true
}

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[ok] $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
    Write-Host "[warn] $Message" -ForegroundColor Yellow
}

function Fail([string]$Message) {
    throw $Message
}

function To-SlashPath([string]$Path) {
    return ([System.IO.Path]::GetFullPath($Path)).Replace("\", "/")
}

function Assert-File([string]$Path, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Fail "$Name not found: $Path"
    }
}

function Assert-Dir([string]$Path, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Fail "$Name not found: $Path"
    }
}

function Assert-Command([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Fail "Command not found in PATH: $Name"
    }
    return $cmd.Source
}

$script:ResolvedFlutterSdk = $null
$script:FlutterSmokePassed = $false

function Get-FlutterSdkFromLocalProperties {
    $localProperties = Join-Path $Repo "flutter\android\local.properties"
    if (-not (Test-Path -LiteralPath $localProperties -PathType Leaf)) {
        return $null
    }

    foreach ($line in (Get-Content -LiteralPath $localProperties)) {
        if ($line -match "^\s*flutter\.sdk\s*=\s*(.+?)\s*$") {
            $path = $Matches[1].Trim()
            $path = $path -replace "\\\\", "\"
            $path = [Environment]::ExpandEnvironmentVariables($path)
            $flutterBat = Join-Path $path "bin\flutter.bat"
            if (Test-Path -LiteralPath $flutterBat -PathType Leaf) {
                return (Resolve-Path -LiteralPath $path).Path
            }
            Write-Warn "flutter.sdk in local.properties does not contain bin\flutter.bat: $path"
        }
    }
    return $null
}

function Use-FlutterSdk {
    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($FlutterSdk)) {
        $candidates += $FlutterSdk
    }
    $localSdk = Get-FlutterSdkFromLocalProperties
    if ($localSdk) {
        $candidates += $localSdk
    }

    foreach ($candidate in $candidates) {
        $flutterBat = Join-Path $candidate "bin\flutter.bat"
        if (Test-Path -LiteralPath $flutterBat -PathType Leaf) {
            $resolved = (Resolve-Path -LiteralPath $candidate).Path
            $script:ResolvedFlutterSdk = $resolved
            $env:Path = (Join-Path $resolved "bin") + ";" + $env:Path
            Write-Ok "Using Flutter SDK: $resolved"
            return
        }
    }

    $flutter = Get-Command "flutter" -ErrorAction SilentlyContinue
    if ($flutter) {
        $bin = Split-Path -Parent $flutter.Source
        $script:ResolvedFlutterSdk = Split-Path -Parent $bin
        Write-Warn "Using Flutter from PATH: $($flutter.Source)"
    }
}

function Test-FlutterToolReady {
    param(
        [string]$Context = "Flutter"
    )

    if ($script:FlutterSmokePassed) {
        return
    }

    $flutterPath = Assert-Command "flutter"
    $flutterDir = Join-Path $Repo "flutter"
    $logPath = Join-Path $LogRoot.FullName ("flutter-smoke-$Stamp.log")
    $outPath = Join-Path $env:TEMP ("kq-flutter-smoke-out-$PID-$Stamp.txt")
    $errPath = Join-Path $env:TEMP ("kq-flutter-smoke-err-$PID-$Stamp.txt")

    Set-Content -LiteralPath $logPath -Encoding UTF8 -Value @(
        "START_TIME=$(Get-Date -Format o)",
        "CONTEXT=$Context",
        "WORKING_DIRECTORY=$flutterDir",
        "COMMAND=$flutterPath --version",
        "TIMEOUT_SECONDS=$FlutterStartupTimeoutSeconds",
        ""
    )

    $commandLine = '"' + $flutterPath + '" --version'
    Write-Host "[$Context Flutter smoke] $commandLine"
    $proc = Start-Process -FilePath "cmd.exe" `
        -ArgumentList @("/d", "/c", $commandLine) `
        -WorkingDirectory $flutterDir `
        -RedirectStandardOutput $outPath `
        -RedirectStandardError $errPath `
        -PassThru `
        -WindowStyle Hidden

    if (-not $proc.WaitForExit($FlutterStartupTimeoutSeconds * 1000)) {
        Add-Content -LiteralPath $logPath -Value "TIMEOUT=1"
        try {
            & taskkill.exe /PID $proc.Id /T /F 2>&1 | ForEach-Object {
                Add-Content -LiteralPath $logPath -Value $_.ToString()
            }
        }
        catch {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
        Fail "Flutter CLI did not return from '--version' within ${FlutterStartupTimeoutSeconds}s. This is usually a stale Flutter cache lock or orphan dart/git process. See log: $logPath"
    }

    $out = if (Test-Path -LiteralPath $outPath) { Get-Content -LiteralPath $outPath -ErrorAction SilentlyContinue } else { @() }
    $err = if (Test-Path -LiteralPath $errPath) { Get-Content -LiteralPath $errPath -ErrorAction SilentlyContinue } else { @() }
    if ($out) { Add-Content -LiteralPath $logPath -Value $out }
    if ($err) { Add-Content -LiteralPath $logPath -Value $err }
    $exitCode = $proc.ExitCode
    if ($null -eq $exitCode) {
        $exitCode = 0
    }
    Add-Content -LiteralPath $logPath -Value "EXIT_CODE=$exitCode"

    Remove-Item -LiteralPath $outPath, $errPath -Force -ErrorAction SilentlyContinue

    if ($exitCode -ne 0) {
        Fail "Flutter CLI smoke check failed with exit code $exitCode. See log: $logPath"
    }

    $firstLine = @($out | Where-Object { $_ }) | Select-Object -First 1
    if ($firstLine) {
        Write-Ok "$Context Flutter CLI ready: $firstLine"
    }
    else {
        Write-Ok "$Context Flutter CLI ready."
    }
    $script:FlutterSmokePassed = $true
}

function Invoke-FlutterPubGetIfNeeded {
    param(
        [string]$BuildRepo,
        [string]$PlatformName
    )

    if ($SkipFlutterPubGet) {
        Write-Warn "Skipping Flutter pub get by request."
        return
    }

    $flutterDir = Join-Path $BuildRepo "flutter"
    $packageConfig = Join-Path $flutterDir ".dart_tool\package_config.json"
    $inputs = @(
        (Join-Path $flutterDir "pubspec.yaml"),
        (Join-Path $flutterDir "pubspec.lock")
    )
    $needsPubGet = -not (Test-Path -LiteralPath $packageConfig -PathType Leaf)
    if (-not $needsPubGet) {
        $packageConfigTime = (Get-Item -LiteralPath $packageConfig).LastWriteTime
        foreach ($input in $inputs) {
            if ((Test-Path -LiteralPath $input -PathType Leaf) -and ((Get-Item -LiteralPath $input).LastWriteTime -gt $packageConfigTime)) {
                $needsPubGet = $true
            }
        }
    }

    if (-not $needsPubGet) {
        Write-Ok "Reusing Flutter package configuration: $packageConfig"
        return
    }

    $logName = "$($PlatformName.ToLowerInvariant())-flutter-pub-get-$Stamp.log"
    Invoke-LoggedCommand `
        -Name "Flutter pub get" `
        -WorkingDirectory $flutterDir `
        -FilePath "flutter" `
        -Arguments @("pub", "get") `
        -LogPath (Join-Path $LogRoot.FullName $logName)
}

function Invoke-LoggedCommand {
    param(
        [string]$Name,
        [string]$WorkingDirectory,
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$LogPath
    )

    $logDir = Split-Path -Parent $LogPath
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $header = @(
        "START_TIME=$(Get-Date -Format o)",
        "NAME=$Name",
        "WORKING_DIRECTORY=$WorkingDirectory",
        "COMMAND=$FilePath $($Arguments -join ' ')",
        ""
    )
    Set-Content -LiteralPath $LogPath -Value $header -Encoding UTF8

    Write-Host "[$Name] $FilePath $($Arguments -join ' ')"
    Write-Host "[$Name] log: $LogPath"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $outPath = Join-Path $env:TEMP ("kq-build-out-$PID-$Stamp-$($Name -replace '[^A-Za-z0-9]+','-').txt")
    $errPath = Join-Path $env:TEMP ("kq-build-err-$PID-$Stamp-$($Name -replace '[^A-Za-z0-9]+','-').txt")
    Remove-Item -LiteralPath $outPath, $errPath -Force -ErrorAction SilentlyContinue
    $detectedBuildFailure = $false

    Push-Location $WorkingDirectory
    try {
        $proc = Start-Process -FilePath $FilePath `
            -ArgumentList $Arguments `
            -WorkingDirectory $WorkingDirectory `
            -RedirectStandardOutput $outPath `
            -RedirectStandardError $errPath `
            -PassThru `
            -WindowStyle Hidden
        $proc.WaitForExit()
        $exitCode = $proc.ExitCode

        foreach ($path in @($outPath, $errPath)) {
            if (-not (Test-Path -LiteralPath $path)) {
                continue
            }
            Get-Content -LiteralPath $path -ErrorAction SilentlyContinue | ForEach-Object {
                $line = $_.ToString()
                if ($line -match '(?i)(Build process failed\.|Unhandled exception:|FAILURE: Build failed|\berror [A-Z][A-Z0-9]*\d+:)') {
                    $detectedBuildFailure = $true
                }
                Add-Content -LiteralPath $LogPath -Value $line
                Write-Host $line
            }
        }
    }
    finally {
        Pop-Location
        Remove-Item -LiteralPath $outPath, $errPath -Force -ErrorAction SilentlyContinue
    }

    $sw.Stop()
    if ($null -eq $exitCode) {
        $exitCode = if ($?) { 0 } else { 1 }
    }
    if ($exitCode -eq 0 -and $detectedBuildFailure) {
        $exitCode = 1
        Add-Content -LiteralPath $LogPath -Value "DETECTED_BUILD_FAILURE=1"
    }
    Add-Content -LiteralPath $LogPath -Value "EXIT_CODE=$exitCode"
    Add-Content -LiteralPath $LogPath -Value ("ELAPSED_SECONDS={0:N1}" -f $sw.Elapsed.TotalSeconds)

    if ($exitCode -ne 0) {
        Fail "$Name failed with exit code $exitCode. See log: $LogPath"
    }
    Write-Ok "$Name finished in $([int]$sw.Elapsed.TotalSeconds)s"
}

function Import-LocalEnvironment {
    $envScript = Join-Path $Repo "scripts\local-env-remotelink.ps1"
    if (Test-Path -LiteralPath $envScript) {
        . $envScript
    }

    if (-not $env:VCPKG_ROOT) {
        $env:VCPKG_ROOT = "D:\tools\vcpkg"
    }
    if (-not $env:ANDROID_HOME) {
        $env:ANDROID_HOME = "D:\AndroidTools\sdk"
    }
    if (-not $env:ANDROID_SDK_ROOT) {
        $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
    }
    if (-not $env:ANDROID_NDK_HOME) {
        $env:ANDROID_NDK_HOME = Join-Path $env:ANDROID_HOME "ndk\26.3.11579264"
    }
    if (-not $env:JAVA_HOME) {
        $env:JAVA_HOME = "D:\jdk17"
    }
    if (-not $env:GRADLE_USER_HOME) {
        $env:GRADLE_USER_HOME = "C:\Users\admin\.gradle-remotelink-build"
    }
    if (-not $env:PUB_HOSTED_URL) {
        $env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
    }
    if (-not $env:FLUTTER_STORAGE_BASE_URL) {
        $env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
    }
    if (-not $env:CARGO_BUILD_JOBS) {
        $env:CARGO_BUILD_JOBS = "1"
    }

    Use-FlutterSdk
}

function Ensure-AsciiRepoPath {
    if ([string]::IsNullOrWhiteSpace($AsciiRepoPath)) {
        return $Repo
    }

    $repoCargo = Join-Path $Repo "Cargo.toml"
    $candidateCargo = Join-Path $AsciiRepoPath "Cargo.toml"
    if (Test-Path -LiteralPath $candidateCargo) {
        try {
            $repoHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $repoCargo).Hash
            $candidateHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidateCargo).Hash
            if ($repoHash -eq $candidateHash) {
                return (Resolve-Path $AsciiRepoPath).Path
            }
            Write-Warn "$AsciiRepoPath exists but does not look like this repo. Using original path."
            return $Repo
        }
        catch {
            Write-Warn "Could not verify $AsciiRepoPath. Using original path. $($_.Exception.Message)"
            return $Repo
        }
    }

    try {
        New-Item -ItemType Junction -Path $AsciiRepoPath -Target $Repo -Force | Out-Null
        Write-Ok "Created ASCII build junction: $AsciiRepoPath -> $Repo"
        return (Resolve-Path $AsciiRepoPath).Path
    }
    catch {
        Write-Warn "Could not create ASCII build junction $AsciiRepoPath. Using original path. $($_.Exception.Message)"
        return $Repo
    }
}

function Get-NewestSourceWriteTime {
    param(
        [string[]]$Paths,
        [string[]]$Extensions = @(".rs", ".toml", ".lock", ".gradle", ".kt", ".java", ".dart", ".yaml", ".yml")
    )

    $newest = [datetime]"1970-01-01"
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        $item = Get-Item -LiteralPath $path
        if (-not $item.PSIsContainer) {
            if ($item.LastWriteTime -gt $newest) {
                $newest = $item.LastWriteTime
            }
            continue
        }

        Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $Extensions -contains $_.Extension -and
                $_.FullName -notmatch "\\target\\" -and
                $_.FullName -notmatch "\\build\\" -and
                $_.FullName -notmatch "\\.dart_tool\\"
            } |
            ForEach-Object {
                if ($_.LastWriteTime -gt $newest) {
                    $newest = $_.LastWriteTime
                }
            }
    }
    return $newest
}

function Test-ArtifactFresh([string]$Artifact, [datetime]$SourceTime) {
    if (-not (Test-Path -LiteralPath $Artifact -PathType Leaf)) {
        return $false
    }
    return ((Get-Item -LiteralPath $Artifact).LastWriteTime -ge $SourceTime)
}

function Add-HashFile([string]$Path) {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
    $hashPath = "$Path.sha256"
    Set-Content -LiteralPath $hashPath -Value "$hash  $([System.IO.Path]::GetFileName($Path))" -Encoding ASCII
    return $hash
}

function Remove-FileIfExists([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Remove-Item -LiteralPath $Path -Force
    }
}

function Remove-DirectoryIfExists([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Container) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Get-ArtifactOutputPath {
    param(
        [string]$StableName,
        [string]$TimestampedName
    )

    if ($UpdateStableNames) {
        return Join-Path $OutputRoot $StableName
    }
    return Join-Path $OutputRoot $TimestampedName
}

function Remove-TimestampedDuplicate {
    param(
        [string]$Path,
        [string]$Kind
    )

    if (-not $UpdateStableNames -or $KeepTimestampedArtifacts) {
        return
    }
    Remove-FileIfExists -Path $Path
    Remove-FileIfExists -Path "$Path.sha256"
    Write-Ok "Removed timestamped duplicate ${Kind}: $Path"
}

function Test-ZipEntry([string]$ZipPath, [string]$EntryName) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.FullName -eq $EntryName) {
                return $true
            }
        }
        return $false
    }
    finally {
        $zip.Dispose()
    }
}

function Normalize-Targets {
    $expanded = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($rawItem in $Target) {
        foreach ($item in ($rawItem -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        if ($item -eq "All") {
            [void]$expanded.Add("Windows")
            [void]$expanded.Add("Android")
        } elseif ($item -in @("Windows", "Android", "Check")) {
            [void]$expanded.Add($item)
        } else {
            Fail "Unknown target '$item'. Use one or more of: All, Windows, Android, Check."
        }
        }
    }
    return $expanded
}

function Get-VcVarsPath {
    $candidates = @(
        "D:\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
    )
    return $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

function Import-VcVars {
    $vcvars = Get-VcVarsPath
    if (-not $vcvars) {
        Fail "Visual Studio Build Tools vcvars64.bat was not found. Install Desktop development with C++ first."
    }
    $preferredVcpkgRoot = $env:VCPKG_ROOT
    Write-Ok "Using MSVC environment: $vcvars"
    $lines = & cmd.exe /c "`"$vcvars`" >nul && set"
    foreach ($line in $lines) {
        if ($line -match "^([^=]+)=(.*)$") {
            Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2]
        }
    }
    if ($preferredVcpkgRoot) {
        $preferredVcpkg = Join-Path $preferredVcpkgRoot "vcpkg.exe"
        if (Test-Path -LiteralPath $preferredVcpkg -PathType Leaf) {
            $env:VCPKG_ROOT = $preferredVcpkgRoot
            Write-Ok "Using preferred VCPKG_ROOT: $env:VCPKG_ROOT"
        }
    }
}

function Test-WindowsSymlinkSupport {
    $dir = Join-Path $env:TEMP ("kq-symlink-test-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        $target = Join-Path $dir "target"
        $link = Join-Path $dir "link"
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop | Out-Null
        if (-not (Test-Path -LiteralPath $link)) {
            Write-Warn "Windows symlink test did not create link: $link"
            return $false
        }
        return $true
    }
    catch {
        Write-Warn "Windows symlink test failed: $($_.Exception.Message)"
        return $false
    }
    finally {
        if (Test-Path -LiteralPath $dir) {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-ExistingWindowsPluginSymlinks([string]$BuildRepo) {
    $depsPath = Join-Path $BuildRepo "flutter\.flutter-plugins-dependencies"
    $linksRoot = Join-Path $BuildRepo "flutter\windows\flutter\ephemeral\.plugin_symlinks"
    if ((-not (Test-Path -LiteralPath $depsPath -PathType Leaf)) -or
        (-not (Test-Path -LiteralPath $linksRoot -PathType Container))) {
        return $false
    }

    try {
        $deps = Get-Content -LiteralPath $depsPath -Raw | ConvertFrom-Json
        $plugins = @($deps.plugins.windows | ForEach-Object { $_.name } | Where-Object { $_ })
    }
    catch {
        Write-Warn "Could not read Windows plugin dependency metadata: $($_.Exception.Message)"
        return $false
    }

    if ($plugins.Count -eq 0) {
        return $true
    }

    $missing = @($plugins | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $linksRoot $_))
    })
    if ($missing.Count -gt 0) {
        Write-Warn "Existing Flutter Windows plugin symlinks are incomplete: $($missing -join ', ')"
        return $false
    }

    Write-Ok "Reusing existing Flutter Windows plugin symlinks."
    return $true
}

function Clear-AndroidBuildEnv {
    Remove-Item Env:\SODIUM_LIB_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:\CLANG_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:\BINDGEN_EXTRA_CLANG_ARGS -ErrorAction SilentlyContinue
    Remove-Item Env:\BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android -ErrorAction SilentlyContinue
    [Environment]::SetEnvironmentVariable("BINDGEN_EXTRA_CLANG_ARGS_aarch64-linux-android", $null, "Process")
    [Environment]::SetEnvironmentVariable("BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android", $null, "Process")
}

function Ensure-WindowsVcpkgDeps {
    $tripletRoot = Join-Path $env:VCPKG_ROOT "installed\x64-windows-static"
    $required = @(
        "lib\aom.lib",
        "lib\vpx.lib",
        "lib\yuv.lib",
        "lib\opus.lib",
        "include\aom\aom.h",
        "include\vpx\vpx_encoder.h",
        "include\libyuv.h",
        "include\opus\opus.h"
    )

    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $tripletRoot $_)) })
    $features = @($WindowsCargoFeatures -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($features -contains "hwcodec") {
        $hwcodec = @(
            "include\libavutil\pixfmt.h",
            "lib\avcodec.lib",
            "lib\avformat.lib",
            "lib\avutil.lib",
            "lib\libmfx.lib"
        )
        $missing += @($hwcodec | Where-Object { -not (Test-Path -LiteralPath (Join-Path $tripletRoot $_)) })
    }

    if ($missing.Count -eq 0) {
        Write-Ok "Windows vcpkg dependencies are present."
        return
    }

    if ($Offline) {
        Fail "Missing Windows vcpkg dependencies in offline mode: $($missing -join ', ')"
    }

    $vcpkg = Join-Path $env:VCPKG_ROOT "vcpkg.exe"
    Assert-File $vcpkg "vcpkg.exe"
    $packages = @("aom:x64-windows-static", "libvpx:x64-windows-static", "libyuv:x64-windows-static", "opus:x64-windows-static")
    if ($features -contains "hwcodec") {
        $packages += "ffmpeg[amf,nvcodec,qsv]:x64-windows-static"
    }
    $args = @("install") + $packages + @(
        "--classic",
        "--triplet", "x64-windows-static",
        "--x-install-root=$($env:VCPKG_ROOT)\installed",
        "--overlay-ports=$Repo\res\vcpkg",
        "--recurse"
    )
    Invoke-LoggedCommand -Name "Windows vcpkg deps" -WorkingDirectory $Repo -FilePath $vcpkg -Arguments $args -LogPath (Join-Path $LogRoot.FullName "windows-vcpkg-$Stamp.log")
}

function Assert-WindowsPrereqs([string]$BuildRepo = $Repo) {
    Write-Step "Windows preflight"
    Assert-Command "cargo" | Out-Null
    Assert-Command "flutter" | Out-Null
    if (-not $SkipWindowsFlutter) {
        Test-FlutterToolReady -Context "Windows"
    }
    Assert-Command "git" | Out-Null
    Import-VcVars
    if ((-not $SkipWindowsFlutter) -and (-not (Test-WindowsSymlinkSupport))) {
        if (Test-ExistingWindowsPluginSymlinks -BuildRepo $BuildRepo) {
            Write-Warn "Current shell cannot create new symlinks, but existing Flutter Windows plugin symlinks are complete. Continuing."
        }
        else {
            Fail "Windows symlink support is not available. Enable Developer Mode or run this script from an elevated PowerShell."
        }
    }
    if (-not $SkipWindowsInstaller) {
        $isccCandidates = @(
            "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
            "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
            "D:\Program Files\Inno Setup 6\ISCC.exe"
        )
        $iscc = $isccCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $iscc) {
            Fail "Inno Setup compiler was not found. Tried: $($isccCandidates -join '; ')"
        }
        Write-Ok "Using Inno Setup: $iscc"
    }
    if (-not $SkipWindowsNative) {
        Ensure-WindowsVcpkgDeps
    }
}

function Build-WindowsArtifacts([string]$BuildRepo) {
    Assert-WindowsPrereqs -BuildRepo $BuildRepo
    Clear-AndroidBuildEnv

    $dll = Join-Path $BuildRepo "target\release\librustdesk.dll"
    $sourceTime = Get-NewestSourceWriteTime -Paths @(
        (Join-Path $BuildRepo "Cargo.toml"),
        (Join-Path $BuildRepo "Cargo.lock"),
        (Join-Path $BuildRepo "build.rs"),
        (Join-Path $BuildRepo "src"),
        (Join-Path $BuildRepo "libs\scrap"),
        (Join-Path $BuildRepo "libs\hbb_common")
    ) -Extensions @(".rs", ".toml", ".lock", ".cc", ".h")

    if ($SkipWindowsNative) {
        Assert-File $dll "Windows Rust DLL"
        Write-Warn "Skipping Windows native build by request."
    }
    elseif ((-not $ForceWindowsNative) -and (Test-ArtifactFresh -Artifact $dll -SourceTime $sourceTime)) {
        Write-Ok "Reusing fresh Windows native DLL: $dll"
    }
    else {
        Invoke-LoggedCommand `
            -Name "Windows native DLL" `
            -WorkingDirectory $BuildRepo `
            -FilePath "cargo" `
            -Arguments @("build", "--features", $WindowsCargoFeatures, "--lib", "--release") `
            -LogPath (Join-Path $LogRoot.FullName "windows-native-$Stamp.log")
    }
    Assert-File $dll "Windows Rust DLL"

    if ($SkipWindowsFlutter) {
        Write-Warn "Skipping Windows Flutter build by request."
    }
    else {
        Invoke-FlutterPubGetIfNeeded -BuildRepo $BuildRepo -PlatformName "Windows"

        Invoke-LoggedCommand `
            -Name "Flutter Windows" `
            -WorkingDirectory (Join-Path $BuildRepo "flutter") `
            -FilePath "flutter" `
            -Arguments @("build", "windows", "--release") `
            -LogPath (Join-Path $LogRoot.FullName "windows-flutter-$Stamp.log")
    }

    $releaseDir = Join-Path $BuildRepo "flutter\build\windows\x64\runner\Release"
    Assert-Dir $releaseDir "Windows Flutter Release directory"
    Copy-Item -LiteralPath $dll -Destination (Join-Path $releaseDir "librustdesk.dll") -Force
    foreach ($item in @("rustdesk.exe", "librustdesk.dll", "flutter_windows.dll", "data\flutter_assets\AssetManifest.bin")) {
        Assert-File (Join-Path $releaseDir $item) "Windows release artifact $item"
    }

    if ($SkipWindowsInstaller) {
        Write-Warn "Skipping Windows installer by request."
        return $releaseDir
    }

    $installerName = "Kunqiong-Remote-Desktop-Setup-$Stamp"
    $installerScript = Join-Path $Repo "scripts\new-kq-inno-installer.ps1"
    Assert-File $installerScript "Inno installer script"
    $version = Get-Date -Format "yyyy.MM.dd.HHmm"
    Invoke-LoggedCommand `
        -Name "Windows installer" `
        -WorkingDirectory $Repo `
        -FilePath "powershell.exe" `
        -Arguments @(
            "-ExecutionPolicy", "Bypass",
            "-File", $installerScript,
            "-ReleaseDir", $releaseDir,
            "-OutputRoot", $OutputRoot,
            "-InstallerName", $installerName,
            "-Version", $version,
            "-CargoFeatures", $WindowsCargoFeatures,
            "-SkipCargoBuild",
            "-SkipFlutterBuild"
        ) `
        -LogPath (Join-Path $LogRoot.FullName "windows-installer-$Stamp.log")

    $installerPath = Join-Path $OutputRoot "$installerName.exe"
    Assert-File $installerPath "Windows installer"
    $finalInstallerPath = Get-ArtifactOutputPath `
        -StableName "Kunqiong-Remote-Desktop-Setup.exe" `
        -TimestampedName "$installerName.exe"
    if ($finalInstallerPath -ne $installerPath) {
        Remove-FileIfExists -Path $finalInstallerPath
        Remove-FileIfExists -Path "$finalInstallerPath.sha256"
        Move-Item -LiteralPath $installerPath -Destination $finalInstallerPath -Force
        Remove-FileIfExists -Path "$installerPath.sha256"
        $installerPath = $finalInstallerPath
    }
    $hash = Add-HashFile $installerPath
    if ($UpdateStableNames) {
        $timestampedInstaller = Join-Path $OutputRoot "$installerName.exe"
        Remove-TimestampedDuplicate -Path $timestampedInstaller -Kind "Windows installer"
    }
    Remove-DirectoryIfExists -Path (Join-Path $OutputRoot "$installerName-inno-build")
    Write-Ok "Windows installer: $installerPath"
    Write-Ok "Windows SHA256: $hash"
    return $installerPath
}

function Get-AndroidNdkPrebuilt {
    $candidate = Join-Path $env:ANDROID_NDK_HOME "toolchains\llvm\prebuilt\windows-x86_64"
    Assert-Dir $candidate "Android NDK LLVM prebuilt"
    return $candidate
}

function Get-LlvmBin {
    $candidates = @(
        "C:\Program Files\LLVM\bin",
        (Join-Path (Get-AndroidNdkPrebuilt) "bin")
    )
    foreach ($candidate in $candidates) {
        if ((Test-Path -LiteralPath (Join-Path $candidate "libclang.dll")) -and
            (Test-Path -LiteralPath (Join-Path $candidate "clang.exe"))) {
            return $candidate
        }
    }
    Fail "libclang.dll and clang.exe were not found. Install LLVM or fix LIBCLANG_PATH."
}

function Ensure-AndroidVcpkgDeps {
    $tripletRoot = Join-Path $env:VCPKG_ROOT "installed\arm64-android"
    $required = @(
        "lib\libsodium.a",
        "lib\liboboe.a",
        "lib\libndk_compat.a",
        "lib\libopus.a",
        "lib\libaom.a",
        "lib\libvpx.a",
        "lib\libyuv.a",
        "include\sodium.h",
        "include\aom\aom.h",
        "include\vpx\vpx_encoder.h",
        "include\libyuv.h"
    )
    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $tripletRoot $_)) })
    if ($missing.Count -eq 0) {
        Write-Ok "Android vcpkg dependencies are present."
        return
    }
    if ($Offline) {
        Fail "Missing Android vcpkg dependencies in offline mode: $($missing -join ', ')"
    }

    $vcpkg = Join-Path $env:VCPKG_ROOT "vcpkg.exe"
    Assert-File $vcpkg "vcpkg.exe"
    $packages = @(
        "libsodium:arm64-android",
        "oboe:arm64-android",
        "cpu-features:arm64-android",
        "opus:arm64-android",
        "libjpeg-turbo:arm64-android",
        "libvpx:arm64-android",
        "libyuv:arm64-android",
        "aom:arm64-android"
    )
    $args = @("install") + $packages + @(
        "--classic",
        "--triplet", "arm64-android",
        "--x-install-root=$($env:VCPKG_ROOT)\installed",
        "--overlay-ports=$Repo\res\vcpkg",
        "--recurse"
    )
    Invoke-LoggedCommand -Name "Android vcpkg deps" -WorkingDirectory $Repo -FilePath $vcpkg -Arguments $args -LogPath (Join-Path $LogRoot.FullName "android-vcpkg-$Stamp.log")
}

function Prepare-AndroidNativeEnv([string]$BuildRepo) {
    $ndkPrebuilt = Get-AndroidNdkPrebuilt
    $llvmBin = Get-LlvmBin
    $sodiumSource = Join-Path $env:VCPKG_ROOT "installed\arm64-android\lib\libsodium.a"
    Assert-File $sodiumSource "Android libsodium.a"

    $sodiumDir = Join-Path $BuildRepo "target\android-sodium-link\arm64-android\lib"
    New-Item -ItemType Directory -Force -Path $sodiumDir | Out-Null
    Copy-Item -LiteralPath $sodiumSource -Destination (Join-Path $sodiumDir "libsodium.a") -Force
    Copy-Item -LiteralPath $sodiumSource -Destination (Join-Path $sodiumDir "liblibsodium.a") -Force

    $ndkSlash = To-SlashPath $ndkPrebuilt
    $bindgenArgs = "--target=aarch64-linux-android$AndroidApiLevel --sysroot=$ndkSlash/sysroot -isystem $ndkSlash/lib/clang/17/include -isystem $ndkSlash/sysroot/usr/include -isystem $ndkSlash/sysroot/usr/include/aarch64-linux-android"
    $env:SODIUM_LIB_DIR = To-SlashPath $sodiumDir
    $env:BINDGEN_EXTRA_CLANG_ARGS = $bindgenArgs
    [Environment]::SetEnvironmentVariable("BINDGEN_EXTRA_CLANG_ARGS_aarch64-linux-android", $bindgenArgs, "Process")
    [Environment]::SetEnvironmentVariable("BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android", $bindgenArgs, "Process")
    $env:LIBCLANG_PATH = To-SlashPath $llvmBin
    $env:CLANG_PATH = To-SlashPath (Join-Path $llvmBin "clang.exe")
    $env:ANDROID_NDK = $env:ANDROID_NDK_HOME
    $env:ANDROID_NDK_ROOT = $env:ANDROID_NDK_HOME

    Write-Ok "Android bindgen and libsodium environment prepared."
}

function Assert-AndroidPrereqs {
    Write-Step "Android preflight"
    Assert-Command "cargo" | Out-Null
    Assert-Command "rustup" | Out-Null
    Assert-Command "flutter" | Out-Null
    Test-FlutterToolReady -Context "Android"
    $bash = Assert-Command "bash"
    if ($bash -notmatch "\\Git\\") {
        Fail "bash resolves to '$bash'. Git Bash must be before WSL bash in PATH."
    }
    Assert-Dir $env:ANDROID_HOME "ANDROID_HOME"
    Assert-Dir $env:ANDROID_NDK_HOME "ANDROID_NDK_HOME"
    Assert-Dir $env:VCPKG_ROOT "VCPKG_ROOT"
    Assert-File (Join-Path $env:JAVA_HOME "bin\java.exe") "Java"
    Assert-File (Join-Path (Get-AndroidNdkPrebuilt) "bin\llvm-strip.exe") "Android llvm-strip"
    Ensure-AndroidVcpkgDeps
}

function Build-AndroidArtifacts([string]$BuildRepo) {
    Assert-AndroidPrereqs
    Prepare-AndroidNativeEnv -BuildRepo $BuildRepo

    $nativeSo = Join-Path $BuildRepo "target\aarch64-linux-android\release\liblibrustdesk.so"
    $sourceTime = Get-NewestSourceWriteTime -Paths @(
        (Join-Path $BuildRepo "Cargo.toml"),
        (Join-Path $BuildRepo "Cargo.lock"),
        (Join-Path $BuildRepo "build.rs"),
        (Join-Path $BuildRepo "src"),
        (Join-Path $BuildRepo "libs\scrap"),
        (Join-Path $BuildRepo "libs\hbb_common")
    ) -Extensions @(".rs", ".toml", ".lock", ".c", ".h")

    if ($SkipAndroidNative) {
        Assert-File $nativeSo "Android native librustdesk.so"
        Write-Warn "Skipping Android native build by request."
    }
    elseif ((-not $ForceAndroidNative) -and (Test-ArtifactFresh -Artifact $nativeSo -SourceTime $sourceTime)) {
        Write-Ok "Reusing fresh Android native library: $nativeSo"
    }
    else {
        Invoke-LoggedCommand `
            -Name "Android rust target" `
            -WorkingDirectory $BuildRepo `
            -FilePath "rustup" `
            -Arguments @("target", "add", "aarch64-linux-android") `
            -LogPath (Join-Path $LogRoot.FullName "android-rust-target-$Stamp.log")

        Invoke-LoggedCommand `
            -Name "Android native library" `
            -WorkingDirectory $BuildRepo `
            -FilePath "bash" `
            -Arguments @(".\flutter\ndk_arm64.sh") `
            -LogPath (Join-Path $LogRoot.FullName "android-native-$Stamp.log")
    }
    Assert-File $nativeSo "Android native librustdesk.so"

    $ndkPrebuilt = Get-AndroidNdkPrebuilt
    $jniDir = Join-Path $BuildRepo "flutter\android\app\src\main\jniLibs\arm64-v8a"
    New-Item -ItemType Directory -Force -Path $jniDir | Out-Null
    Copy-Item -LiteralPath $nativeSo -Destination (Join-Path $jniDir "librustdesk.so") -Force
    Copy-Item -LiteralPath (Join-Path $ndkPrebuilt "sysroot\usr\lib\aarch64-linux-android\libc++_shared.so") -Destination (Join-Path $jniDir "libc++_shared.so") -Force
    $strip = Join-Path $ndkPrebuilt "bin\llvm-strip.exe"
    & $strip (Join-Path $jniDir "librustdesk.so")
    if ($LASTEXITCODE -ne 0) { Fail "llvm-strip failed for librustdesk.so" }
    & $strip (Join-Path $jniDir "libc++_shared.so")
    if ($LASTEXITCODE -ne 0) { Fail "llvm-strip failed for libc++_shared.so" }
    Write-Ok "Copied Android native libraries into jniLibs."

    Invoke-FlutterPubGetIfNeeded -BuildRepo $BuildRepo -PlatformName "Android"

    $apkArgs = @("build", "apk", "--split-per-abi", "--target-platform", "android-arm64", "--release")
    if (-not $NoAndroidObfuscate) {
        $apkArgs += @("--obfuscate", "--split-debug-info", "./split-debug-info")
    }
    Invoke-LoggedCommand `
        -Name "Flutter Android APK" `
        -WorkingDirectory (Join-Path $BuildRepo "flutter") `
        -FilePath "flutter" `
        -Arguments $apkArgs `
        -LogPath (Join-Path $LogRoot.FullName "android-flutter-apk-$Stamp.log")

    $apk = Join-Path $BuildRepo "flutter\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
    Assert-File $apk "Android release APK"
    foreach ($entry in @("lib/arm64-v8a/librustdesk.so", "lib/arm64-v8a/libc++_shared.so", "lib/arm64-v8a/libapp.so", "lib/arm64-v8a/libflutter.so")) {
        if (-not (Test-ZipEntry -ZipPath $apk -EntryName $entry)) {
            Fail "Android APK is missing $entry"
        }
    }

    $timestampedApkName = "Kunqiong-Remote-Desktop-Android-$Stamp.apk"
    $destApk = Get-ArtifactOutputPath `
        -StableName "Kunqiong-Remote-Desktop.apk" `
        -TimestampedName $timestampedApkName
    Copy-Item -LiteralPath $apk -Destination $destApk -Force
    $apkHash = Add-HashFile $destApk
    Write-Ok "Android APK: $destApk"
    Write-Ok "Android APK SHA256: $apkHash"

    if ($UpdateStableNames) {
        $timestampedApk = Join-Path $OutputRoot $timestampedApkName
        if ($KeepTimestampedArtifacts) {
            Copy-Item -LiteralPath $destApk -Destination $timestampedApk -Force
            Add-HashFile $timestampedApk | Out-Null
        }
        else {
            Remove-TimestampedDuplicate -Path $timestampedApk -Kind "Android APK"
        }
    }

    if ($BuildAndroidAab) {
        $aabArgs = @("build", "appbundle", "--target-platform", "android-arm64", "--release")
        if (-not $NoAndroidObfuscate) {
            $aabArgs += @("--obfuscate", "--split-debug-info", "./split-debug-info")
        }
        Invoke-LoggedCommand `
            -Name "Flutter Android AAB" `
            -WorkingDirectory (Join-Path $BuildRepo "flutter") `
            -FilePath "flutter" `
            -Arguments $aabArgs `
            -LogPath (Join-Path $LogRoot.FullName "android-flutter-aab-$Stamp.log")
        $aab = Get-ChildItem -LiteralPath (Join-Path $BuildRepo "flutter\build\app\outputs") -Recurse -Filter "*.aab" |
            Sort-Object LastWriteTime |
            Select-Object -Last 1
        if (-not $aab) {
            Fail "Android AAB was not produced."
        }
        foreach ($entry in @("base/lib/arm64-v8a/librustdesk.so", "base/lib/arm64-v8a/libc++_shared.so")) {
            if (-not (Test-ZipEntry -ZipPath $aab.FullName -EntryName $entry)) {
                Fail "Android AAB is missing $entry"
            }
        }
        $timestampedAabName = "Kunqiong-Remote-Desktop-Android-$Stamp.aab"
        $destAab = Get-ArtifactOutputPath `
            -StableName "Kunqiong-Remote-Desktop.aab" `
            -TimestampedName $timestampedAabName
        Copy-Item -LiteralPath $aab.FullName -Destination $destAab -Force
        Add-HashFile $destAab | Out-Null
        if ($UpdateStableNames) {
            $timestampedAab = Join-Path $OutputRoot $timestampedAabName
            if ($KeepTimestampedArtifacts) {
                Copy-Item -LiteralPath $destAab -Destination $timestampedAab -Force
                Add-HashFile $timestampedAab | Out-Null
            }
            else {
                Remove-TimestampedDuplicate -Path $timestampedAab -Kind "Android AAB"
            }
        }
        Write-Ok "Android AAB: $destAab"
    }
    return $destApk
}

function Show-Summary([object[]]$Artifacts) {
    Write-Step "Build summary"
    if ($Artifacts.Count -eq 0) {
        Write-Host "No artifacts were built. Check mode only."
        return
    }
    foreach ($artifact in $Artifacts) {
        if ($artifact -and (Test-Path -LiteralPath $artifact)) {
            $item = Get-Item -LiteralPath $artifact
            Write-Host ("{0}  {1:N1} MB" -f $item.FullName, ($item.Length / 1MB))
        }
    }
    Write-Host "Logs: $($LogRoot.FullName)"
}

Import-LocalEnvironment
$Targets = Normalize-Targets
$BuildRepo = Ensure-AsciiRepoPath
Write-Ok "Repo: $Repo"
Write-Ok "Build repo: $BuildRepo"
Write-Ok "Output: $OutputRoot"

$artifacts = @()
if ($Targets.Contains("Check")) {
    if ($Targets.Contains("Windows")) { Assert-WindowsPrereqs -BuildRepo $BuildRepo }
    if ($Targets.Contains("Android")) { Assert-AndroidPrereqs }
    if (-not $Targets.Contains("Windows") -and -not $Targets.Contains("Android")) {
        Assert-WindowsPrereqs -BuildRepo $BuildRepo
        Assert-AndroidPrereqs
    }
}
else {
    if ($Targets.Contains("Windows")) {
        $artifacts += Build-WindowsArtifacts -BuildRepo $BuildRepo
    }
    if ($Targets.Contains("Android")) {
        $artifacts += Build-AndroidArtifacts -BuildRepo $BuildRepo
    }
}

Show-Summary -Artifacts $artifacts
