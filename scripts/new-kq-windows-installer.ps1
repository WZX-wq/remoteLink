param(
    [string]$ReleaseDir,
    [string]$OutputRoot = "C:\kq-remote-link-tools",
    [string]$InstallerName,
    [string]$Version = (Get-Date -Format "yyyy.MM.dd.HHmm")
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

function Get-WritableOutputRoot($PreferredPath) {
    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @($PreferredPath, (Join-Path $env:TEMP ("kq-remote-link-tools-" + [guid]::NewGuid().ToString("N"))))) {
        try {
            $dir = New-Item -ItemType Directory -Force -Path $candidate
            $probe = Join-Path $dir.FullName ("write-test-" + [guid]::NewGuid().ToString("N"))
            [System.IO.File]::WriteAllText($probe, "ok")
            Remove-Item -LiteralPath $probe -Force
            return $dir.FullName
        } catch {
            $errors.Add("${candidate}: $($_.Exception.Message)")
            continue
        }
    }
    throw "No writable output directory found. Tried: $($errors -join '; ')"
}

function Invoke-WithRetry($Name, [scriptblock]$Body, [int]$Attempts = 5, [int]$DelaySeconds = 2) {
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            & $Body
            return
        } catch {
            if ($i -ge $Attempts) {
                throw
            }
            Write-Host "$Name failed on attempt $i/${Attempts}: $($_.Exception.Message)"
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

if (-not $ReleaseDir) {
    $ReleaseDir = Join-Path $repo "flutter\build\windows\x64\runner\Release"
}
if (-not $InstallerName) {
    $InstallerName = "KQ-Remote-Link-Setup-$(Get-Date -Format 'yyyyMMdd-HHmm')"
}
if (-not $InstallerName.EndsWith(".exe", [System.StringComparison]::OrdinalIgnoreCase)) {
    $InstallerName = "$InstallerName.exe"
}

$release = Resolve-Path $ReleaseDir
$output = New-Item -ItemType Directory -Force -Path (Get-WritableOutputRoot $OutputRoot)
$installerPath = Join-Path $output.FullName $InstallerName
$buildRoot = Join-Path $output.FullName ([System.IO.Path]::GetFileNameWithoutExtension($InstallerName) + "-build")
$payloadRoot = Join-Path $buildRoot "payload"
$installerStage = Join-Path $buildRoot "installer"
$payloadZip = Join-Path $installerStage "payload.zip"
$sedPath = Join-Path $buildRoot "installer.sed"
$productDisplayName = [string]::Concat([char[]]@(0x9CB2, 0x7A79, 0x8FDC, 0x7A0B, 0x684C, 0x9762))
$brandLogoPngBase64 = ""
$brandIconPath = Join-Path $repo "flutter\windows\runner\resources\app_icon.ico"
$brandIconBase64 = ""
if (Test-Path $brandIconPath) {
    $iconBytes = [System.IO.File]::ReadAllBytes($brandIconPath)
    $brandIconBase64 = [System.Convert]::ToBase64String($iconBytes)
    $pngHeader = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
    $pngOffset = -1
    for ($i = 0; $i -le $iconBytes.Length - $pngHeader.Length; $i++) {
        $matched = $true
        for ($j = 0; $j -lt $pngHeader.Length; $j++) {
            if ($iconBytes[$i + $j] -ne $pngHeader[$j]) {
                $matched = $false
                break
            }
        }
        if ($matched) {
            $pngOffset = $i
            break
        }
    }
    if ($pngOffset -ge 0) {
        $pngLength = $iconBytes.Length - $pngOffset
        $pngBytes = New-Object byte[] $pngLength
        [System.Array]::Copy($iconBytes, $pngOffset, $pngBytes, 0, $pngLength)
        $brandLogoPngBase64 = [System.Convert]::ToBase64String($pngBytes)
    }
}

$required = @(
    "rustdesk.exe",
    "librustdesk.dll",
    "flutter_windows.dll",
    "data\flutter_assets\AssetManifest.bin",
    "data\flutter_assets\assets\kq_toolbox_icon.svg"
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
if (Test-Path $installerPath) {
    Remove-Item -LiteralPath $installerPath -Force
}

New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null
New-Item -ItemType Directory -Path $installerStage -Force | Out-Null
Copy-Item -Path (Join-Path $release.Path "*") -Destination $payloadRoot -Recurse -Force

$exeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $payloadRoot "rustdesk.exe")).Hash.ToLowerInvariant()
$dllHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $payloadRoot "librustdesk.dll")).Hash.ToLowerInvariant()
$manifest = [ordered]@{
    "appName" = $productDisplayName
    "installerName" = $InstallerName
    "version" = $Version
    "generatedAt" = (Get-Date).ToString("o")
    "installScope" = "CurrentUser"
    "installDir" = "%LOCALAPPDATA%\KQRemoteLink"
    "release" = [ordered]@{
        "rustdeskExeSha256" = $exeHash
        "librustdeskDllSha256" = $dllHash
    }
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $payloadRoot "KQ_RELEASE_MANIFEST.json"), (($manifest | ConvertTo-Json -Depth 5) + "`n"), $utf8NoBom)

Invoke-WithRetry "Compress payload" {
    if (Test-Path $payloadZip) {
        Remove-Item -LiteralPath $payloadZip -Force
    }
    Compress-Archive -Path (Join-Path $payloadRoot "*") -DestinationPath $payloadZip -CompressionLevel Optimal
}

$launcherSource = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

internal static class Program
{
    private static string Quote(string value)
    {
        if (value == null)
        {
            return "\"\"";
        }
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    private static int Main(string[] args)
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string ps1 = Path.Combine(dir, "install.ps1");
        var arguments = new StringBuilder();
        arguments.Append("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ");
        arguments.Append(Quote(ps1));
        foreach (string arg in args)
        {
            arguments.Append(' ');
            arguments.Append(Quote(arg));
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = arguments.ToString(),
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
            WorkingDirectory = dir
        };

        using (var process = Process.Start(startInfo))
        {
            if (process == null)
            {
                return 1;
            }
            process.WaitForExit();
            return process.ExitCode;
        }
    }
}
'@
$launcherSourcePath = Join-Path $installerStage "install-launcher.cs"
$launcherExePath = Join-Path $installerStage "install-launcher.exe"
[System.IO.File]::WriteAllText($launcherSourcePath, $launcherSource, [System.Text.Encoding]::ASCII)
$launcherIconArg = @()
if (Test-Path $brandIconPath) {
    $launcherIconArg = @("/win32icon:$brandIconPath")
}
$csc = (Get-Command csc.exe -ErrorAction SilentlyContinue).Source
if (-not $csc) {
    $csc = @(
        "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
        "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $csc) {
    throw "csc.exe not found. .NET Framework compiler is required to create the hidden installer launcher."
}
& $csc /nologo /target:winexe /optimize+ /out:$launcherExePath @launcherIconArg $launcherSourcePath
if (-not (Test-Path $launcherExePath)) {
    throw "Failed to build installer launcher: $launcherExePath"
}

$installPs1 = @'
param(
    [switch]$Silent,
    [string]$Dir,
    [switch]$NoLaunch,
    [switch]$NoDesktopShortcut,
    [switch]$NoStartMenuShortcut,
    [switch]$AutoStart
)

$ErrorActionPreference = "Stop"

$AppId = "KQRemoteLink"
$DisplayName = [string]::Concat([char[]]@(0x9CB2,0x7A79,0x8FDC,0x7A0B,0x684C,0x9762))
$BrandIconBase64 = "__BRAND_ICON_BASE64__"
$BrandLogoPngBase64 = "__BRAND_LOGO_PNG_BASE64__"
$LegacyDisplayName = [string]::Concat([char[]]@(0x9CB2,0x7A79,0x5DE5,0x5177,0x7BB1))
$Publisher = "Kunqiong"
$Version = "__VERSION__"
$DefaultInstallDir = Join-Path $env:LOCALAPPDATA $AppId
$InstallDir = $DefaultInstallDir
$PayloadZip = Join-Path $PSScriptRoot "payload.zip"
$TempDir = Join-Path $env:TEMP ("kq-remote-link-install-" + [guid]::NewGuid().ToString("N"))
$LogPath = Join-Path $env:TEMP "kq-remote-link-install.log"
$UninstallScriptName = "uninstall.ps1"

function U([int[]]$Codes) {
    return [string]::Concat([char[]]$Codes)
}

function Write-InstallLog($Message) {
    $line = "$(Get-Date -Format o) $Message"
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Escape-PowerShellSingleQuotedString($Value) {
    return ($Value -replace "'", "''")
}

function Get-AppProcess {
    Get-Process rustdesk -ErrorAction SilentlyContinue | Where-Object {
        try {
            if (-not $_.Path) {
                return $false
            }
            $_.Path.StartsWith($InstallDir, [System.StringComparison]::OrdinalIgnoreCase) -or
                ($previousInstallDir -and $_.Path.StartsWith($previousInstallDir, [System.StringComparison]::OrdinalIgnoreCase))
        } catch {
            $false
        }
    }
}

function Get-InstallOptions {
    $launchAfterInstall = -not $NoLaunch -and $env:KQ_REMOTE_LINK_INSTALL_NO_LAUNCH -ne "1"
    $installDir = if (-not [string]::IsNullOrWhiteSpace($Dir)) {
        $Dir
    } elseif (-not [string]::IsNullOrWhiteSpace($env:KQ_REMOTE_LINK_INSTALL_DIR)) {
        $env:KQ_REMOTE_LINK_INSTALL_DIR
    } else {
        $DefaultInstallDir
    }

    if ($Silent -or $env:KQ_REMOTE_LINK_INSTALL_SILENT -eq "1") {
        return [pscustomobject]@{
            InstallDir = $installDir
            CreateDesktopShortcut = -not $NoDesktopShortcut
            CreateStartMenuShortcut = -not $NoStartMenuShortcut
            AutoStart = [bool]$AutoStart
            LaunchAfterInstall = $launchAfterInstall
        }
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    [System.Windows.Forms.Application]::EnableVisualStyles()
    $blue = [System.Drawing.Color]::FromArgb(22, 115, 232)
    $blueDark = [System.Drawing.Color]::FromArgb(11, 78, 174)
    $blueSoft = [System.Drawing.Color]::FromArgb(229, 245, 255)
    $sky = [System.Drawing.Color]::FromArgb(196, 231, 255)
    $textPrimary = [System.Drawing.Color]::FromArgb(19, 35, 60)
    $textMuted = [System.Drawing.Color]::FromArgb(92, 111, 137)
    $border = [System.Drawing.Color]::FromArgb(198, 221, 244)
    $cardBack = [System.Drawing.Color]::White

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$DisplayName " + (U @(0x5B89,0x88C5,0x5411,0x5BFC))
    if (-not [string]::IsNullOrWhiteSpace($BrandIconBase64)) {
        try {
            $iconBytes = [System.Convert]::FromBase64String($BrandIconBase64)
            $iconStream = New-Object System.IO.MemoryStream(,$iconBytes)
            $form.Icon = New-Object System.Drawing.Icon($iconStream)
        } catch {
            Write-InstallLog "Failed to set installer icon: $($_.Exception.Message)"
        }
    }
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(680, 438)
    $form.BackColor = [System.Drawing.Color]::FromArgb(246, 251, 255)
    $form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)

    $header = New-Object System.Windows.Forms.Panel
    $header.Location = New-Object System.Drawing.Point(0, 0)
    $header.Size = New-Object System.Drawing.Size(680, 118)
    $header.BackColor = $blueSoft
    $header.Add_Paint({
        param($sender, $eventArgs)
        $graphics = $eventArgs.Graphics
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            $sender.ClientRectangle,
            [System.Drawing.Color]::FromArgb(247, 252, 255),
            [System.Drawing.Color]::FromArgb(214, 239, 255),
            [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal
        )
        $graphics.FillRectangle($brush, $sender.ClientRectangle)
        $brush.Dispose()
        $haloBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(90, 255, 255, 255))
        $graphics.FillEllipse($haloBrush, (New-Object System.Drawing.Rectangle(500, -58, 210, 160)))
        $haloBrush.Dispose()
        $linePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(225, 245, 255), 2)
        $graphics.DrawBezier($linePen, 410, 98, 485, 66, 550, 106, 680, 72)
        $linePen.Dispose()
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(190, 218, 245), 1)
        $graphics.DrawLine($pen, 0, $sender.Height - 1, $sender.Width, $sender.Height - 1)
        $pen.Dispose()
    })
    $form.Controls.Add($header)

    $brandMark = New-Object System.Windows.Forms.Panel
    $brandMark.Location = New-Object System.Drawing.Point(26, 27)
    $brandMark.Size = New-Object System.Drawing.Size(58, 58)
    $brandMark.BackColor = [System.Drawing.Color]::Transparent
    $brandMark.Add_Paint({
        param($sender, $eventArgs)
        $graphics = $eventArgs.Graphics
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $shadow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(40, 36, 118, 210))
        $graphics.FillEllipse($shadow, (New-Object System.Drawing.Rectangle(4, 7, 50, 50)))
        $shadow.Dispose()
        $back = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $graphics.FillEllipse($back, (New-Object System.Drawing.Rectangle(3, 3, 50, 50)))
        $back.Dispose()
    })
    $header.Controls.Add($brandMark)

    if (-not [string]::IsNullOrWhiteSpace($BrandLogoPngBase64)) {
        $logoBytes = [System.Convert]::FromBase64String($BrandLogoPngBase64)
        $logoStream = New-Object System.IO.MemoryStream(,$logoBytes)
        $logoImage = [System.Drawing.Image]::FromStream($logoStream)
        $logo = New-Object System.Windows.Forms.PictureBox
        $logo.Location = New-Object System.Drawing.Point(31, 32)
        $logo.Size = New-Object System.Drawing.Size(48, 48)
        $logo.BackColor = [System.Drawing.Color]::Transparent
        $logo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $logo.Image = $logoImage
        $header.Controls.Add($logo)
        $logo.BringToFront()
    }

    $title = New-Object System.Windows.Forms.Label
    $title.Text = $DisplayName
    $title.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 17, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = $textPrimary
    $title.BackColor = [System.Drawing.Color]::Transparent
    $title.Location = New-Object System.Drawing.Point(98, 28)
    $title.Size = New-Object System.Drawing.Size(520, 32)
    $header.Controls.Add($title)

    $tip = New-Object System.Windows.Forms.Label
    $tip.Text = U @(0x8BF7,0x9009,0x62E9,0x5B89,0x88C5,0x4F4D,0x7F6E,0x548C,0x5B89,0x88C5,0x9009,0x9879,0x3002)
    $tip.ForeColor = $textMuted
    $tip.BackColor = [System.Drawing.Color]::Transparent
    $tip.Location = New-Object System.Drawing.Point(100, 64)
    $tip.Size = New-Object System.Drawing.Size(520, 22)
    $header.Controls.Add($tip)

    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point(26, 140)
    $card.Size = New-Object System.Drawing.Size(628, 216)
    $card.BackColor = $cardBack
    $card.Add_Paint({
        param($sender, $eventArgs)
        $graphics = $eventArgs.Graphics
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $accentBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 251, 255))
        $graphics.FillRectangle($accentBrush, 1, 1, $sender.Width - 2, 54)
        $accentBrush.Dispose()
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(198, 221, 244), 1)
        $graphics.DrawRectangle($pen, 0, 0, $sender.Width - 1, $sender.Height - 1)
        $pen.Dispose()
    })
    $form.Controls.Add($card)

    $pathLabel = New-Object System.Windows.Forms.Label
    $pathLabel.Text = U @(0x5B89,0x88C5,0x4F4D,0x7F6E)
    $pathLabel.ForeColor = $textPrimary
    $pathLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
    $pathLabel.BackColor = $cardBack
    $pathLabel.Location = New-Object System.Drawing.Point(24, 24)
    $pathLabel.Size = New-Object System.Drawing.Size(90, 22)
    $card.Controls.Add($pathLabel)

    $pathBox = New-Object System.Windows.Forms.TextBox
    $pathBox.Text = $installDir
    $pathBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $pathBox.Location = New-Object System.Drawing.Point(112, 22)
    $pathBox.Size = New-Object System.Drawing.Size(390, 24)
    $pathBox.BackColor = [System.Drawing.Color]::FromArgb(252, 254, 255)
    $card.Controls.Add($pathBox)

    $browseButton = New-Object System.Windows.Forms.Button
    $browseButton.Text = U @(0x6D4F,0x89C8,0x002E,0x002E,0x002E)
    $browseButton.Location = New-Object System.Drawing.Point(516, 19)
    $browseButton.Size = New-Object System.Drawing.Size(82, 30)
    $browseButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $browseButton.FlatAppearance.BorderColor = $border
    $browseButton.BackColor = [System.Drawing.Color]::FromArgb(245, 250, 255)
    $browseButton.ForeColor = $blueDark
    $browseButton.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = U @(0x9009,0x62E9,0x5B89,0x88C5,0x76EE,0x5F55)
        if (Test-Path $pathBox.Text -PathType Container) {
            $dialog.SelectedPath = $pathBox.Text
        } else {
            $dialog.SelectedPath = $DefaultInstallDir
        }
        if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $pathBox.Text = $dialog.SelectedPath
        }
    })
    $card.Controls.Add($browseButton)

    $optionLabel = New-Object System.Windows.Forms.Label
    $optionLabel.Text = U @(0x5B89,0x88C5,0x9009,0x9879)
    $optionLabel.ForeColor = $textPrimary
    $optionLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
    $optionLabel.BackColor = $cardBack
    $optionLabel.Location = New-Object System.Drawing.Point(24, 74)
    $optionLabel.Size = New-Object System.Drawing.Size(90, 22)
    $card.Controls.Add($optionLabel)

    $desktopCheck = New-Object System.Windows.Forms.CheckBox
    $desktopCheck.Text = U @(0x521B,0x5EFA,0x684C,0x9762,0x5FEB,0x6377,0x65B9,0x5F0F)
    $desktopCheck.Checked = $true
    $desktopCheck.ForeColor = $textPrimary
    $desktopCheck.BackColor = $cardBack
    $desktopCheck.Location = New-Object System.Drawing.Point(112, 72)
    $desktopCheck.Size = New-Object System.Drawing.Size(220, 24)
    $card.Controls.Add($desktopCheck)

    $startMenuCheck = New-Object System.Windows.Forms.CheckBox
    $startMenuCheck.Text = U @(0x521B,0x5EFA,0x5F00,0x59CB,0x83DC,0x5355,0x5FEB,0x6377,0x65B9,0x5F0F)
    $startMenuCheck.Checked = $true
    $startMenuCheck.ForeColor = $textPrimary
    $startMenuCheck.BackColor = $cardBack
    $startMenuCheck.Location = New-Object System.Drawing.Point(348, 72)
    $startMenuCheck.Size = New-Object System.Drawing.Size(245, 24)
    $card.Controls.Add($startMenuCheck)

    $autoStartCheck = New-Object System.Windows.Forms.CheckBox
    $autoStartCheck.Text = U @(0x5F00,0x673A,0x81EA,0x542F,0x52A8)
    $autoStartCheck.Checked = $false
    $autoStartCheck.ForeColor = $textPrimary
    $autoStartCheck.BackColor = $cardBack
    $autoStartCheck.Location = New-Object System.Drawing.Point(112, 108)
    $autoStartCheck.Size = New-Object System.Drawing.Size(220, 24)
    $card.Controls.Add($autoStartCheck)

    $launchCheck = New-Object System.Windows.Forms.CheckBox
    $launchCheck.Text = U @(0x5B89,0x88C5,0x5B8C,0x6210,0x540E,0x7ACB,0x5373,0x6253,0x5F00)
    $launchCheck.Checked = $launchAfterInstall
    $launchCheck.ForeColor = $textPrimary
    $launchCheck.BackColor = $cardBack
    $launchCheck.Location = New-Object System.Drawing.Point(348, 108)
    $launchCheck.Size = New-Object System.Drawing.Size(245, 24)
    $card.Controls.Add($launchCheck)

    $note = New-Object System.Windows.Forms.Label
    $note.Text = U @(0x5B89,0x88C5,0x540E,0x53EF,0x4EE5,0x901A,0x8FC7,0x684C,0x9762,0x6216,0x5F00,0x59CB,0x83DC,0x5355,0x542F,0x52A8,0x3002)
    $note.ForeColor = $textMuted
    $note.BackColor = $cardBack
    $note.Location = New-Object System.Drawing.Point(112, 158)
    $note.Size = New-Object System.Drawing.Size(480, 22)
    $card.Controls.Add($note)

    $installButton = New-Object System.Windows.Forms.Button
    $installButton.Text = U @(0x5B89,0x88C5)
    $installButton.Location = New-Object System.Drawing.Point(448, 376)
    $installButton.Size = New-Object System.Drawing.Size(96, 36)
    $installButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $installButton.FlatAppearance.BorderSize = 0
    $installButton.BackColor = $blue
    $installButton.ForeColor = [System.Drawing.Color]::White
    $installButton.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9, [System.Drawing.FontStyle]::Bold)
    $installButton.Add_Click({
        if ([string]::IsNullOrWhiteSpace($pathBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show((U @(0x8BF7,0x9009,0x62E9,0x5B89,0x88C5,0x4F4D,0x7F6E,0x3002)), $DisplayName, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        $form.Tag = [pscustomobject]@{
            InstallDir = $pathBox.Text.Trim()
            CreateDesktopShortcut = $desktopCheck.Checked
            CreateStartMenuShortcut = $startMenuCheck.Checked
            AutoStart = $autoStartCheck.Checked
            LaunchAfterInstall = $launchCheck.Checked
        }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($installButton)
    $form.AcceptButton = $installButton

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = U @(0x53D6,0x6D88)
    $cancelButton.Location = New-Object System.Drawing.Point(558, 376)
    $cancelButton.Size = New-Object System.Drawing.Size(96, 36)
    $cancelButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $cancelButton.FlatAppearance.BorderColor = $border
    $cancelButton.BackColor = [System.Drawing.Color]::White
    $cancelButton.ForeColor = $textMuted
    $cancelButton.Add_Click({
        $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Close()
    })
    $form.Controls.Add($cancelButton)
    $form.CancelButton = $cancelButton

    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $form.Tag
    }
    return $null
}

try {
    Write-InstallLog "Install started."
    if (-not (Test-Path $PayloadZip)) {
        throw "Missing installer payload: $PayloadZip"
    }

    $options = Get-InstallOptions
    if ($null -eq $options) {
        Write-InstallLog "Install cancelled."
        exit 0
    }
    $InstallDir = [System.IO.Path]::GetFullPath($options.InstallDir)
    $CreateDesktopShortcut = [bool]$options.CreateDesktopShortcut
    $CreateStartMenuShortcut = [bool]$options.CreateStartMenuShortcut
    $AutoStart = [bool]$options.AutoStart
    $LaunchAfterInstall = [bool]$options.LaunchAfterInstall
    $uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\KQRemoteLink"
    $previousInstallDir = if (Test-Path $uninstallKey) {
        (Get-ItemProperty -Path $uninstallKey -Name InstallLocation -ErrorAction SilentlyContinue).InstallLocation
    } else {
        $null
    }

    $running = Get-AppProcess
    if ($running) {
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $running.Id -Timeout 10 -ErrorAction SilentlyContinue
    }

    if (Test-Path $TempDir) {
        Remove-Item -LiteralPath $TempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    Expand-Archive -LiteralPath $PayloadZip -DestinationPath $TempDir -Force

    if (Test-Path $InstallDir -PathType Leaf) {
        throw "Install path points to a file: $InstallDir"
    }
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Copy-Item -Path (Join-Path $TempDir "*") -Destination $InstallDir -Recurse -Force

    $ExePath = Join-Path $InstallDir "rustdesk.exe"
    if (-not (Test-Path $ExePath)) {
        throw "Installed executable not found: $ExePath"
    }

    $UninstallPath = Join-Path $InstallDir $UninstallScriptName
    $escapedInstallDir = Escape-PowerShellSingleQuotedString $InstallDir
    $uninstallLines = @(
        'param([switch]$Quiet)',
        '$ErrorActionPreference = "SilentlyContinue"',
        '$DisplayName = [string]::Concat([char[]]@(0x9CB2,0x7A79,0x8FDC,0x7A0B,0x684C,0x9762))',
        '$LegacyDisplayName = [string]::Concat([char[]]@(0x9CB2,0x7A79,0x5DE5,0x5177,0x7BB1))',
        "`$InstallDir = '$escapedInstallDir'",
        '$running = Get-Process rustdesk -ErrorAction SilentlyContinue | Where-Object {',
        '    try {',
        '        $_.Path -and $_.Path.StartsWith($InstallDir, [System.StringComparison]::OrdinalIgnoreCase)',
        '    } catch {',
        '        $false',
        '    }',
        '}',
        'if ($running) {',
        '    $running | Stop-Process -Force',
        '    Start-Sleep -Seconds 1',
        '}',
        '$desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "$DisplayName.lnk"',
        '$legacyDesktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "$LegacyDisplayName.lnk"',
        '$startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$DisplayName"',
        '$legacyStartMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$LegacyDisplayName"',
        '$startShortcut = Join-Path $startMenuDir "$DisplayName.lnk"',
        '$startupShortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\$DisplayName.lnk"',
        '$legacyStartupShortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\$LegacyDisplayName.lnk"',
        'Remove-Item -LiteralPath $desktopShortcut -Force',
        'Remove-Item -LiteralPath $legacyDesktopShortcut -Force',
        'Remove-Item -LiteralPath $startShortcut -Force',
        'Remove-Item -LiteralPath $startupShortcut -Force',
        'Remove-Item -LiteralPath $legacyStartupShortcut -Force',
        'Remove-Item -LiteralPath $startMenuDir -Recurse -Force',
        'Remove-Item -LiteralPath $legacyStartMenuDir -Recurse -Force',
        'Remove-Item -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\KQRemoteLink" -Recurse -Force',
        '$cleanup = Join-Path $env:TEMP ("kq-remote-link-uninstall-" + [guid]::NewGuid().ToString("N") + ".cmd")',
        '$quotedInstallDir = $InstallDir.Replace(''"'', ''""'')',
        '@(',
        '    "@echo off",',
        '    "ping 127.0.0.1 -n 3 > nul",',
        '    "rmdir /s /q ""$quotedInstallDir""",',
        '    "del ""%~f0"""',
        ') | Set-Content -LiteralPath $cleanup -Encoding ASCII',
        'Start-Process -FilePath $env:ComSpec -ArgumentList "/c ""$cleanup""" -WindowStyle Hidden',
        'if (-not $Quiet) {',
        '    $shell = New-Object -ComObject WScript.Shell',
        '    $msg = "$DisplayName " + [string]::Concat([char[]]@(0x5DF2,0x5378,0x8F7D,0x3002))',
        '    $shell.Popup($msg, 4, $DisplayName, 64) | Out-Null',
        '}'
    )
    [System.IO.File]::WriteAllLines($UninstallPath, $uninstallLines, [System.Text.UTF8Encoding]::new($false))

    $shell = New-Object -ComObject WScript.Shell
    $legacyDesktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "$LegacyDisplayName.lnk"
    $legacyStartMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$LegacyDisplayName"
    Remove-Item -LiteralPath $legacyDesktopShortcut -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $legacyStartMenuDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\$LegacyDisplayName.lnk") -Force -ErrorAction SilentlyContinue
    if ($previousInstallDir -and
        -not $previousInstallDir.Equals($InstallDir, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path $previousInstallDir)) {
        $previousResolved = (Resolve-Path $previousInstallDir -ErrorAction SilentlyContinue).Path
        if ($previousResolved -and
            $previousResolved.StartsWith($env:LOCALAPPDATA, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $previousResolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "$DisplayName.lnk"
    if ($CreateDesktopShortcut) {
        $shortcut = $shell.CreateShortcut($desktopShortcut)
        $shortcut.TargetPath = $ExePath
        $shortcut.WorkingDirectory = $InstallDir
        $shortcut.IconLocation = "$ExePath,0"
        $shortcut.Description = $DisplayName
        $shortcut.Save()
    } else {
        Remove-Item -LiteralPath $desktopShortcut -Force -ErrorAction SilentlyContinue
    }

    $startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$DisplayName"
    $startShortcut = Join-Path $startMenuDir "$DisplayName.lnk"
    if ($CreateStartMenuShortcut) {
        New-Item -ItemType Directory -Path $startMenuDir -Force | Out-Null
        $shortcut = $shell.CreateShortcut($startShortcut)
        $shortcut.TargetPath = $ExePath
        $shortcut.WorkingDirectory = $InstallDir
        $shortcut.IconLocation = "$ExePath,0"
        $shortcut.Description = $DisplayName
        $shortcut.Save()
    } else {
        Remove-Item -LiteralPath $startShortcut -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $startMenuDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $startupShortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup\$DisplayName.lnk"
    if ($AutoStart) {
        $shortcut = $shell.CreateShortcut($startupShortcut)
        $shortcut.TargetPath = $ExePath
        $shortcut.WorkingDirectory = $InstallDir
        $shortcut.IconLocation = "$ExePath,0"
        $shortcut.Description = $DisplayName
        $shortcut.Save()
    } else {
        Remove-Item -LiteralPath $startupShortcut -Force -ErrorAction SilentlyContinue
    }

    $size = [int](((Get-ChildItem -LiteralPath $InstallDir -Recurse -File | Measure-Object -Property Length -Sum).Sum) / 1KB)
    New-Item -Path $uninstallKey -Force | Out-Null
    Set-ItemProperty -Path $uninstallKey -Name DisplayName -Value $DisplayName
    Set-ItemProperty -Path $uninstallKey -Name DisplayVersion -Value $Version
    Set-ItemProperty -Path $uninstallKey -Name Publisher -Value $Publisher
    Set-ItemProperty -Path $uninstallKey -Name InstallLocation -Value $InstallDir
    Set-ItemProperty -Path $uninstallKey -Name DisplayIcon -Value $ExePath
    Set-ItemProperty -Path $uninstallKey -Name UninstallString -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$UninstallPath"""
    Set-ItemProperty -Path $uninstallKey -Name QuietUninstallString -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$UninstallPath"" -Quiet"
    Set-ItemProperty -Path $uninstallKey -Name NoModify -Value 1 -Type DWord
    Set-ItemProperty -Path $uninstallKey -Name NoRepair -Value 1 -Type DWord
    Set-ItemProperty -Path $uninstallKey -Name EstimatedSize -Value $size -Type DWord

    Remove-Item -LiteralPath $TempDir -Recurse -Force
    Write-InstallLog "Install completed: $InstallDir"

    if ($LaunchAfterInstall) {
        Start-Process -FilePath $ExePath -WorkingDirectory $InstallDir
    }

    $msg = "$DisplayName " + [string]::Concat([char[]]@(0x5B89,0x88C5,0x5B8C,0x6210,0xFF0C,0x5DF2,0x521B,0x5EFA,0x684C,0x9762,0x548C,0x5F00,0x59CB,0x83DC,0x5355,0x5FEB,0x6377,0x65B9,0x5F0F,0x3002))
    $shell.Popup($msg, 4, $DisplayName, 64) | Out-Null
} catch {
    Write-InstallLog "Install failed: $($_.Exception.Message)"
    $shell = New-Object -ComObject WScript.Shell
    $msg = [string]::Concat([char[]]@(0x5B89,0x88C5,0x5931,0x8D25,0xFF1A)) + $_.Exception.Message + "`nLog: $LogPath"
    $shell.Popup($msg, 10, $DisplayName, 16) | Out-Null
    throw
} finally {
    if (Test-Path $TempDir) {
        Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
'@
$installPs1 = $installPs1.Replace("__VERSION__", ($Version -replace "'", "''"))
$installPs1 = $installPs1.Replace("__BRAND_ICON_BASE64__", $brandIconBase64)
$installPs1 = $installPs1.Replace("__BRAND_LOGO_PNG_BASE64__", $brandLogoPngBase64)
[System.IO.File]::WriteAllText((Join-Path $installerStage "install.ps1"), $installPs1, $utf8NoBom)

$iexpress = (Get-Command iexpress.exe -ErrorAction SilentlyContinue).Source
if (-not $iexpress) {
    throw "iexpress.exe not found. Windows IExpress is required to create the installer."
}

$installerStageForSed = $installerStage
if (-not $installerStageForSed.EndsWith("\")) {
    $installerStageForSed = "$installerStageForSed\"
}
$sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$installerPath
FriendlyName=Kunqiong Remote Desktop
AppLaunched=install-launcher.exe
PostInstallCmd=<None>
AdminQuietInstCmd=install-launcher.exe -Silent -NoLaunch
UserQuietInstCmd=install-launcher.exe -Silent -NoLaunch
FILE0="payload.zip"
FILE1="install.ps1"
FILE2="install-launcher.exe"
[SourceFiles]
SourceFiles0=$installerStageForSed
[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
"@
[System.IO.File]::WriteAllText($sedPath, $sed, [System.Text.Encoding]::ASCII)

& $iexpress /N /Q $sedPath
if (-not (Test-Path $installerPath)) {
    throw "Installer was not created: $installerPath. iexpress exit code: $LASTEXITCODE"
}

$installer = Get-Item $installerPath
if ($installer.Length -le 0) {
    throw "Installer is empty: $installerPath"
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $installerPath).Hash
[pscustomobject]@{
    FullName = $installer.FullName
    Length = $installer.Length
    Sha256 = $hash
    InstallDir = "%LOCALAPPDATA%\KQRemoteLink"
}
