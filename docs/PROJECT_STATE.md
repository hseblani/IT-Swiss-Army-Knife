# Project State

## Basis and confidence

This document records what is visible in the current directory and what was established with non-executing static checks on 2026-10-07. No GUI or operational module was run. “Implemented” below means the code path and its files exist and passed the stated structural checks; it does not mean the workflow succeeded on a real Windows system.

The directory is not recognized by Git. `git status --short`, `git rev-parse --show-toplevel`, and related commands returned `fatal: not a git repository`.

## Verified inventory

- 69 PowerShell files and 57 JSON files in the full tree.
- 53 active module manifests under `modules/`, excluding `_deleted`.
- 9 categories in `modules/categories.json`.
- 7 shared scripts under `modules/_shared/`.
- 2 soft-deleted IP Scanner copies under `modules/_deleted/`.
- 2 batch entry points, 1 logo asset, and 5 divergent primary/backup/copy root PowerShell scripts.
- All 57 JSON files parse with `ConvertFrom-Json`.
- Every active manifest resolves to an existing run script, using `run.ps1` as the fallback where `RunPath` is absent.
- One active PowerShell file does not parse; see Known broken/inconsistent areas.

## Active catalog

| Category | Count | Manifest-declared modules |
|---|---:|---|
| Connectivity | 9 | Ping Test Simple; Ping Test Advanced; Net Summary; DNS Resolve; Network Adapter Manager; Trace Route; Port Scanner; Network Speed Test; WiFi Password Viewer |
| Maintenance | 7 | Check Disk (CHKDSK); System File Checker (SFC); DISM (Repairs Windows images); Clean Disk; Common Registry Tweaks; Registry Backup/Restore; Windows Update Manager |
| Storage | 11 | Create Partition; Delete Partition; Format Partition; Initialize Disk; Drive Letters Manager; Shrink/Extend Volumes; Disk Space; Disk Cleanup; Disk Health & SMART Status; Folder Tree Analyzer; Copy Data |
| Identity | 4 | Remove Password; Enable/Disable User; Delete User; Create User |
| Deployment | 3 | WIM/ESD Info (List Editions/Indexes); Deploy Windows to Offline Disk; Convert WIM/ESD |
| Diagnostics | 3 | Power and Sleep Reports; Service Lookup; Event Log Viewer |
| Asset Management | 5 | Collect Support Bundle; Global Report Aggregator; System Baseline Snapshot + Compare; System Info (Computer + OS); Uptime |
| Drivers | 3 | Export Drivers; Import Drivers; Driver Inventory and Age Report |
| Security | 8 | List/Add/Remove/Enable/Disable Firewall Rule; Network & Security Auditor; Startup Analyzer (Safe); Startup Programs Manager |

## Implemented and statically verified structure

- The main launcher has elevation, WPF/WinForms UI construction, catalog discovery, search/reload, manifest-generated controls, asynchronous runspace execution, output coloring, progress handling, Clear, and Stop code paths.
- The manager has folder selection, category/module loading, editing, sorting, JSON persistence, module import, category/module moves, soft deletion, restoration, conflict handling, and unsaved-change prompts.
- Static and dynamic dropdown infrastructure is present. Six of the seven shared scripts provide common reporting or population behavior; all referenced generic dropdown providers except one exist.
- Shared report code can build encoded tables/key-value/tree HTML and collect a hardware tree.
- Modules contain code for all catalog domains listed above.
- The main launcher excludes `_deleted`, `_disabled`, and `_shared`; the manager excludes `_deleted`.
- Backup/copy scripts are not invoked by either provided batch file.

## Partially implemented or inconsistent behavior

- Manifest metadata is richer than the launcher contract. `Shell`, `requiresAdmin`, `required`, `visibleWhen`, and `enabledWhen` are not enforced. `Description` is not copied into runtime module objects although the UI attempts to display it.
- Two parameters use manifest type `select`, but the renderer has no `select` branch. They are rendered by the text fallback, so their option lists are not presented as selection controls.
- The Global Report Aggregator manifest references missing `_shared/populate_available_data.ps1`. The main launcher separately hard-codes the multi-select SupportBundle scan, so impact is path-dependent.
- Progress conventions are inconsistent. The GUI recognizes Information-stream `PROGRESS:n`; several modules emit bracketed output such as `[PROGRESS:n]`, which is display text rather than the recognized progress protocol.
- `Shell` is present on 43 of 53 active manifests (42 `Pwsh`, 1 `WindowsPowerShell`) and absent on 10. The runtime does not use it.
- `requiresAdmin` is present on only 16 manifests and absent on 37. Regardless, the normal launcher elevates the entire application.
- Manifest IDs are absent from two active manifests. The runtime launcher does not use IDs.
- Parameter objects use many different property shapes and casing conventions. PowerShell tolerates case differences; interoperability with stricter tooling is **Unknown / needs verification**.

## Known broken or suspicious areas

- `modules/Drivers/Driver Inventory and Age Report/run.ps1` has a parser error at line 74: `Sort-Object IsOld -Descending, Provider, DeviceName` is parsed as a missing argument. That active module cannot be considered runnable in its current form.
- `modules/Asset Management/Global Report Aggregator/module.json` names a dynamic provider that does not exist: `modules/_shared/populate_available_data.ps1`.
- Storage order 8 is assigned to both Disk Cleanup and Disk Health & SMART Status. Sorting falls back to name for the tie.
- `Get-CategoryOrder` reads `Order` even though current category configuration uses `CategoryOrder`; the displayed tree uses a separate code path that reads `CategoryOrder` correctly.
- The launcher manifest loader swallows all manifest exceptions without reporting which file failed.
- The Stop handler stops and disposes the active PowerShell pipeline but does not track native child processes; native tools may survive cancellation.
- The launcher constructs invocation source text from UI values. Embedded passwords become plain text in that generated script and quoting is fragile for unusual input.
- The three launcher versions and two manager versions all have distinct hashes. Their intended retention/versioning policy is **Unknown / needs verification**.

## Legacy, excluded, or non-test material

- `modules/_deleted/` contains two timestamped IP Scanner copies. They are excluded from active discovery and should be treated as soft-deleted history.
- The `- Backup` and `- Copy` root scripts are divergent snapshots with no active launcher reference.
- `test/module.json` describes category `545454545`, and `test/run.ps1` performs a real DISM WIM/ESD export. No assertion framework or test runner invokes it. It is not evidence of automated test coverage.
- No actionable TODO/FIXME markers were found. The word “placeholder” appears in live loading/empty-value handling, not as an explicit roadmap item.

## Operational dependencies and limitations

- Normal launch requires interactive Windows, WPF/WinForms-capable Windows PowerShell, STA, and acceptance of UAC elevation.
- Many modules require administrator rights and Windows-only management cmdlets/utilities.
- Network Summary contacts `api.ipify.org`; Network Speed Test contacts Cloudflare speed-test endpoints. Network access, endpoint behavior, and privacy requirements are environment-dependent.
- Offline deployment requires Windows images and expendable target disks and can alter partition tables and boot files.
- Reporting and export modules need writable destination paths; some defaults point beneath module folders.
- The manager needs write/move access to the selected module tree.

## Runtime verification status

The following are **Unknown / needs verification**:

- Whether either GUI opens successfully on supported target machines.
- Which Windows and Windows PowerShell versions are supported.
- Runtime success of every module, including read-only modules.
- Safety and rollback behavior of disk, account, registry, firewall, driver, update, cleanup, and deployment operations.
- Correctness of manager save/move/delete/restore behavior under conflicts, locks, and partial failures.
- Encoding/layout of generated reports and console output on target systems.
- Whether antivirus/application-control policy permits execution-policy bypass, inline C# compilation, and unsigned scripts.
- Whether this directory is meant to be nested inside a Git repository located elsewhere.
