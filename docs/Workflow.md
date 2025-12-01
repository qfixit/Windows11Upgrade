# Windows 11 Upgrade – Expected Workflow (v2.5.9, 2025-11-29)

## Overview
- Launched via ConnectWise RMM Task as `NT AUTHORITY\SYSTEM`.
- Entry point: `Windows11Upgrade.ps1` (modular loaders under the same folder).
- Logs to `C:\Windows11UpgradeLog.txt` (device-specific fallback honored).
- State markers: `C:\Temp\WindowsUpdate\ScriptRunning.txt`, `PendingReboot.txt`, `UpgradeFailed.txt`.
- Post-reboot validation: scheduled task `Win11_PostRebootValidation` (ONLOGON, SYSTEM, highest) plus RunOnce fallback; both invoke `Windows11Upgrade.ps1`.

## Connectwise RMM Task Deployment Overview
- Uses *Parameters* delimited by "@" for passing in configuration values. Ex. `@WindowsIsoUrl@`, `@ISOHash@`
- Logs all actions to `C:\Windows11UpgradeLog.txt`

### Task Steps
1) Type: Powershell Script
	1) Downloads the latest release of `Windows11Upgrade.zip` from GitHub release
   2) Saves `Windows11Upgrade.zip` to `C:\Temp\Windows11Upgrade.zip`
   3) Extracts `Windows11Upgrade.zip` to `C:\Temp\WindowsUpdate`
   4) Deletes `Windows11Upgrade.zip`
2) Type: Powershell Script
   1) Creates a new `UpgradeConfig.ps1`, replacing `UpgradeConfig.ps1` in the default package, with Parameters defined in task
3) Type: Command Prompt (CMD) Script
   1) Runs the `Windows11Upgrade.ps1`
   ```
   powershell -ExecutionPolicy Bypass -File "C:\Temp\WindowsUpdate\Windows11Upgrade.ps1" -Wait
   ```
4) Captures logging ouput and shows in *Task Summary* within Connectwise RMM

## Staging (Windows 10)
1) Initialize logging; ensure module paths exist; set `$ErrorActionPreference='Stop'`.
2) SentinelOne gate: if version < 24.2.2.0 or unreadable -> fail, write `UpgradeFailed.txt`, log actionable message.
3) Create `ScriptRunning.txt`; detect OS. If already Windows 11 -> run post-upgrade cleanup and exit success.
4) Hardware checks: TPM 2.0, Secure Boot, 64-bit CPU, RAM ≥ 4 GB, disk space (64 GB default). Fail with logged reason and `UpgradeFailed.txt` if unsupported.
5) ISO handling:
   - Reuse existing ISO if hash matches expected SHA256.
   - Otherwise BITS download with progress logging and download toast; validate size/hash; retry up to 3 times, else fail and write `UpgradeFailed.txt`.
6) Setup staging:
   - Mount ISO, run `setup.exe /Auto Upgrade /copylogs "<SetupLogs>" /DynamicUpdate Enable/Disable /noreboot /EULA accept /Quiet`.
   - Track MoSetup Volatile progress; log duration.
   - On setup failure: swap `ScriptRunning.txt` for `UpgradeFailed.txt` with reason.
7) On successful staging:
   - Register `Win11_PostRebootValidation` (ONLOGON) and RunOnce fallback.
   - Register reboot reminder tasks (`Win11_RebootReminder_1/2`).
   - Fire reboot reminder toast immediately.
   - Save `PendingReboot.txt`; remove `ScriptRunning.txt`; log timings.

## Post-Reboot Validation & Cleanup (Windows 11)
- Trigger: `Win11_PostRebootValidation` task or RunOnce entry runs `Windows11Upgrade.ps1` after logon.
- Flow when Windows 11 is detected:
  - Invoke post-upgrade cleanup.
  - Delete `C:\Temp\WindowsUpdate`. On successful deltetion, remove reminder/validation tasks and RunOnce.
  - If deletion fails (folder locked), retain the validation task and register RunOnce retry; log warning for manual follow-up if it persists.
- Flow when still on Windows 10 after reboot:
  - Mark `UpgradeFailed.txt`; leave state for technician review.

## Error Handling & Self Repair Notes
- Assume this script can be interrupted at any point during its run, and should be able to handle self-repair and re-run automatically without manual technician intervention. (Corruption, Device Sleep/Reboot/Shutdown etc.)
- All instances where a failure occurs that cannot be automatically recovered need to be marked with `UpgradeFailed.txt`.
- External monitoring: ConnectWise RMM watches `PendingReboot.txt`/`UpgradeFailed.txt` and alerts the technician.
