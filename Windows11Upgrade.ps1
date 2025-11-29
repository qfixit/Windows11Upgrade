# Windows 11 Upgrade Orchestrator (Modular)
# Quintin Sheppard
# Updated 11/28/2025
# Author Remark: Quintin Sheppard
# Script Version 2.5.0
# Summary: Downloads/validates the Windows 11 25H2 ISO, stages setup.exe /noreboot, writes state markers, self-heals failed runs, and registers reminder/validation tasks.
# Example: powershell.exe -ExecutionPolicy Bypass -NoProfile -File ".\Windows11Upgrade\Windows11Upgrade_v2.5.0.ps1" -VerboseLogging

param(
    [switch]$VerboseLogging
)

if ($VerboseLogging) {
    $VerbosePreference = 'Continue'
}
$ErrorActionPreference = 'Stop'

$script:CurrentScriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $null }
$privateRoot = if ($script:CurrentScriptPath) { Split-Path -Path $script:CurrentScriptPath -Parent } else { (Get-Location).ProviderPath }
Set-Variable -Name privateRoot -Value $privateRoot -Scope Global -Force
$script:ModulePaths = @{
    Config        = Join-Path -Path $privateRoot -ChildPath "UpgradeConfig.ps1"
    Main          = Join-Path -Path $privateRoot -ChildPath "MainFunctions.ps1"
    State         = Join-Path -Path $privateRoot -ChildPath "UpgradeState.ps1"
    Detection     = Join-Path -Path $privateRoot -ChildPath "Detection.ps1"
    SystemChecks  = Join-Path -Path $privateRoot -ChildPath "SystemChecks.ps1"
    Tasks         = Join-Path -Path $privateRoot -ChildPath "ScheduledTasks.ps1"
    SelfRepair    = Join-Path -Path $privateRoot -ChildPath "SelfRepair.ps1"
    Iso           = Join-Path -Path $privateRoot -ChildPath "IsoDownload.ps1"
    Cleanup       = Join-Path -Path $privateRoot -ChildPath "PostUpgradeCleanup.ps1"
    Orchestration = Join-Path -Path $privateRoot -ChildPath "Start-Windows11Upgrade.ps1"
}

. $script:ModulePaths.Config
$config = Set-UpgradeConfig
$logFile = $config.LogFile
$stateDirectory = $config.StateDirectory
$script:UpgradeStateFiles = $config.UpgradeStateFiles
$script:UsingComputerSpecificLog = ($logFile -eq $config.ComputerSpecificLogFile)

$script:ScriptStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$script:IsoDownloadDuration = $null
$script:SetupExecutionDuration = $null
$script:SummaryLogged = $false
$script:ReminderRegistrationMode = $null

foreach ($moduleEntry in @('Main','State','Detection','Iso','SystemChecks','Tasks','SelfRepair','Cleanup','Orchestration')) {
    $modulePath = $script:ModulePaths[$moduleEntry]
    if (-not (Test-Path -Path $modulePath)) {
        throw ("Required helper module missing at {0}" -f $modulePath)
    }
    . $modulePath
}

if ($script:UsingComputerSpecificLog) {
    Write-Log -Message ("Detected existing device-specific log file at {0}; continuing logging there." -f $logFile) -Level "INFO"
}

Start-Windows11Upgrade
