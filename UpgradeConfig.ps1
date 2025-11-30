# Upgrade Configuration
# Version 2.5.8
# Date 11/29/2025
# Author Remark: Quintin Sheppard
# Summary: Centralized configuration for paths, URLs, hashes, toast assets, and logging/state settings.
# Example: powershell.exe -ExecutionPolicy Bypass -NoProfile -Command ". '\\Windows11Upgrade\\UpgradeConfig.ps1'; $cfg = Set-UpgradeConfig; $cfg.LogFile"

function Set-UpgradeConfig {
    $config = [ordered]@{
        # Logging
        BaseLogFile                  = "C:\Windows11UpgradeLog.txt"                            # primary log target
        ComputerSpecificLogFile      = "C:\Windows11UpgradeLog-$($env:COMPUTERNAME).txt"      # fallback log used if the primary was renamed
        LogFile                      = $null                                                  # resolved log file (set below)
        LoggingLevel                 = "INFO"                                                 # default console/log verbosity

        # State & markers
        StateDirectory               = "C:\Temp\WindowsUpdate"                                # root for sentinels, iso, tasks, and temp scripts
        UpgradeStateFiles            = @{
            ScriptRunning = "C:\Temp\WindowsUpdate\ScriptRunning.txt"                         # active run sentinel
            PendingReboot = "C:\Temp\WindowsUpdate\PendingReboot.txt"                         # staging complete sentinel
        }
        FailureMarker                = "C:\Temp\WindowsUpdate\UpgradeFailed.txt"              # marker watched by RMM

        # ISO download/validation
        Windows11IsoUrl              = "example.com*" # ISO download source
        ExpectedIsoSha256            = "D141F6030FED50F75E2B03E1EB2E53646C4B21E5386047CB860AF5223F102A32"                      # expected ISO hash
        IsoFilePath                  = "C:\Temp\WindowsUpdate\Windows11_25H2.iso"             # staged ISO path
        IsoHashCacheFile             = "C:\Temp\WindowsUpdate\Windows11_25H2.iso.sha256"      # cached SHA for ISO reuse
        MinimumIsoSizeBytes          = [int64](4 * 1GB)                                       # sanity check to guard against HTML downloads

        # Setup execution
        SetupExeArguments            = '/Auto Upgrade /copylogs "{0}" /DynamicUpdate Enable /EULA accept /noreboot /Quiet'     # setup.exe switches; {0}=log path
        MoSetupVolatileKey           = "HKLM:\SYSTEM\Setup\MoSetup\Volatile"                  # progress tracking registry key

        # Task scheduling / reminders
        PostRebootValidationTaskName = "Win11_PostRebootValidation"                           # task that reruns after reboot
        PostRebootValidationRunOnce  = "Win11_PostRebootValidation_RunOnce"                   # RunOnce fallback key to rerun after reboot
        ReminderTaskNames            = @("Win11_RebootReminder_1", "Win11_RebootReminder_2")  # reboot reminder task names
        RebootReminder1Time          = "11:00"                                                # first reboot reminder time
        RebootReminder2Time          = "16:00"                                                # second reboot reminder time
        RebootReminderScript         = "C:\Temp\WindowsUpdate\RebootReminderNotification.ps1" # reminder toast helper script
        RebootReminderVbs            = "C:\Temp\WindowsUpdate\RunHiddenReminder.vbs"          # VBS launcher for reminder toast
        PostRebootScriptPath         = "C:\Temp\WindowsUpdate\Windows11Upgrade.ps1" # post-reboot validation script (reuse main orchestrator)

        # Toast configuration
        ToastAssetsRoot              = "C:\Temp\WindowsUpdate\Toast-Notification"                                  # cached toast assets
        ToastHeroImagePrimaryUrl     = "hero.jpg" # hero image
        ToastLogoImagePrimaryUrl     = "logo.jpg" # logo image
        ToastAttributionText         = "Koltiv"                                               # toast attribution
        ToastHeaderText              = "Windows 11 Upgrade"                                   # toast header/title

        # Compatibility gates
        MinimumSentinelAgentVersion  = [version]'24.2.2.0'                                    # SentinelOne gating
    }

    # Resolve log target with computer-specific fallback
    $config.LogFile = $config.BaseLogFile
    if (-not (Test-Path -Path $config.BaseLogFile) -and (Test-Path -Path $config.ComputerSpecificLogFile)) {
        $config.LogFile = $config.ComputerSpecificLogFile
    }

    # Ensure directories/files exist
    foreach ($dir in @($config.StateDirectory, $config.ToastAssetsRoot)) {
        if (-not (Test-Path -Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }
    if (-not (Test-Path -Path $config.LogFile)) {
        New-Item -Path $config.LogFile -ItemType File -Force | Out-Null
    }

    # Export variables globally for module compatibility
    foreach ($key in $config.Keys) {
        Set-Variable -Name $key -Value $config[$key] -Scope Global -Force
    }

    return $config
}
