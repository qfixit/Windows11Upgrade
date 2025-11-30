# Core Utilities & Progress Helpers
# Version 2.5.8
# Date 11/29/2025
# Author Remark: Quintin Sheppard
# Summary: Common logging, directory creation, and progress/summary helpers used across the upgrade workflow.
# Example: powershell.exe -ExecutionPolicy Bypass -NoProfile -Command ". '\\Windows11Upgrade\\MainFunctions.ps1'; Write-Log 'hello world'"

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "VERBOSE")]
        [string]$Level = "INFO"
    )

    if ([string]::IsNullOrWhiteSpace($logFile)) {
        $logFile = "C:\Windows11UpgradeLog.txt"
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] $Message"

    if (-not [string]::IsNullOrWhiteSpace($logFile)) {
        $directory = Split-Path -Path $logFile -Parent
        if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
    }

    $maxAttempts = 5
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            $fileStream = [System.IO.File]::Open($logFile,
                                                 [System.IO.FileMode]::OpenOrCreate,
                                                 [System.IO.FileAccess]::Write,
                                                 [System.IO.FileShare]::ReadWrite)
            $fileStream.Seek(0, [System.IO.SeekOrigin]::End) | Out-Null
            $writer = New-Object System.IO.StreamWriter($fileStream, [System.Text.Encoding]::UTF8)
            $writer.WriteLine($logMessage)
            $writer.Dispose()
            $fileStream.Dispose()
            break
        } catch {
            if ($attempt -eq $maxAttempts) {
                Write-Warning "Unable to append to $logFile after $maxAttempts attempts. Error: $_"
            } else {
                Start-Sleep -Milliseconds 250
            }
        }
    }

    switch ($Level) {
        "ERROR"   { Write-Error $logMessage }
        "WARN"    { Write-Warning $logMessage }
        "VERBOSE" { Write-Verbose $logMessage }
        default   { Write-Host $logMessage }
    }

    if ($Level -ne "VERBOSE") {
        Write-Verbose $logMessage
    }
}

function Ensure-Directory {
    param ([string]$Path)

    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
        Write-Log -Message "Created directory $Path" -Level "VERBOSE"
    }
}

function Write-LastRebootEventInfo {
    try {
        $lastRebootEvent = Get-WinEvent -LogName System -FilterHashtable @{ Id = 1074 } -MaxEvents 1 -ErrorAction Stop
        if ($lastRebootEvent) {
            $message = ($lastRebootEvent.Message -replace "`r?`n", " ").Trim()
            Write-Log -Message ("Last reboot recorded by Event ID 1074 at {0:u}: {1}" -f $lastRebootEvent.TimeCreated, $message) -Level "INFO"
        } else {
            Write-Log -Message "No Event ID 1074 reboot entries found in the System log." -Level "WARN"
        }
    } catch {
        Write-Log -Message "Unable to read last reboot information. Error: $_" -Level "WARN"
    }
}

function Get-SetupProgressSnapshot {
    try {
        $props = Get-ItemProperty -Path $moSetupVolatileKey -ErrorAction Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
        return $null
    } catch {
        Write-Log -Message ("Unable to query MoSetup progress registry path. Error: {0}" -f $_) -Level "VERBOSE"
        return $null
    }

    if ($props.PSObject.Properties.Match("SetupProgress").Count -eq 0) {
        return $null
    }

    return [pscustomobject]@{
        SetupProgress = [int]$props.SetupProgress
    }
}

function Write-SetupProgressUpdate {
    param(
        [hashtable]$Tracker,
        [switch]$Force
    )

    if (-not $Tracker) {
        $Tracker = @{
            LastProgress   = $null
            SourceDetected = $false
            MissingLogged  = $false
        }
    }

    $snapshot = Get-SetupProgressSnapshot
    if (-not $snapshot) {
        if ($Tracker.SourceDetected -and -not $Tracker.MissingLogged) {
            Write-Log -Message "MoSetup progress registry key not available yet. Waiting for setup.exe to publish progress." -Level "VERBOSE"
            $Tracker.MissingLogged = $true
        }
        return
    }

    $Tracker.MissingLogged = $false
    if (-not $Tracker.SourceDetected) {
        Write-Log -Message "Tracking Windows setup progress." -Level "INFO"
        $Tracker.SourceDetected = $true
    }

    $shouldLog = $false
    if ($null -ne $snapshot.SetupProgress -and ($Force -or $snapshot.SetupProgress -ne $Tracker.LastProgress)) {
        Write-Log -Message ("Install progress {0}%" -f $snapshot.SetupProgress) -Level "INFO"
        $Tracker.LastProgress = $snapshot.SetupProgress
        $shouldLog = $true
    }

    if (-not $shouldLog -and $Force -and $Tracker.SourceDetected) {
        $finalProgress = if ($null -ne $Tracker.LastProgress) { "{0}%" -f $Tracker.LastProgress } else { "unknown" }
        Write-Log -Message ("Install progress final state: {0}" -f $finalProgress) -Level "INFO"
    }
}

function Write-ExecutionSummary {
    if ($script:SummaryLogged) {
        return
    }

    $totalElapsed = $null
    if ($script:ScriptStopwatch) {
        if ($script:ScriptStopwatch.IsRunning) {
            $script:ScriptStopwatch.Stop()
        }
        $totalElapsed = $script:ScriptStopwatch.Elapsed
    }

    $formatDuration = {
        param($Duration)
        if ($null -eq $Duration) {
            return "N/A"
        }

        return ("{0:hh\:mm\:ss\.fff} ({1:N2} seconds)" -f $Duration, $Duration.TotalSeconds)
    }

    Write-Log -Message "Execution timing summary:" -Level "INFO"
    Write-Log -Message (" - Total runtime: {0}" -f (& $formatDuration $totalElapsed)) -Level "INFO"
    Write-Log -Message (" - ISO download: {0}" -f (& $formatDuration $script:IsoDownloadDuration)) -Level "INFO"
    Write-Log -Message (" - setup.exe execution: {0}" -f (& $formatDuration $script:SetupExecutionDuration)) -Level "INFO"

    $script:SummaryLogged = $true
}

function Complete-Execution {
    param([string]$Message = "Windows 11 upgrade script finished.")

    Write-ExecutionSummary
    Write-Log $Message
}
