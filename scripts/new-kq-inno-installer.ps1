param(
    [string]$ReleaseDir,
    [string]$OutputRoot = "C:\kq-remote-link-tools",
    [string]$InstallerName,
    [string]$Version = (Get-Date -Format "yyyy.MM.dd.HHmm"),
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

$release = Resolve-Path $ReleaseDir
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

$required = @(
    "rustdesk.exe",
    "librustdesk.dll",
    "flutter_windows.dll",
    "data\flutter_assets\AssetManifest.bin",
    "data\flutter_assets\assets\icon.png",
    "data\flutter_assets\assets\icon.ico",
    "data\flutter_assets\assets\kq_toolbox_icon.svg"
)
foreach ($item in $required) {
    $path = Join-Path $release.Path $item
    if (-not (Test-Path $path)) {
        throw "Missing release artifact: $path"
    }
}

if (-not $SkipCargoBuild) {
    & cargo build --features flutter --lib --release
    if ($LASTEXITCODE -ne 0) {
        throw "cargo build failed with exit code $LASTEXITCODE"
    }
    $freshDll = Join-Path $repo "target\release\librustdesk.dll"
    if (-not (Test-Path $freshDll)) {
        throw "cargo build did not produce $freshDll"
    }
    Copy-Item -LiteralPath $freshDll -Destination (Join-Path $release.Path "librustdesk.dll") -Force
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
$escapedRelease = $release.Path.Replace('\', '\\')
$escapedOutput = $output.FullName.Replace('\', '\\')
$escapedIcon = $iconPath.Replace('\', '\\')
$escapedWizardSmallImage = $wizardSmallImagePath.Replace('\', '\\')
$escapedWizardImage = $wizardImagePath.Replace('\', '\\')
$chineseMessagesPath = Join-Path $buildRoot "ChineseSimplified.isl"
$escapedChineseMessages = $chineseMessagesPath.Replace('\', '\\')

$iss = @"
#define MyAppName "$appName"
#define MyAppExeName "rustdesk.exe"
#define MyAppPublisher "Kunqiong"
#define MyAppVersion "$Version"

[Setup]
AppId={{D0B24C8B-7E7E-4B2C-9A38-0B2026052701}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\KQRemoteLink
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
ShowLanguageDialog=yes
LanguageDetectionMethod=none
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
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: startup

[Run]
Filename: "{app}\{#MyAppExeName}"; Parameters: "--local-option lang {code:SelectedAppLanguage}"; Flags: runhidden waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Parameters: "--install-service"; Flags: runhidden waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent; Tasks: launch

[UninstallRun]
Filename: "{app}\{#MyAppExeName}"; Parameters: "--uninstall-service"; Flags: runhidden waituntilterminated

[Code]
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
    InstallDir = "%LOCALAPPDATA%\KQRemoteLink"
}
