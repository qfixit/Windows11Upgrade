- /noreboot needs to be changed. Always use /noreboot in the setup.exe arguments and instead call "shutdown.exe /r /t 0" at the very end if $AutoReboot = True
- Reason: When /noreboot is not used, the device automatically reboots right after setup.exe is finished, additional tasks do not get registered
- Convert the UpgradeConfig.ps1 and UpgradeConfig-RMM.ps1 to a .json file that is referenced in UpgradeConfig.ps1. No static values should be present in UpgradeConfig.ps1.
- UpgradeConfig.ps1 will be used to reference the .json file with configuration parameters. UpgradeConfig-RMM.json needs to be changed to do the following
	1) Generate the config.json with "@Parameter@" values in place of actual values
	2) Write the file to C:\Temp\WindowsUpdate\config.json
- The mechanism that changes "Windows11UpgradeLog.txt" to ""C:\Windows11UpgradeLog-$($env:COMPUTERNAME).txt"" is external to this script, controlled by Connectwise RMM. I have adjusted the monitor to only trigger if all of the following conditions are met
	- OS Display Version is "24H2" or "25H2"
	- C:\Windows11UpgradeLog.txt exists
	- C:\Temp\WindowsUpdate does not exist  *this rule was not previously there
	- We can remove any references to "C:\Windows11UpgradeLog-$($env:COMPUTERNAME).txt" because it will only be renamed after this script has run
## Notes from Codex Review
### Version 1
- Entry script sets `$stateDirectory` from configuration but does not use it elsewhere; consider removing the local variable and relying on the globally exported config value to reduce clutter. 
	- *Windows11Upgrade.ps1 Lines 34-39*
- `Write-LastRebootEventInfo` is defined but never referenced across the workflow; pruning it would tighten the utilities module and avoid confusion about reboot logging coverage.
	- *MainFunctions.ps1 Lines 72-84*
- The orchestration routine has deeply nested `try/catch` and repeated reminder/validation registrations that could be extracted into helper functions to improve readability and reduce duplicated error-handling blocks.
	- *Start-Windows11Upgrade.ps1 Lines 90-214*
- Module loading could be simplified by iterating directly over discovered `.ps1` helper files instead of maintaining a manual list, reducing maintenance effort when adding/removing modules.
	- *Windows11Upgrade.ps1 Lines 21-53*
- Logging defaults fall back to `Write-Host` for non-verbose messages, which can interleave with other output; standardizing on `Write-Information` or consistent log-level routing would improve console cleanliness.
	- *MainFunctions.ps1 Lines 51-60*
### Version 2
- The main entry script exports `$stateDirectory` from configuration but never references it afterward; downstream modules already pull state paths from global variables, so either remove the unused assignment or start using it consistently (for example, pass it explicitly to download helpers).
	- *Windows11Upgrade.ps1 Lines 35-39*
- `Write-LastRebootEventInfo` is defined but never invoked anywhere; removing it or calling it when logging boot-time data would trim dead code and keep diagnostics centralized.
	- *MainFunctions.ps1 Lines 72-84*
- For consistency, the entry script sets `$ErrorActionPreference = 'Stop'` but some helper stubs in `IsoDownload.ps1` still use silent defaults; aligning stub behaviors or removing in-file stub fallbacks (now that the main orchestrator dot-sources the modules) would reduce redundancy and make error handling uniform.
	- *IsoDownload.ps1 Lines 11-38*
### Version 3
#### Optimization & Simplification Opportunities
- The entry point reconstructs its location and module paths manually before dot-sourcing, even though `$PSScriptRoot` already provides the root; replacing the custom `$script:CurrentScriptPath`/`$privateRoot` logic and the hard-coded hash of module paths with `$PSScriptRoot`-relative imports would simplify startup and reduce reliance on global variables.
	- *Windows11Upgrade.ps1 Lines 18-53*
- `UpgradeConfig.ps1` exports every configuration value globally; narrowing scope (returning the object and passing it to functions) would reduce global state coupling and make unit testing easier.
	- *UpgradeConfig.ps1 Lines 32-39*
- `LoggingLevel` is defined in the configuration but never consumed; either remove it or plumb it into `Write-Log` to drive console/log verbosity so the setting has an effect.
	- *UpgradeConfig.ps1 Lines 10-17*
- `Write-LastRebootEventInfo` isn’t referenced anywhere; wiring it into diagnostics would eliminate dead code and clarify the supported logging surface.
	- *MainFunctions.ps1 Lines 72-84*
- `IsoDownload.ps1` redefines stub helpers (`Write-Log`, `Write-FailureMarker`, `Clear-FailureMarker`, `Ensure-Directory`) that already exist in the orchestrator load order; consider removing these duplicates or gating them behind a dedicated standalone/test entry point to avoid divergent behaviors between test and production runs.
	- *IsoDownload.ps1 Lines 10-36*
#### Consistency & Cleanliness
- Prefer consistent module initialization: e.g., have each module validate prerequisites internally instead of the entry script looping through a hard-coded list, which would allow automatic discovery and clearer failure messages when modules are added or renamed.
	- *Windows11Upgrade.ps1 Lines 21-53*
- Align helper reuse: functions like `Ensure-SufficientDiskSpace` already encapsulate prerequisites; reusing similar guard patterns (e.g., for TPM/Secure Boot checks) across modules would standardize error handling and logging severity levels.
	- *SystemChecks.ps1 Lines 13-71*