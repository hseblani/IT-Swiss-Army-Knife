# Agent Guide

## Project purpose

IT Swiss-Army Knife is a Windows desktop administration toolkit implemented in PowerShell. Its main WPF/WinForms launcher discovers manifest-described scripts under `modules/`, generates parameter controls from each `module.json`, and runs the selected module in an asynchronous PowerShell runspace. A separate GUI, `ModulesManager.ps1`, edits the module catalog and moves module/category folders.

This description is based on the current source tree. There is no authoritative README, package manifest, or automated test suite in this directory.

## Source of truth

- Treat `IT-SwissArmyKnife-v2.6.ps1`, `ModulesManager.ps1`, `modules/categories.json`, each active `modules/**/module.json`, and the associated scripts as the source of truth.
- Do not infer behavior from filenames, labels, descriptions, comments, backup copies, or the `test/` directory alone. Trace the invoked code.
- `IT-SwissArmyKnife-v2.6 - Backup.ps1`, `IT-SwissArmyKnife-v2.6 - Copy.ps1`, and `ModulesManager - Backup.ps1` have different hashes from their primary counterparts. They are snapshots, not verified current entry points.
- `modules/_deleted/` is excluded by both GUIs and is a soft-delete store. Do not treat its contents as active modules.
- `test/` is a standalone WIM/ESD conversion script and manifest, not a discovered automated test suite.
- This directory was not a Git worktree when inspected on 2026-10-07: Git commands returned `fatal: not a git repository`. **Unknown / needs verification:** whether version-control metadata exists elsewhere.

## Architectural constraints

- The batch entry points use Windows `powershell.exe`, `-STA`, `-ExecutionPolicy Bypass`, and elevation through `RunAs`. The main script also self-elevates.
- The desktop UI depends on WPF and WinForms assemblies and Windows-only management cmdlets/utilities.
- The launcher discovers `module.json` recursively under `modules/`, excluding paths containing `_deleted`, `_disabled`, or `_shared`.
- A missing manifest `RunPath` defaults to `run.ps1`. Module order comes from each manifest; category order comes from `modules/categories.json`.
- The runtime module object currently contains only `Name`, `Category`, `Order`, `Params`, and resolved `RunPath`. Manifest `Shell`, `requiresAdmin`, `required`, `visibleWhen`, and `enabledWhen` are not enforced by the launcher.
- Modules execute in a new runspace created by the already-running host, not in a shell selected from manifest metadata.
- UI-to-script parameter binding is name-based. Renaming a manifest parameter without changing the script parameter, dependency references, and population arguments breaks the module contract.
- `__MODULE_ROOT__`, `__MODULE_OUTPUT__`, and `__MODULE_LOGS__` defaults are resolved by the launcher. Preserve this contract.
- Progress recognized by the GUI is an Information-stream message exactly matching `PROGRESS:<0-100>`.
- Dynamic dropdown scripts are resolved relative to the module directory. Preserve their relative paths and output format.
- The manager writes JSON, creates/renames/moves folders, and soft-deletes into `modules/_deleted/`; changes are not purely in-memory.

## High-risk areas

Do not change these casually:

- Disk initialization, partition creation/deletion/formatting, drive-letter changes, volume resize, cleanup, and offline Windows deployment.
- Local-account and offline-SAM operations.
- Registry, firewall, services, scheduled tasks, Windows Update, drivers, DISM, SFC, CHKDSK, and boot-file operations.
- Module-manager move, delete, overwrite, restore, and save workflows.
- Argument construction and password handling in `Execute-CommandAsync`.
- The Stop handler stops and disposes the active PowerShell pipeline but does not track native child PIDs. Native tools may survive cancellation; never add global termination by executable name because unrelated system processes may exist.

Use disposable test machines or VMs and expendable disks/images for destructive workflows. Never run them merely to establish coverage.

## Required workflow before modifying code

1. Inventory the current files and inspect Git status. If Git reports that this is not a repository, record that fact instead of assuming a clean tree.
2. Read the primary entry point and the exact manifest/script/helper chain affected by the change.
3. For manifest changes, verify category, order, `RunPath`, parameter names/types/defaults, dynamic script paths, and script parameter compatibility.
4. Parse all JSON and PowerShell files statically before runtime testing.
5. Identify whether the change can alter disks, boot configuration, accounts, credentials, registry, firewall, drivers, updates, services, or user data; design a contained manual test if so.
6. Preserve unrelated files and existing behavior. Do not use the backup/copy scripts as automatic replacement sources.
7. Inspect the final diff and report any validation that could not be performed.

## Testing expectations

- There is no detected Pester suite or test runner. Do not say “tests passed” unless a real command was run successfully and state exactly what it covered.
- At minimum, run the static PowerShell parser over all `.ps1` files, parse every `.json`, verify active `RunPath` targets, and validate dynamic `populateScript` references.
- The current baseline is not clean: `modules/Drivers/Driver Inventory and Age Report/run.ps1` has a parser error at line 74.
- GUI smoke tests require interactive Windows, STA, the relevant PowerShell/.NET assemblies, and usually administrator access.
- Operational module tests must be risk-based. Read-only modules can be smoke-tested on an appropriate Windows host; mutating modules require a disposable environment and explicit test data.
- See `docs/TESTING.md` for concrete static commands and a manual matrix.

## Documentation expectations

Update documentation when architecture, entry points, module inventory/schema, launch behavior, external dependencies, test procedures, or known limitations change. Keep these distinctions explicit:

- present in source and statically validated;
- exercised successfully in this environment;
- partial or inconsistent implementation;
- excluded/legacy code;
- **Unknown / needs verification**.

Never convert a UI label, comment, manifest description, or dormant file into a claim of working behavior without tracing and, where safe, exercising the actual path.

## Current repository-specific cautions

- One active module currently fails PowerShell parsing: `modules/Drivers/Driver Inventory and Age Report/run.ps1` line 74.
- The launcher does not place manifest `Description` on its runtime module object, although the UI reads `$m.Description`; selected-module descriptions are therefore expected to be blank from this code path.
- Manifest type `select` has no dedicated renderer and falls through to a text box; two Convert WIM/ESD parameters use it.
- `required`, `visibleWhen`, and `enabledWhen` metadata are present but not consumed by the launcher.
- Ten active manifests omit `Shell`; 37 omit `requiresAdmin`. The launcher ignores both fields and globally elevates.
- Storage orders contain a duplicate: Disk Cleanup and Disk Health & SMART Status both use order 8.
- The manifest schema varies in casing and optional fields. PowerShell property lookup is case-insensitive, but other tools may not be.
- The manager can rewrite JSON formatting/property order and can move whole directories. Review its proposed scope before using Save, Move, Delete, Restore, or overwrite options.
- Output and debug files may be written under module folders or `%TEMP%`; check for generated artifacts after manual runs.
