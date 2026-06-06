param(
    [string]$ReleaseDir,
    [string]$OutputRoot = "C:\kq-remote-link-tools",
    [string]$InstallerName,
    [string]$Version = (Get-Date -Format "yyyy.MM.dd.HHmm"),
    [string]$CargoFeatures = "flutter,hwcodec,vram",
    [switch]$SkipFlutterBuild,
    [switch]$SkipCargoBuild
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

if (-not $ReleaseDir) {
    $ReleaseDir = Join-Path $repo "flutter\build\windows\x64\runner\Release"
}
if (-not $InstallerName) {
    $InstallerName = "Kunqiong-Remote-Desktop-Setup-$(Get-Date -Format 'yyyyMMdd-HHmm')"
}
$InstallerName = [System.IO.Path]::GetFileNameWithoutExtension($InstallerName)

$output = New-Item -ItemType Directory -Force -Path $OutputRoot
$buildRoot = Join-Path $output.FullName "$InstallerName-inno-build"
$issPath = Join-Path $buildRoot "installer.iss"
$iconPath = Join-Path $repo "flutter\windows\runner\resources\app_icon.ico"
$wizardSmallImagePath = Join-Path $repo "res\installer-small.bmp"
$wizardImagePath = Join-Path $repo "res\installer-side.bmp"
$iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
$chineseMessagesSourcePath = Join-Path $repo "scripts\installer\ChineseSimplified.isl"

if (-not (Test-Path $iscc)) {
    throw "Inno Setup compiler not found: $iscc"
}
if (-not (Test-Path $iconPath)) {
    throw "Installer icon not found: $iconPath"
}
if (-not (Test-Path $wizardSmallImagePath)) {
    throw "Installer small wizard image not found: $wizardSmallImagePath"
}
if (-not (Test-Path $wizardImagePath)) {
    throw "Installer wizard image not found: $wizardImagePath"
}
if (-not (Test-Path $chineseMessagesSourcePath)) {
    throw "Chinese installer language file not found: $chineseMessagesSourcePath"
}

function Build-RustLibrary {
    if ([string]::IsNullOrWhiteSpace($CargoFeatures)) {
        throw "CargoFeatures must not be empty"
    }
    $featureSet = @($CargoFeatures -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($featureSet -contains "hwcodec") {
        if (-not $env:VCPKG_ROOT) {
            $defaultVcpkgRoot = Join-Path $OutputRoot "vcpkg"
            if (Test-Path $defaultVcpkgRoot) {
                $env:VCPKG_ROOT = $defaultVcpkgRoot
            }
        }
        if (-not $env:VCPKG_ROOT) {
            throw "VCPKG_ROOT is required when CargoFeatures contains hwcodec"
        }
        $vcpkgTriplet = Join-Path $env:VCPKG_ROOT "installed\x64-windows-static"
        $requiredVcpkgFiles = @(
            "include\libavutil\pixfmt.h",
            "lib\avcodec.lib",
            "lib\avformat.lib",
            "lib\avutil.lib",
            "lib\libmfx.lib"
        )
        foreach ($item in $requiredVcpkgFiles) {
            $path = Join-Path $vcpkgTriplet $item
            if (-not (Test-Path $path)) {
                throw "Missing hwcodec build dependency: $path. Run vcpkg install `"ffmpeg[amf,nvcodec,qsv]:x64-windows-static`" --classic --overlay-ports=`"$repo\res\vcpkg`" --recurse"
            }
        }
    }

    Write-Host "Building Rust library with features: $CargoFeatures"
    & cargo build --features $CargoFeatures --lib --release
    if ($LASTEXITCODE -ne 0) {
        throw "cargo build failed with exit code $LASTEXITCODE"
    }
    $freshDll = Join-Path $repo "target\release\librustdesk.dll"
    if (-not (Test-Path $freshDll)) {
        throw "cargo build did not produce $freshDll"
    }
    return $freshDll
}

$freshRustDll = $null
if (-not $SkipCargoBuild) {
    # Flutter's Windows CMake install copies target\release\librustdesk.dll,
    # so the Rust library must exist before `flutter build windows`.
    $freshRustDll = Build-RustLibrary
}

if (-not $SkipFlutterBuild) {
    Push-Location (Join-Path $repo "flutter")
    try {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) {
            throw "flutter build failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

$release = Resolve-Path $ReleaseDir

if (-not $SkipCargoBuild) {
    Copy-Item -LiteralPath $freshRustDll -Destination (Join-Path $release.Path "librustdesk.dll") -Force
}

function Test-PathUnderRoot([string]$Path, [string]$Root) {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($Root)
    if (-not $fullRoot.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $fullRoot = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    }
    return $fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

function Remove-ItemUnderRoot([string]$Path, [string]$Root) {
    if (-not (Test-Path $Path)) {
        return
    }
    if (-not (Test-PathUnderRoot -Path $Path -Root $Root)) {
        throw "Refusing to remove path outside root. Path=$Path Root=$Root"
    }
    Remove-Item -LiteralPath $Path -Recurse -Force
}

function Get-Sha256FromSums([string]$SumsPath, [string]$FileName) {
    $pattern = "^([a-fA-F0-9]{64}) \*$([regex]::Escape($FileName))$"
    $match = Select-String -Path $SumsPath -Pattern $pattern | Select-Object -First 1
    if (-not $match) {
        throw "sha256sums does not include $FileName"
    }
    return $match.Matches.Groups[1].Value.ToUpperInvariant()
}

function Invoke-DownloadFile([string]$Uri, [string]$OutFile) {
    $tmp = "$OutFile.download"
    if (Test-Path $tmp) {
        Remove-Item -LiteralPath $tmp -Force
    }
    Invoke-WebRequest -Uri $Uri -OutFile $tmp -UseBasicParsing
    Move-Item -LiteralPath $tmp -Destination $OutFile -Force
}

function Ensure-CachedDownload([string]$Uri, [string]$OutFile) {
    if (Test-Path $OutFile) {
        Write-Host "Using cached file: $OutFile"
        return
    }
    Invoke-DownloadFile -Uri $Uri -OutFile $OutFile
}

function Ensure-RemotePrinterArtifacts([string]$ReleasePath, [string]$CacheRoot) {
    $driverInf = Join-Path $ReleasePath "drivers\RustDeskPrinterDriver\RustDeskPrinterDriver.inf"
    $adapterDll = Join-Path $ReleasePath "printer_driver_adapter.dll"
    if ((Test-Path $driverInf) -and (Test-Path $adapterDll)) {
        Write-Host "Remote printer artifacts already exist in release directory."
        return
    }

    Write-Host "Preparing remote printer driver artifacts."
    New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null

    $driverZipName = "rustdesk_printer_driver_v4-1.4.zip"
    $adapterZipName = "printer_driver_adapter.zip"
    $driverZip = Join-Path $CacheRoot $driverZipName
    $adapterZip = Join-Path $CacheRoot $adapterZipName
    $sha256Sums = Join-Path $CacheRoot "sha256sums"
    $baseUri = "https://github.com/rustdesk/hbb_common/releases/download/driver"

    Ensure-CachedDownload -Uri "$baseUri/$driverZipName" -OutFile $driverZip
    Ensure-CachedDownload -Uri "$baseUri/$adapterZipName" -OutFile $adapterZip
    Ensure-CachedDownload -Uri "$baseUri/sha256sums" -OutFile $sha256Sums

    $expectedDriver = Get-Sha256FromSums -SumsPath $sha256Sums -FileName $driverZipName
    $actualDriver = (Get-FileHash -Algorithm SHA256 -LiteralPath $driverZip).Hash.ToUpperInvariant()
    if ($actualDriver -ne $expectedDriver) {
        throw "$driverZipName checksum mismatch. Expected $expectedDriver, got $actualDriver"
    }

    $expectedAdapter = Get-Sha256FromSums -SumsPath $sha256Sums -FileName $adapterZipName
    $actualAdapter = (Get-FileHash -Algorithm SHA256 -LiteralPath $adapterZip).Hash.ToUpperInvariant()
    if ($actualAdapter -ne $expectedAdapter) {
        throw "$adapterZipName checksum mismatch. Expected $expectedAdapter, got $actualAdapter"
    }

    $extractRoot = Join-Path $CacheRoot "extract"
    Remove-ItemUnderRoot -Path $extractRoot -Root $CacheRoot
    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null

    $driverExtract = Join-Path $extractRoot "driver"
    $adapterExtract = Join-Path $extractRoot "adapter"
    New-Item -ItemType Directory -Force -Path $driverExtract | Out-Null
    New-Item -ItemType Directory -Force -Path $adapterExtract | Out-Null
    Expand-Archive -LiteralPath $driverZip -DestinationPath $driverExtract -Force
    Expand-Archive -LiteralPath $adapterZip -DestinationPath $adapterExtract -Force

    $driverSource = Join-Path $driverExtract "rustdesk_printer_driver_v4-1.4"
    $adapterSource = Join-Path $adapterExtract "printer_driver_adapter.dll"
    if (-not (Test-Path (Join-Path $driverSource "RustDeskPrinterDriver.inf"))) {
        throw "Downloaded printer driver archive does not contain RustDeskPrinterDriver.inf"
    }
    if (-not (Test-Path $adapterSource)) {
        throw "Downloaded printer adapter archive does not contain printer_driver_adapter.dll"
    }

    $driverTarget = Join-Path $ReleasePath "drivers\RustDeskPrinterDriver"
    Remove-ItemUnderRoot -Path $driverTarget -Root $ReleasePath
    New-Item -ItemType Directory -Force -Path $driverTarget | Out-Null
    Get-ChildItem -LiteralPath $driverSource -Force |
        Copy-Item -Destination $driverTarget -Recurse -Force
    Copy-Item -LiteralPath $adapterSource -Destination $adapterDll -Force

    if (-not (Test-Path $driverInf)) {
        throw "Remote printer driver INF was not copied to release: $driverInf"
    }
    if (-not (Test-Path $adapterDll)) {
        throw "Remote printer adapter DLL was not copied to release: $adapterDll"
    }
}

Ensure-RemotePrinterArtifacts `
    -ReleasePath $release.Path `
    -CacheRoot (Join-Path $OutputRoot "printer-driver-cache")

$required = @(
    "rustdesk.exe",
    "librustdesk.dll",
    "flutter_windows.dll",
    "data\flutter_assets\AssetManifest.bin",
    "data\flutter_assets\assets\icon.png",
    "data\flutter_assets\assets\icon.ico",
    "data\flutter_assets\assets\kq_toolbox_icon.svg",
    "drivers\RustDeskPrinterDriver\RustDeskPrinterDriver.inf",
    "printer_driver_adapter.dll"
)
foreach ($item in $required) {
    $path = Join-Path $release.Path $item
    if (-not (Test-Path $path)) {
        throw "Missing release artifact: $path"
    }
}

if (Test-Path $buildRoot) {
    $resolvedBuildRoot = (Resolve-Path $buildRoot).Path
    if (-not $resolvedBuildRoot.StartsWith($output.FullName, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove unexpected build path: $resolvedBuildRoot"
    }
    Remove-Item -LiteralPath $resolvedBuildRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null

$appName = [string]::Concat([char[]]@(0x9CB2, 0x7A79, 0x8FDC, 0x7A0B, 0x684C, 0x9762))
$legacyAppName = [string]::Concat([char[]]@(0x9CB2, 0x7A79, 0x5DE5, 0x5177, 0x7BB1))
$cnUpgradeCaption = [string]::Concat([char[]]@(0x5347, 0x7EA7, 0x0020, 0x002D, 0x0020, 0x007B, 0x0023, 0x004D, 0x0079, 0x0041, 0x0070, 0x0070, 0x004E, 0x0061, 0x006D, 0x0065, 0x007D))
$cnWelcomeTitle = [string]::Concat([char[]]@(0x6B22, 0x8FCE, 0x4F7F, 0x7528, 0x0020, 0x007B, 0x0023, 0x004D, 0x0079, 0x0041, 0x0070, 0x0070, 0x004E, 0x0061, 0x006D, 0x0065, 0x007D, 0x0020, 0x5347, 0x7EA7, 0x5411, 0x5BFC))
$cnWelcomeLine1 = [string]::Concat([char[]]@(0x5C06, 0x628A, 0x60A8, 0x7535, 0x8111, 0x4E0A, 0x7684, 0x0020, 0x007B, 0x0023, 0x004D, 0x0079, 0x0041, 0x0070, 0x0070, 0x004E, 0x0061, 0x006D, 0x0065, 0x007D, 0x0020, 0x5347, 0x7EA7, 0x5230, 0x7248, 0x672C, 0x0020, 0x007B, 0x0023, 0x004D, 0x0079, 0x0041, 0x0070, 0x0070, 0x0056, 0x0065, 0x0072, 0x0073, 0x0069, 0x006F, 0x006E, 0x007D, 0x3002))
$cnUpgradePath = [string]::Concat([char[]]@(0x5F53, 0x524D, 0x5347, 0x7EA7, 0x8DEF, 0x5F84, 0xFF1A))
$cnVersion = [string]::Concat([char[]]@(0x7248, 0x672C, 0xFF1A))
$cnWelcomeLine2 = [string]::Concat([char[]]@(0x5347, 0x7EA7, 0x4F1A, 0x4FDD, 0x7559, 0x539F, 0x5B89, 0x88C5, 0x76EE, 0x5F55, 0x3001, 0x767B, 0x5F55, 0x72B6, 0x6001, 0x548C, 0x73B0, 0x6709, 0x8BBE, 0x7F6E, 0x3002, 0x5EFA, 0x8BAE, 0x60A8, 0x5728, 0x7EE7, 0x7EED, 0x524D, 0x5173, 0x95ED, 0x5176, 0x4ED6, 0x5E94, 0x7528, 0x7A0B, 0x5E8F, 0x3002))
$cnReadyTitle = [string]::Concat([char[]]@(0x51C6, 0x5907, 0x5347, 0x7EA7))
$cnReadyDesc = [string]::Concat([char[]]@(0x5B89, 0x88C5, 0x7A0B, 0x5E8F, 0x51C6, 0x5907, 0x5C31, 0x7EEA, 0xFF0C, 0x73B0, 0x5728, 0x53EF, 0x4EE5, 0x5F00, 0x59CB, 0x5347, 0x7EA7, 0x0020, 0x007B, 0x0023, 0x004D, 0x0079, 0x0041, 0x0070, 0x0070, 0x004E, 0x0061, 0x006D, 0x0065, 0x007D, 0x3002))
$cnReadyBody = [string]::Concat([char[]]@(0x70B9, 0x51FB, 0x201C, 0x5347, 0x7EA7, 0x201D, 0x7EE7, 0x7EED, 0x3002, 0x5B89, 0x88C5, 0x7A0B, 0x5E8F, 0x4F1A, 0x81EA, 0x52A8, 0x5173, 0x95ED, 0x6B63, 0x5728, 0x8FD0, 0x884C, 0x7684, 0x0020, 0x007B, 0x0023, 0x004D, 0x0079, 0x0041, 0x0070, 0x0070, 0x004E, 0x0061, 0x006D, 0x0065, 0x007D, 0xFF0C, 0x5E76, 0x5728, 0x539F, 0x76EE, 0x5F55, 0x5B8C, 0x6210, 0x6587, 0x4EF6, 0x66F4, 0x65B0, 0x3002))
$cnNextButton = [string]::Concat([char[]]@(0x4E0B, 0x4E00, 0x6B65, 0x0028, 0x0026, 0x004E, 0x0029, 0x0020, 0x003E))
$cnUpgradeButton = [string]::Concat([char[]]@(0x5347, 0x7EA7, 0x0028, 0x0026, 0x0055, 0x0029))
$cnInstallingTitle = [string]::Concat([char[]]@(0x6B63, 0x5728, 0x5347, 0x7EA7))
$cnInstallingDesc = [string]::Concat([char[]]@(0x5B89, 0x88C5, 0x7A0B, 0x5E8F, 0x6B63, 0x5728, 0x5347, 0x7EA7, 0x0020, 0x007B, 0x0023, 0x004D, 0x0079, 0x0041, 0x0070, 0x0070, 0x004E, 0x0061, 0x006D, 0x0065, 0x007D, 0x3002))
$cnInstallingStatus = [string]::Concat([char[]]@(0x6B63, 0x5728, 0x5347, 0x7EA7, 0x0020, 0x007B, 0x0023, 0x004D, 0x0079, 0x0041, 0x0070, 0x0070, 0x004E, 0x0061, 0x006D, 0x0065, 0x007D, 0xFF0C, 0x8BF7, 0x7A0D, 0x5019, 0x3002))
$cnFinishedTitle = [string]::Concat([char[]]@(0x007B, 0x0023, 0x004D, 0x0079, 0x0041, 0x0070, 0x0070, 0x004E, 0x0061, 0x006D, 0x0065, 0x007D, 0x0020, 0x5347, 0x7EA7, 0x5B8C, 0x6210))
$cnFinishedBody1 = [string]::Concat([char[]]@(0x007B, 0x0023, 0x004D, 0x0079, 0x0041, 0x0070, 0x0070, 0x004E, 0x0061, 0x006D, 0x0065, 0x007D, 0x0020, 0x5DF2, 0x6210, 0x529F, 0x5347, 0x7EA7, 0x5230, 0x7248, 0x672C, 0x0020, 0x007B, 0x0023, 0x004D, 0x0079, 0x0041, 0x0070, 0x0070, 0x0056, 0x0065, 0x0072, 0x0073, 0x0069, 0x006F, 0x006E, 0x007D, 0x3002))
$cnFinishedBody2 = [string]::Concat([char[]]@(0x539F, 0x5B89, 0x88C5, 0x76EE, 0x5F55, 0x548C, 0x73B0, 0x6709, 0x8BBE, 0x7F6E, 0x5DF2, 0x4FDD, 0x7559, 0x3002))
$escapedRelease = $release.Path.Replace('\', '\\')
$escapedOutput = $output.FullName.Replace('\', '\\')
$escapedIcon = $iconPath.Replace('\', '\\')
$escapedWizardSmallImage = $wizardSmallImagePath.Replace('\', '\\')
$escapedWizardImage = $wizardImagePath.Replace('\', '\\')
$chineseMessagesPath = Join-Path $buildRoot "ChineseSimplified.isl"
$escapedChineseMessages = $chineseMessagesPath.Replace('\', '\\')

$iss = @"
#define MyAppName "$appName"
#define LegacyAppName "$legacyAppName"
#define MyAppExeName "rustdesk.exe"
#define MyAppPublisher "Kunqiong"
#define MyAppVersion "$Version"

[Setup]
AppId={{D0B24C8B-7E7E-4B2C-9A38-0B2026052701}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={code:GetDefaultInstallDir}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=$escapedOutput
OutputBaseFilename=$InstallerName
SetupIconFile=$escapedIcon
WizardSmallImageFile=$escapedWizardSmallImage
WizardImageFile=$escapedWizardImage
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
CloseApplicationsFilter=rustdesk.exe
ShowLanguageDialog=no
LanguageDetectionMethod=uilanguage
UsePreviousAppDir=yes
UsePreviousGroup=yes
UsePreviousLanguage=yes
UsePreviousTasks=yes
DisableWelcomePage=no

[Languages]
Name: "chinesesimp"; MessagesFile: "$escapedChineseMessages"
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce
Name: "startup"; Description: "{cm:AutoStartProgram,{#MyAppName}}"; GroupDescription: "{cm:AutoStartProgramGroupDescription}"; Flags: unchecked
Name: "launch"; Description: "{cm:LaunchProgram,{#MyAppName}}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "$escapedRelease\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{commonstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: startup

[Run]
Filename: "{app}\{#MyAppExeName}"; Parameters: "--local-option lang {code:SelectedAppLanguage}"; Flags: runhidden waituntilterminated; Check: KqIsFreshInstall
Filename: "{app}\{#MyAppExeName}"; Parameters: "--local-option enable-udp-punch Y"; Flags: runhidden waituntilterminated; Check: KqIsFreshInstall
Filename: "{app}\{#MyAppExeName}"; Parameters: "--local-option kq-force-always-relay N"; Flags: runhidden waituntilterminated; Check: KqIsFreshInstall
Filename: "{sys}\reg.exe"; Parameters: "add HKEY_CLASSES_ROOT\kqremote /f /v ""URL Protocol"" /t REG_SZ /d """""; Flags: runhidden waituntilterminated
Filename: "{sys}\reg.exe"; Parameters: "add HKEY_CLASSES_ROOT\kqremote\shell\open\command /f /ve /t REG_SZ /d ""\""{app}\{#MyAppExeName}\"" \""%1\"""""; Flags: runhidden waituntilterminated
Filename: "{sys}\reg.exe"; Parameters: "add HKEY_CLASSES_ROOT\rustdesk /f /v ""URL Protocol"" /t REG_SZ /d """""; Flags: runhidden waituntilterminated
Filename: "{sys}\reg.exe"; Parameters: "add HKEY_CLASSES_ROOT\rustdesk\shell\open\command /f /ve /t REG_SZ /d ""\""{app}\{#MyAppExeName}\"" \""%1\"""""; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""KQRemoteLink TCP In"""; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""KQRemoteLink TCP Out"""; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""KQRemoteLink UDP In"""; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""KQRemoteLink UDP Out"""; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""KQRemoteLink TCP In"" dir=in action=allow program=""{app}\{#MyAppExeName}"" enable=yes profile=any protocol=TCP"; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""KQRemoteLink TCP Out"" dir=out action=allow program=""{app}\{#MyAppExeName}"" enable=yes profile=any protocol=TCP"; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""KQRemoteLink UDP In"" dir=in action=allow program=""{app}\{#MyAppExeName}"" enable=yes profile=any protocol=UDP"; Flags: runhidden waituntilterminated
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""KQRemoteLink UDP Out"" dir=out action=allow program=""{app}\{#MyAppExeName}"" enable=yes profile=any protocol=UDP"; Flags: runhidden waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Parameters: "--install-service --no-launch"; Flags: runhidden waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent; Tasks: launch; Check: KqIsFreshInstall

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""KQRemoteLink TCP In"""; Flags: runhidden waituntilterminated; RunOnceId: "KQDeleteFirewallTcpIn"
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""KQRemoteLink TCP Out"""; Flags: runhidden waituntilterminated; RunOnceId: "KQDeleteFirewallTcpOut"
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""KQRemoteLink UDP In"""; Flags: runhidden waituntilterminated; RunOnceId: "KQDeleteFirewallUdpIn"
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""KQRemoteLink UDP Out"""; Flags: runhidden waituntilterminated; RunOnceId: "KQDeleteFirewallUdpOut"
Filename: "{sys}\reg.exe"; Parameters: "delete HKEY_CLASSES_ROOT\kqremote /f"; Flags: runhidden waituntilterminated; RunOnceId: "KQDeleteKqRemoteProtocol"
Filename: "{sys}\reg.exe"; Parameters: "delete HKEY_CLASSES_ROOT\rustdesk /f"; Flags: runhidden waituntilterminated; RunOnceId: "KQDeleteRustDeskProtocol"
Filename: "{app}\{#MyAppExeName}"; Parameters: "--uninstall-service"; Flags: runhidden waituntilterminated; RunOnceId: "KQUninstallService"

[Code]
var
  KqUpgradeInstall: Boolean;
  KqExistingInstallDir: String;
  KqLegacyInstallDir: String;
  KqExistingVersion: String;

function KqUninstallKey(): String;
begin
  Result := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{D0B24C8B-7E7E-4B2C-9A38-0B2026052701}_is1';
end;

function KqLegacyUninstallKey(): String;
begin
  Result := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\KQRemoteLink';
end;

function KqReadInstalledString(ValueName: String; var Value: String): Boolean;
begin
  Result := RegQueryStringValue(HKLM, KqUninstallKey(), ValueName, Value);
  if not Result then
    Result := RegQueryStringValue(HKCU, KqUninstallKey(), ValueName, Value);
end;

function KqNextVersionPart(var Version: String): Integer;
var
  Dot: Integer;
  Part: String;
begin
  Dot := Pos('.', Version);
  if Dot = 0 then begin
    Part := Version;
    Version := '';
  end else begin
    Part := Copy(Version, 1, Dot - 1);
    Delete(Version, 1, Dot);
  end;
  Result := StrToIntDef(Part, 0);
end;

function KqCompareVersions(Left: String; Right: String): Integer;
var
  I: Integer;
  LeftPart: Integer;
  RightPart: Integer;
begin
  Result := 0;
  for I := 1 to 4 do begin
    LeftPart := KqNextVersionPart(Left);
    RightPart := KqNextVersionPart(Right);
    if LeftPart > RightPart then begin
      Result := 1;
      Exit;
    end;
    if LeftPart < RightPart then begin
      Result := -1;
      Exit;
    end;
  end;
end;

function InitializeSetup(): Boolean;
var
  LegacyVersion: String;
begin
  Result := True;
  KqUpgradeInstall := False;
  KqExistingInstallDir := '';
  KqLegacyInstallDir := '';
  KqExistingVersion := '';

  if KqReadInstalledString('DisplayVersion', KqExistingVersion) then begin
    KqUpgradeInstall := True;
    KqReadInstalledString('InstallLocation', KqExistingInstallDir);
  end else begin
    if RegQueryStringValue(HKCU, KqLegacyUninstallKey(), 'InstallLocation', KqLegacyInstallDir) then begin
      KqUpgradeInstall := True;
      RegQueryStringValue(HKCU, KqLegacyUninstallKey(), 'DisplayVersion', LegacyVersion);
      KqExistingVersion := LegacyVersion;
    end;
  end;

  if (KqExistingVersion <> '') and (KqCompareVersions(KqExistingVersion, '{#MyAppVersion}') > 0) then begin
    MsgBox('{#MyAppName} is already installed with a newer version: ' + KqExistingVersion + '. Please uninstall it before installing an older package.', mbError, MB_OK);
    Result := False;
  end;
end;

function KqIsUpgrade(): Boolean;
begin
  Result := KqUpgradeInstall;
end;

function KqIsFreshInstall(): Boolean;
begin
  Result := not KqUpgradeInstall;
end;

function KqIsChineseInstaller(): Boolean;
begin
  Result := ActiveLanguage = 'chinesesimp';
end;

function KqUpgradeVersionText(): String;
begin
  if KqExistingVersion <> '' then
    Result := KqExistingVersion + ' -> {#MyAppVersion}'
  else
    Result := '{#MyAppVersion}';
end;

function GetDefaultInstallDir(Param: String): String;
begin
  if KqExistingInstallDir <> '' then
    Result := KqExistingInstallDir
  else if KqLegacyInstallDir <> '' then
    Result := KqLegacyInstallDir
  else
    Result := ExpandConstant('{autopf}\KQRemoteLink');
end;

procedure ExecQuiet(FileName: String; Params: String);
var
  ResultCode: Integer;
begin
  Exec(FileName, Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure StopExistingKqRuntimeForInstall();
begin
  ExecQuiet(ExpandConstant('{sys}\sc.exe'), 'stop "{#MyAppName}"');
  ExecQuiet(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#MyAppExeName} /T');
  Sleep(1200);
  ExecQuiet(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#MyAppExeName} /T');
end;

procedure StopExistingKqRuntimeForUninstall();
var
  AppExe: String;
begin
  AppExe := ExpandConstant('{app}\{#MyAppExeName}');
  if FileExists(AppExe) then begin
    ExecQuiet(AppExe, '--uninstall-service');
  end;

  ExecQuiet(ExpandConstant('{sys}\sc.exe'), 'stop "{#MyAppName}"');
  ExecQuiet(ExpandConstant('{sys}\sc.exe'), 'delete "{#MyAppName}"');
  ExecQuiet(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#MyAppExeName} /T');
  Sleep(1200);
  ExecQuiet(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#MyAppExeName} /T');
  ExecQuiet(ExpandConstant('{sys}\sc.exe'), 'delete "{#MyAppName}"');
end;

procedure CleanupLegacyInstallRegistration();
begin
  RegDeleteKeyIncludingSubkeys(HKCU, KqLegacyUninstallKey());
end;

procedure CleanupLegacyUserShortcuts();
var
  LegacyAppName: String;
begin
  LegacyAppName := '{#LegacyAppName}';
  DeleteFile(ExpandConstant('{userdesktop}\{#MyAppName}.lnk'));
  DeleteFile(ExpandConstant('{userdesktop}\' + LegacyAppName + '.lnk'));
  DeleteFile(ExpandConstant('{userstartup}\{#MyAppName}.lnk'));
  DeleteFile(ExpandConstant('{userstartup}\' + LegacyAppName + '.lnk'));
  DeleteFile(ExpandConstant('{userprograms}\{#MyAppName}\{#MyAppName}.lnk'));
  DeleteFile(ExpandConstant('{userprograms}\' + LegacyAppName + '\' + LegacyAppName + '.lnk'));
  DelTree(ExpandConstant('{userprograms}\{#MyAppName}'), True, True, True);
  DelTree(ExpandConstant('{userprograms}\' + LegacyAppName), True, True, True);
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if KqIsUpgrade() then begin
    if (PageID = wpSelectDir) or (PageID = wpSelectProgramGroup) or (PageID = wpSelectTasks) then
      Result := True;
  end;
end;

procedure ApplyUpgradeWizardText(CurPageID: Integer);
begin
  if not KqIsUpgrade() then
    Exit;

  if KqIsChineseInstaller() then begin
    WizardForm.Caption := '$cnUpgradeCaption';

    if CurPageID = wpWelcome then begin
      WizardForm.WelcomeLabel1.Caption := '$cnWelcomeTitle';
      WizardForm.WelcomeLabel2.Caption :=
        '$cnWelcomeLine1' + #13#10#13#10 +
        '$cnUpgradePath' + GetDefaultInstallDir('') + #13#10 +
        '$cnVersion' + KqUpgradeVersionText() + #13#10#13#10 +
        '$cnWelcomeLine2';
      WizardForm.NextButton.Caption := '$cnNextButton';
    end else if CurPageID = wpReady then begin
      WizardForm.PageNameLabel.Caption := '$cnReadyTitle';
      WizardForm.PageDescriptionLabel.Caption := '$cnReadyDesc';
      WizardForm.ReadyLabel.Caption :=
        '$cnReadyBody';
      WizardForm.NextButton.Caption := '$cnUpgradeButton';
    end else if CurPageID = wpInstalling then begin
      WizardForm.PageNameLabel.Caption := '$cnInstallingTitle';
      WizardForm.PageDescriptionLabel.Caption := '$cnInstallingDesc';
      WizardForm.StatusLabel.Caption := '$cnInstallingStatus';
    end else if CurPageID = wpFinished then begin
      WizardForm.FinishedHeadingLabel.Caption := '$cnFinishedTitle';
      WizardForm.FinishedLabel.Caption :=
        '$cnFinishedBody1' + #13#10#13#10 +
        '$cnFinishedBody2';
    end;
  end else begin
    WizardForm.Caption := 'Upgrade - {#MyAppName}';

    if CurPageID = wpWelcome then begin
      WizardForm.WelcomeLabel1.Caption := 'Welcome to the {#MyAppName} Upgrade Wizard';
      WizardForm.WelcomeLabel2.Caption :=
        'This wizard will upgrade {#MyAppName} to version {#MyAppVersion}.' + #13#10#13#10 +
        'Upgrade path: ' + GetDefaultInstallDir('') + #13#10 +
        'Version: ' + KqUpgradeVersionText() + #13#10#13#10 +
        'Your existing install directory, login state, and settings will be preserved.';
      WizardForm.NextButton.Caption := '&Next >';
    end else if CurPageID = wpReady then begin
      WizardForm.PageNameLabel.Caption := 'Ready to Upgrade';
      WizardForm.PageDescriptionLabel.Caption := 'Setup is ready to upgrade {#MyAppName}.';
      WizardForm.ReadyLabel.Caption :=
        'Click Upgrade to continue. Setup will close the running app and update files in the existing directory.';
      WizardForm.NextButton.Caption := '&Upgrade';
    end else if CurPageID = wpInstalling then begin
      WizardForm.PageNameLabel.Caption := 'Upgrading';
      WizardForm.PageDescriptionLabel.Caption := 'Setup is upgrading {#MyAppName}.';
      WizardForm.StatusLabel.Caption := 'Upgrading {#MyAppName}, please wait.';
    end else if CurPageID = wpFinished then begin
      WizardForm.FinishedHeadingLabel.Caption := '{#MyAppName} Upgrade Complete';
      WizardForm.FinishedLabel.Caption :=
        '{#MyAppName} has been upgraded to version {#MyAppVersion}.' + #13#10#13#10 +
        'Your existing install directory and settings were preserved.';
    end;
  end;
end;

procedure InitializeWizard();
begin
  ApplyUpgradeWizardText(wpWelcome);
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  ApplyUpgradeWizardText(CurPageID);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then begin
    StopExistingKqRuntimeForInstall();
  end else if CurStep = ssPostInstall then begin
    CleanupLegacyInstallRegistration();
    CleanupLegacyUserShortcuts();
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then begin
    StopExistingKqRuntimeForUninstall();
  end;
end;

function SelectedAppLanguage(Param: String): String;
var
  Lang: String;
begin
  Lang := ActiveLanguage;
  if Lang = 'chinesesimp' then
    Result := 'zh-cn'
  else if Lang = 'english' then
    Result := 'en'
  else if Lang = 'french' then
    Result := 'fr'
  else if Lang = 'russian' then
    Result := 'ru'
  else if Lang = 'arabic' then
    Result := 'ar'
  else if Lang = 'spanish' then
    Result := 'es'
  else
    Result := 'zh-cn';
end;

"@

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
Copy-Item -LiteralPath $chineseMessagesSourcePath -Destination $chineseMessagesPath -Force
[System.IO.File]::WriteAllText($issPath, $iss, $utf8Bom)

& $iscc $issPath
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup failed with exit code $LASTEXITCODE"
}

$installerPath = Join-Path $output.FullName "$InstallerName.exe"
if (-not (Test-Path $installerPath)) {
    throw "Installer was not created: $installerPath"
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $installerPath).Hash
[pscustomobject]@{
    FullName = $installerPath
    Length = (Get-Item $installerPath).Length
    Sha256 = $hash
    InstallDir = "%ProgramFiles%\KQRemoteLink, or the existing install directory during upgrade"
}
