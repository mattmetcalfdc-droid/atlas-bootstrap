<#
  Atlas Logic - new-laptop bootstrap.  One paste on a fresh Windows 11 machine (stock Windows PowerShell 5.1):

    irm https://raw.githubusercontent.com/mattmetcalfdc-droid/atlas-bootstrap/main/bootstrap.ps1 | iex

  Installs the tools, signs in to GitHub, clones the private workstation-backup repo, runs its restore.ps1 (every repo,
  Claude's memory, every .dev.vars, hooks, npm), sets up the 1Password service-account token, starts the Claude and
  Chrome sign-ins and runs preflight. It pauses only where a person has to sign in. Safe to run again: every step checks
  first and skips what is already done.

  Dry run (prints every action, changes nothing):
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File bootstrap.ps1 -DryRun
    $env:ATLAS_BOOTSTRAP_DRYRUN = '1'; irm <url> | iex

  This file is public. It holds no secret: the private repos need a GitHub sign-in, and the 1Password token is typed
  into a masked prompt, stored only as a Windows user environment variable, and never printed or logged.
  Written for Windows PowerShell 5.1 (ASCII only, no PowerShell 7 syntax) - PowerShell 7 parts run in pwsh.exe.
  Source of truth: github.com/mattmetcalfdc-droid/workstation-backup (bootstrap.ps1); the public copy must match it.
#>
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
if ($env:ATLAS_BOOTSTRAP_DRYRUN -eq '1') { $DryRun = $true }

$Dev       = 'C:\dev'
$Backup    = 'C:\dev\workstation-backup'
$Hq        = 'C:\dev\Cloudflare-HQ'
$BackupUrl = 'https://github.com/mattmetcalfdc-droid/workstation-backup'
$TokenPage = 'https://my.1password.com/developer-tools/infra-secrets/serviceaccount'
$ChromeExt = 'https://chromewebstore.google.com/detail/claude/fcoeoabgfenejglbffodgkkbkcdhcgfn'
$WingetIds = @('Git.Git', 'OpenJS.NodeJS.LTS', 'Microsoft.PowerShell', 'GitHub.cli', 'AgileBits.1Password',
               'AgileBits.1Password.CLI', 'Gitleaks.Gitleaks', 'Amazon.AWSCLI', 'Google.Chrome')
$PendingLog = Join-Path $env:LOCALAPPDATA 'atlas-bootstrap\bootstrap.log'
$script:Results = @()

function Get-LogPath {
  if (Test-Path (Join-Path $Backup '.git')) {
    $final = Join-Path $Backup 'bootstrap.log'
    if (Test-Path $PendingLog) { Get-Content $PendingLog | Add-Content $final; Remove-Item $PendingLog -Force }
    return $final
  }
  $dir = Split-Path $PendingLog
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  return $PendingLog
}
function Log([string]$msg) {
  $line = (Get-Date -Format s) + ' ' + $msg
  if (-not $DryRun) { Add-Content -Path (Get-LogPath) -Value $line }
  Write-Host $msg
}
function Step([string]$title) {
  Write-Host ''; Write-Host ('== ' + $title) -ForegroundColor Cyan
  if (-not $DryRun) { Add-Content -Path (Get-LogPath) -Value ((Get-Date -Format s) + ' STEP ' + $title) }
}
function Act([string]$what, [scriptblock]$do) {
  if ($DryRun) { Write-Host ('   [dry-run] would: ' + $what) -ForegroundColor DarkYellow; return }
  Log ('   ' + $what)
  & $do
}
function Pause-For([string]$what) {
  if ($DryRun) { Write-Host ('   [dry-run] would pause for you: ' + $what) -ForegroundColor DarkYellow; return }
  Write-Host ''
  Write-Host ('   >>> ' + $what) -ForegroundColor Yellow
  [void](Read-Host '   Press Enter when done')
}
function Refresh-Path {
  $m = [Environment]::GetEnvironmentVariable('Path', 'Machine'); $u = [Environment]::GetEnvironmentVariable('Path', 'User')
  $extra = @((Join-Path $HOME '.local\bin'), (Join-Path $env:ProgramFiles 'PowerShell\7'), (Join-Path $env:ProgramFiles 'GitHub CLI'))
  $env:Path = (@($m, $u) + $extra) -join ';'
}
function Have([string]$cmd) { return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function Note([string]$name, [bool]$ok, [string]$detail) { $script:Results += New-Object psobject -Property @{ Name = $name; Ok = $ok; Detail = $detail } }

Write-Host 'Atlas Logic laptop bootstrap' -ForegroundColor Green
if ($DryRun) { Write-Host 'DRY RUN - nothing will be installed, cloned, written or opened.' -ForegroundColor DarkYellow }
Write-Host ('PowerShell ' + $PSVersionTable.PSVersion + ' - log: ' + $(if ($DryRun) { '(none in dry run)' } else { Get-LogPath }))

# ---------- 1. tools ----------
Step '1. Install the tools (winget)'
if (-not (Have 'winget')) { throw 'winget is missing. Open the Microsoft Store, update "App Installer", then paste the command again.' }
foreach ($id in $WingetIds) {
  $null = & winget list --id $id --exact --accept-source-agreements 2>$null
  $present = ($LASTEXITCODE -eq 0)
  if ($id -eq 'Google.Chrome') { $present = $present -or (Test-Path (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe')) -or (Test-Path (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')) }
  if ($present) { Write-Host ('   ok  ' + $id + ' already installed'); continue }
  Act ('winget install ' + $id) {
    & winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { Log ('   WARN winget exit ' + $LASTEXITCODE + ' for ' + $id) }
  }
}
Refresh-Path
if (-not (Have 'claude')) {
  Act 'install Claude Code (official installer: irm https://claude.ai/install.ps1 | iex)' {
    Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
    Refresh-Path
  }
} else { Write-Host '   ok  Claude Code already installed' }
if (-not $DryRun) {
  foreach ($c in @('git', 'node', 'pwsh', 'gh', 'op', 'gitleaks', 'aws')) {
    if (-not (Have $c)) { throw ($c + ' is still not on PATH. Close this window, open a new PowerShell and paste the command again.') }
  }
}
Pause-For '1Password app: open it from the Start menu and sign in with your Emergency Kit (email, Secret Key, master password).'

# ---------- 2. GitHub ----------
Step '2. Sign in to GitHub'
$ghOk = $false
if (Have 'gh') { & gh auth status 2>$null | Out-Null; $ghOk = ($LASTEXITCODE -eq 0) }
if ($ghOk) { Write-Host '   ok  gh already signed in' }
else {
  Write-Host '   A browser opens: copy the one-time code shown here, paste it on github.com, sign in as mattmetcalfdc-droid, approve 2FA on the phone, click Authorize.'
  Act 'gh auth login --web (GitHub.com, HTTPS, Matt clicks Authorize)' {
    & gh auth login --web --hostname github.com --git-protocol https
    if ($LASTEXITCODE -ne 0) { throw 'GitHub sign-in did not finish. Paste the command again.' }
  }
}
Act 'gh auth setup-git (private clones use the GitHub sign-in)' { & gh auth setup-git | Out-Null }

# ---------- 3. backup repo ----------
Step '3. Get the backup repo'
if (Test-Path (Join-Path $Backup '.git')) {
  Act ('git pull ' + $Backup) { & git -C $Backup pull --ff-only --quiet }
} else {
  Act ('git clone ' + $BackupUrl + ' ' + $Backup) {
    if (-not (Test-Path $Dev)) { New-Item -ItemType Directory -Force -Path $Dev | Out-Null }
    & git clone --quiet $BackupUrl $Backup
    if ($LASTEXITCODE -ne 0) { throw 'Clone of workstation-backup failed (GitHub sign-in?).' }
  }
}

# ---------- 4. restore ----------
Step '4. Restore every repo, Claude memory, .dev.vars, hooks, npm (restore.ps1 in PowerShell 7)'
Act ('pwsh -File ' + $Backup + '\restore.ps1') {
  & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Backup 'restore.ps1')
  if ($LASTEXITCODE -ne 0) { Log ('   WARN restore.ps1 exit ' + $LASTEXITCODE + ' - read its checklist above') }
}

# ---------- 5. 1Password service-account token ----------
Step '5. 1Password service-account token (for op run)'
$script:tokenOk = $false
$existing = [Environment]::GetEnvironmentVariable('OP_SERVICE_ACCOUNT_TOKEN', 'User')
if ($existing) {
  $env:OP_SERVICE_ACCOUNT_TOKEN = $existing
  if (Have 'op') { & op whoami 2>$null | Out-Null; $script:tokenOk = ($LASTEXITCODE -eq 0) }
}
$existing = $null
if ($script:tokenOk) { Write-Host '   ok  a working token is already set' }
else {
  Write-Host '   The 1Password page opens. Click "New Service Account", name it cf-hq-<this computer>, give it READ access to'
  Write-Host '   the vault "Cloudflare Secrets" only, create it, and click Copy on the token. Then paste it below (it stays hidden).'
  Act ('open ' + $TokenPage) { Start-Process $TokenPage }
  Act 'ask for the token (masked), save it as the user environment variable OP_SERVICE_ACCOUNT_TOKEN, check it with op whoami' {
    for ($try = 1; $try -le 3 -and -not $script:tokenOk; $try++) {
      $secure = Read-Host -AsSecureString '   Paste the service-account token'
      $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
      try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        $env:OP_SERVICE_ACCOUNT_TOKEN = $plain
        & op whoami 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
          [Environment]::SetEnvironmentVariable('OP_SERVICE_ACCOUNT_TOKEN', $plain, 'User')
          $script:tokenOk = $true
        } else { Write-Host '   That token did not work (op whoami failed). Try again.' -ForegroundColor Red }
      } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr); $plain = $null; $secure = $null
      }
    }
    if ($script:tokenOk) { Log '   token saved for this Windows user (value not logged)' } else { Log '   WARN no working token after 3 tries' }
  }
}
Note '1Password token' ($script:tokenOk -or $DryRun) $(if ($script:tokenOk) { 'set' } elseif ($DryRun) { '(dry run)' } else { 'not set - redo step 5' })

# ---------- 6. Claude ----------
Step '6. Sign in to Claude Code'
Write-Host '   A new PowerShell window opens in C:\dev\Cloudflare-HQ running claude. In it: pick the theme, choose'
Write-Host '   "Claude account with subscription", the browser opens, click Authorize, come back, then type /model fable.'
Act 'open a new window: claude in C:\dev\Cloudflare-HQ (it inherits the op token)' {
  Start-Process pwsh -WorkingDirectory $Hq -ArgumentList @('-NoExit', '-Command', 'claude')
}
Pause-For 'Claude says you are logged in (leave that window open).'

# ---------- 7. Chrome ----------
Step '7. Chrome: Google sign-in + Claude in Chrome'
Act 'open Chrome to the Google sign-in and the Claude in Chrome extension page' {
  Start-Process chrome -ArgumentList @('https://accounts.google.com/signin', $ChromeExt)
}
Write-Host '   Sign in to your Google profile, click "Add to Chrome" on the Claude extension and sign in to it.'
Write-Host '   Cloudflare, AWS, Telnyx, Stripe dashboards: sign in when you need them, each from 1Password.'
Pause-For 'Chrome is signed in (or skip and do it later).'

# ---------- 8. preflight ----------
Step '8. Preflight'
$script:green = $false
Act ('pwsh -File ' + $Hq + '\preflight.ps1') {
  $out = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Hq 'preflight.ps1') 2>&1
  $out | ForEach-Object { Write-Host ('   ' + $_) }
  $script:green = [bool]($out | Select-String -SimpleMatch 'PREFLIGHT GREEN')
}
Note 'Preflight' ($script:green -or $DryRun) $(if ($script:green) { 'GREEN' } elseif ($DryRun) { '(dry run)' } else { 'RED - fix the FAIL lines above' })

# ---------- done ----------
Write-Host ''
foreach ($r in $script:Results) {
  $color = 'Green'; if (-not $r.Ok) { $color = 'Red' }
  Write-Host ('   ' + $r.Name + ': ' + $r.Detail) -ForegroundColor $color
}
Log 'DONE'
Write-Host ''
Write-Host 'Close this window and open a new PowerShell (so it picks up the token), then:' -ForegroundColor Green
Write-Host 'Open Claude in C:\dev\Cloudflare-HQ and say: Laptop was replaced, re-register the backup task and tell me where every project stands.' -ForegroundColor Green
