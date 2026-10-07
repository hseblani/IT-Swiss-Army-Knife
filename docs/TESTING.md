# Testing

## Current test structure

No automated test framework or runner was found. Searches found no Pester `Describe`/`It`/`Should` suite and no `Invoke-Pester` entry point. There is no CI configuration in the current tree.

The `test/` directory is not an automated test suite:

- `test/module.json` is a module-style manifest with name `test`, category `545454545`, shell `Pwsh`, and no parameters.
- `test/run.ps1` performs an actual DISM WIM/ESD export after validating paths. Running it can create a large image file and requires a suitable Windows image and DISM environment.
- Nothing in the launcher discovers `test/`, because discovery is rooted at `modules/`.

Do not treat that directory as test coverage or run it as a harmless test.

## Validation performed for this documentation

The following non-operational checks were run on 2026-10-07:

| Check | Result |
|---|---|
| Inventory all files with `rg --files -uu` | 69 `.ps1`, 57 `.json`, 53 active manifests, 7 shared scripts, 2 deleted manifests. |
| Parse every `.json` with `ConvertFrom-Json` | All 57 parsed successfully. |
| Parse every `.ps1` with `System.Management.Automation.Language.Parser.ParseFile` | Failed for one active file: `modules/Drivers/Driver Inventory and Age Report/run.ps1`, line 74, “Missing argument in parameter list.” No other parser errors were reported. |
| Resolve each active manifest's `RunPath`, defaulting to `run.ps1` | All 53 targets exist. |
| Resolve dynamic `populateScript` paths | All 16 remaining references resolve. |
| Compare category/order pairs | Duplicate Storage order 8 found. No active module referenced an unknown configured category. |
| Search for a Pester suite | None found. |
| Inspect Git state | Git reported that the current directory is not a repository. |

No GUI, module, native administrative utility, network endpoint, or mutating workflow was executed. Therefore no runtime tests passed during this task.

## Reproducible static checks

Run from the project root in PowerShell. These commands inspect code; they do not invoke module entry points.

### Parse PowerShell

```powershell
$root = (Get-Location).Path
Get-ChildItem -Recurse -File -Filter *.ps1 | ForEach-Object {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $_.FullName,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null
    foreach ($error in @($errors)) {
        [pscustomobject]@{
            File    = $_.FullName.Substring($root.Length + 1)
            Line    = $error.Extent.StartLineNumber
            Message = $error.Message
        }
    }
}
```

Expected current baseline: one error in Driver Inventory and Age Report at line 74. A clean result should only be expected after a separately authorized source change.

### Parse JSON

```powershell
Get-ChildItem -Recurse -File -Filter *.json | ForEach-Object {
    try {
        Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json | Out-Null
    }
    catch {
        [pscustomobject]@{ File = $_.FullName; Error = $_.Exception.Message }
    }
}
```

No output means no parse errors. This checks JSON syntax, not schema or runtime compatibility.

### Validate active run paths

```powershell
Get-ChildItem modules -Recurse -Filter module.json |
    Where-Object { $_.FullName -notmatch '\\_deleted\\' } |
    ForEach-Object {
        $manifest = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
        $runPath = if ($manifest.RunPath) { $manifest.RunPath } else { 'run.ps1' }
        if (-not (Test-Path -LiteralPath (Join-Path $_.DirectoryName $runPath))) {
            [pscustomobject]@{ Manifest = $_.FullName; MissingRunPath = $runPath }
        }
    }
```

### Validate dynamic population scripts

```powershell
Get-ChildItem modules -Recurse -Filter module.json |
    Where-Object { $_.FullName -notmatch '\\_deleted\\' } |
    ForEach-Object {
        $file = $_
        $manifest = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        foreach ($parameter in @($manifest.Params)) {
            if ($parameter.dynamic -or $parameter.populateScript) {
                [pscustomobject]@{
                    Module = $manifest.Name
                    Parameter = $parameter.Name
                    Script = $parameter.populateScript
                    Exists = Test-Path -LiteralPath (Join-Path $file.DirectoryName $parameter.populateScript)
                }
            }
        }
    }
```

## Manual test requirements

### Environment

- Interactive Windows desktop with Windows PowerShell and WPF/WinForms.
- STA host and administrator credentials/UAC approval for the normal launch path.
- Required Windows cmdlets and native utilities for the feature under test.
- Internet connectivity only for features that explicitly require it.
- Writable temporary and output locations.
- A VM snapshot or other rollback mechanism for mutating tests.

Exact supported OS editions/builds and PowerShell versions are **Unknown / needs verification**.

### Suggested risk tiers

1. Static-only: parser, JSON, paths, manifest/schema consistency, duplicate IDs/orders, and helper references.
2. UI smoke: launch both GUIs; verify discovery count, tree ordering, search, parameter rendering, reload, output Clear, and closing behavior without running a module.
3. Read-only modules: use System Info, Uptime, Disk Space, Service Lookup, DNS, or similar inventory actions on a non-production machine. Confirm argument binding, output streams, progress, and exports.
4. Controlled mutation: firewall, registry, startup, accounts, driver import, Windows Update, and cleanup need a disposable VM plus before/after assertions and rollback.
5. Destructive storage/deployment: use only expendable virtual disks and images. Verify target selection, dry-run/WhatIf behavior where actually implemented, cancellation, partitioning, image application, boot creation, and recovery from failure.

Manifest defaults must not be assumed safe. Inspect the target script before each test; not every module exposes or honors a dry-run option.

### GUI checks

- Confirm the main UI requests elevation and loads exactly the expected active manifests.
- Verify excluded `_deleted` content does not appear.
- Check every supported control type, especially dynamic dropdown dependencies, passwords, file/folder/drive browsing, multi-select, and checkbox `disables` rules.
- Verify required inputs manually because `required` is not enforced by the launcher.
- Confirm `select` parameters in Convert WIM/ESD; current static analysis predicts a text box rather than a selector.
- Confirm selected module descriptions; current static analysis predicts blank descriptions.
- Test output from `Write-Output`, `Write-Host`/Information, Warning, and Error streams.
- Test Stop in an isolated environment and verify both UI recovery and whether any native child process survives pipeline cancellation.

### Module-manager checks

Use a temporary copy of `modules/`, never the only working copy.

- Load categories and all active modules.
- Edit a name/description/order and inspect the exact JSON diff.
- Add and rename a category and verify its folder and `categories.json`.
- Import a disposable module folder and verify copy behavior.
- Move a module between categories and verify both folder location and manifest category.
- Delete and restore categories/modules, including every conflict option.
- Simulate locked files and failed writes to observe partial-update behavior.
- Verify Cancel/close prompts and whether unsaved in-memory changes are discarded.

## Coverage gaps

- No unit tests for manifest parsing, control generation, argument quoting, progress/output routing, cancellation, ordering, or manager persistence.
- No schema validation for manifests or categories.
- No integration tests for shared dynamic providers.
- No automated safety tests for destructive modules.
- No compatibility matrix for OS/PowerShell editions.
- No network mocking for Cloudflare or ipify integrations.
- No tests for unusual paths/values containing quotes, spaces, commas, Unicode, or shell metacharacters.
- No automated verification of generated JSON/CSV/HTML/ZIP/EVTX output.
- No CI and no verified Git worktree in the current directory.
