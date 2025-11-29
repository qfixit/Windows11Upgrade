# Upgrade Configuration
# Version 2.5.1
# Date 2025-12-08
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
        Windows11IsoUrl              = "https://acsia-my.sharepoint.com/:u:/g/personal/qsheppard_koltiv_com/ESDEaFWZhrdOrKBuT8VyYHABHSP6rvW0OG2u6XkHGxksFw?download=1" # ISO download source
        ExpectedIsoSha256            = "D141F6030FED50F75E2B03E1EB2E53646C4B21E5386047CB860AF5223F102A32"                      # expected ISO hash
        IsoFilePath                  = "C:\Temp\WindowsUpdate\Windows11_25H2.iso"             # staged ISO path
        IsoHashCacheFile             = "C:\Temp\WindowsUpdate\Windows11_25H2.iso.sha256"      # cached SHA for ISO reuse
        MinimumIsoSizeBytes          = [int64](4 * 1GB)                                       # sanity check to guard against HTML downloads

        # Setup execution
        SetupExeArguments            = '/Auto Upgrade /copylogs "{0}" /DynamicUpdate Enable /EULA accept /noreboot /Quiet'     # setup.exe switches; {0}=log path
        MoSetupVolatileKey           = "HKLM:\SYSTEM\Setup\MoSetup\Volatile"                  # progress tracking registry key

        # Task scheduling / reminders
        PostRebootValidationTaskName = "Win11_PostRebootValidation"                           # task that reruns after reboot
        ReminderTaskNames            = @("Win11_RebootReminder_1", "Win11_RebootReminder_2")  # reboot reminder task names
        RebootReminder1Time          = "11:00"                                                # first reboot reminder time
        RebootReminder2Time          = "16:00"                                                # second reboot reminder time
        RebootReminderScript         = "C:\Temp\WindowsUpdate\RebootReminderNotification.ps1" # reminder toast helper script
        RebootReminderVbs            = "C:\Temp\WindowsUpdate\RunHiddenReminder.vbs"          # VBS launcher for reminder toast
        PostRebootScriptPath         = "C:\Temp\WindowsUpdate\Windows11Upgrade_PostReboot.ps1" # persisted script for post-reboot validation

        # Toast configuration
        ToastAssetsRoot              = "C:\Temp\ToastAssets"                                  # cached toast assets
        ToastHeroImagePrimaryUrl     = "https://msftstories.thesourcemediaassets.com/sites/620/2021/09/Hero-Bloom-Logo-800x533.jpg" # hero image
        ToastLogoImagePrimaryUrl     = "https://media.licdn.com/dms/image/v2/D560BAQH_g3042zbH8Q/company-logo_200_200/B56ZfLQBu3HoAI-/0/1751461666023?e=2147483647&v=beta&t=mgsvAe6Nkh8iJIHtcBlQy5CCKH8Wg3e4tvtY1vrBOxg" # logo image
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
    foreach ($dir in @($config.StateDirectory, $config.ToastAssetsRoot, "C:\Temp\ToastAssets")) {
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
