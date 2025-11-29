# Scheduled Task Helpers
# Version 2.5.1
# Date 11/28/2025
# Author Remark: Quintin Sheppard
# Summary: Registers/cleans reboot reminder tasks and post-reboot validation tasks.
# Example: powershell.exe -ExecutionPolicy Bypass -NoProfile -Command ". '\\Windows11Upgrade\\ScheduledTasks.ps1'; Register-RebootReminderTasks"

function Register-RebootReminderTasks {
    Write-Log -Message "Configuring reboot reminder notifications." -Level "INFO"

    try {
        if ([string]::IsNullOrWhiteSpace($privateRoot)) {
            try {
                if ($PSScriptRoot) {
                    $privateRoot = $PSScriptRoot
                } elseif ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
                    $privateRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
                } else {
                    $privateRoot = (Get-Location).ProviderPath
                }
            } catch {
                $privateRoot = (Get-Location).ProviderPath
            }
            Write-Log -Message ("Resolved privateRoot to {0} for reminder task registration." -f $privateRoot) -Level "VERBOSE"
        }
        $user = $null
        try {
            $user = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty UserName
        } catch {
            Write-Log -Message "Unable to query logged-on user for reminders. Error: $_" -Level "WARN"
        }

    $toastReminderScript = Join-Path -Path $privateRoot -ChildPath "Toast-Notification\Toast-Windows11RebootReminder.ps1"
    $powershellExe = Join-Path -Path $env:SystemRoot -ChildPath "System32\WindowsPowerShell\v1.0\powershell.exe"

    if ([string]::IsNullOrWhiteSpace($toastReminderScript) -or -not (Test-Path -Path $toastReminderScript -PathType Leaf)) {
        Write-Log -Message ("Reboot reminder toast script missing at {0}; reminder tasks will not be registered. privateRoot={1}" -f $toastReminderScript, $privateRoot) -Level "WARN"
        return
    }

    if (-not (Test-Path -Path $powershellExe -PathType Leaf)) {
        Write-Log -Message ("PowerShell executable not found at expected path {0}; reminder tasks will not be registered." -f $powershellExe) -Level "WARN"
        return
    }

    $command = "`"$powershellExe`" -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$toastReminderScript`""
    Write-Log -Message ("Reminder task command: {0}" -f $command) -Level "VERBOSE"

    foreach ($taskName in $reminderTaskNames) {
        schtasks /Delete /TN $taskName /F 2>$null
    }

    if ($user) {
        $taskCommand = ('"{0}"' -f $command)
        $createArgs1 = "/Create", "/TN", $reminderTaskNames[0], "/TR", $taskCommand, "/SC", "DAILY", "/ST", $RebootReminder1Time, "/RL", "HIGHEST", "/F", "/IT", "/RU", $user
        $output1 = & C:\Windows\System32\schtasks.exe $createArgs1 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log -Message ("Failed to register {0}. Exit code: {1}. Command: schtasks {2}" -f $reminderTaskNames[0], $LASTEXITCODE, ($createArgs1 -join " ")) -Level "ERROR"
            if ($output1) { Write-Log -Message ("schtasks output: {0}" -f (($output1 | Out-String).Trim())) -Level "WARN" }
        } else {
            Write-Log -Message ("{0} registered for {1} daily." -f $reminderTaskNames[0], $RebootReminder1Time) -Level "INFO"
        }

        $createArgs2 = "/Create", "/TN", $reminderTaskNames[1], "/TR", $taskCommand, "/SC", "DAILY", "/ST", $RebootReminder2Time, "/RL", "HIGHEST", "/F", "/IT", "/RU", $user
        $output2 = & C:\Windows\System32\schtasks.exe $createArgs2 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log -Message ("Failed to register {0}. Exit code: {1}. Command: schtasks {2}" -f $reminderTaskNames[1], $LASTEXITCODE, ($createArgs2 -join " ")) -Level "ERROR"
            if ($output2) { Write-Log -Message ("schtasks output: {0}" -f (($output2 | Out-String).Trim())) -Level "WARN" }
        } else {
            Write-Log -Message ("{0} registered for {1} daily." -f $reminderTaskNames[1], $RebootReminder2Time) -Level "INFO"
        }
        $script:ReminderRegistrationMode = "ImmediateUser"
    } else {
        Write-Log -Message "No interactive user detected; scheduling reboot reminders to display at next user logon." -Level "WARN"
        try {
            Import-Module ScheduledTasks -ErrorAction Stop
        } catch {
            Write-Log -Message "Unable to import ScheduledTasks module. Reminder tasks will not be queued. Error: $_" -Level "ERROR"
            return
        }

        $trigger = New-ScheduledTaskTrigger -AtLogOn
        if ([string]::IsNullOrWhiteSpace($powershellExe) -or [string]::IsNullOrWhiteSpace($toastReminderScript)) {
            Write-Log -Message ("Cannot create reminder action because PowerShell or toast script path is empty. PowerShell={0}; Toast={1}" -f $powershellExe, $toastReminderScript) -Level "WARN"
            return
        }
        $actionObj = New-ScheduledTaskAction -Execute $powershellExe -Argument ("-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"{0}`"" -f $toastReminderScript)
        $principal = New-ScheduledTaskPrincipal -UserId "INTERACTIVE" -LogonType Interactive -RunLevel Highest

        foreach ($taskName in $reminderTaskNames) {
            try {
                Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $actionObj -Principal $principal -Force | Out-Null
                Write-Log -Message "$taskName registered with Interactive logon trigger." -Level "INFO"
            } catch {
                Write-Log -Message "Failed to register $taskName for logon reminder. Error: $_" -Level "ERROR"
            }
        }
        $script:ReminderRegistrationMode = "LogonFallback"
    }
    } catch {
        Write-Log -Message ("Failed to register reboot reminder tasks. Error: {0}" -f $_) -Level "WARN"
    }
}

function Remove-RebootReminderTasks {
    foreach ($taskName in $reminderTaskNames) {
        schtasks /Delete /TN $taskName /F 2>$null
        Write-Log -Message "Removed scheduled task $taskName (if it existed)." -Level "VERBOSE"
    }

    if (Test-Path -Path $rebootReminderScript) {
        Remove-Item -Path $rebootReminderScript -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -Path $rebootReminderVbs) {
        Remove-Item -Path $rebootReminderVbs -Force -ErrorAction SilentlyContinue
    }
}

function Ensure-PostRebootScript {
    if (-not $script:CurrentScriptPath -or -not (Test-Path -Path $script:CurrentScriptPath)) {
        Write-Log -Message "Unable to persist script for post-reboot validation because the current script path is unavailable." -Level "WARN"
        return $null
    }

    try {
        Ensure-Directory -Path $stateDirectory

        $sourcePath = [System.IO.Path]::GetFullPath($script:CurrentScriptPath)
        $destinationPath = [System.IO.Path]::GetFullPath($postRebootScriptPath)

        if ($sourcePath -eq $destinationPath -and (Test-Path -Path $destinationPath)) {
            return $destinationPath
        }

        Copy-Item -Path $sourcePath -Destination $destinationPath -Force
        Write-Log -Message "Persisted current script to $destinationPath for post-reboot validation." -Level "VERBOSE"
        return $destinationPath
    } catch {
        Write-Log -Message "Unable to persist script for post-reboot validation. Error: $_" -Level "ERROR"
        return $null
    }
}

function Register-PostRebootValidationTask {
    $targetScript = Ensure-PostRebootScript
    if (-not $targetScript) {
        Write-Log -Message "Skipping registration of post-reboot validation task because the script could not be persisted." -Level "WARN"
        return
    }

    schtasks /Delete /TN $postRebootValidationTaskName /F 2>$null

    $powershellExe = Join-Path -Path $env:SystemRoot -ChildPath "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -Path $powershellExe -PathType Leaf)) {
        Write-Log -Message ("PowerShell executable not found at expected path {0}; post-reboot validation task will not be registered." -f $powershellExe) -Level "WARN"
        return
    }

    if (-not (Test-Path -Path $targetScript -PathType Leaf)) {
        Write-Log -Message ("Post-reboot validation script missing at {0}; task will not be registered." -f $targetScript) -Level "WARN"
        return
    }

    $command = "`"$powershellExe`" -ExecutionPolicy Bypass -NoProfile -File `"$targetScript`""
    $schtasksExe = Join-Path -Path $env:SystemRoot -ChildPath "System32\schtasks.exe"
    $schtasksArgs = @(
        "/Create",
        "/TN", $postRebootValidationTaskName,
        "/TR", $command,
        "/SC", "ONSTART",
        "/RL", "HIGHEST",
        "/F",
        "/RU", "SYSTEM"
    )

    try {
        $schtasksOutput = & $schtasksExe @schtasksArgs 2>&1
    } catch {
        Write-Log -Message ("Register-PostRebootValidationTask execution failed. Command: {0} {1}. Error: {2}" -f $schtasksExe, ($schtasksArgs -join " "), $_) -Level "WARN"
        return
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Log -Message ("Failed to register post-reboot validation task. Exit code: {0}. Command: {1}" -f $LASTEXITCODE, $command) -Level "WARN"
        if ($schtasksOutput) {
            $formatted = ($schtasksOutput | Where-Object { $_ } | Out-String).Trim()
            if ($formatted) {
                Write-Log -Message ("schtasks output: {0}" -f $formatted) -Level "WARN"
            }
        }
    } else {
        Write-Log -Message "Post-reboot validation task registered to rerun the script after the next restart." -Level "INFO"
    }
}

function Remove-PostRebootValidationTask {
    schtasks /Delete /TN $postRebootValidationTaskName /F 2>$null
    Write-Log -Message "Removed post-reboot validation task (if it existed)." -Level "VERBOSE"

    if (Test-Path -Path $postRebootScriptPath) {
        try {
            Remove-Item -Path $postRebootScriptPath -Force -ErrorAction Stop
            Write-Log -Message "Removed persisted post-reboot script at $postRebootScriptPath." -Level "VERBOSE"
        } catch {
            Write-Log -Message "Failed to remove persisted post-reboot script. Error: $_" -Level "WARN"
        }
    }
}
