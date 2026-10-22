# sync-guard

**A tiny PowerShell watchdog that stops Google Drive for desktop and OneDrive from eating your CPU, by pinning them to a couple of cores at low priority instead of killing them.**

> [!WARNING]
> **Experimental.** Built for and used daily on one Windows 11 laptop (6 cores / 12 threads) since October 2026. Tested on Windows 11 with Windows PowerShell 5.1 and PowerShell 7.6.6 (2026-10-22). It has no installer and no tests beyond that. **With the default settings it force-closes iCloud Photos** (see [Configuration](#configuration)).

**TL;DR**
- Cloud-sync clients can sit at high CPU for long stretches (initial sync, re-indexing, large photo libraries), and Windows gives them the same priority as the app you are working in.
- You usually cannot just close them: Google Drive for desktop and OneDrive serve the mounted drive and download ("hydrate") files on demand. Freeze or kill them and opening a file from the drive hangs.
- `SyncGuard.ps1` runs in the background, and every 20 seconds:
  - **throttles** processes on the throttle list: sets their priority (`Idle`, `BelowNormal`, ...) and their CPU affinity (for example cores 0-1 only), once per process ID;
  - **kills** processes on the kill list (by default iCloud Photos, for machines where you do not want photo sync at all).
- Create a file named `STOP` next to the script and it restores normal priority and all cores to the throttled processes, then exits.

---

## The problem

Sync clients are background work, but Windows schedules them like foreground work. On a laptop that means fans, heat and a sluggish editor while the sync client re-hashes a folder you did not touch.

The two obvious fixes both break something:

| Fix | What goes wrong |
|---|---|
| Pause sync in the client | Has to be redone by hand, and resumes on its own after a few hours. |
| Close or suspend the client | The virtual drive (`G:` for Google Drive, Files On-Demand for OneDrive) stops serving files. Apps that open a file there hang. |
| Lower priority once in Task Manager | Lost on every restart, and the clients restart their processes often. |

Lowering priority **and** limiting the client to a few cores keeps it working (files still open, sync still finishes) while leaving the rest of the CPU to you. `sync-guard` just re-applies that every time the client starts a new process.

## Install

Requirements: Windows 10/11, Windows PowerShell 5.1 (built in) or PowerShell 7.

1. Put the folder somewhere permanent, e.g. `%LOCALAPPDATA%\sync-guard`.
2. Optional: copy `syncguard.example.json` to `syncguard.json` and edit it (see below).
3. Try it in a console first:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\SyncGuard.ps1
   ```
   Watch `guard.log` in the same folder, then stop it with `New-Item STOP` (or Ctrl+C).
4. To run it at every log-on without a window, create a Task Scheduler task with an **At log on** trigger and this action:
   ```
   wscript.exe "C:\path\to\sync-guard\launch-hidden.vbs"
   ```
   or from PowerShell:
   ```powershell
   $vbs = Join-Path (Resolve-Path .) 'launch-hidden.vbs'
   Register-ScheduledTask -TaskName SyncGuard -Trigger (New-ScheduledTaskTrigger -AtLogOn) `
     -Action (New-ScheduledTaskAction -Execute wscript.exe -Argument "`"$vbs`"")
   ```

It does not need administrator rights for processes that run as your own user, which is how all three clients run.

## Configuration

`syncguard.json` next to the script (or `-Config <path>`). If the file is missing, the built-in defaults below are used, which are the same as `syncguard.example.json`:

```json
{
  "intervalSec": 20,
  "kill": ["iCloudPhotos", "ApplePhotoStreams"],
  "throttle": [
    { "procs": ["GoogleDriveFS"], "affinity": "0x3", "priority": "Idle" },
    { "procs": ["OneDrive", "OneDrive.Sync.Service"], "affinity": "0x7", "priority": "BelowNormal" }
  ]
}
```

| Key | Meaning |
|---|---|
| `intervalSec` | Seconds between passes. |
| `kill` | Process names (without `.exe`) that are force-closed every pass. **Set to `[]` if you use iCloud Photos.** |
| `throttle[].procs` | Process names to throttle. |
| `throttle[].affinity` | CPU bit mask as a hex string or number. `0x3` = logical processors 0 and 1, `0x7` = 0-2. |
| `throttle[].priority` | `Idle`, `BelowNormal`, `Normal`, `AboveNormal`, `High`. |

To find a process name: `Get-Process | Sort-Object CPU -Descending | Select-Object -First 15 Name, CPU`.

## How it works

- Each pass: `Get-Process <name>` for every name on both lists. Kill-list processes are stopped with `Stop-Process -Force` and logged with the CPU seconds they had used.
- Throttle-list processes get `PriorityClass` and `ProcessorAffinity` set, **once per process ID**. The script remembers the IDs it has handled and forgets IDs that have exited, so a restarted client is throttled again on the next pass.
- On `STOP`: every process on the throttle list gets affinity = all logical processors and priority `Normal`, the `STOP` file is deleted, and the script exits.
- `guard.log` is cleared when it grows past 300 KB at start-up.

## Limitations

- **Restoring happens only through `STOP`.** If you end the script any other way, already-throttled processes stay throttled until they restart (or until you sign out).
- **Throttled processes are slower on purpose.** A large first-time sync takes longer. If you need a sync to finish quickly, `New-Item STOP` and start the guard again later.
- **The kill list is blunt.** It does not ask and does not check what the process is doing.
- Affinity masks above 64 logical processors (multiple processor groups) are not handled.
- Process names are the ones these clients used in October 2026; vendors rename them occasionally. Check `guard.log` to see whether anything is being matched.
- Windows only.

## License

MIT, see [LICENSE](LICENSE).
