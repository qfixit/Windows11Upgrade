# Start-Windows11Upgrade Orchestration
# Version 2.5.1
# Date 11/28/2025
# Author Remark: Quintin Sheppard
# Summary: Implements the Expected Workflow to stage the Windows 11 upgrade, handle reboots, and self-heal failures.
# Example: powershell.exe -ExecutionPolicy Bypass -NoProfile -Command ". '\\Windows11Upgrade\\Start-Windows11Upgrade.ps1'; Start-Windows11Upgrade"

function Start-Windows11Upgrade {
try {
    Write-Log "Windows 11 25H2 upgrade script started."

    if (-not (Ensure-SentinelAgentCompatible)) {
        Remove-RebootReminderTasks
        Clear-UpgradeState
        Complete-Execution -Message "Windows 11 25H2 upgrade script finished."
        return
    }

    $state = Get-UpgradeState
    $currentBootTime = Get-LastBootTime

    if ($currentBootTime) {
        Write-Log -Message ("Current boot time: {0:o}" -f $currentBootTime) -Level "VERBOSE"
    }

    if ($state -and $state.Status -eq "UpgradeFailed" -and $state.PSObject.Properties.Match("Reason").Count -gt 0) {
        $reason = $state.Reason
        if ($reason) {
            Write-Log -Message ("Previous upgrade failure detected: {0}" -f $reason) -Level "WARN"
        }
        Invoke-UpgradeFailureCleanup -PreserveHealthyIso
        $state = $null
    }

    if (-not $state -or $state.Status -eq "ScriptRunning") {
        $scriptState = [pscustomobject]@{
            Status            = "ScriptRunning"
            StartedOn         = (Get-Date).ToString("o")
            LastKnownBootTime = if ($currentBootTime) { $currentBootTime.ToString("o") } else { $null }
            ProcessId         = $PID
        }
        Save-UpgradeState -State $scriptState
        $state = $scriptState
    }

    if (Test-IsWindows11) {
        Write-Log -Message "Windows 11 already detected on this device." -Level "INFO"
        Invoke-PostUpgradeCleanup -State $state
        Complete-Execution -Message "Windows 11 25H2 upgrade script finished."
        return
    }

    $needsStaging = $true
    $pendingHandledViaSelfRepair = $false
    $pendingStateDetected = $false

    if ($state -and $state.Status -eq "PendingReboot") {
        $pendingStateDetected = $true
        $needsStaging = $false
        Write-Log -Message "Pending reboot state detected from previous run." -Level "INFO"

        $deviceRestartedAfterStaging = $false
        if ($state.LastKnownBootTime) {
            try {
                $recordedBoot = [datetime]::Parse($state.LastKnownBootTime)
            } catch {
                $recordedBoot = $null
            }

            if ($recordedBoot -and $currentBootTime -and $currentBootTime -gt $recordedBoot.AddSeconds(30)) {
                $deviceRestartedAfterStaging = $true
            }
        }

        if ($deviceRestartedAfterStaging) {
            Write-Log -Message "Device has rebooted since staging but upgrade did not complete. Initiating self-repair." -Level "WARN"
            $restaged = Invoke-SelfRepair -State $state
            $pendingHandledViaSelfRepair = $true
            if (-not $restaged) {
                $needsStaging = $true
            }
        } else {
            Write-Log -Message "Awaiting reboot to finalize the upgrade." -Level "VERBOSE"
            Clear-FailureMarker
            Register-RebootReminderTasks
            Register-PostRebootValidationTask
        }
    }

    if ($needsStaging) {
        Write-Log -Message "Pre-flight checks completed; beginning staging pipeline." -Level "INFO"
        try {
            Check-SystemRequirements | Out-Null
        } catch {
            Write-Log -Message "System requirements validation failed prior to ISO download. Error: $_" -Level "ERROR"
            Write-FailureMarker "Hardware requirements validation failed."
            Complete-Execution -Message "Windows 11 25H2 upgrade script finished."
            return
        }

        Write-Log -Message "System requirements confirmed; proceeding to ISO download and staging." -Level "INFO"

        try {
            $isoPath = Download-Windows11Iso
            $stagingResult = Stage-UpgradeFromIso -IsoPath $isoPath -SkipCompatCheck

            if ($stagingResult) {
                Clear-FailureMarker

                $stateToSave = [pscustomobject]@{
                    Status            = "PendingReboot"
                    StagedOn          = (Get-Date).ToString("o")
                    LastKnownBootTime = if ($currentBootTime) { $currentBootTime.ToString("o") } else { (Get-Date).ToString("o") }
                    RebootReminders   = $true
                }

                try {
                    Register-PostRebootValidationTask
                } catch {
                    Write-Log -Message "Failed to register post-reboot validation task after staging. Error: $_" -Level "WARN"
                }

                try {
                    Register-RebootReminderTasks
                } catch {
                    Write-Log -Message "Failed to register reboot reminder tasks after staging. Error: $_" -Level "WARN"
                }

                if ($script:ReminderRegistrationMode) {
                    $stateToSave | Add-Member -NotePropertyName "ReminderMode" -NotePropertyValue $script:ReminderRegistrationMode -Force
                } else {
                    $stateToSave | Add-Member -NotePropertyName "ReminderMode" -NotePropertyValue "ImmediateUser" -Force
                }

                Save-UpgradeState -State $stateToSave
                try {
                    $toastRoot = if ($privateRoot) { $privateRoot } elseif ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Path $MyInvocation.MyCommand.Path -Parent }
                    $toastScript = Join-Path -Path (Join-Path -Path $toastRoot -ChildPath "Toast-Notification") -ChildPath "Toast-Windows11RebootReminder.ps1"
                    $powershellExe = [System.IO.Path]::Combine($env:SystemRoot, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")

                    if (Test-Path -Path $toastScript -PathType Leaf) {
                        Start-Process -FilePath $powershellExe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$toastScript`"" -WindowStyle Hidden -ErrorAction Stop
                        Write-Log -Message ("Reboot reminder toast invoked via {0}." -f $toastScript) -Level "INFO"
                    } else {
                        Write-Log -Message ("Reboot reminder toast script missing at {0}; skipping notification." -f $toastScript) -Level "WARN"
                    }
                } catch {
                    Write-Log -Message ("Reboot reminder toast failed; script={0}; error={1}" -f $toastScript, $_) -Level "WARN"
                }
            } else {
                Write-Log -Message "Staging routine did not complete successfully." -Level "ERROR"
                try {
                    Clear-UpgradeState
                    Write-Log -Message "Cleared ScriptRunning/PendingReboot sentinels after staging failure to surface failure marker on next run." -Level "VERBOSE"
                } catch {
                    Write-Log -Message ("Failed to clear upgrade state after staging failure. Error: {0}" -f $_) -Level "WARN"
                }

                if (Test-Path -Path $failureMarker) {
                    try {
                        $failureReason = (Get-Content -Path $failureMarker -Raw -ErrorAction Stop).Trim()
                        if ($failureReason) {
                            Write-Log -Message ("Staging failure reason preserved in marker: {0}" -f $failureReason) -Level "WARN"
                        }
                    } catch {
                        Write-Log -Message ("Unable to read failure marker after staging failure. Error: {0}" -f $_) -Level "WARN"
                    }
                }
            }
        } catch {
            Write-Log -Message "Unhandled error during staging: $_" -Level "ERROR"
            throw
        }
    } elseif (-not $pendingHandledViaSelfRepair) {
        if ($pendingStateDetected) {
            Write-Log -Message "Upgrade staging already in place. No further action required until reboot." -Level "INFO"
        } else {
            Write-Log -Message "A previous staging attempt is pending review. Scheduling reboot reminders." -Level "INFO"
            Clear-FailureMarker
            Register-RebootReminderTasks
            Register-PostRebootValidationTask
        }
    }

    Complete-Execution -Message "Windows 11 upgrade script finished."
} catch {
    Write-Log -Message "Windows 11 upgrade script encountered an unexpected interruption or error: $_" -Level "ERROR"
    $failureMarked = $false
    try {
        Write-FailureMarker ("Unexpected termination: {0}" -f $_)
        $failureMarked = $true
    } catch {
        Write-Log -Message ("Failed to record failure marker during interruption handling. Error: {0}" -f $_) -Level "WARN"
    }
    if (-not $failureMarked) {
        try {
            Clear-UpgradeState
        } catch {
            Write-Log -Message ("Unable to clear upgrade state after interruption. Error: {0}" -f $_) -Level "WARN"
        }
    }
    try {
        Invoke-UpgradeFailureCleanup -PreserveHealthyIso
    } catch {
        Write-Log -Message "Cleanup after failure encountered an additional error: $_" -Level "WARN"
    }

    try {
        Register-PostRebootValidationTask
    } catch {
        Write-Log -Message "Failed to register post-reboot validation after interruption. Error: $_" -Level "WARN"
    }

    Complete-Execution -Message "Windows 11 25H2 upgrade script finished with errors."
}
}
