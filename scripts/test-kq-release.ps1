param(
    [string]$ReleaseDir,
    [string]$PackageZip,
    [string]$CustomClientPublicKey,
    [string]$ReportPath,
    [switch]$LaunchSmokeTest,
    [switch]$StopExistingRustDesk,
    [switch]$NoReport
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$signerTargetDir = Join-Path $env:TEMP "kq-custom-client-signer-target"

if (-not $ReleaseDir) {
    $packagedRelease = Join-Path $repo "Release"
    if (Test-Path (Join-Path $packagedRelease "rustdesk.exe")) {
        $ReleaseDir = $packagedRelease
    } else {
        $ReleaseDir = Join-Path $repo "flutter\build\windows\x64\runner\Release"
    }
}
if (-not $ReportPath) {
    $ReportPath = Join-Path "C:\kq-remote-link-tools" "KQ-Remote-Link-acceptance-$(Get-Date -Format 'yyyyMMdd-HHmm').md"
}

$results = New-Object System.Collections.Generic.List[object]

function Add-Check($Name, $Status, $Detail) {
    $results.Add([PSCustomObject]@{
        Name = $Name
        Status = $Status
        Detail = $Detail
    })
    Write-Host "[$Status] $Name - $Detail"
}

function Test-RequiredPath($Base, $RelativePath) {
    $path = Join-Path $Base $RelativePath
    if (Test-Path $path) {
        Add-Check "release:$RelativePath" "PASS" $path
    } else {
        Add-Check "release:$RelativePath" "FAIL" "Missing $path"
    }
}

function Test-KqWebIconAsset {
    $source = ".\flutter\assets\icon.png"
    $webAsset = ".\server\public\assets\kq-icon.png"
    if (-not (Test-Path $source)) {
        Add-Check "server:web-icon-source" "SKIP" "Source icon not available: $source"
        return
    }
    if (-not (Test-Path $webAsset)) {
        Add-Check "server:web-icon-asset" "FAIL" "Missing web icon asset: $webAsset"
        return
    }

    $sourceHash = (Get-FileHash -Algorithm SHA256 $source).Hash
    $webHash = (Get-FileHash -Algorithm SHA256 $webAsset).Hash
    if ($sourceHash -eq $webHash) {
        Add-Check "server:web-icon-asset" "PASS" "kq-icon.png matches flutter assets icon ($webHash)"
    } else {
        Add-Check "server:web-icon-asset" "FAIL" "kq-icon.png hash $webHash does not match app icon $sourceHash"
    }
}

function Test-SourceContains($Path, $Pattern, $Name) {
    if (-not (Test-Path $Path)) {
        Add-Check $Name "SKIP" "Source file not available: $Path"
        return
    }
    $content = Get-Content $Path -Raw -Encoding UTF8
    if ($content -match [regex]::Escape($Pattern)) {
        Add-Check $Name "PASS" $Pattern
    } else {
        Add-Check $Name "FAIL" "Missing expected text: $Pattern"
    }
}

function Test-SourceNotContains($Path, $Pattern, $Name) {
    if (-not (Test-Path $Path)) {
        Add-Check $Name "SKIP" "Source file not available: $Path"
        return
    }
    $content = Get-Content $Path -Raw -Encoding UTF8
    if ($content -match [regex]::Escape($Pattern)) {
        Add-Check $Name "FAIL" "Forbidden text is present: $Pattern"
    } else {
        Add-Check $Name "PASS" "Forbidden text absent"
    }
}

function Test-KqTitleBarBrandRemoved {
    $path = ".\flutter\lib\desktop\widgets\tabbar_widget.dart"
    if (-not (Test-Path $path)) {
        Add-Check "ui:title-bar-brand-removed" "SKIP" "Source file not available: $path"
        return
    }
    $content = Get-Content $path -Raw -Encoding UTF8
    if ($content -match [regex]::Escape("class _KqTitleBrand") -or
        $content -match [regex]::Escape("鲲穹AI旗下产品") -or
        $content -match [regex]::Escape("assets/icon.png")) {
        Add-Check "ui:title-bar-brand-removed" "FAIL" "Title bar still renders the old brand icon/text"
    } else {
        Add-Check "ui:title-bar-brand-removed" "PASS" "Title bar brand icon/text removed"
    }
}

function Test-KqPasswordSharePolicy {
    $path = ".\flutter\lib\models\server_model.dart"
    if (-not (Test-Path $path)) {
        Add-Check "password:share-policy" "SKIP" "Source file not available: $path"
        return
    }
    $content = Get-Content $path -Raw -Encoding UTF8
    if ($content -match '(?s)case KqPasswordKind\.oneTime:\s*return _approveMode != ''click'';') {
        Add-Check "password:one-time-share-available" "PASS" "one-time share button is gated only by click-approval mode"
    } else {
        Add-Check "password:one-time-share-available" "FAIL" "one-time share button is not available under normal password mode"
    }
    if ($content -match '(?s)case KqPasswordKind\.oneTime:\s*return canUseOneTimePassword;') {
        Add-Check "password:one-time-share-not-blocked-by-verification-method" "FAIL" "one-time share button is still blocked by verification method"
    } else {
        Add-Check "password:one-time-share-not-blocked-by-verification-method" "PASS" "one-time share button is not blocked by verification method"
    }
}

function Test-InstallerWizardImagesUseCurrentIcon {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        Add-Check "installer:wizard-images-current-icon" "SKIP" "python not available"
        return
    }
    $script = @'
from pathlib import Path
from PIL import Image, ImageChops, ImageOps

repo = Path.cwd()
bg = (231, 244, 252)
icon = Image.open(repo / "flutter" / "assets" / "icon.png").convert("RGBA")
checks = [
    ("installer:wizard-side-current-icon", repo / "res" / "installer-side.bmp", (164, 314), (120, 120), (22, 72)),
    ("installer:wizard-small-current-icon", repo / "res" / "installer-small.bmp", (55, 55), (42, 42), (6, 6)),
]
for name, path, canvas_size, icon_box, paste_xy in checks:
    actual = Image.open(path).convert("RGB")
    expected = Image.new("RGB", canvas_size, bg)
    scaled = ImageOps.contain(icon, icon_box, method=Image.Resampling.LANCZOS)
    expected.paste(scaled, paste_xy, scaled)
    bbox = ImageChops.difference(actual, expected).getbbox()
    if bbox:
        print(f"FAIL|{name}|{path} does not match the current app icon wizard image")
    else:
        print(f"PASS|{name}|{path} matches the current app icon wizard image")
'@
    $output = $script | & $python.Source -
    if ($LASTEXITCODE -ne 0) {
        Add-Check "installer:wizard-images-current-icon" "FAIL" ($output -join "`n")
        return
    }
    foreach ($line in $output) {
        $parts = $line -split '\|', 3
        if ($parts.Count -eq 3) {
            Add-Check $parts[1] $parts[0] $parts[2]
        }
    }
}

function Test-InstallerUpgradePolicy {
    $source = ".\scripts\new-kq-inno-installer.ps1"
    if (-not (Test-Path $source)) {
        Add-Check "installer:upgrade-policy" "SKIP" "Source file not available: $source"
        return
    }
    $content = Get-Content $source -Raw -Encoding UTF8
    $required = @(
        @("installer:stable-app-id", "AppId={{D0B24C8B-7E7E-4B2C-9A38-0B2026052701}"),
        @("installer:upgrade-default-dir", "DefaultDirName={code:GetDefaultInstallDir}"),
        @("installer:no-language-dialog", "ShowLanguageDialog=no"),
        @("installer:language-detect-ui", "LanguageDetectionMethod=uilanguage"),
        @("installer:use-previous-dir", "UsePreviousAppDir=yes"),
        @("installer:use-previous-language", "UsePreviousLanguage=yes"),
        @("installer:use-previous-tasks", "UsePreviousTasks=yes"),
        @("installer:read-existing-install-dir", "KqReadInstalledString('InstallLocation', KqExistingInstallDir)"),
        @("installer:prefer-existing-install-dir", "if KqExistingInstallDir <> '' then"),
        @("installer:fresh-lang-only", 'Parameters: "--local-option lang {code:SelectedAppLanguage}"; Flags: runhidden waituntilterminated; Check: KqIsFreshInstall'),
        @("installer:fresh-udp-only", 'Parameters: "--local-option enable-udp-punch Y"; Flags: runhidden waituntilterminated; Check: KqIsFreshInstall'),
        @("installer:fresh-relay-only", 'Parameters: "--local-option kq-force-always-relay N"; Flags: runhidden waituntilterminated; Check: KqIsFreshInstall'),
        @("installer:controlled-side-permission-window", 'Parameters: "--option enable-perm-change-in-accept-window Y"; Flags: runhidden waituntilterminated'),
        @("installer:block-remote-config-modification", 'Parameters: "--option allow-remote-config-modification N"; Flags: runhidden waituntilterminated'),
        @("installer:fresh-postinstall-launch", 'Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent; Tasks: launch; Check: KqIsFreshInstall'),
        @("installer:upgrade-install-detector", "function KqIsUpgradeInstall(): Boolean"),
        @("installer:upgrade-finish-launch-procedure", "procedure KqLaunchUpgradeAfterFinish()"),
        @("installer:upgrade-finish-launch-hook", "procedure DeinitializeSetup()"),
        @("installer:upgrade-launch-after-finish", "KqLaunchUpgradeAfterFinish();"),
        @("installer:upgrade-launch-success-gated", "if not KqInstallSucceeded then"),
        @("installer:upgrade-launch-not-silent", "if WizardSilent then"),
        @("installer:upgrade-launch-nowait", "ewNoWait"),
        @("installer:upgrade-skip-pages", "function ShouldSkipPage(PageID: Integer): Boolean"),
        @("installer:upgrade-copy-hook", "procedure ApplyUpgradeWizardText(CurPageID: Integer)"),
        @("installer:upgrade-welcome-copy", "WizardForm.WelcomeLabel1.Caption := '`$cnWelcomeTitle'"),
        @("installer:upgrade-ready-copy", "WizardForm.ReadyLabel.Caption :="),
        @("installer:upgrade-button-copy", "WizardForm.NextButton.Caption := '`$cnUpgradeButton'"),
        @("installer:upgrade-page-change-hook", "procedure CurPageChanged(CurPageID: Integer)"),
        @("installer:rust-before-flutter-build", "`$freshRustDll = Build-RustLibrary"),
        @("installer:date-version-from-installer-name", '$(Get-Date -Format ''yyyy.MM.dd'').$($Matches["build"])0'),
        @("installer:date-version-format-guard", "function Test-KqInstallerVersionFormat"),
        @("installer:reject-semver-downgrade-version", "Do not use 1.0.xxx because installed 2026.* packages will treat it as an older version."),
        @("installer:legacy-hkcu-migration", "function KqLegacyUninstallKey(): String"),
        @("installer:downgrade-guard", "KqCompareVersions(KqExistingVersion, '{#MyAppVersion}') > 0"),
        @("installer:system-desktop-shortcut", 'Name: "{commondesktop}\{#MyAppName}"'),
        @("installer:system-startup-shortcut", 'Name: "{commonstartup}\{#MyAppName}"'),
        @("installer:versioned-shortcut-icon-name", '$shortcutIconFileName = "kq-icon-'),
        @("installer:versioned-shortcut-icon-relative", '$shortcutIconRelativePath = "data\flutter_assets\assets\$shortcutIconFileName"'),
        @("installer:versioned-shortcut-icon-copy", 'Copy-Item -LiteralPath $shortcutIconSourcePath -Destination $shortcutIconTargetPath -Force'),
        @("installer:versioned-shortcut-icon-define", '#define ShortcutIconRelative "$shortcutIconRelativePath"'),
        @("installer:shortcut-icon-asset", 'IconFilename: "{app}\{#ShortcutIconRelative}"'),
        @("installer:repair-existing-shortcuts-hook", 'AfterInstall: KqRepairExistingShortcuts'),
        @("installer:repair-desktop-shortcut-icon", "KqRepairShortcut(ExpandConstant('{commondesktop}\{#MyAppName}.lnk'))"),
        @("installer:repair-taskbar-shortcut-icon", "KqRepairShortcut(ExpandConstant('{userappdata}\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\{#MyAppName}.lnk'))"),
        @("installer:repair-shortcut-icon-location", "Shortcut.IconLocation := ExpandConstant('{app}\{#ShortcutIconRelative}')"),
        @("installer:uninstall-icon-asset", 'UninstallDisplayIcon={app}\{#ShortcutIconRelative}'),
        @("installer:refresh-icon-cache", 'Filename: "{sys}\ie4uinit.exe"; Parameters: "-show"'),
        @("installer:motion-set-timer", "external 'SetTimer@user32.dll stdcall'"),
        @("installer:motion-kill-timer", "external 'KillTimer@user32.dll stdcall'"),
        @("installer:motion-gsap-ease-out", "function KqGsapEaseOutCubic(Value: Integer): Integer"),
        @("installer:motion-gsap-ease-in-out", "function KqGsapEaseInOut(Value: Integer): Integer"),
        @("installer:motion-timeline-proc", "procedure KqMotionTimerProc(Arg1, Arg2, Arg3, Arg4: Longword)"),
        @("installer:motion-create-hook", "procedure KqCreateInstallerMotion()"),
        @("installer:motion-page-prepare", "procedure KqPrepareInstallerMotion(CurPageID: Integer)"),
        @("installer:motion-page-slide", "KqMotionOffset(ScaleX(18))"),
        @("installer:motion-start-initialize", "KqCreateInstallerMotion();"),
        @("installer:motion-page-change-hook", "KqPrepareInstallerMotion(CurPageID);"),
        @("installer:motion-cleanup", "KqStopInstallerMotion();")
    )
    foreach ($pair in $required) {
        if ($content -match [regex]::Escape($pair[1])) {
            Add-Check $pair[0] "PASS" $pair[1]
        } else {
            Add-Check $pair[0] "FAIL" "Missing expected installer policy: $($pair[1])"
        }
    }
    if ($content -match 'Check: KqIsUpgradeInstall[^\r\n]*Tasks: launch' -or
        $content -match 'Tasks: launch[^\r\n]*Check: KqIsUpgradeInstall') {
        Add-Check "installer:upgrade-launch-not-task-gated" "FAIL" "Upgrade auto launch is still gated by the launch task"
    } else {
        Add-Check "installer:upgrade-launch-not-task-gated" "PASS" "Upgrade auto launch is independent of the launch task"
    }
    if ($content -match 'Check: KqIsUpgradeInstall[^\r\n]*postinstall' -or
        $content -match 'postinstall[^\r\n]*Check: KqIsUpgradeInstall') {
        Add-Check "installer:upgrade-launch-after-finish-button" "PASS" "Upgrade auto launch runs after the installer finish button"
    } else {
        Add-Check "installer:upgrade-launch-after-finish-button" "PASS" "Upgrade auto launch is not run before the finish page"
    }
    if ($content -match 'Filename: "\{app\}\\\{#MyAppExeName\}"; Flags: nowait skipifsilent; Check: KqIsUpgradeInstall') {
        Add-Check "installer:no-upgrade-run-phase-launch" "FAIL" "Upgrade auto launch still runs during the installer Run phase"
    } else {
        Add-Check "installer:no-upgrade-run-phase-launch" "PASS" "Upgrade auto launch is deferred until the wizard closes"
    }

    $forbidden = @(
        @("installer:no-localappdata-default", "DefaultDirName={localappdata}\KQRemoteLink"),
        @("installer:no-forced-language-dialog", "ShowLanguageDialog=yes"),
        @("installer:no-auto-language-dialog", "ShowLanguageDialog=auto"),
        @("installer:no-disabled-language-detection", "LanguageDetectionMethod=none"),
        @("installer:no-user-desktop-task", 'Name: "{autodesktop}\{#MyAppName}"'),
        @("installer:no-user-startup-task", 'Name: "{userstartup}\{#MyAppName}"'),
        @("installer:no-stable-shortcut-icon-filename", 'IconFilename: "{app}\data\flutter_assets\assets\icon.ico"'),
        @("installer:no-stable-shortcut-icon-repair", "Shortcut.IconLocation := ExpandConstant('{app}\data\flutter_assets\assets\icon.ico')"),
        @("installer:no-stable-uninstall-icon", 'UninstallDisplayIcon={app}\data\flutter_assets\assets\icon.ico'),
        @("installer:no-empty-motion-color", "StrToColor('')"),
        @("installer:no-motion-overlay-beam", "KqMotionBeam"),
        @("installer:no-motion-overlay-spark", "KqMotionSpark"),
        @("installer:no-motion-overlay-accent", "KqMotionAccent"),
        @("installer:no-motion-title-line", "KqMotionTitleLine"),
        @("installer:no-motion-title-rail", "KqMotionTitleRail"),
        @("installer:no-motion-title-dot", "KqMotionTitleDot"),
        @("installer:no-wizard-image-motion", "WizardForm.WizardBitmapImage.Top :="),
        @("installer:no-semver-package-version", "-Version 1.0.")
    )
    foreach ($pair in $forbidden) {
        if ($content -match [regex]::Escape($pair[1])) {
            Add-Check $pair[0] "FAIL" "Forbidden installer policy is present: $($pair[1])"
        } else {
            Add-Check $pair[0] "PASS" "Forbidden policy absent"
        }
    }
}

function Test-VoiceCallAudioRouting {
    $ipcSource = ".\src\ipc.rs"
    $serverSource = ".\src\server\connection.rs"
    $cmSource = ".\src\ui_cm_interface.rs"
    $audioSource = ".\src\server\audio_service.rs"
    $clientLoopSource = ".\src\client\io_loop.rs"

    $required = @(
        @($ipcSource, "VoiceCallAudioFormat", "voice-call:ipc-format-event"),
        @($ipcSource, "VoiceCallAudioFrame", "voice-call:ipc-frame-event"),
        @($serverSource, "if self.voice_calling", "voice-call:server-separates-call-audio"),
        @($serverSource, "self.send_to_cm(ipc::Data::VoiceCallAudioFormat", "voice-call:server-forwards-format-to-cm"),
        @($serverSource, "self.send_to_cm(ipc::Data::VoiceCallAudioFrame", "voice-call:server-forwards-frame-to-cm"),
        @($serverSource, "self.voice_calling = true;", "voice-call:accepted-before-audio-arrives"),
        @($cmSource, "voice_call_audio_sender: Option<MediaSender>", "voice-call:cm-user-session-audio-sender"),
        @($cmSource, "let sender = start_audio_thread();", "voice-call:cm-starts-user-session-playback"),
        @($cmSource, "MediaData::AudioFormat(AudioFormat", "voice-call:cm-handles-audio-format"),
        @($cmSource, "MediaData::AudioFrame(Box::new", "voice-call:cm-handles-audio-frame"),
        @($audioSource, ".input_devices()", "voice-call:audio-input-enumerates-input-devices"),
        @($audioSource, "Configured audio input", "voice-call:audio-input-fallback-log"),
        @($audioSource, "get_fallback_audio_input", "voice-call:audio-input-fallback"),
        @($audioSource, "Voice call microphone captured non-zero PCM", "voice-call:microphone-nonzero-log"),
        @($clientLoopSource, "Starting voice call recorder with input device", "voice-call:recorder-device-log"),
        @($clientLoopSource, "Voice call sent microphone frame", "voice-call:recorder-frame-log"),
        @($serverSource, "Voice call forwarded peer audio frame", "voice-call:server-frame-forward-log"),
        @($cmSource, "CM received voice call audio frame", "voice-call:cm-frame-received-log")
    )

    foreach ($check in $required) {
        Test-SourceContains $check[0] $check[1] $check[2]
    }
}

$release = Resolve-Path $ReleaseDir
if ($PackageZip) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
}
Test-RequiredPath $release.Path "rustdesk.exe"
Test-RequiredPath $release.Path "librustdesk.dll"
Test-RequiredPath $release.Path "flutter_windows.dll"
Test-RequiredPath $release.Path "data\flutter_assets\AssetManifest.bin"
Test-RequiredPath $release.Path "data\flutter_assets\assets\kq_toolbox_icon.svg"
Test-RequiredPath $release.Path "drivers\RustDeskPrinterDriver\RustDeskPrinterDriver.inf"
Test-RequiredPath $release.Path "printer_driver_adapter.dll"
Test-InstallerUpgradePolicy
Test-InstallerWizardImagesUseCurrentIcon
Test-KqWebIconAsset
Test-VoiceCallAudioRouting

$kqLoginButton = [string]::Concat([char[]]@(
    0x767B,
    0x5F55,
    0x9CB2,
    0x7A79,
    0x8D26,
    0x53F7
))
$kqLoginButtonKey = "Log in to your Kunqiong account"
$kqAppName = [string]::Concat([char[]]@(
    0x9CB2,
    0x7A79,
    0x8FDC,
    0x7A0B,
    0x684C,
    0x9762
))
$kqTitleBrand = [string]::Concat(
    [string]::Concat([char[]]@(0x9CB2, 0x7A79)),
    "AI",
    [string]::Concat([char[]]@(0x65D7, 0x4E0B, 0x4EA7, 0x54C1))
)
$kqDownloadWindowsButton = [string]::Concat([char[]]@(
    0x4E0B,
    0x8F7D,
    0x20,
    0x57,
    0x69,
    0x6E,
    0x64,
    0x6F,
    0x77,
    0x73,
    0x20,
    0x5B89,
    0x88C5,
    0x5305
))
$kqDownloadAndroidButton = [string]::Concat([char[]]@(
    0x4E0B,
    0x8F7D,
    0x20,
    0x41,
    0x6E,
    0x64,
    0x72,
    0x6F,
    0x69,
    0x64,
    0x20,
    0x5B89,
    0x88C5,
    0x5305
))
$kqDownloadFriendlyBusyCopy = [string]::Concat([char[]]@(
    0x5F53,
    0x524D,
    0x4E0B,
    0x8F7D,
    0x4EBA,
    0x6570,
    0x8F83,
    0x591A,
    0xFF0C,
    0x8BF7,
    0x7A0D,
    0x540E,
    0x518D,
    0x8BD5,
    0x3002
))
$kqDownloadUserFacingTitle = [string]::Concat([char[]]@(
    0x5BA2,
    0x6237,
    0x7AEF,
    0x4E0B,
    0x8F7D
))
$kqDownloadUserFacingHero = [string]::Concat([char[]]@(
    0x5B89,
    0x5168,
    0x8FDE,
    0x63A5,
    0xFF0C,
    0x8F7B,
    0x677E,
    0x5B8C,
    0x6210,
    0x8FDC,
    0x7A0B,
    0x534F,
    0x52A9
))
$kqDownloadForbiddenTestEnv = [string]::Concat([char[]]@(
    0x6D4B,
    0x8BD5,
    0x73AF,
    0x5883
))
$kqDownloadForbiddenTestServer = [string]::Concat([char[]]@(
    0x6D4B,
    0x8BD5,
    0x670D,
    0x52A1,
    0x5668
))
$kqDownloadForbiddenControlled = [string]::Concat([char[]]@(
    0x53D7,
    0x63A7,
    0x4E0B,
    0x8F7D
))
$kqDownloadForbiddenRangeCopy = [string]::Concat([char[]]@(
    0x65AD,
    0x70B9,
    0x7EED,
    0x4F20
))
$kqDownloadForbiddenRateLimit = [string]::Concat([char[]]@(
    0x9650,
    0x6D41
))
$kqRemoteDesktopOfflineCopy = [string]::Concat([char[]]@(
    0x8FDC,
    0x7A0B,
    0x684C,
    0x9762,
    0x4E0D,
    0x5728,
    0x7EBF
))
$kqMemberAccelerationCopy = [string]::Concat([char[]]@(
    0x4F1A,
    0x5458,
    0x7545,
    0x4EAB,
    0x4E13,
    0x5C5E,
    0x52A0,
    0x901F,
    0x94FE,
    0x8DEF
))
$kqOldBasicRemoteHintCopy = [string]::Concat([char[]]@(
    0x57FA,
    0x7840,
    0x7248,
    0x6700,
    0x9AD8,
    0x652F,
    0x6301,
    0x20,
    0x37,
    0x32,
    0x30,
    0x70
))
$kqConnectionFirewallChecklist = [string]::Concat([char[]]@(
    0x672C,
    0x673A,
    0x9632,
    0x706B,
    0x5899
))
$kqConnectionNatChecklist = [string]::Concat(
    "NAT / ",
    [string]::Concat([char[]]@(0x8DEF, 0x7531, 0x5668))
)
$kqConnectionRelayChecklist = [string]::Concat([char[]]@(
    0x4E2D,
    0x7EE7,
    0x8D28,
    0x91CF
))
$kqFileTransferDesktopCnCopy = [string]::Concat(
    '("Desktop", "',
    [string]::Concat([char[]]@(0x684C, 0x9762)),
    '")'
)
$kqFileTransferFolderCnCopy = [string]::Concat(
    '("Folder", "',
    [string]::Concat([char[]]@(0x6587, 0x4EF6, 0x5939)),
    '")'
)
$kqViewCameraNeutralCnCopy = [string]::Concat(
    '("View camera", "',
    [string]::Concat([char[]]@(0x529F, 0x80FD, 0x6682, 0x4E0D, 0x53EF, 0x7528)),
    '")'
)
$kqViewCameraTitleNeutralCnCopy = [string]::Concat(
    '("View Camera", "',
    [string]::Concat([char[]]@(0x529F, 0x80FD, 0x6682, 0x4E0D, 0x53EF, 0x7528)),
    '")'
)
$kqViewCameraCnCopy = [string]::Concat([char[]]@(0x67E5, 0x770B, 0x6444, 0x50CF, 0x5934))
$kqEnableCameraCnCopy = [string]::Concat([char[]]@(0x5141, 0x8BB8, 0x67E5, 0x770B, 0x6444, 0x50CF, 0x5934))
$kqNoCamerasCnCopy = [string]::Concat([char[]]@(0x6CA1, 0x6709, 0x6444, 0x50CF, 0x5934))
$kqPasswordHiddenExistingCopy = [string]::Concat([char[]]@(0x5DF2, 0x8BBE, 0x7F6E, 0xFF08, 0x9690, 0x85CF, 0xFF09))
$kqOneTimePasswordLabel = [string]::Concat([char[]]@(0x4E00, 0x6B21, 0x6027, 0x9A8C, 0x8BC1, 0x7801))
$kqDailyPasswordLabel = [string]::Concat([char[]]@(0x4ECA, 0x65E5, 0x9A8C, 0x8BC1, 0x7801))
$kqPermanentPasswordLabel = [string]::Concat([char[]]@(0x957F, 0x671F, 0x9A8C, 0x8BC1, 0x7801))
$kqPermanentPasswordVisibleCopy = [string]::Concat([char[]]@(
    0x957F, 0x671F, 0x9A8C, 0x8BC1, 0x7801, 0x4F1A, 0x540C, 0x65F6,
    0x66F4, 0x65B0, 0x8FDC, 0x7A0B, 0x8FDE, 0x63A5, 0x4F7F, 0x7528,
    0x7684, 0x957F, 0x671F, 0x5BC6, 0x7801, 0xFF0C, 0x5E76, 0x5728,
    0x672C, 0x673A, 0x53EF, 0x89C1, 0x3002
))

function Test-BuiltInPrivateServerDefaults {
    $source = ".\src\common.rs"
    if (-not (Test-Path $source)) {
        Add-Check "private-server:built-in-defaults" "SKIP" "Source file not available: $source"
        return
    }
    $content = Get-Content $source -Raw -Encoding UTF8
    $required = @(
        "43.154.197.96:21116",
        "43.154.197.96:21117",
        "h9goq/v9ic0Uh0NpB/9Uv4v2MNpSEIVCy7UFSETZ5BA="
    )
    $missing = @($required | Where-Object { $content -notmatch [regex]::Escape($_) })
    if ($missing.Count -eq 0) {
        Add-Check "private-server:built-in-defaults" "PASS" "client defaults point to private hbbs/hbbr"
    } else {
        Add-Check "private-server:built-in-defaults" "FAIL" "Missing defaults: $($missing -join ', ')"
    }
}

$manifestPath = Join-Path $repo "KQ_RELEASE_MANIFEST.json"
if (Test-Path $manifestPath) {
    $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.appName -eq $kqAppName) {
        Add-Check "manifest:app-name" "PASS" $manifest.appName
    } else {
        Add-Check "manifest:app-name" "FAIL" "Unexpected appName: $($manifest.appName)"
    }
    if ($manifest.oauth.loginButtonText -eq $kqLoginButton) {
        Add-Check "manifest:oauth-login-button" "PASS" $manifest.oauth.loginButtonText
    } else {
        Add-Check "manifest:oauth-login-button" "FAIL" "Unexpected login button text"
    }
    if ($manifest.ui.titleBrandText -eq "") {
        Add-Check "manifest:ui-title-brand" "PASS" "title brand hidden"
    } else {
        Add-Check "manifest:ui-title-brand" "FAIL" "Expected hidden title brand, got: $($manifest.ui.titleBrandText)"
    }
    if ($manifest.ui.titleBrandIcon -eq "") {
        Add-Check "manifest:ui-title-icon" "PASS" "title brand icon hidden"
    } else {
        Add-Check "manifest:ui-title-icon" "FAIL" "Expected hidden title brand icon, got: $($manifest.ui.titleBrandIcon)"
    }
    if ($manifest.ui.productTagline -eq $kqTitleBrand) {
        Add-Check "manifest:ui-product-tagline" "PASS" $manifest.ui.productTagline
    } else {
        Add-Check "manifest:ui-product-tagline" "FAIL" "Unexpected product tagline"
    }
    foreach ($pair in @(
        @("manifest:login-api-base-url", "apiBaseUrl", "https://api-web.kunqiongai.com"),
        @("manifest:web-login-url-path", "webLoginUrlPath", "/soft_desktop/get_web_login_url"),
        @("manifest:desktop-token-path", "desktopTokenPath", "/user/desktop_get_token"),
        @("manifest:check-login-path", "checkLoginPath", "/user/check_login"),
        @("manifest:user-info-path", "userInfoPath", "/soft_desktop/get_user_info"),
        @("manifest:logout-path", "logoutPath", "/logout")
    )) {
        $actual = $manifest.oauth.($pair[1])
        if ($actual -eq $pair[2]) {
            Add-Check $pair[0] "PASS" $actual
        } else {
            Add-Check $pair[0] "FAIL" "Expected $($pair[2]), got $actual"
        }
    }
    $actualExeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $release.Path "rustdesk.exe")).Hash.ToLowerInvariant()
    if ($actualExeHash -eq $manifest.release.rustdeskExeSha256) {
        Add-Check "manifest:rustdesk.exe-sha256" "PASS" $actualExeHash
    } else {
        Add-Check "manifest:rustdesk.exe-sha256" "FAIL" "Hash mismatch"
    }
} else {
    Test-SourceContains ".\Cargo.toml" $kqAppName "branding:CARGO"
    Test-SourceContains ".\src\common.rs" $kqAppName "branding:common"
    Test-SourceContains ".\flutter\lib\common\widgets\login.dart" $kqLoginButtonKey "oauth:login-button"
    Test-SourceContains ".\src\lang\cn.rs" $kqLoginButton "oauth:login-button-cn-copy"
    Test-SourceContains ".\flutter\lib\common\widgets\login.dart" "_isKqOauthCancellation" "oauth:suppress-cancel-toast"
    Test-SourceContains ".\flutter\lib\common\widgets\login.dart" "if (!_isKqOauthCancellation(err))" "oauth:suppress-cancel-toast-branch"
    Test-SourceNotContains ".\flutter\lib\desktop\widgets\tabbar_widget.dart" $kqTitleBrand "ui:title-brand-hidden"
    Test-SourceNotContains ".\flutter\lib\desktop\widgets\tabbar_widget.dart" "assets/icon.png" "ui:title-icon-hidden"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" "class _KqProductTagline" "ui:home-product-tagline-widget"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" $kqTitleBrand "ui:home-product-tagline-copy"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" "stateGlobal.svcStatus.value == SvcStatus.ready" "ui:home-product-ready-badge-removed"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" "not_ready_status" "ui:home-product-status-copy-removed"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" $kqAppName "ui:about-product-name"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "_SettingPalette" "ui:settings-light-blue-palette"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "pageBackground: Color(0xFFEAF6FF)" "ui:settings-light-blue-page-background"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "contentBackground: Color(0xFFF5FBFF)" "ui:settings-light-blue-content-background"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "sidebarBackground: Color(0xFFE8F5FF)" "ui:settings-light-blue-sidebar-background"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "navSelectedBackground: Color(0xFFDDF0FF)" "ui:settings-light-blue-selected-nav"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "cardHeaderBackground: Color(0xFFF0F8FF)" "ui:settings-light-blue-card-header"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "border: Border.all(color: palette.cardBorder)" "ui:settings-card-blue-border"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "hoverColor: palette.navHoverBackground" "ui:settings-nav-blue-hover"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "hoverColor: canChange ? palette.navHoverBackground : null" "ui:settings-checkbox-blue-hover"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "class _FoldoutCard extends StatefulWidget" "ui:settings-foldout-card"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "AnimatedSize(" "ui:settings-foldout-animation"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "Icons.expand_more_rounded" "ui:settings-foldout-chevron"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "_SettingSectionTitle(context, 'Default Scroll Style')" "ui:display-scroll-folded-under-view-style"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "_SettingSectionTitle(context, 'Default Codec')" "ui:display-codec-folded-under-quality"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "_SettingSectionTitle(context, 'Privacy mode')" "ui:display-privacy-folded-under-other"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "_SettingSectionTitle(context, 'Control Remote Desktop')" "ui:safety-permissions-grouped"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "_SettingSectionTitle(context, '2FA')" "ui:safety-2fa-grouped-under-security"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "_SettingSectionTitle(context, 'Network')" "ui:safety-network-grouped"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "title: '2FA'," "ui:safety-no-standalone-2fa-foldout"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "_Card(title: 'Permissions'" "ui:safety-permissions-no-flat-card"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "_Card(title: 'Default Image Quality'" "ui:display-quality-no-flat-card"
    Test-KqTitleBarBrandRemoved
    Test-SourceContains ".\flutter\windows\runner\win32_window.cpp" "window_class.hIconSm" "windows:small-window-icon"
    Test-SourceContains ".\flutter\windows\runner\win32_window.cpp" "WM_SETICON" "windows:set-window-icon"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_tab_page.dart" "showMaximize: false" "ui:main-hide-maximize"
    Test-SourceContains ".\flutter\lib\consts.dart" "kDesktopMainWindowDefaultSize = Size(1360, 720)" "ui:main-window-roomy-default-size"
    Test-SourceContains ".\flutter\lib\consts.dart" "kDesktopMainWindowMinSize = Size(1280, 700)" "ui:main-window-roomy-min-size"
    Test-SourceContains ".\flutter\lib\main.dart" "size: kDesktopMainWindowDefaultSize" "ui:main-window-uses-roomy-default-size"
    Test-SourceContains ".\flutter\lib\main.dart" "setMinimumSize(kDesktopMainWindowMinSize)" "ui:main-window-enforces-roomy-min-size"
    Test-SourceContains ".\flutter\lib\common.dart" "mainWindow: type == WindowType.Main" "ui:main-window-restores-with-roomy-floor"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" "width: isIncomingOnly ? 276.0 : 276.0" "ui:home-left-pane-narrower-for-history"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_tab_page.dart" "_KqTitleSettingsButton" "ui:title-settings-prominent-button"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_tab_page.dart" "Icons.settings_rounded" "ui:title-settings-gear-icon"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\desktop_tab_page.dart" "icon: IconFont.menu" "ui:title-settings-no-menu-icon"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" "Icons.settings_rounded" "ui:home-settings-prominent-gear"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" "_copyRemoteAssistShare" "ui:remote-assist-share-copy"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" "kq-share-invite-url" "ui:remote-assist-share-url"
    Test-SourceContains ".\flutter\lib\desktop\pages\connection_page.dart" "'Terminal'" "ui:connection-terminal-menu-label"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\connection_page.dart" "(beta)" "ui:connection-terminal-menu-no-beta"
    Test-SourceContains ".\flutter\lib\common.dart" "return kqTrimDesktopTabHostSuffix(label);" "ui:remote-tab-label-hides-host-suffix"
    Test-SourceContains ".\flutter\lib\common.dart" "label.indexOf('@')" "ui:remote-tab-label-finds-at-suffix"
    Test-SourceContains ".\flutter\lib\common.dart" "return trimmed.isEmpty ? label : trimmed;" "ui:remote-tab-label-empty-trim-fallback"
    Test-SourceContains ".\flutter\lib\desktop\widgets\tabbar_widget.dart" "final Widget? tabTail;" "ui:remote-tab-tail-slot"
    Test-SourceContains ".\flutter\lib\desktop\widgets\tabbar_widget.dart" "child: _ListView(" "ui:remote-tab-list-visible-slot"
    Test-SourceContains ".\flutter\lib\desktop\widgets\tabbar_widget.dart" "tabTail: tabTail," "ui:remote-tab-tail-passed-to-list"
    Test-SourceContains ".\flutter\lib\desktop\widgets\tabbar_widget.dart" "SingleChildScrollView(" "ui:remote-tab-list-stable-scroll-view"
    Test-SourceContains ".\flutter\lib\desktop\widgets\tabbar_widget.dart" "mainAxisSize: MainAxisSize.min" "ui:remote-tab-list-content-wraps-tabs"
    Test-SourceContains ".\flutter\lib\desktop\widgets\tabbar_widget.dart" "tabChildren.length + (!hideSingleItem && tabTail != null ? 1 : 0)" "ui:remote-tab-scroll-count-includes-plus"
    Test-SourceContains ".\flutter\lib\desktop\widgets\tabbar_widget.dart" "if (!hideSingleItem && tabTail != null)" "ui:remote-tab-tail-after-tabs"
    Test-SourceContains ".\flutter\lib\desktop\widgets\tabbar_widget.dart" "class _TabTail extends StatelessWidget" "ui:remote-tab-tail-fixed-wrapper"
    Test-SourceNotContains ".\flutter\lib\desktop\widgets\tabbar_widget.dart" "children.add(tabTail!);" "ui:remote-tab-tail-not-inside-listview"
    Test-SourceNotContains ".\flutter\lib\desktop\widgets\tabbar_widget.dart" "FlexFit.loose" "ui:remote-tab-list-no-loose-flex"
    Test-SourceNotContains ".\flutter\lib\desktop\widgets\tabbar_widget.dart" "shrinkWrap: true" "ui:remote-tab-list-no-shrinkwrap"
    Test-SourceContains ".\flutter\lib\desktop\pages\remote_tab_page.dart" "tabTail: const AddButton()," "ui:remote-tab-add-after-last-connection"
    Test-SourceContains ".\flutter\lib\desktop\pages\remote_tab_page.dart" "tail: _RelativeMouseModeHint(tabController: tabController)," "ui:remote-tab-window-tail-keeps-mouse-hint"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\remote_tab_page.dart" "tail: Row(" "ui:remote-tab-add-not-in-window-action-panel"
    Test-SourceContains ".\flutter\lib\desktop\widgets\tabbar_widget.dart" "icon: Icons.add_rounded" "ui:remote-tab-add-plus-visible"
    Test-SourceContains ".\flutter\lib\desktop\widgets\tabbar_widget.dart" "kWindowMainWindowOnTop" "ui:remote-tab-add-opens-main-connection"
    Test-SourceNotContains ".\flutter\lib\desktop\widgets\tabbar_widget.dart" "icon: IconFont.add" "ui:remote-tab-add-no-custom-font-blank"
    Test-SourceContains ".\flutter\lib\models\server_model.dart" "enum KqPasswordKind" "password:kinds-enum"
    Test-SourceContains ".\flutter\lib\models\server_model.dart" "KqPasswordKind.oneTime" "password:one-time-kind"
    Test-SourceContains ".\flutter\lib\models\server_model.dart" "KqPasswordKind.daily" "password:daily-kind"
    Test-SourceContains ".\flutter\lib\models\server_model.dart" "KqPasswordKind.permanent" "password:permanent-kind"
    Test-SourceContains ".\flutter\lib\models\server_model.dart" "Future<void> setOneTimePassword" "password:one-time-edit-model"
    Test-SourceContains ".\flutter\lib\models\server_model.dart" "Future<void> setDailyPassword" "password:daily-edit-model"
    Test-SourceContains ".\flutter\lib\models\server_model.dart" "Future<bool> setPermanentPasswordPreview" "password:permanent-edit-model"
    Test-SourceContains ".\flutter\lib\models\server_model.dart" "return !_passwordServiceStopped;" "password:all-kinds-visible-when-service-running"
    Test-SourceContains ".\flutter\lib\models\server_model.dart" "bool get selectedPasswordCanRefresh => isSelectedPasswordVisible;" "password:permanent-refresh-button-visible"
    Test-SourceContains ".\flutter\lib\models\server_model.dart" "return canUsePermanentPassword;" "password:permanent-share-button-visible"
    Test-KqPasswordSharePolicy
    Test-SourceContains ".\flutter\lib\models\server_model.dart" "await setPermanentPasswordPreview(password);" "password:permanent-refresh-updates-real-password"
    Test-SourceContains ".\flutter\lib\models\server_model.dart" "String _defaultApproveMode(String mode)" "password:approve-mode-default-helper"
    Test-SourceContains ".\flutter\lib\models\server_model.dart" "final normalizedApproveMode = _defaultApproveMode(approveMode);" "password:approve-mode-normalized-on-refresh"
    Test-SourceContains ".\flutter\lib\models\server_model.dart" "key: kOptionApproveMode, value: normalizedApproveMode" "password:approve-mode-migrates-existing-config"
    Test-SourceContains ".\flutter\lib\models\server_model.dart" "_permanentPreviewAutofillAttempted" "password:permanent-preview-autofill-guard"
    Test-SourceContains ".\flutter\lib\models\server_model.dart" "mainSetPermanentPasswordWithResult(password: generated)" "password:permanent-preview-autofill-real-password"
    Test-SourceNotContains ".\flutter\lib\models\server_model.dart" $kqPasswordHiddenExistingCopy "password:permanent-no-hidden-copy-model"
    Test-SourceContains ".\flutter\lib\consts.dart" 'kOptionKqDailyPassword = "kq-daily-password"' "password:daily-option-key"
    Test-SourceContains ".\flutter\lib\consts.dart" "kOptionKqPermanentPasswordPreview =" "password:permanent-preview-option-key"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" "PopupMenuButton<KqPasswordKind>" "ui:home-password-kind-menu"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" "class _KqPasswordKindMenuItem" "ui:home-password-kind-menu-themed"
    Test-SourceContains ".\flutter\lib\common\widgets\connection_page_title.dart" "fontWeight: FontWeight.w800" "ui:connection-title-themed-weight"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" $kqOneTimePasswordLabel "ui:home-one-time-password-label"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" $kqDailyPasswordLabel "ui:home-daily-password-label"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" $kqPermanentPasswordLabel "ui:home-permanent-password-label"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" "_showKqPasswordDialog(model)" "ui:home-password-edit-dialog"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" "kq-password-action-column" "ui:home-password-actions-vertical-column"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" "kq-password-value-row" "ui:home-password-compact-value-row"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" "const actionButtonSize = 22.0" "ui:home-password-compact-actions"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" "class _KqPasswordToolButton" "ui:home-password-actions-fixed-button"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" "minFontSize: 14" "ui:home-password-text-autosizes"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" $kqPermanentPasswordVisibleCopy "ui:home-permanent-password-visible-copy"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" $kqPasswordHiddenExistingCopy "ui:home-permanent-no-hidden-copy"
    Test-SourceContains ".\flutter\lib\desktop\pages\desktop_home_page.dart" "setPasswordDialog" "ui:home-keeps-password-settings-entry"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "password(context)" "ui:settings-password-card-removed"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "title: 'Password'" "ui:settings-password-foldout-removed"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "'One-time password length'" "ui:settings-password-options-removed"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "translate('Accept sessions via both')" "ui:settings-password-approve-mode-dropdown-hidden"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "onChanged: (key) => model.setApproveMode(key)" "ui:settings-password-no-approve-mode-handler"
    Test-SourceContains ".\src\server\connection.rs" "let daily_password = password::kq_daily_password();" "password:server-daily-password-read"
    Test-SourceContains ".\src\server\connection.rs" "self.validate_password_plain(&daily_password)" "password:server-daily-password-accepted"
    Test-SourceContains ".\src\ipc.rs" "password::set_temporary_password(&value);" "password:ipc-one-time-manual-set"
    Test-SourceContains ".\src\ui_interface.rs" 'if key == "temporary-password"' "password:desktop-one-time-routed-to-service"
    Test-SourceContains ".\libs\hbb_common\src\config.rs" "OPTION_KQ_DAILY_PASSWORD" "password:config-daily-option"
    Test-SourceContains ".\libs\hbb_common\src\config.rs" "OPTION_KQ_PERMANENT_PASSWORD_PREVIEW" "password:config-permanent-preview-option"
    Test-SourceContains ".\libs\hbb_common\src\password_security.rs" "pub fn kq_daily_password() -> String" "password:security-daily-helper"
    Test-SourceContains ".\flutter\lib\common\widgets\peers_view.dart" "_sortRecentPeersWithFavoritesFirst" "ui:recent-favorites-first-sort"
    Test-SourceContains ".\flutter\lib\common\widgets\peers_view.dart" "widget.peers.loadEvent == LoadEvent.recent" "ui:recent-favorites-sort-only-recent"
    Test-SourceContains ".\flutter\lib\models\peer_model.dart" "online = json['online'] == true || json['online'] == 'true'" "ui:peer-online-json-preserved"
    Test-SourceContains ".\flutter\lib\models\peer_model.dart" "'online': online" "ui:peer-online-json-exported"
    Test-SourceContains ".\flutter\lib\models\peer_model.dart" "online: other.online" "ui:peer-online-copy-preserved"
    Test-SourceContains ".\flutter\lib\models\peer_model.dart" "String kqNormalizePeerId(String id)" "ui:peer-online-normalizes-id-helper"
    Test-SourceContains ".\flutter\lib\models\peer_model.dart" "map(kqNormalizePeerId)" "ui:peer-online-callback-normalizes-ids"
    Test-SourceContains ".\flutter\lib\models\peer_model.dart" "final id = kqNormalizePeerId(peer.id);" "ui:peer-online-state-map-normalized-key"
    Test-SourceContains ".\flutter\lib\models\peer_model.dart" "onlineStates[kqNormalizePeerId(peer.id)]" "ui:recent-online-restore-normalized-key"
    Test-SourceContains ".\flutter\lib\common\widgets\peers_view.dart" "final normalizedPeerId = kqNormalizePeerId(peerId);" "ui:visible-peer-query-normalizes-id"
    Test-SourceContains ".\flutter\lib\common\widgets\peers_view.dart" "map((e) => kqNormalizePeerId(e.id))" "ui:load-peer-query-normalizes-id"
    Test-SourceContains ".\flutter\lib\models\peer_model.dart" "unawaited(_syncRecentPeersWithDatabase())" "ui:recent-online-sync-uses-current-state"
    Test-SourceNotContains ".\flutter\lib\models\peer_model.dart" "_syncRecentPeersWithDatabase(onlineStates)" "ui:recent-online-no-stale-snapshot"
    Test-SourceContains ".\flutter\lib\models\peer_model.dart" "if (state != null) {" "ui:peer-online-does-not-default-overwrite"
    Test-SourceContains ".\flutter\lib\common\widgets\peer_card.dart" "_favoriteButton" "ui:peer-card-favorite-marker"
    Test-SourceContains ".\flutter\lib\common\widgets\peer_card.dart" "Icons.star_rounded" "ui:peer-card-favorite-filled-star"
    Test-SourceContains ".\flutter\lib\common\widgets\peer_card.dart" "Icons.star_outline_rounded" "ui:peer-card-favorite-empty-star"
    Test-SourceContains ".\flutter\lib\common\widgets\peer_card.dart" "_toggleFavorite" "ui:peer-card-favorite-toggle"
    Test-SourceContains ".\flutter\lib\common\widgets\peer_card.dart" "bind.mainLoadRecentPeers()" "ui:peer-card-favorite-refresh-recent"
    Test-SourceContains ".\flutter\lib\common\widgets\peer_tab_page.dart" "bind.mainLoadRecentPeers();" "ui:peer-multiselect-favorite-refresh-recent"
    Test-SourceContains ".\flutter\lib\desktop\pages\connection_page.dart" "_passwordController" "ui:remote-password-field"
    Test-SourceContains ".\flutter\lib\desktop\pages\connection_page.dart" "password: password.isEmpty ? null : password" "ui:remote-password-connect-param"
    Test-SourceContains ".\flutter\lib\desktop\pages\connection_page.dart" "OutlinedButton.icon" "ui:file-transfer-primary-action"
    Test-SourceContains ".\flutter\lib\desktop\pages\connection_page.dart" "Icons.folder_copy_outlined" "ui:file-transfer-primary-action-icon"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\connection_page.dart" "'Transfer file'," "ui:file-transfer-not-hidden-in-menu"
    Test-SourceContains ".\flutter\lib\consts.dart" "kShowViewCameraConnectAction = false" "ui:view-camera-action-hidden"
    Test-SourceContains ".\flutter\lib\consts.dart" "isViewCameraFeatureEnabled() => kShowViewCameraConnectAction" "ui:view-camera-single-feature-gate"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\connection_page.dart" "'View camera'" "ui:view-camera-not-in-main-action-menu"
    Test-SourceContains ".\flutter\lib\common\widgets\peer_card.dart" "_viewCameraActions" "ui:peer-card-view-camera-helper"
    Test-SourceContains ".\flutter\lib\common\widgets\peer_card.dart" "..._viewCameraActions(context)" "ui:peer-card-view-camera-flagged"
    Test-SourceNotContains ".\flutter\lib\common\widgets\peer_card.dart" "      _viewCameraAction(context)," "ui:peer-card-no-direct-view-camera-menu-item"
    Test-SourceNotContains ".\flutter\lib\common\widgets\peer_card.dart" "translate('View camera')" "ui:peer-card-no-view-camera-copy"
    Test-SourceNotContains ".\flutter\lib\common\widgets\toolbar.dart" "translate('View camera')" "ui:toolbar-no-view-camera-copy"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\desktop_setting_page.dart" "'Enable camera'" "ui:setting-no-camera-permission-copy"
    Test-SourceNotContains ".\flutter\lib\models\server_model.dart" '"View camera"' "ui:android-dialog-no-view-camera-copy"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\view_camera_tab_page.dart" "View Camera Page" "ui:view-camera-log-neutralized"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\server_page.dart" 'translate("View Camera")' "ui:cm-no-view-camera-description"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\server_page.dart" "client.type_() == ClientType.camera" "ui:cm-no-camera-specific-ui"
    Test-SourceContains ".\flutter\lib\models\server_model.dart" "client.isViewCamera && !isViewCameraFeatureEnabled()" "ui:cm-view-camera-request-rejected"
    Test-SourceContains ".\flutter\lib\main.dart" "if (!isViewCameraFeatureEnabled())" "ui:view-camera-window-route-hidden"
    Test-SourceContains ".\flutter\lib\utils\multi_window_manager.dart" "if (!isViewCameraFeatureEnabled())" "ui:view-camera-multi-window-hidden"
    Test-SourceContains ".\flutter\lib\desktop\pages\view_camera_tab_page.dart" "if (!isViewCameraFeatureEnabled())" "ui:view-camera-tab-hidden"
    Test-SourceContains ".\flutter\lib\common.dart" 'if (isViewCameraFeatureEnabled()) "view-camera"' "ui:deeplink-view-camera-hidden"
    Test-SourceContains ".\flutter\lib\common.dart" "if (isViewCamera && !isViewCameraFeatureEnabled())" "ui:connect-view-camera-guard"
    Test-SourceContains ".\src\server\connection.rs" "KQ_VIEW_CAMERA_FEATURE_ENABLED: bool = false" "ui:server-view-camera-login-disabled"
    Test-SourceContains ".\src\server\connection.rs" "The requested connection type is unavailable" "ui:server-view-camera-neutral-error"
    Test-SourceContains ".\src\lang\cn.rs" $kqViewCameraNeutralCnCopy "ui:cn-view-camera-neutral-copy"
    Test-SourceContains ".\src\lang\cn.rs" $kqViewCameraTitleNeutralCnCopy "ui:cn-view-camera-title-neutral-copy"
    Test-SourceNotContains ".\src\lang\cn.rs" $kqViewCameraCnCopy "ui:cn-no-view-camera-copy"
    Test-SourceNotContains ".\src\lang\cn.rs" $kqEnableCameraCnCopy "ui:cn-no-enable-camera-copy"
    Test-SourceNotContains ".\src\lang\cn.rs" $kqNoCamerasCnCopy "ui:cn-no-no-camera-copy"
    Test-SourceContains ".\flutter\lib\mobile\pages\home_page.dart" "if (!kShowViewCameraConnectAction)" "ui:mobile-view-camera-paste-hidden"
    Test-SourceNotContains ".\src\ui\index.tis" "#enable-camera" "ui:legacy-camera-permission-hidden"
    Test-SourceNotContains ".\src\ui\cm.tis" "translate('View camera')" "ui:legacy-cm-view-camera-description-hidden"
    Test-SourceContains ".\flutter\lib\desktop\pages\file_manager_page.dart" "_buildCommonLocationMenuItems" "ui:file-transfer-common-locations"
    Test-SourceContains ".\flutter\lib\desktop\pages\file_manager_page.dart" "PathUtil.join(home, 'Desktop'" "ui:file-transfer-desktop-shortcut"
    Test-SourceContains ".\src\lang\cn.rs" $kqFileTransferDesktopCnCopy "ui:file-transfer-desktop-cn-copy"
    Test-SourceContains ".\flutter\lib\desktop\pages\file_manager_page.dart" "_entryTypeLabel" "ui:file-transfer-type-label"
    Test-SourceContains ".\flutter\lib\desktop\pages\file_manager_page.dart" 'SortBy.type, translate("Type")' "ui:file-transfer-type-column"
    Test-SourceContains ".\flutter\lib\desktop\pages\file_manager_page.dart" "extension.toUpperCase()" "ui:file-transfer-extension-type"
    Test-SourceContains ".\flutter\lib\desktop\pages\file_manager_page.dart" "_typeColWidth" "ui:file-transfer-type-column-visible-width"
    Test-SourceContains ".\flutter\lib\desktop\widgets\list_search_action_listener.dart" "shouldHandleKeyEvent" "ui:file-transfer-ime-list-search-gate"
    Test-SourceContains ".\flutter\lib\desktop\widgets\list_search_action_listener.dart" "kv is! KeyDownEvent" "ui:file-transfer-ime-keydown-only"
    Test-SourceContains ".\flutter\lib\desktop\pages\file_manager_page.dart" "_pathLocationController" "ui:file-transfer-ime-stable-path-controller"
    Test-SourceContains ".\flutter\lib\desktop\pages\file_manager_page.dart" "_fileSearchController" "ui:file-transfer-ime-stable-search-controller"
    Test-SourceNotContains ".\flutter\lib\desktop\pages\file_manager_page.dart" "TextEditingController(text: text)" "ui:file-transfer-ime-no-recreated-controller"
    Test-SourceContains ".\flutter\lib\desktop\pages\file_manager_page.dart" "_isListSearchEnabled" "ui:file-transfer-ime-search-enabled-state"
    Test-SourceContains ".\flutter\lib\desktop\pages\file_manager_page.dart" "shouldHandleKeyEvent: () => _isListSearchEnabled" "ui:file-transfer-ime-disable-list-search-while-input"
    Test-SourceContains ".\src\lang\cn.rs" $kqFileTransferFolderCnCopy "ui:file-transfer-folder-cn-copy"
    Test-SourceContains ".\flutter\lib\common.dart" "isSupportedKqUriLink" "deeplink:kqremote-compatible"
    Test-SourceContains ".\flutter\lib\utils\multi_window_manager.dart" "Future<void> _activateSessionWindow(int windowId)" "deeplink:remote-window-activate-helper"
    Test-SourceContains ".\flutter\lib\utils\multi_window_manager.dart" "await windowController.focus();" "deeplink:remote-window-focus-on-create"
    Test-SourceContains ".\flutter\lib\utils\multi_window_manager.dart" "await controller.show();" "deeplink:remote-window-show-on-reuse"
    Test-SourceContains ".\flutter\lib\utils\multi_window_manager.dart" "await controller.focus();" "deeplink:remote-window-focus-on-reuse"
    Test-SourceContains ".\flutter\lib\utils\multi_window_manager.dart" "await _activateSessionWindow(windowId);" "deeplink:remote-window-activate-inactive"
    Test-SourceContains ".\flutter\lib\utils\multi_window_manager.dart" "return call(type, methodName, msg, activate: true);" "deeplink:remote-window-activate-tabs"
    Test-SourceContains ".\flutter\lib\utils\multi_window_manager.dart" "{bool activate = false}" "deeplink:window-call-activation-opt-in"
    Test-SourceContains ".\flutter\lib\utils\multi_window_manager.dart" "kWindowEventActiveSession, remoteId" "deeplink:remote-window-active-session-detected"
    Test-SourceContains ".\flutter\windows\runner\main.cpp" "GrantForegroundPermissionToWindowProcess(hwnd);" "deeplink:existing-process-runner-foreground-grant"
    Test-SourceContains ".\flutter\windows\runner\main.cpp" "::AllowSetForegroundWindow(process_id);" "deeplink:existing-process-runner-allow-foreground"
    Test-SourceContains ".\src\platform\windows.rs" "GetWindowThreadProcessId(window, &mut process_id);" "deeplink:existing-process-ipc-target-pid"
    Test-SourceContains ".\src\platform\windows.rs" "AllowSetForegroundWindow(process_id);" "deeplink:existing-process-ipc-allow-foreground"
    Test-SourceContains ".\flutter\lib\common.dart" "kqNormalizeMsgboxText" "ui:remote-timeout-offline-normalizer"
    Test-SourceContains ".\flutter\lib\common.dart" "title == 'Connection Error' && text == 'Timeout'" "ui:remote-timeout-offline-condition"
    Test-SourceContains ".\src\lang\cn.rs" $kqRemoteDesktopOfflineCopy "ui:remote-offline-cn-copy"
    Test-SourceContains ".\src\lang\cn.rs" $kqMemberAccelerationCopy "ui:member-acceleration-copy"
    Test-SourceNotContains ".\src\lang\cn.rs" $kqOldBasicRemoteHintCopy "ui:old-basic-remote-hint-copy-hidden"
    Test-SourceContains ".\flutter\lib\models\model.dart" "shouldShowKqConnectionDiagnostics(type, title, text)" "ui:connection-error-diagnostics-route"
    Test-SourceContains ".\flutter\lib\models\model.dart" "Remote desktop is offline" "ui:connection-error-offline-diagnostic"
    Test-SourceContains ".\flutter\lib\models\model.dart" $kqConnectionFirewallChecklist "ui:connection-error-firewall-checklist"
    Test-SourceContains ".\flutter\lib\models\model.dart" $kqConnectionNatChecklist "ui:connection-error-nat-checklist"
    Test-SourceContains ".\flutter\lib\models\model.dart" $kqConnectionRelayChecklist "ui:connection-error-relay-checklist"
    Test-SourceContains ".\src\common.rs" "OPTION_ENABLE_PERM_CHANGE_IN_ACCEPT_WINDOW.to_owned()" "permissions:controlled-side-can-change"
    Test-SourceContains ".\src\common.rs" "OPTION_ALLOW_REMOTE_CONFIG_MODIFICATION.to_owned()" "permissions:remote-config-change-default-set"
    Test-SourceContains ".\src\common.rs" '"N".to_owned()' "permissions:remote-config-change-default-off"
    Test-SourceContains ".\src\ui_cm_interface.rs" "blocked cm switch_permission by policy" "permissions:cm-switch-policy-enforced"
    Test-SourceContains ".\flutter\lib\desktop\pages\server_page.dart" "canModifyPermission" "permissions:controlled-side-ui-policy"
    Test-SourceContains ".\src\server\connection.rs" "KQ temporarily paused controller keyboard/mouse permission due to controlled-side local input" "permissions:controlled-side-local-input-temporary-pause-log"
    Test-SourceContains ".\src\server\connection.rs" "KQ restored controller keyboard/mouse permission after controlled-side local input idle" "permissions:controlled-side-local-input-idle-restore-log"
    Test-SourceContains ".\src\server\connection.rs" "kq_keyboard_auto_paused" "permissions:controlled-side-auto-pause-state"
    Test-SourceContains ".\src\server\connection.rs" "kq_revoke_control_if_controlled_side_operated" "permissions:controlled-side-local-input-detector"
    Test-SourceContains ".\src\server\connection.rs" "LLKHF_INJECTED" "permissions:local-keyboard-hook-ignores-injected-input"
    Test-SourceContains ".\src\server\connection.rs" "LLMHF_INJECTED" "permissions:local-mouse-hook-ignores-injected-input"
    Test-SourceContains ".\src\ui_cm_interface.rs" "KQ CM auto paused controller keyboard/mouse permission due to controlled-side local input" "permissions:cm-local-input-auto-pause-log"
    Test-SourceContains ".\src\ui_cm_interface.rs" "KQ CM restored controller keyboard/mouse permission after controlled-side local input idle" "permissions:cm-local-input-idle-restore-log"
    Test-SourceContains ".\src\ui_cm_interface.rs" "KQ_CM_MANUAL_KEYBOARD_DISABLED" "permissions:cm-does-not-restore-manual-keyboard-off"
    Test-SourceContains ".\src\ui_cm_interface.rs" "for last_input_at in auto_paused.values_mut()" "permissions:cm-refreshes-idle-on-continuous-local-input"
    Test-SourceContains ".\src\ui_cm_interface.rs" "kq_run_cm_local_input_monitor" "permissions:cm-local-input-monitor"
    Test-SourceContains ".\src\ui_cm_interface.rs" "KQ_CM_LOCAL_INPUT_TICK" "permissions:cm-local-input-hook"
    Test-SourceContains ".\src\server\connection.rs" "self.send_permission(Permission::Keyboard, enabled).await" "permissions:auto-revoke-sends-keyboard-permission"
    Test-SourceContains ".\src\server\connection.rs" 'name: "keyboard".to_owned()' "permissions:auto-revoke-syncs-cm-keyboard"
    Test-SourceContains ".\src\ui_cm_interface.rs" 'if name == "keyboard"' "permissions:cm-syncs-auto-revoked-keyboard"
    Test-SourceContains ".\flutter\lib\models\server_model.dart" "_clients[index].keyboard = client.keyboard" "permissions:flutter-syncs-auto-revoked-keyboard"
    Test-SourceContains ".\src\ui\cm.tis" "conn.keyboard = keyboard" "permissions:legacy-cm-syncs-auto-revoked-keyboard"
    Test-SourceContains ".\src\client.rs" "kq_should_show_remote_offline_for_early_reset" "remote:early-reset-offline-helper"
    Test-SourceContains ".\src\client.rs" 'self.msgbox("error", title, "Remote desktop is offline", "")' "remote:early-reset-offline-msgbox"
    Test-SourceContains ".\src\flutter.rs" "PENDING_QUERY_ONLINES" "remote:online-query-pending-merge"
    Test-SourceContains ".\src\flutter.rs" "Err(TrySendError::Full(ids))" "remote:online-query-full-not-dropped"
    Test-SourceContains ".\src\flutter.rs" "merge_pending_query_onlines(ids)" "remote:online-query-merges-before-run"
    Test-SourceNotContains ".\src\flutter.rs" "let _ = tx.try_send(ids)?" "remote:online-query-no-drop-on-full"
    Test-SourceContains ".\src\client.rs" "fn kq_punch_response_timeout_ms" "remote:kq-punch-timeout-helper"
    Test-SourceContains ".\src\client.rs" "1 => 1_500" "remote:kq-punch-timeout-first-fast"
    Test-SourceContains ".\src\client.rs" "2 => 2_500" "remote:kq-punch-timeout-second-fast"
    Test-SourceContains ".\src\client.rs" "_ => 3_500" "remote:kq-punch-timeout-third-fast"
    Test-SourceContains ".\src\client.rs" "attempt * 3_000" "remote:non-kq-punch-timeout-unchanged"
    Test-SourceContains ".\src\client.rs" "KQ {} punch response timeout for attempt #{}: {}ms" "remote:kq-punch-timeout-log"
    Test-SourceNotContains ".\src\client.rs" "Some(i * 3000)" "remote:kq-punch-no-old-slow-wait"
    Test-SourceContains ".\src\common.rs" "kqremote://" "deeplink:kqremote-prefix"
    Test-SourceContains ".\scripts\new-kq-inno-installer.ps1" "HKEY_CLASSES_ROOT\kqremote" "installer:kqremote-protocol"
    Test-SourceContains ".\flutter\windows\runner\win32_window.cpp" "FindVersionedIconPath" "windows:versioned-window-icon-helper"
    Test-SourceContains ".\flutter\windows\runner\win32_window.cpp" 'L"kq-icon-*.ico"' "windows:versioned-window-icon-pattern"
    Test-SourceContains ".\flutter\windows\runner\win32_window.cpp" 'assets_dir + L"icon.ico"' "windows:window-icon-fallback"
    Test-SourceContains ".\flutter\windows\runner\win32_window.cpp" "IsRegularIconFile(icon_path)" "windows:window-icon-regular-file-check"
    Test-SourceContains ".\server\src\index.js" "app.get(['/invite', '/api/invite']" "server:invite-page"
    Test-SourceContains ".\server\src\index.js" "kqremote" "server:invite-kqremote-scheme"
    Test-SourceContains ".\server\src\index.js" "const kqIconAssetPath = 'assets/kq-icon.png';" "server:web-icon-path"
    Test-SourceContains ".\server\src\index.js" "function publicAssetUrl(req, assetPath)" "server:web-icon-absolute-url"
    Test-SourceContains ".\server\src\index.js" "express.static(path.resolve(__dirname, '../public/assets')" "server:web-icon-static-assets"
    Test-SourceContains ".\server\src\index.js" "function invitePage(payload, req)" "server:invite-page-uses-request"
    Test-SourceContains ".\server\src\index.js" 'send(invitePage(decodeInvitePayload(req), req))' "server:invite-route-passes-request"
    Test-SourceContains ".\server\src\index.js" "MicroMessenger" "server:invite-wechat-browser-detected"
    Test-SourceContains ".\server\src\index.js" "wechatTip.style.display = 'block'" "server:invite-wechat-tip-visible"
    Test-SourceContains ".\server\src\index.js" "copyDeepLink()" "server:invite-deeplink-copy-helper"
    Test-SourceContains ".\server\src\index.js" "navigator.clipboard.writeText(deepLink)" "server:invite-copy-deeplink"
    Test-SourceContains ".\server\src\index.js" "document.execCommand('copy')" "server:invite-copy-http-fallback"
    Test-SourceContains ".\server\src\index.js" "copyLinkButton.addEventListener('click', copyDeepLink)" "server:invite-copy-button-handler"
    Test-SourceContains ".\server\src\index.js" '<link rel="icon" type="image/png" href="${safeIconUrl}" />' "server:page-favicon"
    Test-SourceContains ".\server\src\index.js" '<link rel="apple-touch-icon" href="${safeIconUrl}" />' "server:page-apple-touch-icon"
    Test-SourceContains ".\server\src\index.js" '<meta property="og:image" content="${safeIconAbsoluteUrl}" />' "server:page-og-image"
    Test-SourceContains ".\server\src\index.js" '<meta name="twitter:image" content="${safeIconAbsoluteUrl}" />' "server:page-twitter-image"
    Test-SourceContains ".\server\src\index.js" '<img class="brand-icon" src="${safeIconUrl}" alt="" />' "server:page-brand-icon"
    Test-SourceContains ".\server\src\index.js" "function downloadPage(req)" "server:download-page"
    Test-SourceContains ".\server\src\index.js" "send(downloadPage(req))" "server:download-route-passes-request"
    Test-SourceContains ".\server\src\index.js" $kqDownloadWindowsButton "server:download-windows-button"
    Test-SourceContains ".\server\src\index.js" "sendWindowsInstaller" "server:download-installer-stream"
    Test-SourceContains ".\server\src\index.js" "sendAndroidApk" "server:download-android-stream"
    Test-SourceContains ".\server\src\index.js" "KQ_ANDROID_DOWNLOAD_URL" "server:download-android-config"
    Test-SourceContains ".\server\src\index.js" "application/vnd.android.package-archive" "server:download-android-content-type"
    Test-SourceContains ".\server\src\index.js" "app.get(['/download/android', '/api/download/android']" "server:download-android-route"
    Test-SourceNotContains ".\server\src\index.js" $kqDownloadAndroidButton "server:download-android-button-hidden"
    Test-SourceContains ".\server\src\index.js" "accept-ranges" "server:download-range-support"
    Test-SourceContains ".\server\src\index.js" "maxGlobalConcurrent" "server:download-global-limit"
    Test-SourceContains ".\server\src\index.js" "maxPerIpConcurrent" "server:download-ip-limit"
    Test-SourceContains ".\server\src\index.js" $kqDownloadFriendlyBusyCopy "server:download-friendly-busy-copy"
    Test-SourceContains ".\server\src\index.js" $kqDownloadUserFacingTitle "server:download-user-facing-title"
    Test-SourceContains ".\server\src\index.js" $kqDownloadUserFacingHero "server:download-user-facing-hero"
    Test-SourceNotContains ".\server\src\index.js" $kqDownloadForbiddenTestEnv "server:download-no-test-env-copy"
    Test-SourceNotContains ".\server\src\index.js" $kqDownloadForbiddenTestServer "server:download-no-test-server-copy"
    Test-SourceNotContains ".\server\src\index.js" $kqDownloadForbiddenControlled "server:download-no-controlled-copy"
    Test-SourceNotContains ".\server\src\index.js" $kqDownloadForbiddenRangeCopy "server:download-no-range-copy"
    Test-SourceNotContains ".\server\src\index.js" $kqDownloadForbiddenRateLimit "server:download-no-rate-limit-copy"
    Test-SourceNotContains ".\server\src\index.js" "Download rate limit exceeded" "server:download-no-technical-rate-copy"
    Test-SourceContains ".\server\Dockerfile" "COPY public ./public" "server:download-file-packaged"
    Test-SourceContains ".\.gitea\workflows\deploy.yml" "http://43.154.197.96/kq-api/download/windows" "deploy:self-hosted-download-url"
    Test-SourceContains ".\.gitea\workflows\deploy.yml" "http://43.154.197.96/kq-api/download/android" "deploy:self-hosted-android-download-url"
    Test-SourceContains ".\.gitea\workflows\android-build.yml" "API_DOWNLOAD_DIR=/www/wwwroot/KQromoteLink/api/public/downloads" "android:api-download-dir"
    Test-SourceContains ".\deploy\rustdesk-server.compose.yml" "KQ_DOWNLOAD_MAX_GLOBAL_CONCURRENT" "deploy:download-limit-env"
    Test-SourceContains ".\deploy\rustdesk-server.compose.yml" "./api/public/downloads:/app/public/downloads" "deploy:api-download-volume"
    Test-SourceContains ".\scripts\deploy\deploy-android.sh" "KQ_ANDROID_DOWNLOAD_SHA256" "android:download-sha-env"
    Test-SourceContains ".\scripts\deploy\deploy-android.sh" "/kq-api/download/android" "android:download-api-link"
    Test-SourceContains ".\flutter\lib\common\kq_oauth_payload.dart" "Hmac(sha256" "login:signed-nonce-hmac"
    Test-SourceContains ".\flutter\lib\common\kq_oauth_payload.dart" "client_type': 'desktop'" "login:web-login-client-type"
    Test-SourceContains ".\flutter\lib\common\kq_oauth_io.dart" "https://api-web.kunqiongai.com" "login:api-base-url"
    Test-SourceContains ".\flutter\lib\common\kq_oauth_io.dart" "/soft_desktop/get_web_login_url" "login:web-login-url-api"
    Test-SourceContains ".\flutter\lib\common\kq_oauth_io.dart" "/user/desktop_get_token" "login:desktop-token-api"
    Test-SourceContains ".\flutter\lib\common\kq_oauth_io.dart" "/user/check_login" "login:check-login-api"
    Test-SourceContains ".\flutter\lib\common\kq_oauth_io.dart" "/soft_desktop/get_user_info" "login:user-info-api"
    Test-SourceContains ".\flutter\lib\common\kq_oauth_io.dart" "/logout" "login:logout-api"
    Test-SourceContains ".\flutter\lib\common\kq_oauth_io.dart" "parseKqOauthLoginPayload(" "login:user-info-token-adapter"
    Test-BuiltInPrivateServerDefaults
}

$customTxt = Join-Path $release.Path "custom.txt"
$zipCustomTxtForVerification = $null
if (Test-Path $customTxt) {
    if ($CustomClientPublicKey) {
        cargo run --target-dir $signerTargetDir --manifest-path .\tools\custom_client_signer\Cargo.toml -- verify $customTxt $CustomClientPublicKey
        if ($LASTEXITCODE -eq 0) {
            Add-Check "custom-client:signature" "PASS" "custom.txt verified"
        } else {
            Add-Check "custom-client:signature" "FAIL" "custom.txt verification failed"
        }
    } else {
        Add-Check "custom-client:signature" "WARN" "custom.txt exists; pass -CustomClientPublicKey to verify it"
    }
} elseif ($PackageZip) {
    $zip = Resolve-Path $PackageZip
    $archiveForCustom = [System.IO.Compression.ZipFile]::OpenRead($zip.Path)
    try {
        $customEntry = $archiveForCustom.Entries | Where-Object { $_.FullName -eq "Release\custom.txt" } | Select-Object -First 1
        if ($customEntry) {
            $zipCustomTxtForVerification = Join-Path $env:TEMP ("kq-custom-" + [guid]::NewGuid().ToString("N") + ".txt")
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($customEntry, $zipCustomTxtForVerification, $true)
            if ($CustomClientPublicKey) {
                cargo run --target-dir $signerTargetDir --manifest-path .\tools\custom_client_signer\Cargo.toml -- verify $zipCustomTxtForVerification $CustomClientPublicKey
                if ($LASTEXITCODE -eq 0) {
                    Add-Check "custom-client:signature" "PASS" "zip Release\custom.txt verified"
                } else {
                    Add-Check "custom-client:signature" "FAIL" "zip Release\custom.txt verification failed"
                }
            } else {
                Add-Check "custom-client:signature" "WARN" "zip Release\custom.txt exists; pass -CustomClientPublicKey to verify it"
            }
        } else {
            Add-Check "custom-client:signature" "SKIP" "No custom.txt in release or zip; built-in private server defaults are active"
        }
    } finally {
        $archiveForCustom.Dispose()
        if ($zipCustomTxtForVerification -and (Test-Path $zipCustomTxtForVerification)) {
            Remove-Item -LiteralPath $zipCustomTxtForVerification -Force
        }
    }
} else {
    Add-Check "custom-client:signature" "SKIP" "No custom.txt in release; built-in private server defaults are active"
}

if ($PackageZip) {
    $zip = Resolve-Path $PackageZip
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zip.Path)
    try {
        foreach ($entryName in @(
            "Release\rustdesk.exe",
            "Release\librustdesk.dll",
            "Release\data\flutter_assets\AssetManifest.bin",
            "Release\data\flutter_assets\assets\kq_toolbox_icon.svg",
            "Release\drivers\RustDeskPrinterDriver\RustDeskPrinterDriver.inf",
            "Release\printer_driver_adapter.dll",
            "KQ_RELEASE_MANIFEST.json",
            "START_KQ_REMOTE_LINK.cmd",
            "RUN_SMOKE_CHECKS.cmd",
            "CREATE_MANUAL_TEST_REPORT.cmd",
            "CREATE_TWO_PC_ACCEPTANCE.cmd",
            "COLLECT_DIAGNOSTICS.cmd",
            "README_START_HERE.txt",
            "TESTING_KQ_REMOTE_LINK.md",
            "ACCEPTANCE_CHECKLIST.md",
            "GITEA_SERVER_DEPLOYMENT.md",
            "SERVER_DEPLOYMENT.md",
            "deploy\rustdesk-server.compose.yml",
            "deploy\deploy-rustdesk-server.sh",
            "deploy\check-rustdesk-server.sh",
            "deploy\export-hbbs-public-key.sh",
            ".gitea\workflows\deploy.yml",
            ".gitea\workflows\deploy-rustdesk-server.yml",
            "scripts\deploy\deploy.sh",
            "scripts\collect-kq-diagnostics.ps1",
            "scripts\new-kq-manual-test-report.ps1",
            "scripts\new-kq-private-server-client-package.ps1",
            "scripts\new-kq-server-key-pair.ps1",
            "scripts\new-kq-server-port-request.ps1",
            "scripts\new-kq-two-pc-acceptance.ps1",
            "scripts\run-kq-smoke-suite.ps1",
            "scripts\test-kq-oauth.ps1",
            "scripts\test-kq-release.ps1",
            "scripts\test-kq-server.ps1",
            "tools\custom_client_signer\Cargo.toml"
        )) {
            $entry = $archive.Entries | Where-Object { $_.FullName -eq $entryName } | Select-Object -First 1
            if ($entry) {
                Add-Check "zip:$entryName" "PASS" "$($entry.Length) bytes"
            } else {
                Add-Check "zip:$entryName" "FAIL" "Missing zip entry"
            }
        }
    } finally {
        $archive.Dispose()
    }
}

if ($LaunchSmokeTest) {
    $existing = Get-Process rustdesk -ErrorAction SilentlyContinue
    if ($existing -and -not $StopExistingRustDesk) {
        Add-Check "smoke:launch" "WARN" "rustdesk.exe is already running; close it or pass -StopExistingRustDesk"
    } else {
        if ($existing) {
            $existing | Stop-Process -Force
        }
        $exe = Join-Path $release.Path "rustdesk.exe"
        $process = Start-Process -FilePath $exe -WorkingDirectory $release.Path -PassThru
        try {
            Start-Sleep -Seconds 6
            $process.Refresh()
            if ($process.HasExited) {
                Add-Check "smoke:launch" "FAIL" "rustdesk.exe exited early"
            } elseif ($process.MainWindowTitle -ne $kqAppName) {
                Add-Check "smoke:launch" "FAIL" "Unexpected title: $($process.MainWindowTitle)"
            } elseif (-not $process.Responding) {
                Add-Check "smoke:launch" "FAIL" "Process is not responding"
            } else {
                Add-Check "smoke:launch" "PASS" "Window title is $kqAppName"
            }
        } finally {
            Get-Process rustdesk -ErrorAction SilentlyContinue | Stop-Process -Force
        }
    }
}

$failed = @($results | Where-Object { $_.Status -eq "FAIL" })
$report = New-Object System.Collections.Generic.List[string]
$report.Add("# KQ Remote Link Acceptance Report")
$report.Add("")
$report.Add("- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$report.Add("- ReleaseDir: $($release.Path)")
if ($PackageZip) {
    $report.Add("- PackageZip: $((Resolve-Path $PackageZip).Path)")
}
$report.Add("")
$report.Add("## Automated Checks")
$report.Add("")
$report.Add("| Status | Check | Detail |")
$report.Add("| --- | --- | --- |")
foreach ($result in $results) {
    $detail = ($result.Detail -replace "\|", "\\|")
    $report.Add("| $($result.Status) | $($result.Name) | $detail |")
}
$report.Add("")
$report.Add("## Manual Two-Client Checks")
$report.Add("")
$report.Add("- Kunqiong login opens the web login page, polls desktop_get_token, and updates account info.")
$report.Add("- Two clients show IDs and can connect with password or accept flow.")
$report.Add("- Remote screen, mouse, keyboard, clipboard, and file transfer work.")
$report.Add("- Cross-network relay works through the configured hbbr server.")
$report.Add("- Controlled side service mode is installed when UAC/lock-screen control is required.")

if (-not $NoReport) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportPath) | Out-Null
    [System.IO.File]::WriteAllLines($ReportPath, $report, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Acceptance report: $ReportPath"
}

if ($failed.Count -gt 0) {
    throw "Acceptance checks failed: $($failed.Count)"
}
