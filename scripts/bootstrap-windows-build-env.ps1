param(
    [string]$ToolsRoot = "C:\kq-remote-link-tools",
    [switch]$InstallVcpkgPackages,
    [switch]$InstallMsvcBuildTools,
    [switch]$EnableDeveloperMode
)

$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path $ToolsRoot | Out-Null

function Add-PathForCurrentProcess($PathToAdd) {
    if (-not ($env:Path -split ';' | Where-Object { $_ -eq $PathToAdd })) {
        $env:Path = "$PathToAdd;$env:Path"
    }
}

function Add-UserPath($PathToAdd) {
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not ($current -split ';' | Where-Object { $_ -eq $PathToAdd })) {
        [Environment]::SetEnvironmentVariable("Path", "$PathToAdd;$current", "User")
    }
}

function Download-File($Url, $OutFile) {
    Remove-Item -Force -Path $OutFile -ErrorAction SilentlyContinue
    $expectedLength = $null
    try {
        $headers = curl.exe -L -I --ssl-no-revoke --http1.1 $Url
        $lengthHeader = $headers | Where-Object { $_ -match "^Content-Length:\s*(\d+)" } | Select-Object -Last 1
        if ($lengthHeader -match "^Content-Length:\s*(\d+)") {
            $expectedLength = [int64]$Matches[1]
        }
    } catch {
        $expectedLength = $null
    }

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Remove-Item -Force -Path $OutFile -ErrorAction SilentlyContinue
        curl.exe -L --ssl-no-revoke --http1.1 --retry 5 --retry-delay 2 --retry-all-errors $Url -o $OutFile
        if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt 0 -and ((-not $expectedLength) -or (Get-Item $OutFile).Length -eq $expectedLength)) {
            break
        }

        Remove-Item -Force -Path $OutFile -ErrorAction SilentlyContinue
        $ProgressPreference = "SilentlyContinue"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        try {
            Invoke-WebRequest -Uri $Url -OutFile $OutFile
        } catch {
            if ($attempt -eq 3) {
                throw
            }
        }
        if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt 0 -and ((-not $expectedLength) -or (Get-Item $OutFile).Length -eq $expectedLength)) {
            break
        }
    }

    if (-not (Test-Path $OutFile) -or (Get-Item $OutFile).Length -eq 0) {
        throw "Download failed: $Url"
    }
    if ($expectedLength -and (Get-Item $OutFile).Length -ne $expectedLength) {
        throw "Download failed: $Url expected $expectedLength bytes, got $((Get-Item $OutFile).Length)"
    }
}

function Invoke-GitClone($Url, $Destination, $ExtraArgs = @()) {
    if (Test-Path $Destination) {
        return
    }

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Remove-Item -Recurse -Force -Path $Destination -ErrorAction SilentlyContinue
        git -c http.sslBackend=openssl clone @ExtraArgs $Url $Destination
        if ($LASTEXITCODE -eq 0 -and (Test-Path $Destination)) {
            return
        }
        Start-Sleep -Seconds (5 * $attempt)
    }

    throw "git clone failed: $Url"
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Enable-WindowsDeveloperMode {
    if (-not (Test-IsAdministrator)) {
        throw "Enabling Windows Developer Mode requires an elevated PowerShell session."
    }

    $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
    New-Item -Path $key -Force | Out-Null
    New-ItemProperty `
        -Path $key `
        -Name AllowDevelopmentWithoutDevLicense `
        -PropertyType DWord `
        -Value 1 `
        -Force | Out-Null
    Write-Host "Windows Developer Mode registry flag is enabled."
}

function Install-ZipTool($Name, $Url, $InstallDir, $BinDir) {
    if (Test-Path $BinDir) {
        Add-PathForCurrentProcess $BinDir
        Add-UserPath $BinDir
        return
    }

    $zipPath = Join-Path $ToolsRoot "$Name.zip"
    $extractRoot = Join-Path $ToolsRoot "$Name-extract"
    Remove-Item -Recurse -Force -Path $extractRoot -ErrorAction SilentlyContinue
    Download-File $Url $zipPath
    Remove-Item -Recurse -Force -Path $InstallDir -ErrorAction SilentlyContinue
    Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force
    $root = Get-ChildItem -Path $extractRoot -Directory | Select-Object -First 1
    if ($null -eq $root) {
        $root = Get-Item $extractRoot
    }
    Move-Item -Path $root.FullName -Destination $InstallDir
    Remove-Item -Recurse -Force -Path $extractRoot -ErrorAction SilentlyContinue
    Add-PathForCurrentProcess $BinDir
    Add-UserPath $BinDir
}

if ($EnableDeveloperMode) {
    Enable-WindowsDeveloperMode
}

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    $rustup = Join-Path $ToolsRoot "rustup-init.exe"
    Download-File "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe" $rustup
    & $rustup -y --default-toolchain stable --profile minimal
}

$cargoBin = Join-Path $env:USERPROFILE ".cargo\bin"
Add-PathForCurrentProcess $cargoBin
Add-UserPath $cargoBin

$flutterRoot = Join-Path $ToolsRoot "flutter"
if (-not (Test-Path $flutterRoot)) {
    Invoke-GitClone "https://github.com/flutter/flutter.git" $flutterRoot @("--depth", "1", "--branch", "stable")
}
$flutterBin = Join-Path $flutterRoot "bin"
Add-PathForCurrentProcess $flutterBin
Add-UserPath $flutterBin

Install-ZipTool `
    -Name "cmake-3.29.6-windows-x86_64" `
    -Url "https://github.com/Kitware/CMake/releases/download/v3.29.6/cmake-3.29.6-windows-x86_64.zip" `
    -InstallDir (Join-Path $ToolsRoot "cmake") `
    -BinDir (Join-Path $ToolsRoot "cmake\bin")

Install-ZipTool `
    -Name "ninja-win-1.12.1" `
    -Url "https://github.com/ninja-build/ninja/releases/download/v1.12.1/ninja-win.zip" `
    -InstallDir (Join-Path $ToolsRoot "ninja") `
    -BinDir (Join-Path $ToolsRoot "ninja")

$libclangRoot = Join-Path $ToolsRoot "libclang.runtime.win-x64"
$llvmBin = Join-Path $libclangRoot "runtimes\win-x64\native"
$libclang = Join-Path $llvmBin "libclang.dll"
if (-not (Test-Path $libclang)) {
    $libclangPackage = Join-Path $ToolsRoot "libclang.runtime.win-x64.18.1.3.2.nupkg"
    $libclangZip = Join-Path $ToolsRoot "libclang.runtime.win-x64.18.1.3.2.zip"
    $libclangExtract = Join-Path $ToolsRoot "libclang.runtime.win-x64-extract"
    Remove-Item -Recurse -Force -Path $libclangExtract -ErrorAction SilentlyContinue
    Download-File "https://www.nuget.org/api/v2/package/libclang.runtime.win-x64/18.1.3.2" $libclangPackage
    Copy-Item -Force -Path $libclangPackage -Destination $libclangZip
    Expand-Archive -Path $libclangZip -DestinationPath $libclangExtract -Force
    Remove-Item -Recurse -Force -Path $libclangRoot -ErrorAction SilentlyContinue
    Move-Item -Path $libclangExtract -Destination $libclangRoot
}
Add-PathForCurrentProcess $llvmBin
Add-UserPath $llvmBin
[Environment]::SetEnvironmentVariable("LIBCLANG_PATH", $llvmBin, "User")
$env:LIBCLANG_PATH = $llvmBin

$vcpkgRoot = Join-Path $ToolsRoot "vcpkg"
$vcpkgExe = Join-Path $vcpkgRoot "vcpkg.exe"
if (-not (Test-Path $vcpkgRoot)) {
    try {
        Invoke-GitClone "https://github.com/microsoft/vcpkg.git" $vcpkgRoot @("--depth", "1")
    } catch {
        $vcpkgZip = Join-Path $ToolsRoot "vcpkg-master.zip"
        $vcpkgExtract = Join-Path $ToolsRoot "vcpkg-master-extract"
        Remove-Item -Recurse -Force -Path $vcpkgExtract -ErrorAction SilentlyContinue
        Download-File "https://github.com/microsoft/vcpkg/archive/refs/heads/master.zip" $vcpkgZip
        Expand-Archive -Path $vcpkgZip -DestinationPath $vcpkgExtract -Force
        $vcpkgArchiveRoot = Get-ChildItem -Path $vcpkgExtract -Directory | Select-Object -First 1
        if ($null -eq $vcpkgArchiveRoot) {
            throw "vcpkg archive did not contain a root directory"
        }
        Move-Item -Path $vcpkgArchiveRoot.FullName -Destination $vcpkgRoot
        Remove-Item -Recurse -Force -Path $vcpkgExtract -ErrorAction SilentlyContinue
    }
}
if (-not (Test-Path $vcpkgExe)) {
    & (Join-Path $vcpkgRoot "bootstrap-vcpkg.bat")
}
[Environment]::SetEnvironmentVariable("VCPKG_ROOT", $vcpkgRoot, "User")
$env:VCPKG_ROOT = $vcpkgRoot

if ($InstallVcpkgPackages) {
    & (Join-Path $vcpkgRoot "vcpkg.exe") install `
        libvpx:x64-windows-static `
        libyuv:x64-windows-static `
        opus:x64-windows-static `
        aom:x64-windows-static
}

if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
    if ($InstallMsvcBuildTools) {
        if (-not (Test-IsAdministrator)) {
            throw "MSVC Build Tools installation requires an elevated PowerShell session. Re-run this script as Administrator or install Visual Studio 2022 Build Tools manually."
        }
        $vsInstaller = Join-Path $ToolsRoot "vs_BuildTools.exe"
        Download-File "https://aka.ms/vs/17/release/vs_BuildTools.exe" $vsInstaller
        & $vsInstaller `
            --quiet `
            --wait `
            --norestart `
            --nocache `
            --installPath (Join-Path $ToolsRoot "VSBuildTools") `
            --add Microsoft.VisualStudio.Workload.VCTools `
            --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            --add Microsoft.VisualStudio.Component.Windows11SDK.22621 `
            --includeRecommended
        if ($LASTEXITCODE -ne 0) {
            throw "Visual Studio Build Tools installer failed with exit code $LASTEXITCODE"
        }
    } else {
        Write-Warning "MSVC cl.exe was not found. Re-run with -InstallMsvcBuildTools or install Visual Studio 2022 Build Tools with the Desktop development with C++ workload before building."
    }
}

Write-Host "Bootstrap finished. Open a new PowerShell window, then run scripts/check-build-env.ps1."
