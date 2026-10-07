# Technical Debt

This register is limited to concerns visible in the current repository. It describes debt; it does not authorize fixes.

## Critical and high-risk concerns

### Active module has a parser error

`modules/Drivers/Driver Inventory and Age Report/run.ps1` fails static parsing at line 74 with “Missing argument in parameter list.” The active manifest and run path are otherwise discoverable, so the launcher can present a module that cannot parse when invoked.

### Stop is process-global

The main Stop handler disposes its runspace and then force-stops every process named `ping`, `sfc`, `dism`, or `chkdsk`. It does not retain child process IDs. On an elevated administration workstation this can terminate unrelated maintenance work.

### Arguments and passwords are composed as source text

`Execute-CommandAsync` serializes UI values into a command-line-like string embedded in a generated PowerShell script passed to `AddScript`. Double quotes are doubled, but this is not equivalent to typed parameter binding for every PowerShell input. Password box contents are materialized as plain text in generated script text. Edge-case quoting, injection resistance, and memory exposure are **Unknown / needs verification**.

### Destructive operations share the general module path

Read-only inventory and destructive disk/account/registry/deployment actions use the same discovery, rendering, and execution pipeline. Safety relies primarily on individual scripts, defaults, checkboxes, and confirmations. Manifest `required` and `requiresAdmin` are not enforced centrally.

## Manifest/runtime contract drift

- The launcher drops `Description`, `Shell`, and `requiresAdmin` while building runtime module objects.
- `required`, `visibleWhen`, and `enabledWhen` appear in manifests but have no launcher consumers.
- `select` appears twice but has no renderer, so it becomes a free-text control and loses its options.
- Ten active manifests omit `Shell`, 37 omit `requiresAdmin`, and two omit `Id`.
- Property casing and parameter shapes vary widely. There is no JSON Schema or validation layer.
- The Global Report Aggregator manifest references missing `_shared/populate_available_data.ps1`; its current specialized multi-select implementation bypasses the generic provider mechanism.
- Storage has duplicate order 8 and no order 9. Sorting remains deterministic by name for the tie, but ordering data is inconsistent.
- The launcher has `Get-CategoryOrder` code reading `Order`, while current category entries use `CategoryOrder`; another code path handles the actual tree correctly.

## Shell and privilege ambiguity

The batch launcher and self-elevation path use Windows `powershell.exe`, and module code runs in an in-process runspace. The catalog nevertheless declares `Pwsh` for 42 modules and `WindowsPowerShell` for one. Because `Shell` is ignored, compatibility assumptions expressed by manifests are not honored.

The main application elevates globally even for read-only modules, while per-manifest `requiresAdmin` is sparse and ignored. Some scripts repeat their own admin checks and others rely on the host. The least-privilege boundary is therefore coarse and inconsistent.

## Weak error handling and observability

- `Get-ToolkitModules` silently swallows manifest load failures.
- Many scripts use broad `catch {}` or `-ErrorAction SilentlyContinue`, so missing data can be indistinguishable from a healthy empty result.
- Error conventions vary among exceptions, exit codes, `Write-Error`, `Write-Output`, `Write-Host`, and prefixed strings.
- The generated execution wrapper sets `$ErrorActionPreference = 'Continue'`, even when a module sets stricter behavior internally.
- Fixed-name `%TEMP%` logs such as `populate_disks_DEBUG.log`, `populate_max_size_DEBUG.log`, and `populate_volumes_DEBUG.log` can combine sessions and are not tied to a run ID.
- Some progress messages use `PROGRESS:n`, others `[PROGRESS:n]`, and some use host/output streams; only the exact Information-stream protocol updates the GUI progress bar.

## Manager consistency and partial-update risk

The module manager combines UI state, cache state, JSON writes, folder creation, copy/move operations, category renames, and soft deletion in one large script. These operations are not transactional. A filesystem operation can succeed while the following JSON write fails, or vice versa. Code reports several such failures, but there is no rollback journal.

Saving rewrites JSON with `ConvertTo-Json` and can change formatting/property order. Description loading prefers an `InfoNote` parameter while saving updates the top-level `Description`, creating two possible description sources. Delete/restore naming encodes category and module names into folder names; conflict and sanitization edge cases require manual verification.

## Duplication and large-script maintainability

- Three divergent launcher scripts and two divergent manager scripts are stored at the root with no documented version policy.
- `IT-SwissArmyKnife-v2.6.ps1` and `ModulesManager.ps1` both contain category-folder sanitization/rename logic.
- Module scripts repeatedly implement admin checks, progress wrappers, boolean conversion, output formatting, dropdown-value parsing, external-process invocation, and WhatIf handling instead of consistently using shared helpers.
- The largest active files include `WindowsOfflineDeploy/functions.ps1` (625 lines), Copy Data (569), Startup Programs Manager (565), Disk Health (537), Collect Support Bundle (536), and the 2,826-line manager. UI, state management, persistence, and filesystem mutations are tightly coupled.
- `common.ps1` is optional and only some modules source it, leaving multiple competing conventions.

## Hard-coded values and external-service risk

- Network Speed Test hard-codes Cloudflare endpoints and fixed 10/50/100 MB payloads.
- Network Summary hard-codes the ipify public-IP endpoint and an eight-second timeout.
- The Stop handler hard-codes a four-process name list.
- UI dimensions, colors, output prefix matching, timeout defaults, protected account names, registry paths, service names, and native utility paths are embedded in scripts.
- The offline-deployment workflow contains fixed drive-letter assumptions in BCDBoot-related code.

Endpoint availability, terms, proxy behavior, TLS compatibility, and privacy expectations are **Unknown / needs verification**.

## Testing and release debt

- No Pester suite, test runner, CI configuration, dependency lock, or package/build definition was found.
- `test/` contains a real DISM conversion script, not assertions, and risks being mistaken for a safe test.
- There is no automated regression coverage for the launcher, manager, manifest renderer, parameter binding, cancellation, filesystem transactions, or any module.
- There is no compatibility matrix for Windows editions, PowerShell versions, locales, privilege levels, or policy restrictions.
- No formal release metadata exists beyond `v2.6` in filenames. The current root snapshots have different hashes.
- The current directory is not a Git worktree, preventing normal diff/status/history-based provenance checks.

## Security and data-handling concerns requiring verification

- Password values are strings at module boundaries and may be included in command/process arguments or generated unattended configuration.
- Support bundles, reports, event logs, network data, user information, registry exports, minidumps, and Wi-Fi credentials can contain sensitive information.
- The WiFi Password Viewer and support/export modules need explicit handling guidance for storage, disclosure, and cleanup; none is present in repository documentation or policy files.
- Scripts run with execution-policy bypass and frequently with administrator rights; signing and application-control expectations are absent.
- HTML report construction encodes some values but not every interpolated fragment uniformly. Full output-safety review is **Unknown / needs verification**.

## Legacy and dead-code indicators

- Backup/copy scripts are not referenced by launchers and differ from primaries.
- Two IP Scanner versions remain in `_deleted`.
- Launcher functions related to category rename reference manager-style state and are not part of the normal launcher's visible module-execution workflow; actual reachability is **Unknown / needs verification**.
- No explicit actionable TODO/FIXME list exists. Comments such as “placeholder” refer to live UI placeholder behavior, so planned work cannot be inferred from them.

## Documentation and governance gaps

Before this documentation set, the current tree contained no README, support matrix, license, change log, manifest specification, security guidance, contributor workflow, or release procedure. Ownership, distribution method, production usage, supported targets, credential policy, and recovery expectations are all **Unknown / needs verification**.

