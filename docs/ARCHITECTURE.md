# Architecture

## Scope and platform

The project is a file-based, Windows-only PowerShell desktop toolkit. It has two independent GUI applications:

1. `IT-SwissArmyKnife-v2.6.ps1` discovers and executes administration modules.
2. `ModulesManager.ps1` organizes and edits the module catalog.

Both provided `.bat` launchers start Windows PowerShell in STA mode with execution-policy bypass and request elevation. There is no build system, installer, package manifest, database, web server, or long-running service in the current tree.

Runtime compatibility beyond the Windows environment implied by the scripts is **Unknown / needs verification**. In particular, many manifests say `Pwsh`, but the launcher runs under `powershell.exe` and does not consume the `Shell` field.

## Top-level structure

| Path | Verified role |
|---|---|
| `RUN-IT-SwissArmyKnife.bat` | Elevated STA launcher for `IT-SwissArmyKnife-v2.6.ps1`. |
| `IT-SwissArmyKnife-v2.6.ps1` | Primary catalog UI, generated parameter UI, asynchronous module execution, output console, progress, and Stop behavior. |
| `RUN-ModulesManager.bat` | Elevated STA launcher for `ModulesManager.ps1`. |
| `ModulesManager.ps1` | Catalog editor for categories, module metadata/order, imports, folder moves, soft deletion, and restoration. |
| `modules/categories.json` | Ordered category registry. |
| `modules/<Category>/<Module>/module.json` | Module manifest consumed by both GUIs. |
| `modules/<Category>/<Module>/run.ps1` | Normal module entry point; one deployment module also uses `functions.ps1`. |
| `modules/_shared/*.ps1` | Shared report/progress helpers and dynamic-dropdown data providers. |
| `modules/_deleted/` | Timestamped soft-deleted module/category storage excluded from active discovery. |
| `pics/techputno-1_white.png` | Logo loaded by both GUIs when present. |
| `test/` | Standalone conversion script/manifest; no discovered test-runner integration. |
| `* - Backup.ps1`, `* - Copy.ps1` | Divergent snapshots; not referenced by provided launchers. |

## Main application

### Initialization and UI

`IT-SwissArmyKnife-v2.6.ps1` loads WPF, WinForms, drawing, and WindowsFormsIntegration assemblies. It self-elevates if necessary, derives `modules/` and `pics/` from its own directory, builds a WPF window from inline XAML, and embeds a WinForms `RichTextBox`. An inline C# `PowerShellConsole` class appends colored output to that control.

The crash trap writes `IT-Toolkit-CRASH-<timestamp>.log` under `%TEMP%`.

### Discovery and catalog ordering

`Get-ToolkitModules` recursively reads `module.json` under `modules/` and excludes paths matching `_deleted`, `_disabled`, or `_shared`. Invalid manifests are silently skipped by an empty `catch`. It produces runtime objects containing:

- `Name`
- `Category`
- integer `Order`
- `Params`
- resolved `RunPath`

The tree groups by category. Category display order comes from `CategoryOrder` in `modules/categories.json`; module display order comes from `Order`, then `Name`. Categories marked `IsEmpty: true` would be hidden, although no current category entry has that field.

### Manifest-to-control rendering

`Render-ModuleUI` maps manifest parameters as follows:

| Manifest type | UI/runtime behavior |
|---|---|
| `info` | Read-only text block; not passed to the module. |
| `separator` | Visual heading/rule; not passed. |
| `checkbox` | Custom toggle backed by a hidden WPF checkbox; passed as `$true`/`$false`. |
| `password` | WPF password box; value is inserted into the generated invocation text. |
| `multi-select` | Button with a specialized SupportBundle JSON selection workflow. |
| `dropdown` | Static combo box or dynamically populated combo box. |
| `drive`, `folder`, `file` | Text box plus an appropriate picker. |
| any other/missing type | Plain text box. Current `select` entries therefore use this fallback. |

Checkbox `disables` relationships are enforced. `inline` affects layout. Token defaults `__MODULE_ROOT__`, `__MODULE_OUTPUT__`, and `__MODULE_LOGS__` resolve relative to the selected module directory.

The renderer does not consume `required`, `visibleWhen`, or `enabledWhen`. The loader does not carry `Description`, `Shell`, or `requiresAdmin` into runtime module objects.

### Dynamic dropdown flow

For a dynamic `dropdown`, `Populate-DynamicDropdown` resolves `populateScript` relative to the module folder, gathers named `populateArgs` from controls already registered in `$script:InputControls`, executes the helper synchronously, and treats each non-empty output line as an option.

Verified shared providers enumerate adapters, disks, partitions, volumes, available disk size, and online/offline local users. `modules/_shared/common.ps1` supplies progress, admin detection, JSON reading, hardware collection, and HTML report generation.

The Global Report Aggregator's `multi-select` control is special-cased in the main launcher and scans SupportBundle folders directly. Its manifest also names a missing `populate_available_data.ps1`; that generic reference is not used by the specialized `multi-select` branch. Runtime behavior remains **Unknown / needs verification**.

### Execution and output flow

```text
module.json
  -> recursive discovery and ordering
  -> generated parameter controls
  -> string-form argument list
  -> generated PowerShell script text
  -> new in-process PowerShell runspace / BeginInvoke
  -> module run.ps1
  -> output, Information, Warning, Error, Verbose, Debug streams
  -> 100 ms dispatcher polling
  -> colored embedded console and progress bar
```

The launcher builds a script string containing the module path and every current control value, then calls `AddScript` and `BeginInvoke`. It does not start `pwsh.exe` or `powershell.exe` per module. The `Shell` manifest field therefore has no runtime selection effect.

`Process-AllStreams` recognizes Information messages exactly matching `PROGRESS:<integer>` and updates the progress bar. Other records are colorized by stream, host foreground color, or line prefix.

The Stop button calls `PowerShell.Stop()`, disposes the runspace, and force-stops all processes named `ping`, `sfc`, `dism`, or `chkdsk`. It does not track only the selected module's child process.

## Module manager

`ModulesManager.ps1` is a separate WPF application. It starts with no module path selected. The user selects a folder; the manager then:

1. Reads `categories.json` and creates in-memory category entries, including empty configured categories.
2. Recursively loads `module.json`, excluding `_deleted`.
3. Caches parsed JSON and maintains category/module sort and dirty-state maps.
4. Presents category and module details for editing and ordering.
5. Persists selected/all changes back to `categories.json` and `module.json`.

It can import a folder containing `run.ps1`, create category folders, rename categories, move module folders between categories, and normalize order values. Delete moves a folder to `modules/_deleted/` using timestamped names. Restore recognizes those generated category/module names and supports conflict actions including rename, choose category, and overwrite (where the replaced folder is itself moved to `_deleted`).

The manager uses an inline C# COM declaration for a modern folder picker and falls back to `Shell.Application`.

## Module domains

The active catalog has 53 manifests in nine categories:

- Connectivity: ping, DNS, route tracing, adapter operations, ports, network summary/speed, and Wi-Fi profiles.
- Maintenance: CHKDSK, SFC, DISM, cleanup, registry changes/backup, and Windows Update management.
- Storage: disk/partition/volume operations, health, cleanup, space, tree reporting, and data copy.
- Identity: local-user create/delete/enable/disable/password operations, including offline paths.
- Deployment: WIM/ESD inspection/conversion and offline Windows deployment.
- Diagnostics: power reports, services, and event logs.
- Asset Management: system/uptime reports, support bundles, baselines, and aggregate reports.
- Drivers: inventory, import, and export.
- Security: firewall, startup, and network/security audit workflows.

Presence in the catalog confirms discoverable source, not successful operation on a real machine.

## Data and persistence

There is no database. Persistent inputs and outputs are files:

- JSON manifests and `categories.json` define the catalog.
- Many reporting modules write JSON, CSV, HTML, EVTX, ZIP, or text outputs to user-selected paths or a module-local `output/` default.
- `__MODULE_LOGS__` maps to a module-local `logs/` path when used.
- Shared disk/volume population scripts write fixed-name debug logs in `%TEMP%`.
- The main application writes crash logs in `%TEMP%`.
- The manager changes module JSON and directory layout directly.
- Identity/deployment/registry modules may load offline registry hives temporarily.

Exact output sets and cleanup behavior for every module are **Unknown / needs verification** because operational modules were not executed during documentation work.

## External dependencies and integrations

Verified code dependencies include:

- Windows PowerShell, WPF, WinForms, System.Drawing, WindowsFormsIntegration, COM folder selection, and inline C# compilation.
- Windows management cmdlets for Storage, NetTCPIP/NetAdapter, Firewall, Defender, CIM/WMI, local users/groups, services, scheduled tasks, event logs, updates, and Windows images.
- Native Windows utilities including DISM, SFC, CHKDSK, DiskPart, BCDBoot, `reg.exe`, `net.exe`, `netsh.exe`, `pnputil.exe`, `powercfg.exe`, `wevtutil.exe`, `robocopy.exe`, `ping.exe`, and `tracert.exe`.
- Cloudflare speed-test download/upload endpoints in Network Speed Test.
- `api.ipify.org` in Network Summary.

No third-party PowerShell module is explicitly installed by the repository. Availability across Windows editions and PowerShell versions is **Unknown / needs verification**.

## Architectural boundaries

- The launcher owns discovery, generated UI, execution orchestration, cancellation, and stream presentation; operational logic belongs in module folders.
- Manifests are the contract between launcher/manager and scripts, but no formal JSON schema is present.
- Shared scripts are sourced or executed by modules; there is no packaged PowerShell module boundary.
- The manager is an authoring tool and is not called by the runtime launcher.
- Soft-deleted and backup files are retained in the distribution but excluded from normal runtime entry points.

