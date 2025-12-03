# Error Code Definitions for Windows11Upgrade
# Version 2.6.3
# Date 11/30/2025
# Author: Quintin Sheppard
# Summary: Centralized error code catalog with technician-friendly descriptions and remediation hints.

$script:ErrorCatalog = @(
    [pscustomobject]@{
        Code        = 10
        Title       = "System shutdown in progress"
        Description = "Windows reported a shutdown while the upgrade was running."
        Remediation = "Allow the device to fully reboot, then rerun the upgrade script; the self-repair task will restage."
    },
    [pscustomobject]@{
        Code        = 11
        Title       = "ISO download transport unavailable"
        Description = "BITS and the web-request fallback could not fetch the Windows 11 ISO."
        Remediation = "Verify internet access, proxy/auth requirements, and BITS service health; rerun to resume download."
    },
    [pscustomobject]@{
        Code        = 12
        Title       = "ISO validation failed after retries"
        Description = "The downloaded ISO could not pass health/hash checks after multiple attempts."
        Remediation = "Confirm the ISO URL and expected SHA256; rerun after updating configuration."
    },
    [pscustomobject]@{
        Code        = 13
        Title       = "ISO mount/staging failed after retries"
        Description = "setup.exe could not mount or stage from the ISO after multiple retries."
        Remediation = "Check disk space, retry download, and review setup logs under C:\Temp\WindowsUpdate\SetupLogs."
    },
    [pscustomobject]@{
        Code        = 14
        Title       = "Application/driver compatibility block (0xC1900208)"
        Description = "setup.exe reported an app or driver compatibility block."
        Remediation = "Review setup logs for the blocking app/driver, remediate, then rerun the upgrade."
    }
)

function Get-ErrorCodeInfo {
    param(
        [Parameter(Mandatory)][int]$Code
    )

    $match = $script:ErrorCatalog | Where-Object { $_.Code -eq $Code } | Select-Object -First 1
    if ($match) { return $match }

    return [pscustomobject]@{
        Code        = $Code
        Title       = "Unknown error"
        Description = "No description available."
        Remediation = "Review logs for additional details."
    }
}
