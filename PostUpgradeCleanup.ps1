# Post-Upgrade Cleanup (RunOnce/Task Target)
# Version 2.5.8
# Date 11/29/2025
# Summary: Post-reboot cleanup that verifies Windows 11, removes reminder/validation tasks, and deletes the staging folder with retries.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Defaults (kept local for robustness)
$stateDirectory = "C:\Temp\WindowsUpdate"
$logFilePrimary = "C:\Windows11UpgradeLog.txt"
$logFileDevice  = "C:\Windows11UpgradeLog-$($env:COMPUTERNAME).txt"
$reminderTaskNames = @("Win11_RebootReminder_1", "Win11_RebootReminder_2")
$postRebootValidationTaskName = "Win11_PostRebootValidation"
$postRebootValidationRunOnce  = "Win11_PostRebootValidation_RunOnce"

# Resolve log target and ensure it exists
$logFile = $logFilePrimary
if (-not (Test-Path -Path $logFilePrimary) -and (Test-Path -Path $logFileDevice)) {
    $logFile = $logFileDevice
}
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
        default   { Write-Host $line }
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

try {
    Write-Log -Message "Post-reboot cleanup started." -Level "INFO"

    $isWin11 = Test-IsWindows11Simple
    if (-not $isWin11) {
        Write-Log -Message "Windows 11 not detected; skipping cleanup to preserve staging." -Level "WARN"
        return
    }

    # Attempt folder removal up to 3 times
    if (Test-Path -Path $stateDirectory -PathType Container) {
        $removed = $false
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
    }

    Remove-TasksAndRunOnce
    Write-Log -Message "Post-reboot cleanup complete. Log file retained at $logFile." -Level "INFO"
} catch {
    Write-Log -Message "Post-reboot cleanup encountered an error: $_" -Level "ERROR"
    throw
}
