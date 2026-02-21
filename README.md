# IT Swiss-Army Knife

A Windows PowerShell toolkit for everyday IT operations:
- connectivity checks
- diagnostics
- maintenance
- identity/user tasks
- storage and deployment workflows

## Quick start

1. Open PowerShell as Administrator.
2. If scripts are blocked, run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

3. Run one of:

```powershell
.\IT-SwissArmyKnife-v2.6.ps1
.\ModulesManager.ps1
```

Or use:
- `RUN-IT-SwissArmyKnife.bat`
- `RUN-ModulesManager.bat`

## Project structure

- `modules/` module definitions and `run.ps1` scripts by category
- `pics/` assets
- `test/` test module example

