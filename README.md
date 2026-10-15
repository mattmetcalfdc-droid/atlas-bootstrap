# atlas-bootstrap

One paste that turns a fresh Windows 11 computer into Matt's working Atlas Logic machine.

Open **Windows PowerShell** and paste:

```powershell
irm https://raw.githubusercontent.com/mattmetcalfdc-droid/atlas-bootstrap/main/bootstrap.ps1 | iex
```

It installs the tools with winget, then stops only for the sign-ins a person has to do: 1Password (Emergency Kit),
GitHub, 1Password web (one service-account token, typed into a hidden prompt), Claude, Google Chrome. Everything
else is automatic. About 30 minutes. Safe to run again: every step checks first and skips what is done.

Dry run (prints every action, changes nothing):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File bootstrap.ps1 -DryRun
```

This repo is public so the paste needs no sign-in. It holds no secret and nothing private: the repos it restores are
private and need the GitHub sign-in, and the 1Password token is never written to a file or a log. The source of truth
is `bootstrap.ps1` in the private `workstation-backup` repo; that repo's CI fails if this copy differs.

After a fresh clone, install the gitleaks hook before the first commit: `Copy-Item hooks\pre-commit .git\hooks\pre-commit`.
