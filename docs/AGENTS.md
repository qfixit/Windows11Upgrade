# Repository Guidelines

## Additional Instruction References
- Refer to `docs/Workflow.md` on the expected workflow of this package
- Refer to - Refer to `docs/powershell.instructions.md` for additional Coding Style and Naming Conventions.

## Project Structure & Module Organization
- Root PowerShell entry point: `Windows11Upgrade.ps1` orchestrates staging, toast notifications, scheduled tasks, and post-upgrade cleanup using helpers such as `MainFunctions.ps1`, `Detection.ps1`, `IsoDownload.ps1`, `SystemChecks.ps1`, `ScheduledTasks.ps1`, `SelfRepair.ps1`, and `PostUpgradeCleanup.ps1`.
- Configuration emitters live in `UpgradeConfig.ps1` and `UpgradeConfig-RMM.ps1`; version stamp is tracked in `Version.txt`.
- Toast assets/scripts sit under `Toast-Notification`; keep `hero.jpg`, `logo.jpg`, and toast scripts aligned with the orchestrator.
- `docs/README.md` holds the technicians' guide and changelog; reference it for expected paths, tasks, and smoke tests.

## Project Workspace Structure
```
WindowsUpdate\
│   .gitignore
│   Detection.ps1
│   IsoDownload.ps1
│   MainFunctions.ps1
│   PostUpgradeCleanup.ps1
│   ScheduledTasks.ps1
│   SelfRepair.ps1
│   Start-Windows11Upgrade.ps1
│   SystemChecks.ps1
│   UpgradeConfig-RMM.ps1
│   UpgradeConfig.ps1
│   UpgradeState.ps1
│   Version.txt
│   Windows11Upgrade.ps1
│   WindowsUpdate.code-workspace
│
├───docs
│   │   AGENTS.md
│   │   powershell.instructions.md
│   │   README.md
│   │
│   ├───CW RMM
│   │       SampleRun-ConfigureSetup.png
│   │       SampleRun-Schedule.png
│   │       SampleRun-Select.png
│   │       Upgrade to Windows 11.md
│   │
│   └───Toast-Notifications
│           Toast-Download.xml
│           Toast-Install.xml
│           Toast-RebootReminder.xml
│
└───Toast-Notification
        hero.jpg
        logo.jpg
        Toast-Windows11Download.ps1
        Toast-Windows11InstallComplete.ps1
        Toast-Windows11RebootReminder.ps1
```

## Deployed Package Structure on Device

```
C:\Temp\WindowsUpdate\
│   Detection.ps1
│   IsoDownload.ps1
│   MainFunctions.ps1
│   PostUpgradeCleanup.ps1
│   ScheduledTasks.ps1
│   SelfRepair.ps1
│   Start-Windows11Upgrade.ps1
│   SystemChecks.ps1
│   UpgradeConfig-RMM.ps1
│   UpgradeConfig.ps1
│   UpgradeState.ps1
│   Version.txt
│   Windows11Upgrade.ps1
│
└───Toast-Notification
        hero.jpg
        logo.jpg
        Toast-Windows11Download.ps1
        Toast-Windows11InstallComplete.ps1
        Toast-Windows11RebootReminder.ps1
```

## Versioning and Date Requirements
- Every time this file is modified, update both the Version (# Version X.Y.Z) and Date (# Date MM/DD/YYYY) in the header.
- Versions use a three-number semantic format: Major.Minor.Patch
- Each segment may be one or two digits (e.g., 2.5.8, 2.5.12, 2.10.1).
- Patch and Minor version increments are chosen at the agent’s discretion based on the scope of the change.
- Major version increments must be approved or decided by the technician.
- The Date must always reflect the current date when changes are made.

## Build, Test, and Development Commands
- All scripts must be PowerShell 5 compatible
- This package will be deployed en-mass to production devices
- Testing is handled by the Technician on a Windows 10 Virtual Machine with a snapshot of the *Starting Point* so it can be reverted from Windows 11 to Windows 10 post-upgrade for additional tests.

## Coding Style & Naming Conventions
- Preserve relative paths and marker filenames (`ScriptRunning.txt`, `PendingReboot.txt`, `UpgradeFailed.txt`) expected under `C:\Temp\WindowsUpdate`.
- Keep logging consistent with existing helpers; add actionable context to log lines that touch scheduling, ISO handling, or cleanup.
- File names follow PascalCase with hyphens for script entry points (e.g., `Start-Windows11Upgrade.ps1`).
- Refer to `docs/powershell.instructions.md` for additional Coding Style and Naming Conventions.

## Testing Guidelines
- The Technician will test in a virtual enviornment, and report back with any issues or improvements.
- You will be provided the `Windows11UpgradeLog.txt` for reference on how the script performed. If more context or information is needed, ask the technician.

## Commit & Pull Request Guidelines
- Use short, imperative commit messages; conventional prefixes like `feat:`/`fix:` are common (`git log` shows both styles—keep the subject focused on the change).
- Pull requests should describe the scenario, behavior change, and rollout impact, plus manual test evidence (log snippets, task scheduler output, or toast screenshots when UI is involved).
- Link any related tickets/issues and call out risk areas (reboot gating, task creation, ISO download paths) so reviewers can target validation.

## Security & Configuration Tips
- Do not embed credentials, tokens, or proprietary URLs. Accept configuration via parameters and keep defaults pointing to `C:\Temp\WindowsUpgrade`.
- When altering paths or assets, ensure corresponding functions, scheduled tasks and toast scripts reference the updated locations before merging.
