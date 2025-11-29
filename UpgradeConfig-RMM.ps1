# Upgrade Configuration (RMM Parameter-Aware Builder)
# Version 2.5.7
# Date 11/28/2025
# Author Remark: Quintin Sheppard
# Summary: Accepts ConnectWise RMM parameter substitutions, writes the resolved config to C:\Temp\Windows11Upgrade\UpgradeConfig.ps1, and exposes Set-UpgradeConfig for direct use.
# Example (RMM task build step):
#   powershell.exe -ExecutionPolicy Bypass -NoProfile -File ".\UpgradeConfig-RMM.ps1" -EmitResolvedFile `
#       -Windows11IsoUrl @Windows11IsoUrl@ -ISOHash @ISOHash@ -DynamicUpdate @DynamicUpdate@ -AutoReboot @AutoReboot@ `
#       -RebootReminder1Time @RebootReminder1Time@ -RebootReminder2Time @RebootReminder2Time@
# Example (direct use after copy):
#   powershell.exe -ExecutionPolicy Bypass -NoProfile -Command ". '\\Windows11Upgrade\\UpgradeConfig.ps1'; Set-UpgradeConfig"

param(
    [switch]$EmitResolvedFile,
    [string]$Windows11IsoUrl,
    [string]$ISOHash,
    [string]$DynamicUpdate,
    [string]$AutoReboot,
    [string]$RebootReminder1Time,
    [string]$RebootReminder2Time
)

# Parameter placeholders that RMM will replace; allow direct parameter overrides for task execution.
$script:Windows11IsoUrlParam      = if ($PSBoundParameters.ContainsKey("Windows11IsoUrl")) { $Windows11IsoUrl } else { "@Windows11IsoUrl@" }
$script:ExpectedIsoSha256Param    = if ($PSBoundParameters.ContainsKey("ISOHash")) { $ISOHash } else { "@ISOHash@" }
$script:DynamicUpdateParam        = if ($PSBoundParameters.ContainsKey("DynamicUpdate")) { $DynamicUpdate } else { "@DynamicUpdate@" }
$script:AutoRebootParam           = if ($PSBoundParameters.ContainsKey("AutoReboot")) { $AutoReboot } else { "@AutoReboot@" }
$script:RebootReminder1TimeParam  = if ($PSBoundParameters.ContainsKey("RebootReminder1Time")) { $RebootReminder1Time } else { "@RebootReminder1Time@" }
$script:RebootReminder2TimeParam  = if ($PSBoundParameters.ContainsKey("RebootReminder2Time")) { $RebootReminder2Time } else { "@RebootReminder2Time@" }

function Resolve-ParameterValue {
    param(
        [string]$Value,
        [string]$Default
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $Default }
    if ($Value.StartsWith("@") -and $Value.EndsWith("@")) { return $Default }
    return $Value
}

function Resolve-BoolParameter {
    param(
        [string]$Value,
        [bool]$Default
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $Default }
    if ($Value.StartsWith("@") -and $Value.EndsWith("@")) { return $Default }

    $parsed = $null
    if ([bool]::TryParse($Value, [ref]$parsed)) {
        return [bool]$parsed
    }

    return $Default
}

$resolvedWindows11IsoUrl    = Resolve-ParameterValue -Value $script:Windows11IsoUrlParam     -Default "https://acsia-my.sharepoint.com/:u:/g/personal/qsheppard_koltiv_com/ESDEaFWZhrdOrKBuT8VyYHABHSP6rvW0OG2u6XkHGxksFw?download=1"
$resolvedExpectedIsoSha256  = Resolve-ParameterValue -Value $script:ExpectedIsoSha256Param   -Default "D141F6030FED50F75E2B03E1EB2E53646C4B21E5386047CB860AF5223F102A32"
$resolvedDynamicUpdate      = Resolve-BoolParameter   -Value $script:DynamicUpdateParam      -Default $true
$resolvedAutoReboot         = Resolve-BoolParameter   -Value $script:AutoRebootParam         -Default $false
$resolvedRebootReminder1    = Resolve-ParameterValue  -Value $script:RebootReminder1TimeParam -Default "11:00"
$resolvedRebootReminder2    = Resolve-ParameterValue  -Value $script:RebootReminder2TimeParam -Default "16:00"
$resolvedToastAssetsRoot    = "C:\Temp\Windows11Upgrade\Toast-Notification"
$resolvedToastHeroImage     = "hero.jpg"
$resolvedToastLogoImage     = "logo.jpg"
$resolvedSetupArgs          = $null

function New-SetupArgumentsString {
    $dynamicPart = if ($resolvedDynamicUpdate) { "/DynamicUpdate Enable" } else { "/DynamicUpdate Disable" }
    $arguments = "/Auto Upgrade /copylogs `"{0}`" $dynamicPart /EULA accept /Quiet"

    if (-not $resolvedAutoReboot) {
        $arguments += " /noreboot"
    }

    return $arguments
}

$resolvedSetupArgs = New-SetupArgumentsString

function Set-UpgradeConfig {
    $config = [ordered]@{
        BaseLogFile                  = "C:\Windows11UpgradeLog.txt"
        ComputerSpecificLogFile      = "C:\Windows11UpgradeLog-$($env:COMPUTERNAME).txt"
        LogFile                      = $null
        LoggingLevel                 = "INFO"

        StateDirectory               = "C:\Temp\WindowsUpdate"
        UpgradeStateFiles            = @{
            ScriptRunning = "C:\Temp\WindowsUpdate\ScriptRunning.txt"
            PendingReboot = "C:\Temp\WindowsUpdate\PendingReboot.txt"
        }
        FailureMarker                = "C:\Temp\WindowsUpdate\UpgradeFailed.txt"

        Windows11IsoUrl              = $resolvedWindows11IsoUrl
        ExpectedIsoSha256            = $resolvedExpectedIsoSha256
        IsoFilePath                  = "C:\Temp\WindowsUpdate\Windows11_25H2.iso"
        IsoHashCacheFile             = "C:\Temp\WindowsUpdate\Windows11_25H2.iso.sha256"
        MinimumIsoSizeBytes          = [int64](4 * 1GB)

        SetupExeArguments            = $resolvedSetupArgs
        MoSetupVolatileKey           = "HKLM:\SYSTEM\Setup\MoSetup\Volatile"

        PostRebootValidationTaskName = "Win11_PostRebootValidation"
        ReminderTaskNames            = @("Win11_RebootReminder_1", "Win11_RebootReminder_2")
        RebootReminder1Time          = $resolvedRebootReminder1
        RebootReminder2Time          = $resolvedRebootReminder2
        RebootReminderScript         = "C:\Temp\WindowsUpdate\RebootReminderNotification.ps1"
        RebootReminderVbs            = "C:\Temp\WindowsUpdate\RunHiddenReminder.vbs"
        PostRebootScriptPath         = "C:\Temp\WindowsUpdate\Windows11Upgrade_PostReboot.ps1"

        ToastAssetsRoot              = $resolvedToastAssetsRoot
        ToastHeroImage               = $resolvedToastHeroImage
        ToastLogoImage               = $resolvedToastLogoImage
        ToastAttributionText         = "Koltiv"
        ToastHeaderText              = "Windows 11 Upgrade"

        MinimumSentinelAgentVersion  = [version]'24.2.2.0'
    }

    $config.LogFile = $config.BaseLogFile
    if (-not (Test-Path -Path $config.BaseLogFile) -and (Test-Path -Path $config.ComputerSpecificLogFile)) {
        $config.LogFile = $config.ComputerSpecificLogFile
    }

    foreach ($dir in @($config.StateDirectory, $config.ToastAssetsRoot, $resolvedToastAssetsRoot)) {
        if (-not (Test-Path -Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }
    if (-not (Test-Path -Path $config.LogFile)) {
        New-Item -Path $config.LogFile -ItemType File -Force | Out-Null
    }

    foreach ($key in $config.Keys) {
        Set-Variable -Name $key -Value $config[$key] -Scope Global -Force
    }

    return $config
}

function Write-ResolvedUpgradeConfigFile {
    $targetPath = "C:\Temp\Windows11Upgrade\UpgradeConfig.ps1"
    $targetDir = Split-Path -Path $targetPath -Parent

    if (-not (Test-Path -Path $targetDir)) {
        New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
    }

    $template = @'
# Upgrade Configuration
# Version 2.5.7
# Date 11/28/2025
# Author Remark: Quintin Sheppard
# Generated by RMM task with parameter substitution.

function Set-UpgradeConfig {
    $config = [ordered]@{
        BaseLogFile                  = "C:\Windows11UpgradeLog.txt"
        ComputerSpecificLogFile      = "C:\Windows11UpgradeLog-$($env:COMPUTERNAME).txt"
        LogFile                      = $null
        LoggingLevel                 = "INFO"

        StateDirectory               = "C:\Temp\WindowsUpdate"
        UpgradeStateFiles            = @{
            ScriptRunning = "C:\Temp\WindowsUpdate\ScriptRunning.txt"
            PendingReboot = "C:\Temp\WindowsUpdate\PendingReboot.txt"
        }
        FailureMarker                = "C:\Temp\WindowsUpdate\UpgradeFailed.txt"

        Windows11IsoUrl              = "__ISOURL__"
        ExpectedIsoSha256            = "__ISOHASH__"
        IsoFilePath                  = "C:\Temp\WindowsUpdate\Windows11_25H2.iso"
        IsoHashCacheFile             = "C:\Temp\WindowsUpdate\Windows11_25H2.iso.sha256"
        MinimumIsoSizeBytes          = [int64](4 * 1GB)

        SetupExeArguments            = '__SETUPARGS__'
        MoSetupVolatileKey           = "HKLM:\SYSTEM\Setup\MoSetup\Volatile"

        PostRebootValidationTaskName = "Win11_PostRebootValidation"
        ReminderTaskNames            = @("Win11_RebootReminder_1", "Win11_RebootReminder_2")
        RebootReminder1Time          = "__REM1__"
        RebootReminder2Time          = "__REM2__"
        RebootReminderScript         = "C:\Temp\WindowsUpdate\RebootReminderNotification.ps1"
        RebootReminderVbs            = "C:\Temp\WindowsUpdate\RunHiddenReminder.vbs"
        PostRebootScriptPath         = "C:\Temp\WindowsUpdate\Windows11Upgrade_PostReboot.ps1"

        ToastAssetsRoot              = "__ASSETROOT__"
        ToastHeroImage               = "__HERO__"
        ToastLogoImage               = "__LOGO__"
        ToastAttributionText         = "Koltiv"
        ToastHeaderText              = "Windows 11 Upgrade"

        MinimumSentinelAgentVersion  = [version]'24.2.2.0'
    }

    $config.LogFile = $config.BaseLogFile
    if (-not (Test-Path -Path $config.BaseLogFile) -and (Test-Path -Path $config.ComputerSpecificLogFile)) {
        $config.LogFile = $config.ComputerSpecificLogFile
    }

    foreach ($dir in @($config.StateDirectory, $config.ToastAssetsRoot, "__ASSETROOT__")) {
        if (-not (Test-Path -Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }
    if (-not (Test-Path -Path $config.LogFile)) {
        New-Item -Path $config.LogFile -ItemType File -Force | Out-Null
    }

    foreach ($key in $config.Keys) {
        Set-Variable -Name $key -Value $config[$key] -Scope Global -Force
    }

    return $config
}
'@

    $replacements = @{
        "__ISOURL__"    = $resolvedWindows11IsoUrl
        "__ISOHASH__"   = $resolvedExpectedIsoSha256
        "__SETUPARGS__" = $resolvedSetupArgs
        "__REM1__"      = $resolvedRebootReminder1
        "__REM2__"      = $resolvedRebootReminder2
        "__ASSETROOT__" = $resolvedToastAssetsRoot
        "__HERO__"      = $resolvedToastHeroImage
        "__LOGO__"      = $resolvedToastLogoImage
    }

    $content = $template
    foreach ($k in $replacements.Keys) {
        $content = $content.Replace($k, $replacements[$k])
    }

    Set-Content -Path $targetPath -Value $content -Encoding ASCII
    Write-Host "UpgradeConfig.ps1 generated at $targetPath"
}

# Always write the resolved config so the active UpgradeConfig.ps1 is replaced for the current run.
Write-ResolvedUpgradeConfigFile
