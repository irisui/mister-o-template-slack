# install-windows-autostart.ps1 - Inregistreaza agentul in Windows Task Scheduler.
#
# Echivalentul Windows pentru generate-launchd.sh de pe macOS: creeaza un task
# care porneste agentul automat la fiecare logon al userului curent.
#
# Lantul de lansare (nu mai e un singur script, ca in prima versiune):
#   Task Scheduler -> agent-start-windows.sh (supervisor, fara fereastra proprie)
#                  -> launch-agent-window.ps1 -> fereastra Windows Terminal cu
#                     claude interactiv (echivalentul tmux pe Windows)
# Motivul: `claude --dangerously-skip-permissions "PROMPT"` fara TTY real
# (stdout redirectat spre fisier, cum facea prima versiune) trece pe
# comportament non-interactiv si iese dupa primul task — de-aia agentul
# reporneste la fiecare ~2 minute si spameaza Slack cu "sunt online" in bucla.
# O fereastra Windows Terminal ofera un TTY real, deci sesiunea ramane vie.
#
# Cerinte: Git for Windows, Windows Terminal (winget install Microsoft.WindowsTerminal),
# Claude Code CLI instalat si autentificat (`claude` in PATH).
#
# Usage (din PowerShell, in folderul proiectului sau oriunde):
#   .\scripts\install-windows-autostart.ps1
#
# Dezinstalare:
#   Unregister-ScheduledTask -TaskName "my-agent-slack" -Confirm:$false

param(
    [string]$ProjectDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$TaskName = "my-agent-slack"

# Gaseste bash.exe (Git for Windows)
$BashCandidates = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)
$BashExe = $BashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $BashExe) {
    $cmd = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($cmd) { $BashExe = $cmd.Source }
}

if (-not $BashExe) {
    Write-Error "Nu am gasit bash.exe (Git for Windows). Instaleaza Git for Windows: https://git-scm.com/download/win"
    exit 1
}

$ScriptPath = Join-Path $ProjectDir "scripts\agent-start-windows.sh"
if (-not (Test-Path $ScriptPath)) {
    Write-Error "Nu am gasit $ScriptPath"
    exit 1
}

$LauncherPath = Join-Path $ProjectDir "scripts\launch-agent-window.ps1"
if (-not (Test-Path $LauncherPath)) {
    Write-Error "Nu am gasit $LauncherPath"
    exit 1
}

$WtCheck = "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
if (-not (Test-Path $WtCheck) -and -not (Get-Command wt.exe -ErrorAction SilentlyContinue)) {
    Write-Error "Windows Terminal (wt.exe) nu a fost gasit. Instaleaza-l: winget install --id Microsoft.WindowsTerminal"
    exit 1
}

Write-Output "Bash gasit la: $BashExe"
Write-Output "Windows Terminal: OK"
Write-Output "Proiect: $ProjectDir"

# Sterge task-ul vechi daca exista (reinstall idempotent)
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

# Actiunea: ruleaza bash.exe cu scriptul, fara fereastra vizibila
$WrappedPath = $ScriptPath -replace '\\', '/' -replace '^([A-Za-z]):', '/$1'
$WrappedPath = $WrappedPath.Substring(0,1) + $WrappedPath.Substring(1,1).ToLower() + $WrappedPath.Substring(2)

$Action = New-ScheduledTaskAction `
    -Execute $BashExe `
    -Argument "-lc `"bash '$ScriptPath'`"" `
    -WorkingDirectory $ProjectDir

# Trigger: la logon-ul userului curent
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

# Setari: ruleaza doar cat userul e logat, restart daca esueaza.
# -Hidden ascunde fereastra SUPERVISOR-ului (bash-ul care verifica la 30s daca
# agentul mai ruleaza) — dar acel supervisor lanseaza la randul lui o fereastra
# Windows Terminal VIZIBILA cu claude interactiv (necesar pentru TTY real, vezi
# launch-agent-window.ps1). Nu mai e deci complet-ascuns ca in prima versiune;
# fereastra "Agent Slack" poate fi minimizata manual, dar nu inchisa.
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -Hidden `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Hours 0)  # fara limita de timp

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -Description "Porneste agentul personal Claude Code + Slack la logon (mister-o-template-slack)" `
    -RunLevel Limited `
    | Out-Null

Write-Output ""
Write-Output "Task '$TaskName' inregistrat. Agentul va porni automat la urmatorul logon."
Write-Output ""
Write-Output "Comenzi utile:"
Write-Output "  Porneste acum (fara sa astepti logon):  Start-ScheduledTask -TaskName '$TaskName'"
Write-Output "  Verifica starea:                        Get-ScheduledTask -TaskName '$TaskName' | Get-ScheduledTaskInfo"
Write-Output "  Opreste task-ul programat:               Disable-ScheduledTask -TaskName '$TaskName'"
Write-Output "  Dezinstaleaza complet:                   Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
Write-Output ""
Write-Output "Loguri agent: $env:USERPROFILE\.agent-logs\activity.log"
