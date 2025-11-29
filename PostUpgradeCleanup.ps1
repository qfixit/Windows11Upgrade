# Post-Upgrade Cleanup Helpers
# Version 2.5.0
# Date 11/28/2025
# Author Remark: Quintin Sheppard
# Summary: Cleans staged artifacts after success/failure, archives logs, and resets state/sentinels for the Windows 11 upgrade workflow.
# Example (dry list of targets): powershell.exe -ExecutionPolicy Bypass -NoProfile -File ".\Private\Post-Upgrade Cleanup\PostUpgradeCleanup.ps1" -ListCleanupTargets

[CmdletBinding()]
param(
    [switch]$ListCleanupTargets
)

if (-not $logFile) {
    $baseLog = "C:\Windows11UpgradeLog.txt"
    $deviceLog = "C:\Windows11UpgradeLog-$($env:COMPUTERNAME).txt"
    $logFile = if ((-not (Test-Path -Path $baseLog)) -and (Test-Path -Path $deviceLog)) { $deviceLog } else { $baseLog }
    if (-not (Test-Path -Path $logFile)) {
        try { New-Item -Path $logFile -ItemType File -Force | Out-Null } catch { }
    }
}

if (-not (Get-Command -Name Write-Log -ErrorAction SilentlyContinue)) {
    function Write-Log {
        param([string]$Message, [string]$Level = "INFO")
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $formatted = "$timestamp [$Level] $Message"
        try {
            if ($script:logFile -and (Test-Path -Path $script:logFile)) {
                Add-Content -Path $script:logFile -Value $formatted
            } elseif ($logFile) {
                Add-Content -Path $logFile -Value $formatted
            }
        } catch {}
        Write-Host $formatted
    }
}

if (-not (Get-Command -Name Ensure-Directory -ErrorAction SilentlyContinue)) {
    function Ensure-Directory {
        param([string]$Path)
        if (-not (Test-Path -Path $Path)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }
    }
}

if (-not (Get-Command -Name Save-UpgradeState -ErrorAction SilentlyContinue)) {
    function Save-UpgradeState {
        param([psobject]$State)
        Write-Log -Message "Save-UpgradeState stub invoked (test mode)." -Level "VERBOSE"
    }
}

if (-not (Get-Command -Name Clear-UpgradeState -ErrorAction SilentlyContinue)) {
    function Clear-UpgradeState {}
}

if (-not (Get-Command -Name Clear-FailureMarker -ErrorAction SilentlyContinue)) {
    function Clear-FailureMarker {}
}

if (-not $stateDirectory) {
    $stateDirectory = "C:\Temp\WindowsUpdate"
}

if (-not $isoFilePath) {
    $isoFilePath = Join-Path -Path $stateDirectory -ChildPath "Windows11_25H2.iso"
}

if (-not $isoHashCacheFile) {
    $isoHashCacheFile = Join-Path -Path $stateDirectory -ChildPath "Windows11_25H2.iso.sha256"
}

if (-not $failureMarker) {
    $failureMarker = Join-Path -Path $stateDirectory -ChildPath "UpgradeFailed.txt"
}

function Invoke-PostUpgradeCleanup {
    param ([psobject]$State)

    Write-Log -Message "Running post-upgrade cleanup tasks." -Level "INFO"

    if (Get-Command -Name Write-LastRebootEventInfo -ErrorAction SilentlyContinue) {
        Write-LastRebootEventInfo
    }
    if (Get-Command -Name Remove-RebootReminderTasks -ErrorAction SilentlyContinue) {
        Remove-RebootReminderTasks
    }
    if (Get-Command -Name Remove-PostRebootValidationTask -ErrorAction SilentlyContinue) {
        Remove-PostRebootValidationTask
    }

    $setupLogsPath = Join-Path -Path $stateDirectory -ChildPath "SetupLogs"
    if (Test-Path -Path $setupLogsPath) {
        $setupLogsArchive = Join-Path -Path $stateDirectory -ChildPath "SetupLogs_PostUpgrade.zip"
        try {
            if (Test-Path -Path $setupLogsArchive) {
                Remove-Item -Path $setupLogsArchive -Force -ErrorAction SilentlyContinue
            }
            Compress-Archive -Path (Join-Path -Path $setupLogsPath -ChildPath "*") -DestinationPath $setupLogsArchive -Force
            Write-Log -Message "Archived setup logs to $setupLogsArchive." -Level "INFO"
        } catch {
            Write-Log -Message "Failed to archive setup logs prior to cleanup. Error: $_" -Level "WARN"
        }
    }

    $pathsToDelete = @(
        $setupLogsPath,
        (Join-Path -Path $stateDirectory -ChildPath "ToastAssets"),
        "C:\Temp\ToastAssets",
        (Join-Path -Path $stateDirectory -ChildPath "RunHidden_*.vbs"),
        (Join-Path -Path $stateDirectory -ChildPath "RebootReminderNotification.ps1"),
        (Join-Path -Path $stateDirectory -ChildPath "RunHiddenReminder.vbs"),
        (Join-Path -Path $stateDirectory -ChildPath "Show-Notification.ps1")
    )

    foreach ($path in $pathsToDelete) {
        if (Test-Path -Path $path) {
            try {
                Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                Write-Log -Message "Removed staging artifact $path." -Level "VERBOSE"
            } catch {
                Write-Log -Message "Failed to remove staging artifact $path. Error: $_" -Level "WARN"
            }
        }
    }

    foreach ($toastFile in @("Toast-Download.ps1", "Toast-RebootReminder.ps1")) {
        $toastPath = Join-Path -Path $stateDirectory -ChildPath $toastFile
        if (Test-Path -Path $toastPath) {
            try {
                Remove-Item -Path $toastPath -Force -ErrorAction Stop
                Write-Log -Message "Removed toast script $toastPath." -Level "VERBOSE"
            } catch {
                Write-Log -Message "Failed to remove toast script $toastPath. Error: $_" -Level "WARN"
            }
        }
    }

    if (Test-Path -Path $isoHashCacheFile) {
        try {
            Remove-Item -Path $isoHashCacheFile -Force -ErrorAction Stop
            Write-Log -Message "Removed cached ISO hash at $isoHashCacheFile." -Level "VERBOSE"
        } catch {
            Write-Log -Message "Failed to remove cached ISO hash. Error: $_" -Level "WARN"
        }
    }

    try {
        Get-ChildItem -Path $stateDirectory -Filter "RunHidden_*.vbs" -ErrorAction Stop | ForEach-Object {
            Remove-Item -Path $_.FullName -Force -ErrorAction Stop
            Write-Log -Message ("Removed temporary toast helper {0}." -f $_.FullName) -Level "VERBOSE"
        }
    } catch {
        if ($_.Exception -and -not ($_.Exception -is [System.IO.DirectoryNotFoundException])) {
            Write-Log -Message ("Failed to purge temporary toast helpers. Error: {0}" -f $_) -Level "WARN"
        }
    }

    if (Test-Path -Path $isoFilePath) {
        try {
            Remove-Item -Path $isoFilePath -Force -ErrorAction Stop
            Write-Log -Message "Deleted downloaded ISO at $isoFilePath." -Level "VERBOSE"
        } catch {
            Write-Log -Message "Failed to delete ISO at $isoFilePath. Error: $_" -Level "WARN"
        }
    }

    Clear-FailureMarker
    if ($State) {
        $State.Status = "Completed"
        $State.CompletedOn = (Get-Date).ToString("o")
        Save-UpgradeState -State $State
    } else {
        Clear-UpgradeState
    }

    try {
        if (Test-Path -Path $stateDirectory) {
            Remove-Item -Path $stateDirectory -Recurse -Force -ErrorAction Stop
            Write-Log -Message "Removed state directory $stateDirectory." -Level "VERBOSE"
        }
    } catch {
        Write-Log -Message "Unable to remove state directory during cleanup. Error: $_" -Level "WARN"
    }

    Write-Log -Message "Post-upgrade cleanup complete. Log file retained at $logFile." -Level "INFO"
}

function Invoke-UpgradeFailureCleanup {
    param([switch]$PreserveHealthyIso)

    Write-Log -Message "Starting cleanup of failed upgrade artifacts." -Level "WARN"

    $pathsToClear = @(
        "C:\`$WINDOWS.~BT",
        "C:\`$WINDOWS.~BT\DUImageSandbox",
        "C:\`$WINDOWS.~WS",
        "C:\`$WINDOWS.~LS"
    )

    foreach ($path in $pathsToClear) {
        if (-not (Test-Path -Path $path)) {
            continue
        }

        try {
            Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
            Write-Log -Message ("Removed failure artifact {0}." -f $path) -Level "VERBOSE"
        } catch {
            Write-Log -Message ("Unable to remove failure artifact {0}. Error: {1}" -f $path, $_) -Level "WARN"
        }
    }

    if (Test-Path -Path $stateDirectory) {
        $preserveNames = @()

        if ($PreserveHealthyIso -and (Test-Path -Path $isoFilePath)) {
            if (Get-Command -Name Test-IsoFileHealthy -ErrorAction SilentlyContinue) {
                if (Test-IsoFileHealthy -Path $isoFilePath -and (Test-IsoHashValid -Path $isoFilePath -AllowUnknownCache)) {
                    $preserveNames += (Split-Path -Path $isoFilePath -Leaf)
                    if (Test-Path -Path $isoHashCacheFile) {
                        $preserveNames += (Split-Path -Path $isoHashCacheFile -Leaf)
                    }
                    Write-Log -Message "Preserving validated ISO while clearing staging folder after failure." -Level "INFO"
                } else {
                    try {
                        Remove-Item -Path $isoFilePath -Force -ErrorAction Stop
                        Write-Log -Message "Deleted invalid ISO during failure cleanup." -Level "WARN"
                    } catch {
                        Write-Log -Message "Unable to delete invalid ISO during failure cleanup. Error: $_" -Level "WARN"
                    }
                    if (Test-Path -Path $isoHashCacheFile) {
                        Remove-Item -Path $isoHashCacheFile -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }

        if (Test-Path -Path $failureMarker) {
            $preserveNames += (Split-Path -Path $failureMarker -Leaf)
        }

        try {
            $items = Get-ChildItem -Path $stateDirectory -Force -ErrorAction Stop
            foreach ($entry in $items) {
                if ($preserveNames -contains $entry.Name) {
                    continue
                }

                try {
                    Remove-Item -Path $entry.FullName -Recurse -Force -ErrorAction Stop
                    Write-Log -Message ("Removed failure staging artifact {0}." -f $entry.FullName) -Level "VERBOSE"
                } catch {
                    Write-Log -Message ("Unable to remove failure staging artifact {0}. Error: {1}" -f $entry.FullName, $_) -Level "WARN"
                }
            }
        } catch {
            Write-Log -Message ("Unable to enumerate state directory {0}. Error: {1}" -f $stateDirectory, $_) -Level "WARN"
        }
    }

    Ensure-Directory -Path $stateDirectory
    Write-Log -Message "Failure cleanup completed." -Level "INFO"
}

if ($ListCleanupTargets) {
    Write-Log -Message "Cleanup targets preview:" -Level "INFO"
    $targets = @(
        (Join-Path -Path $stateDirectory -ChildPath "SetupLogs"),
        (Join-Path -Path $stateDirectory -ChildPath "SetupLogs_PostUpgrade.zip"),
        (Join-Path -Path $stateDirectory -ChildPath "ToastAssets"),
        (Join-Path -Path $stateDirectory -ChildPath "RunHidden_*.vbs"),
        (Join-Path -Path $stateDirectory -ChildPath "RebootReminderNotification.ps1"),
        (Join-Path -Path $stateDirectory -ChildPath "RunHiddenReminder.vbs"),
        (Join-Path -Path $stateDirectory -ChildPath "Show-Notification.ps1"),
        (Join-Path -Path $stateDirectory -ChildPath "Toast-Download.ps1"),
        (Join-Path -Path $stateDirectory -ChildPath "Toast-RebootReminder.ps1"),
        $isoHashCacheFile,
        $isoFilePath,
        $stateDirectory
    ) | Where-Object { $_ }

    foreach ($target in $targets) {
        Write-Log -Message (" - {0}" -f $target) -Level "INFO"
    }
}
