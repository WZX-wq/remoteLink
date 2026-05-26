$ErrorActionPreference = "Stop"

function Import-VsDevCmd {
    if (Get-Command cl -ErrorAction SilentlyContinue) {
        return
    }
    $existingVcpkgRoot = $env:VCPKG_ROOT

    $candidates = @(
        "C:\kq-remote-link-tools\VSBuildTools\Common7\Tools\VsDevCmd.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat"
    )

    $vswherePaths = @(
        "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe",
        "C:\Program Files\Microsoft Visual Studio\Installer\vswhere.exe"
    )
    foreach ($vswhere in $vswherePaths) {
        if (Test-Path $vswhere) {
            $installationPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
            if ($installationPath) {
                $candidates += (Join-Path $installationPath "Common7\Tools\VsDevCmd.bat")
            }
        }
    }

    $vsDevCmd = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $vsDevCmd) {
        return
    }

    $envLines = cmd.exe /c "`"$vsDevCmd`" -arch=x64 -host_arch=x64 >nul && set"
    foreach ($line in $envLines) {
        $index = $line.IndexOf("=")
        if ($index -gt 0) {
            [Environment]::SetEnvironmentVariable($line.Substring(0, $index), $line.Substring($index + 1), "Process")
        }
    }
    if ($existingVcpkgRoot) {
        $env:VCPKG_ROOT = $existingVcpkgRoot
    }
}

Import-VsDevCmd

function Import-Libclang {
    $candidates = @()
    if ($env:LIBCLANG_PATH) {
        $candidates += $env:LIBCLANG_PATH
    }
    $candidates += @(
        "C:\kq-remote-link-tools\libclang.runtime.win-x64\runtimes\win-x64\native",
        "C:\kq-remote-link-tools\LLVM\bin",
        "C:\Program Files\LLVM\bin"
    )

    $libclangDir = $candidates | Where-Object { Test-Path (Join-Path $_ "libclang.dll") } | Select-Object -First 1
    if ($libclangDir) {
        $env:LIBCLANG_PATH = $libclangDir
        if (-not ($env:Path -split ';' | Where-Object { $_ -eq $libclangDir })) {
            $env:Path = "$libclangDir;$env:Path"
        }
    }
}

Import-Libclang

function Test-SymlinkSupport {
    $root = Join-Path $env:TEMP "kq-symlink-check"
    $target = Join-Path $root "target.txt"
    $link = Join-Path $root "link.txt"
    try {
        Remove-Item -Recurse -Force -Path $root -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        Set-Content -Path $target -Value "ok"
        New-Item -ItemType SymbolicLink -Path $link -Target $target -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    } finally {
        Remove-Item -Recurse -Force -Path $root -ErrorAction SilentlyContinue
    }
}

$commands = @(
    "git",
    "python",
    "cargo",
    "rustc",
    "flutter",
    "dart",
    "cmake",
    "ninja",
    "cl"
)

$missing = @()
foreach ($command in $commands) {
    $found = Get-Command $command -ErrorAction SilentlyContinue
    if ($null -eq $found) {
        $missing += $command
        Write-Host "[missing] $command"
    } else {
        Write-Host "[ok]      $command -> $($found.Source)"
    }
}

if (-not $env:VCPKG_ROOT) {
    Write-Host "[missing] VCPKG_ROOT environment variable"
    $missing += "VCPKG_ROOT"
} else {
    Write-Host "[ok]      VCPKG_ROOT -> $env:VCPKG_ROOT"
}

if (-not $env:KQ_CUSTOM_CLIENT_PUBKEY) {
    Write-Host "[warn]    KQ_CUSTOM_CLIENT_PUBKEY is not set; default RustDesk custom-client signing key will be used"
} else {
    Write-Host "[ok]      KQ_CUSTOM_CLIENT_PUBKEY is set"
}

if (-not $env:LIBCLANG_PATH -or -not (Test-Path (Join-Path $env:LIBCLANG_PATH "libclang.dll"))) {
    Write-Host "[missing] LIBCLANG_PATH / libclang.dll"
    $missing += "LIBCLANG_PATH / libclang.dll"
} else {
    Write-Host "[ok]      LIBCLANG_PATH -> $env:LIBCLANG_PATH"
}

if (Test-SymlinkSupport) {
    Write-Host "[ok]      Windows symlink support"
} else {
    Write-Host "[missing] Windows symlink support / Developer Mode"
    $missing += "Windows symlink support / Developer Mode"
}

if ($missing.Count -gt 0) {
    Write-Error "Missing build requirements: $($missing -join ', ')"
}

Write-Host "Build environment check passed."
