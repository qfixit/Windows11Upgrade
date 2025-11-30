# Post-Upgrade Cleanup (RunOnce/Task Target)
# Version 2.6.0
# Date 11/30/2025
# Author: Quintin Sheppard
# Summary: Post-reboot cleanup that verifies Windows 11, removes reminder/validation tasks, and deletes the staging folder with retries.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Defaults (kept local for robustness)
$stateDirectory = "C:\Temp\WindowsUpdate"
$logFile = "C:\Windows11UpgradeLog.txt"
$reminderTaskNames = @("Win11_RebootReminder_1", "Win11_RebootReminder_2")
$postRebootValidationTaskName = "Win11_PostRebootValidation"
$postRebootValidationRunOnce  = "Win11_PostRebootValidation_RunOnce"

# Resolve log target and ensure it exists
if (-not (Test-Path -Path $logFile)) {
    try { New-Item -Path $logFile -ItemType File -Force | Out-Null } catch {}
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","VERBOSE")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp [$Level] $Message"
    try { Add-Content -Path $logFile -Value $line } catch {}
    switch ($Level) {
        "ERROR"   { Write-Error $line }
        "WARN"    { Write-Warning $line }
        "VERBOSE" { Write-Verbose $line }
        default   { Write-Information -MessageData $line -InformationAction Continue }
    }
    if ($Level -ne "VERBOSE") { Write-Verbose $line }
}

function Test-IsWindows11Simple {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        if ($os.Caption -and ($os.Caption -match "Windows 11")) { return $true }
        if ($os.BuildNumber -and ([int]$os.BuildNumber -ge 22000)) { return $true }
    } catch {
        Write-Log -Message "OS detection failed; assuming not Windows 11. Error: $_" -Level "WARN"
    }
    return $false
}

function Remove-TasksAndRunOnce {
    $schtasksExe = Join-Path -Path $env:SystemRoot -ChildPath "System32\schtasks.exe"

    foreach ($taskName in $reminderTaskNames + @($postRebootValidationTaskName)) {
        try { & $schtasksExe /Delete /TN $taskName /F 2>$null | Out-Null } catch {}
    }

    try {
        $runOnceKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
        if (Test-Path -Path $runOnceKey) {
            if ($postRebootValidationRunOnce) {
                Remove-ItemProperty -Path $runOnceKey -Name $postRebootValidationRunOnce -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-Log -Message "Failed to remove RunOnce entry. Error: $_" -Level "WARN"
    }
}

function Ensure-RunOnceRetry {
    try {
        $powershellExe = Join-Path -Path $env:SystemRoot -ChildPath "System32\WindowsPowerShell\v1.0\powershell.exe"
        $runOnceKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
        $runOnceName = if ($postRebootValidationRunOnce) { $postRebootValidationRunOnce } else { "Win11_PostCleanup_Retry" }
        $scriptPath = if ($script:CurrentScriptPath) { $script:CurrentScriptPath } else { Join-Path -Path $stateDirectory -ChildPath "Windows11Upgrade.ps1" }
        $cmd = ('"{0}" -ExecutionPolicy Bypass -NoProfile -File "{1}"' -f $powershellExe, $scriptPath)
        New-Item -Path $runOnceKey -Force | Out-Null
        Set-ItemProperty -Path $runOnceKey -Name $runOnceName -Value $cmd -Force
        Write-Log -Message ("Cleanup retry registered via RunOnce {0} because {1} still exists." -f $runOnceName, $stateDirectory) -Level "WARN"
    } catch {
        Write-Log -Message ("Failed to register RunOnce retry for cleanup. Error: {0}" -f $_) -Level "ERROR"
    }
}

try {
    Write-Log -Message "Post-reboot cleanup started." -Level "INFO"

    $isWin11 = Test-IsWindows11Simple
    if (-not $isWin11) {
        Write-Log -Message "Windows 11 not detected; skipping cleanup to preserve staging." -Level "WARN"
        return
    }

    # Attempt folder removal up to 3 times
    $removed = $false
    if (Test-Path -Path $stateDirectory -PathType Container) {
        foreach ($attempt in 1..3) {
            try {
                Remove-Item -Path $stateDirectory -Recurse -Force -ErrorAction Stop
                Write-Log -Message ("Removed state directory {0} on attempt {1}." -f $stateDirectory, $attempt) -Level "INFO"
                $removed = $true
                break
            } catch {
                Write-Log -Message ("Attempt {0} to remove {1} failed. Error: {2}" -f $attempt, $stateDirectory, $_) -Level "WARN"
                Start-Sleep -Seconds 3
            }
        }

        if (-not $removed) {
            Write-Log -Message ("State directory {0} could not be removed after 3 attempts; cleanup will need manual review." -f $stateDirectory) -Level "ERROR"
        }
    } else {
        Write-Log -Message ("State directory {0} not found; nothing to remove." -f $stateDirectory) -Level "VERBOSE"
        $removed = $true
    }

    if ($removed -or -not (Test-Path -Path $stateDirectory -PathType Container)) {
        Remove-TasksAndRunOnce
        Write-Log -Message "Post-reboot cleanup complete. Log file retained at $logFile." -Level "INFO"
    } else {
        Ensure-RunOnceRetry
        Write-Log -Message ("State directory {0} still present; validation task retained for retry." -f $stateDirectory) -Level "WARN"
    }
} catch {
    Write-Log -Message "Post-reboot cleanup encountered an error: $_" -Level "ERROR"
    throw
}
